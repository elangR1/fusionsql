import sys
import os
import re
import json
import logging
import requests
import pandas as pd
import numpy as np
import jaydebeapi
import threading
import warnings
import io
from datetime import datetime, timedelta
from fastapi import FastAPI
from apscheduler.schedulers.background import BackgroundScheduler
from huggingface_hub import HfApi

pd.set_option('future.no_silent_downcasting', True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [ETL] %(levelname)s: %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)
warnings.filterwarnings("ignore", message=".*SQLAlchemy connectable.*", category=UserWarning)

app = FastAPI()
query_lock = threading.Lock()
REGISTRY_FILE = 'etl_registry.json'

# ==========================================
def get_oracle_connection():
    driver_class = 'my.jdbc.wsdl_driver.WsdlDriver'
    jdbc_url = os.getenv('FUSION_REPORT_PATH')
    username = os.getenv('FUSION_USER')
    password = os.getenv('FUSION_PASS')
    jar_path = os.getenv('JAR_PATH')
    return jaydebeapi.connect(driver_class, jdbc_url, [username, password], jar_path)
    
# ==========================================
def load_registry():
    try:
        with open(REGISTRY_FILE, 'r', encoding='utf-8') as f:
            raw_data = json.load(f)
        # Filter only for active tables
        active_tables = [row for row in raw_data if row.get('is_active', False) is True]
        logger.info(f"Loaded {len(active_tables)} active tables from {REGISTRY_FILE}")
        return active_tables, raw_data # Return active list and full raw data for saving later
    except Exception as e:
        logger.error(f"Failed to load {REGISTRY_FILE}: {str(e)}")
        return [], []
        
# ==========================================
def save_registry(full_data):
    try:
        with open(REGISTRY_FILE, 'w', encoding='utf-8') as f:
            json.dump(full_data, f, indent=2)
        logger.info(f"Successfully saved updated {REGISTRY_FILE}")
    except Exception as e:
        logger.error(f"Failed to save {REGISTRY_FILE}: {str(e)}")
        
# ==========================================
def push_to_hf_parquet(df, table_name):
    hf_token = os.environ.get("HF_TOKEN")
    repo_id = "StringFellow/fusion-dw" # CHANGE THIS to your actual HF Dataset repo ID
    
    if not hf_token:
        logger.error("HF_TOKEN secret is missing! Cannot upload to Hugging Face.")
        return

    local_parquet_path = f"/tmp/{table_name}.parquet"
    df.to_parquet(local_parquet_path, engine="pyarrow", compression="snappy")
    file_size_mb = os.path.getsize(local_parquet_path) / (1024 * 1024)
    logger.info(f"  [{table_name}] Saved Parquet file locally ({file_size_mb:.2f} MB).")

    api = HfApi()
    try:
        api.upload_file(
            path_or_fileobj=local_parquet_path,
            path_in_repo=f"{table_name}.parquet",
            repo_id=repo_id,
            repo_type="dataset",
            token=hf_token,
            commit_message=f"ETL Update for {table_name} on {datetime.now().strftime('%Y-%m-%d %H:%M')}"
        )
        logger.info(f"  [{table_name}] Successfully uploaded Parquet to Hugging Face Dataset!")
    except Exception as e:
        logger.error(f"  [{table_name}] Failed to upload to HF: {str(e)}")
    
    if os.path.exists(local_parquet_path):
        os.remove(local_parquet_path)

