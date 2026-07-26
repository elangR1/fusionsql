let
    PayloadRecord = [
        report_path = "Custom/Financials/PBI/SKL_PRC_PENDING_APPROVAL_RPT.xdo",
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
            #"Parsed Data" = Table.TransformColumns(
                // First, apply standard number conversions
                Table.TransformColumnTypes
                (parquetData,
                    {{"DOCUMENT_TYPE", type text}, 
                    {"PROCESS_NAME", type text}, 
                    {"DOCUMENT_NUMBER_ID", type text},
                    {"SUBMITTED_BY", type text}, 
                    {"PROCESS_DESCRIPTION", type text},
                    {"ASSIGNEES", type text},
                    {"PROCESS_STATUS", type text},
                    {"DOCUMENT_STATUS", type text},
                    {"RUNNING_NUMBER", Int64.Type}
                    }),
                {
                    {"SUBMIT_DATE", each try DateTime.FromText(Text.From(_), [Format="dd/MM/yyyy HH:mm", Culture="en-US"]) otherwise null, type datetime},
                    {"ASSIGNED_DATE", each try DateTime.FromText(Text.From(_), [Format="dd/MM/yyyy HH:mm", Culture="en-US"]) otherwise null, type datetime},
                    {"ACTION_DATE", each try DateTime.FromText(Text.From(_), [Format="dd/MM/yyyy HH:mm", Culture="en-US"]) otherwise null, type datetime}
                }
            ),
            #"Added Duration" = Table.AddColumn(
                #"Parsed Data", 
                "Duration_Hours", 
                each 
                    if [ACTION_DATE] = null then 
                        Duration.TotalHours(DateTime.LocalNow() - [ASSIGNED_DATE])
                    else 
                        Duration.TotalHours([ACTION_DATE] - [ASSIGNED_DATE]),
                type number
            )
        in
            #"Added Duration"
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
  #"Inserted conditional column" = Table.AddColumn(FinalResult, "DURATION_DAYS", each if [Duration_Hours] < 24 then "0 Day" else if [Duration_Hours] < 48 then "1 Day" else if [Duration_Hours] < 72 then "2 Day" else if [Duration_Hours] < 120 then "3-5 Days" else if [Duration_Hours] < 720 then "5-30 Days" else if [Duration_Hours] >= 720 then "more than 30 Days" else "")
in
    #"Inserted conditional column"
