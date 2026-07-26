let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_PO_PURCHASE_ORDER_RPT.xdo",
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
                    {"VERSION_ID", type text}, 
                    {"PO_VERSION", type text},
                    {"PO_LINE_ID", type text}, 
                    {"CATEGORY_ID", type text},
                    {"LINE_LOCATION_ID", type text},
                    {"CODE_COMBINATION_ID", type text},
                    {"REQ_DISTRIBUTION_ID", type text},
                    {"REQUISITION_HEADER_ID", type text},
                    {"REQUISITION_LINE_ID", type text}
                    }),
                {
                    //{"PO_CREATED_DATE", each try DateTime.FromText(Text.From(_), [Format="dd/MM/yyyy HH:mm", Culture="en-US"]) otherwise null, type datetime},
                    //{"LAST_UPDATED_DATE", each try DateTime.AddHours(DateTime.FromText(Text.From(_)), 7) otherwise null, type datetime},
                    //{"PO_CREATION_DATE", each try DateTime.AddHours(DateTime.FromText(Text.From(_)), 7) otherwise null, type datetime},
                    {"PO_SUBMITTED_DATE", each try Date.FromText(Text.From(_)) otherwise null, type date},
                    {"PO_APPROVED_DATE", each try Date.FromText(Text.From(_)) otherwise null, type date},
                    {"NEED_BY_DATE", each try Date.FromText(Text.From(_)) otherwise null, type date},
                    {"PROMISED_DATE", each try Date.FromText(Text.From(_)) otherwise null, type date}
                }
            ),
            #"Reordered Columns" = Table.ReorderColumns(#"Parsed Data",{"PO_HEADER_ID", "PO_NUMBER", "VERSION_ID", "PO_VERSION", "DOCUMENT_STATUS", "CREATED_BY", "PO_TYPE", "BU", "LAST_UPDATED_BY", "CURRENCY_CODE", "RATE", "COMMENTS", "INPUT_BY", "PO_CREATION_DATE", "PO_SUBMITTED_DATE", "PO_APPROVED_DATE", "LAST_UPDATED_DATE", "SUPPLIER_NAME", "SUPPLIER_SITE", "PO_LINE_ID", "LINE_NUM", "ITEM_CODE", "ITEM_DESCRIPTION", "UOM", "LINE_QUANTITY", "UNIT_PRICE", "LINE_AMOUNT", "TAX_RATE_CODE", "TAX_AMT", "TOTAL_LINE_AMOUNT", "LINE_STATUS", "NOTE_TO_VENDOR", "LINE_DETAIL", "CATEGORY_ID", "PURCHASING_CATEGORY", "LINE_LOCATION_ID", "SHIPMENT_QUANTITY", "IO_NAME", "QTY_RCV_TOLERANCE", "QTY_RCV_EXCEPTION_CODE", "RECEIPT_DAYS_EXCEPTION_CODE", "NEED_BY_DATE", "PROMISED_DATE", "QUANTITY_ORDERED", "QUANTITY_DELIVERED", "QUANTITY_CANCELLED", "QUANTITY_BILLED", "CODE_COMBINATION_ID", "DESTINATION_TYPE_CODE", "REQ_DISTRIBUTION_ID", "REQUISITION_LINE_ID", "REQUISITION_HEADER_ID"}),
            #"Changed Type" = Table.TransformColumnTypes(#"Reordered Columns",{{"PO_CREATION_DATE", type datetime}, {"LAST_UPDATED_DATE", type datetime}})
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
