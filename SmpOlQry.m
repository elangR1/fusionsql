let
    // 1. Get raw SQL text from GitHub
    GitHubUrl = "https://raw.githubusercontent.com/elangR1/fusionsql/main/ItemList.sql",
    SqlBinary = Web.Contents(GitHubUrl),
    SqlText = Text.FromBinary(SqlBinary),

    // 2. Mandatory Parameter Logic
    StartText = DateTime.ToText(RangeStart, "yyyy-MM-dd HH:mm:ss"),
    EndText = DateTime.ToText(RangeEnd, "yyyy-MM-dd HH:mm:ss"),

    // 3. Conditional Logic: Optional dynamic filters
    F_ItemLike = if ParamItemNumberLike <> null and ParamItemNumberLike <> "" then " AND esi.ITEM_NUMBER LIKE '" & ParamItemNumberLike & "'" else "",
    F_Class    = if ParamItemClassName <> null and ParamItemClassName <> "" then " AND ics.ITEM_CLASS_NAME = '" & ParamItemClassName & "'" else "",
    F_DescLike = if ParamDescriptionLike <> null and ParamDescriptionLike <> "" then " AND esi.description LIKE '" & ParamDescriptionLike & "'" else "",
    F_DescNot  = if ParamDescriptionNotLike <> null and ParamDescriptionNotLike <> "" then " AND esi.description NOT LIKE '" & ParamDescriptionNotLike & "'" else "",
    F_OrgIn    = if ParamOrgNameIn <> null and ParamOrgNameIn <> "" then " AND iodv.ORGANIZATION_NAME IN (" & ParamOrgNameIn & ")" else "",
    F_Org      = if ParamOrgName <> null and ParamOrgName <> "" then " AND iodv.ORGANIZATION_NAME = '" & ParamOrgName & "'" else "",
    ActiveFilters = F_ItemLike & F_Class & F_DescLike & F_DescNot & F_OrgIn & F_Org,

    // 4. DYNAMIC INJECTION: Inject parameters cleanly into original SQL layout
    InjectDates = Text.Replace(Text.Replace(SqlText, "__START_DATE__", StartText), "__END_DATE__", EndText),
    FinalSQL    = Text.Replace(InjectDates, "__DYNAMIC_FILTERS__", ActiveFilters),

    // 5. Establish connection payload parameters
    ProxyUrl = "https://stringfellow-fsn-pstgrs-prxy.hf.space/query",
    JsonPayload = Binary.Buffer(Json.FromValue([sql = FinalSQL])),
    
    // 6. Execute POST Request (ADDED Binary.Buffer TO PREVENT DUPLICATE CALLS)
    SourceWeb = Binary.Buffer(
        Web.Contents(
            ProxyUrl,
            [
                Headers = [
                    #"Content-Type" = "application/json",
                    #"Accept" = "text/csv"
                ],
                Content = JsonPayload,
                Timeout = #duration(0, 0, 15, 0)
            ]
        )
    ),
    
    // 7. HIGH-PERFORMANCE CSV PARSING
    CsvTable = Csv.Document(SourceWeb, [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    
    // 8. Final formatting step
    #"Promoted Headers" = Table.PromoteHeaders(CsvTable, [PromoteAllScalarTypes=true])
in
    #"Promoted Headers"
