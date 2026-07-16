SELECT
	ft.application_short_name
	, ft.table_name
	, ft.description AS table_desc
	, ft.table_type
	, ft.tablespace_type
	, ft.last_update_date
	, fc.COLUMN_NAME AS fc_column
	, fc.COLUMN_TYPE 
	, fc.DESCRIPTION 
FROM
	FND_TABLES ft
LEFT JOIN
	FND_COLUMNS fc ON ft.table_id = fc.table_id 
WHERE
-- By Table Names
ft.table_name LIKE '%USER%'
--AND ft.APPLICATION_SHORT_NAME = 'FND'
--AND ft.DESCRIPTION LIKE '%hist%'
AND ft.TABLESPACE_TYPE = 'TRANSACTION_TABLES'
-- By Column Names
AND fc.description LIKE '%name%'
ORDER BY
ft.table_name, fc.column_sequence
