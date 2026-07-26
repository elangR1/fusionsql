from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel
import os
import io
import requests
import base64
import pandas as pd
import urllib3
import gc
import time

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

app = FastAPI()

# ==========================================
# 0. CUSTOM LOGGING FOR 422 ERRORS
# ==========================================
# Catch bad JSON payloads from Power BI before they crash the app
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    body = await request.body()
    print("========== 422 VALIDATION ERROR ==========")
    print(f"Raw Request Body from Power BI: {body.decode('utf-8')}")
    print(f"Validation Error Details: {exc.errors()}")
    print("==========================================")
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors(), "body": body.decode('utf-8')}
    )

# ==========================================
# 1. THE GENERIC BIP CLIENT
# ==========================================
class FusionBIPClient:
    def __init__(self, host, username, password):
        self.host = host.rstrip('/')
        self.url = f"{self.host}/xmlpserver/services/ExternalReportWSSService"
        self.auth = (username, password)
        self.headers = {'Content-Type': 'application/soap+xml; charset=utf-8'}

    def _generate_soap_envelope(self, report_path, params, output_format="CSV"):
        """Dynamically builds the SOAP 1.2 envelope for any report."""
        params_xml = ""
        for key, value in params.items():
            params_xml += f"""
            <pub:item>
                <pub:name>{key}</pub:name>
                <pub:values>
                    <pub:item>{value}</pub:item>
                </pub:values>
            </pub:item>"""

        return f"""<?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">
           <soap:Header/>
           <soap:Body>
              <pub:runReport>
                 <pub:reportRequest>
                    <pub:reportAbsolutePath>{report_path}</pub:reportAbsolutePath>
                    <pub:sizeOfDataChunkDownload>-1</pub:sizeOfDataChunkDownload>
                    <pub:byPassCache>false</pub:byPassCache>
                    <pub:flattenXML>false</pub:flattenXML>
                    <pub:parameterNameValues>
                        {params_xml}
                    </pub:parameterNameValues>
                    <pub:appParams/>
                    <pub:reportFormat>{output_format}</pub:reportFormat>
                 </pub:reportRequest>
              </pub:runReport>
           </soap:Body>
        </soap:Envelope>"""

    def extract_report(self, report_path, params):
        """Extracts the report, handles CSV/Excel automatically, and converts to Parquet."""
        soap_envelope = self._generate_soap_envelope(report_path, params, "CSV")
        
        response = requests.post(self.url, data=soap_envelope.encode('utf-8'), 
                                 headers=self.headers, auth=self.auth, verify=False)
        
        if response.status_code != 200:
            raise Exception(f"BIP API Error: {response.status_code} - {response.text}")

        # Extract Base64 data
        start_tag = "<ns2:reportBytes>"
        end_tag = "</ns2:reportBytes>"
        if start_tag not in response.text:
            start_tag = "<reportBytes>"
            end_tag = "</reportBytes>"
            
        start_idx = response.text.find(start_tag) + len(start_tag)
        end_idx = response.text.find(end_tag)
        base64_data = response.text[start_idx:end_idx].strip()
        
        # Free up memory from the large raw text response
        del response 
        gc.collect()

        decoded_bytes = base64.b64decode(base64_data)
        
        # Free up memory from the base64 string
        del base64_data 
        gc.collect()

        # SMART FILE DETECTION
        if decoded_bytes.startswith(b'\xd0\xcf\x11\xe0'):
            df = pd.read_excel(io.BytesIO(decoded_bytes))
        elif decoded_bytes.startswith(b'PK\x03\x04'):
            raise Exception("Report returned a ZIP file. Please check BIP layout.")
        else:
            # low_memory=False prevents mixed datatype warnings on massive CSVs
            df = pd.read_csv(io.BytesIO(decoded_bytes), low_memory=False)

        # Free up memory from the decoded bytes payload
        del decoded_bytes
        gc.collect()

        # Convert to Parquet for maximum Power BI speed
        parquet_buffer = io.BytesIO()
        df.to_parquet(parquet_buffer, engine='pyarrow', compression='snappy')
        
        # Free up the dataframe memory
        del df
        gc.collect()
        
        return parquet_buffer.getvalue()

# ==========================================
# 2. FASTAPI ROUTES
# ==========================================
FUSION_HOST = os.getenv("FUSION_HOST")
FUSION_USER = os.getenv("FUSION_USER")
FUSION_PASS = os.getenv("FUSION_PASS")

class ReportRequest(BaseModel):
    report_path: str
    params: dict

@app.get("/")
def health_check():
    return {
        "status": "running", 
        "message": "Fusion BIP Extractor is ready!",
        "usage": "POST to /extract with JSON body containing 'report_path' and 'params'"
    }

# NEW: Dummy GET route to satisfy Power BI Service network/credential probes
@app.get("/extract")
def extract_probe():
    return {
        "status": "ready", 
        "message": "Endpoint is alive. Please use POST to extract data."
    }

# THE MAIN ENDPOINT
# Runs synchronously (no async def) to allow parallel ThreadPool execution
@app.post("/extract")
def extract_bip_report(request: ReportRequest):
    start_time = time.time()
    print(f"========== EXTRACTION STARTED ==========")
    print(f"Target XDO Report : {request.report_path}")
    print(f"Parameters Passed : {request.params}")
    
    try:
        client = FusionBIPClient(FUSION_HOST, FUSION_USER, FUSION_PASS)
        
        # Extract and convert to Parquet
        parquet_bytes = client.extract_report(
            report_path=request.report_path, 
            params=request.params
        )
        
        elapsed_time = round(time.time() - start_time, 2)
        print(f"========== EXTRACTION SUCCESS ==========")
        print(f"Successfully finished : {request.report_path}")
        print(f"Time Taken          : {elapsed_time} seconds")
        print(f"Final Parquet Size  : {len(parquet_bytes)} bytes")
        print("==========================================")
        
        # Stream the Parquet file back to Power BI
        return StreamingResponse(
            io.BytesIO(parquet_bytes),
            media_type="application/octet-stream",
            headers={"Content-Disposition": "attachment; filename=data.parquet"}
        )
    except Exception as e:
        elapsed_time = round(time.time() - start_time, 2)
        print(f"========== EXTRACTION FAILED ==========")
        print(f"Failed Report       : {request.report_path}")
        print(f"Time Elapsed        : {elapsed_time} seconds")
        print(f"Error Message       : {str(e)}")
        print("==========================================")
        raise HTTPException(status_code=500, detail=str(e))
