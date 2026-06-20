let
    GitHubUrl = "https://raw.githubusercontent.com/elangR1/fusionsql/main/ItemList.sql",
    SqlBinary = Web.Contents(GitHubUrl),
    SqlText = Text.FromBinary(SqlBinary),

    // 2. Mandatory Parameter Logic
    StartDt = DateTime.ToText(RangeStart, "yyyy-MM-dd HH:mm:ss"),
    EndDt = DateTime.ToText(RangeEnd, "yyyy-MM-dd HH:mm:ss"),

    // 3. Conditional Logic: Optional dynamic filters
    F_ItemLike = if ParamItemNumberLike <> null and ParamItemNumberLike <> "" then " AND esi.ITEM_NUMBER LIKE '" & ParamItemNumberLike & "'" else "",
    F_Class    = if ParamItemClassName <> null and ParamItemClassName <> "" then " AND ics.ITEM_CLASS_NAME = '" & ParamItemClassName & "'" else "",
    F_DescLike = if ParamDescriptionLike <> null and ParamDescriptionLike <> "" then " AND esi.description LIKE '" & ParamDescriptionLike & "'" else "",
    F_DescNot  = if ParamDescriptionNotLike <> null and ParamDescriptionNotLike <> "" then " AND esi.description NOT LIKE '" & ParamDescriptionNotLike & "'" else "",
    F_OrgIn    = if ParamOrgNameIn <> null and ParamOrgNameIn <> "" then " AND iodv.ORGANIZATION_NAME IN (" & ParamOrgNameIn & ")" else "",
    F_Org      = if ParamOrgName <> null and ParamOrgName <> "" then " AND iodv.ORGANIZATION_NAME = '" & ParamOrgName & "'" else "",
    CondFilters = F_ItemLike & F_Class & F_DescLike & F_DescNot & F_OrgIn & F_Org,

    InjectDates = Text.Replace(Text.Replace(SqlText, "__START_DATE__", StartDt), "__END_DATE__", EndDt),
    FinalSQL    = Text.Replace(InjectDates, "__DYNAMIC_FILTERS__", CondFilters),

    ProxyUrl = "https://stringfellow-fsn-pstgrs-prxy.hf.space/query",
    JsonPayload = Binary.Buffer(Json.FromValue([sql = FinalSQL])),

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
    
    CsvTable = Csv.Document(SourceWeb, [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    #"Promoted Headers" = Table.PromoteHeaders(CsvTable, [PromoteAllScalarTypes=true])
in
    #"Promoted Headers"
