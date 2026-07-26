let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_SCE_WORK_ORDER_RPT.xdo",
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
            #"Parsed Data" = Table.RemoveColumns(parquetData,{"DATE_CHANGE"}),
            #"Parsed Data1" = Table.TransformColumns(#"Parsed Data", {
    		{"START_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
    		{"CLOSE_DATE_SYSTEM", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
    		{"CANCELED_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
    		{"FIRST_CLOSE_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
    		{"LAST_CLOSE_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
    		{"STATUS_CHANGE_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime}
	        }),
            #"Parsed Data2" = Table.RenameColumns(#"Parsed Data1",{{"INVENTORY_ORGANIZATION_NAME", "Inventory Organization"}})
        in
            #"Parsed Data2"
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
    #"Changed Type" = Table.TransformColumnTypes(FinalResult,{{"PROCESS_NAME", type text}, {"PLANNED_QUANTITY", type text}, {"ACTUAL_OUTPUT_QUANTITY", type text}})
in
    #"Changed Type"
