import os
import sys
import threading
import warnings
import io
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import jaydebeapi
import pandas as pd

# 1. Silence the noisy pandas warning globally
warnings.filterwarnings("ignore", message=".*SQLAlchemy connectable.*", category=UserWarning)

app = FastAPI()

# 2. Prevent concurrent query crashes by forcing a sequential queue
query_lock = threading.Lock()

@app.get("/")
def read_root():
    return {"status": "OFJDBC API is running successfully! Connect to /query via POST."}

class QueryRequest(BaseModel):
    sql: str

@app.post("/query")
def run_query(request: QueryRequest):
    # 3. DYNAMIC ENV LOADING: Fetch credentials securely from Hugging Face Secrets
    driver_class = 'my.jdbc.wsdl_driver.WsdlDriver'
    jdbc_url = os.getenv('FUSION_SQL_REPORT_PATH')
    username = os.getenv('FUSION_USER')
    password = os.getenv('FUSION_PASS')
    jar_path = os.getenv('JAR_PATH')
    
    # 4. Queue request processing sequentially
    with query_lock:
        print("================ INCOMING QUERY ================", file=sys.stderr)
        print(request.sql, file=sys.stderr)
        print("================================================", file=sys.stderr)
        
        # Guard clause: Verify environment variables are completely loaded
        if not all([jdbc_url, username, password, jar_path]):
            error_msg = "CRITICAL ERROR: One or more environment variables (JDBC_URL, FUSION_USER, FUSION_PASS, JAR_PATH) are missing in HF Secrets configuration."
            print(error_msg, file=sys.stderr)
            error_df = pd.DataFrame({"Error": [error_msg]})
            error_stream = io.StringIO()
            error_df.to_csv(error_stream, index=False)
            return StreamingResponse(iter([error_stream.getvalue()]), media_type="text/csv")

        conn = None
        try:
            # Establish driver connection dynamically
            conn = jaydebeapi.connect(driver_class, jdbc_url, [username, password], jar_path)
            # Fetch table data into a pandas DataFrame
            df = pd.read_sql(request.sql, conn)
            print("Query executed successfully. Streaming CSV payload back to Power BI.", file=sys.stderr)
            
            # Convert to memory-buffer CSV stream for fast transfer
            stream = io.StringIO()
            df.to_csv(stream, index=False)
            
            response = StreamingResponse(
                iter([stream.getvalue()]),
                media_type="text/csv"
            )
            response.headers["Content-Disposition"] = "attachment; filename=export.csv"
            return response
            
        except Exception as e:
            print(f"CRITICAL DATABASE ERROR: {str(e)}", file=sys.stderr)
            # Fallback error response as plain text/csv format
            error_df = pd.DataFrame({"Error": [str(e)]})
            error_stream = io.StringIO()
            error_df.to_csv(error_stream, index=False)
            return StreamingResponse(iter([error_stream.getvalue()]), media_type="text/csv")
            
            
        finally:
            if conn:
                try:
                    conn.close()
                    print("JDBC Connection closed successfully.", file=sys.stderr)
                except Exception as close_error:
                    print(f"Warning during connection closure: {str(close_error)}", file=sys.stderr)
