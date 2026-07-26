let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_OM_SALES_ORDER_RPT.xdo",
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
                    {{"BU_NAME", type text}, 
                    {"ORDER_NUMBER", type text}, 
                    {"ORDER_STATUS", type text},
                    {"CUSTOMER_PO_NUMBER", type text}
                    }),
                {
                    {"CREATION_DATE2", each try Date.FromText(Text.From(_)) otherwise null, type date}
                }
            ),
            #"Changed Type" = Table.TransformColumnTypes(#"Parsed Data",{
                {"CREATION_DATE", type datetime}, 
                {"ORDERED_DATE", type datetime},
                {"REQUEST_SHIP_DATE", type datetime},
                {"ACTUAL_SHIP_DATE", type datetime}
                }),
            #"Reordered Columns" = Table.ReorderColumns(#"Changed Type", {"BU_NAME", "CREATION_DATE", "CREATION_DATE2", "ORDERED_DATE", "ORDER_NUMBER", "ORDER_STATUS", "CUSTOMER_PO_NUMBER", "CUSTOMER_NAME", "ORDER_TYPE", "INPUT_BY", "LINE_NUMBER", "ITEM_CODE", "ITEM_DESCRIPTION", "QUANTITY", "UOM", "REQUEST_SHIP_DATE", "ACTUAL_SHIP_DATE", "LINE_STATUS", "IO_NAME"}),
            #"Added Custom" = Table.AddColumn(#"Reordered Columns", "LINE_STATUS2", each 
                if [LINE_STATUS] = "Manual Reservation Required" 
                    and not Text.Contains([ORDER_TYPE], "SDA - Ekspor", Comparer.OrdinalIgnoreCase)
                    and Date.From([CREATION_DATE]) < Date.AddMonths(Date.From(DateTime.LocalNow()), -1)
                then "Cancelled" 
                else [LINE_STATUS],
                type text
                ),
            #"Lowercased Columns" = Table.TransformColumnNames(#"Added Custom", Text.Lower)
        in
            #"Lowercased Columns"
            
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
