let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_PO_PURCHASE_ORDER_draft_RPT.xdo",
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
                Table.TransformColumnTypes
                (parquetData,
                    {{"PO_HEADER_ID", type text},
                    {"PO_LINE_ID", type text}, 
                    {"CATEGORY_ID", type text},
                    {"LINE_LOCATION_ID", type text}
                    //{"CODE_COMBINATION_ID", type text},
                    //{"REQ_DISTRIBUTION_ID", type text},
                    //{"REQUISITION_HEADER_ID", type text},
                    //{"REQUISITION_LINE_ID", type text}
                    }),
                {
                    //{"SUBMIT_DATE", each try DateTime.FromText(Text.From(_), [Format="dd/MM/yyyy HH:mm", Culture="en-US"]) otherwise null, type datetime},
                    //{"PO_CREATED_DATE", each try DateTime.FromText(Text.From(_), [Format="dd/MM/yyyy HH:mm", Culture="en-US"]) otherwise null, type datetime},
                    {"NEED_BY_DATE", each try Date.FromText(Text.From(_)) otherwise null, type date},
                    {"PROMISED_DATE", each try Date.FromText(Text.From(_)) otherwise null, type date}
                }
            ),
            #"Changed Type" = Table.TransformColumnTypes(#"Parsed Data",{{"PO_CREATED_DATE", type datetime}})
        in
            #"Changed Type"
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