# ==========================================
def process_table(registry_row):
    sql_url = registry_row['sql_url']
    target_table = registry_row['target_table']
    date_filter_pattern = registry_row.get('date_filter_pattern')
    
    lookback_days = registry_row.get('lookback_days') or 30
    cursor_date = registry_row.get('cursor_date')
    
    logger.info(f"Processing table: {target_table} (Lookback: {lookback_days} days)")
    today = datetime.now().date()
    
    # A. Determine Date Range
    if cursor_date:
        if isinstance(cursor_date, str):
            start_date = datetime.strptime(cursor_date, '%Y-%m-%d').date()
        else:
            start_date = cursor_date - timedelta(days=2)
    else:
        start_date = today - timedelta(days=lookback_days)
    
    if (today - start_date).days <= 30:
        start_date = today - timedelta(days=30)
        end_date = today
        is_caught_up = True
        logger.info(f"  [{target_table}] CAUGHT UP: Running 30-day rolling refresh ({start_date} to {end_date})")
    else:
        target_end = start_date + timedelta(days=14)
        end_date = min(target_end, today)
        is_caught_up = False
        logger.info(f"  [{target_table}] CATCH-UP MODE: Jumping 14 days ({start_date} to {end_date})")
    
    start_str = start_date.strftime('%Y-%m-%d')
    end_str = end_date.strftime('%Y-%m-%d')
    
    # B. Fetch SQL from GitHub
    sql_text = requests.get(sql_url).text
    
    # C. Bulletproof Date Injection
    if "__START_DATE__" in sql_text:
        final_sql = sql_text.replace("__START_DATE__", start_str).replace("__END_DATE__", end_str)
        logger.info(f"  [{target_table}] Injected dates using direct token replacement.")
    else:
        final_sql = sql_text
        if date_filter_pattern and "BETWEEN" in date_filter_pattern.upper():
            col_part = date_filter_pattern.split("BETWEEN")[0].strip()
            if col_part:
                smart_pattern = f"({col_part})\\s+BETWEEN\\s+'[^']+'\\s+AND\\s+'[^']+'"
                replacement = f"\\1 BETWEEN '{start_str}' AND '{end_str}'"
                final_sql = re.sub(smart_pattern, replacement, final_sql, flags=re.IGNORECASE)
    
    # D. Query Oracle Fusion
    conn_ora = get_oracle_connection()
    df = pd.read_sql(final_sql, conn_ora)
    conn_ora.close()
    logger.info(f"  [{target_table}] Fetched {len(df)} rows from Oracle.")
    
    if df.empty:
        logger.info(f"  [{target_table}] No data returned. Skipping upload.")
        return is_caught_up, end_str
    
    # E. Clean Column Names
    df.columns = [c.lower().replace(' ', '_').replace('_x0020_', '').replace('-', '_').strip('_') for c in df.columns]
    seen = {}
    new_cols = []
    for c in df.columns:
        if c in seen:
            seen[c] += 1
            new_cols.append(f"{c}_{seen[c]}")
        else:
            seen[c] = 0
            new_cols.append(c)
    df.columns = new_cols
    
    # F. Bulletproof Nullifier
    df = df.replace(r'^\s*$', np.nan, regex=True)
    df = df.replace([np.nan, 'nan', 'None', 'NaT', ''], None)
    for col in df.columns:
        df[col] = df[col].apply(lambda x: str(x) if pd.notna(x) and x is not None else None)
    
    # G. Push to Hugging Face as Parquet
    push_to_hf_parquet(df, target_table)
    logger.info(f"  [{target_table}] Processing complete.")
    
    return is_caught_up, end_str

# 6. THE MASTER ETL ORCHESTRATOR
# ==========================================
def run_master_etl():
    logger.info("=" * 60)
    logger.info("=== MASTER ETL ORCHESTRATOR STARTED ===")
    logger.info("=" * 60)
    
    with query_lock:
        try:
            active_tables, full_registry_data = load_registry()
            if not active_tables:
                logger.error("No active tables found in registry. Exiting.")
                return
            
            for row in active_tables:
                try:
                    is_caught_up, end_str = process_table(row)
                    
                    # UPDATE CURSOR DATE IN JSON IF NOT CAUGHT UP
                    if not is_caught_up and row.get('date_column'):
                        row['cursor_date'] = end_str
                        logger.info(f"  [{row['target_table']}] Cursor updated in JSON to {end_str}.")
                    else:
                        logger.info(f"  [{row['target_table']}] Caught up or no date filter. Cursor unchanged.")
                        
                except Exception as table_error:
                    logger.error(f"  [{row['target_table']}] FAILED: {str(table_error)}", exc_info=True)
                    continue
            
            # SAVE UPDATED REGISTRY BACK TO JSON
            save_registry(full_registry_data)
            
            logger.info("=" * 60)
            logger.info("=== MASTER ETL ORCHESTRATOR COMPLETED ===")
            logger.info("=" * 60)
            
        except Exception as e:
            logger.error(f"MASTER ETL FAILED: {str(e)}", exc_info=True)

# 7. SCHEDULER (Runs Every 1 Hour)
# ==========================================
scheduler = BackgroundScheduler()
scheduler.add_job(func=run_master_etl, trigger="interval", hours=1)
scheduler.start()
logger.info("Background Scheduler started. Will run every 1 hour.")

# 8. AUTO-START & MANUAL TRIGGER
# ==========================================
@app.on_event("startup")
async def startup_event():
    logger.info("App started. Triggering initial ETL in background...")
    thread = threading.Thread(target=run_master_etl)
    thread.start()

@app.get("/run-etl")
def manual_trigger():
    logger.info("Manual trigger received.")
    thread = threading.Thread(target=run_master_etl)
    thread.start()
    return {"status": "Master ETL started in background. Check logs!"}

@app.get("/")
def read_root():
    return {"status": "OFJDBC to HF Parquet ETL Engine is running."}
