let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_SCE_INBOUND_TO_RPT.xdo",
        params = [] 
    ],

    jsonPayload = Json.FromValue(PayloadRecord),

    apiResponse = Web.Contents(
        "https://stringfellow-fsn-etl-neon.hf.space/extract", // Verify this is your current active URL
        [
            Headers = [
                #"Content-Type" = "application/json",
                #"Accept" = "application/octet-stream"
            ],
            Content = jsonPayload,
            ManualStatusHandling = {500, 422}
        ]
    ),
    responseStatus = Value.Metadata(apiResponse)[Response.Status],
    FinalResult = if responseStatus = 200 then
        let
            bufferedResponse = Binary.Buffer(apiResponse),
            parquetData = Parquet.Document(bufferedResponse),
            #"Parsed Data" = Table.TransformColumns(
                // First, apply standard number conversions
                Table.TransformColumnTypes(parquetData,{{"TO_NUMBER", type text}, {"SHIPMENT_HEADER_ID", type text}, {"SHIPMENT_NUMBER", type text}, {"SHIPPED_QTY", type number}, {"RECEIVED_QTY", type number}, {"DELIVERED_QTY", type number}, {"NO_PICKWAVE", type text}, {"ITOL_HEADER", type text}, {"ITOL_RQ_QTY", type number}, {"ITOL_RCV_QTY", type number}, {"INTRANSIT_EXP_QTY", type number}, 
                    {"RQ_AMOUNT", type number}
                }),
                {
                    {"ORDER_DATE", each try Date.FromText(Text.From(_), [Format="yyyy-MM-dd", Culture="en-US"]) otherwise null, type date},
                    {"TO_RQ_DLV_DATE", each try Date.FromText(Text.From(_), [Format="yyyy-MM-dd", Culture="en-US"]) otherwise null, type date},
                    {"TO_SCH_SHIP_DATE", each try DateTime.FromText(Text.From(_), [Format="yy/MM/dd HH:mm", Culture="en-US"]) otherwise null, type datetime},
                    {"TO_LAST_UPDATE", each try DateTime.FromText(Text.From(_), [Format="yy/MM/dd HH:mm", Culture="en-US"]) otherwise null, type datetime},
                    {"GL_DATE", each try Date.FromText(Text.From(_), [Format="yyyy-MM-dd", Culture="en-US"]) otherwise null, type date},
                    {"EXPECTED_RECEIPT_DATE", each try Date.FromText(Text.From(_), [Format="yyyy-MM-dd", Culture="en-US"]) otherwise null, type date},
                    {"ACT_SHIPPED_DATE", each try Date.FromText(Text.From(_), [Format="yyyy-MM-dd", Culture="en-US"]) otherwise null, type date},
                    {"TO_CREATION_DATE", each try DateTime.FromText(Text.From(_), [Format="yy/MM/dd HH:mm", Culture="en-US"]) otherwise null, type datetime}
                }
            )
        in
            #"Parsed Data"
    else
        let
            errorJson = Json.Document(apiResponse),
            errorMessage = try errorJson[detail] otherwise "Unknown Extraction Error",
            customError = error Error.Record(
                "Oracle_BIP_Error", 
                "API Error Details: " & Text.From(errorMessage)
            )
        in
            customError
in
    FinalResult
