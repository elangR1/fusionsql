let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_PO_RETURN_VENDOR_RPT.xdo",
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
            #"Parsed Data" = Table.TransformColumns(parquetData, {
    		    {"RETURN_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"PO_CREATION_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"PO_SUBMIT_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"PO_LAST_APPROVED_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"RECEIPT_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime}
	        }),
            #"Parsed Data1" = Table.RenameColumns(#"Parsed Data",{{"INV_ORG_NAME", "Inventory Organization"}}),
        in
            #"Parsed Data1"
    else
        let
            errorJson = Json.Document(apiResponse),
            errorMessage = try errorJson[detail] otherwise "Unknown Extraction Error",
            customError = error Error.Record(
                "Oracle_BIP_Error", 
                "API Error Details: " & Text.From(errorMessage)
            )
        in
            customError,
	#"Changed Type" = Table.TransformColumnTypes(#"Parsed Data1",{{"TRANSACTION_ID", type text}, {"RECEIPT_NUM", type text}, {"QUANTITY", type text}, {"INV_ORG_CODE", type text}})
in
    #"Changed Type"
