let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_SCE_WO_COMP_RPT.xdo",
        params = [] 
    ],

    jsonPayload = Json.FromValue(PayloadRecord),

    apiResponse = Web.Contents(
        "https://stringfellow-fsn-etl-neon.hf.space/extract",
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
    		    {"CREATION_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"START_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"RELEASE_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"ACTUAL_COMPLETION_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime},
            {"CLOSED_DATE", each DateTime.FromText(_, [Format="yy/MM/dd HH:mm"]), type datetime}
	        }),
            #"Parsed Data1" = Table.RenameColumns(#"Parsed Data",{{"ORG_NAME", "Inventory Organization"}, {"START_DATE", "Start Date Completion Before Issue"}})
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
    #"Changed Type" = Table.TransformColumnTypes(FinalResult,{{"PROCESS_NAME", type text}, {"PLANNED_QUANTITY", type text}, {"ACTUAL_QUANTITY", type text}})
in
    #"Changed Type"
