WITH WO_Close_Dates AS (
    SELECT 
        h.work_order_id
        , MIN(h.status_change_date) AS first_close_date
        , MAX(h.status_change_date) AS last_close_date
    FROM wie_wo_status_history h
    JOIN wie_wo_statuses_tl s ON h.new_status_id = s.wo_status_id AND s.language = 'US'
    WHERE TRIM(UPPER(s.wo_status_name)) = 'CLOSED'
    GROUP BY h.work_order_id
)
SELECT 
    org.organization_name AS inventory_organization_name
    , wo.work_order_number AS work_order_name
    , wd.work_definition_header_name AS process_name
    , item.item_number AS item
    , wo.planned_start_quantity AS planned_quantity
    , wo.completed_quantity AS actual_output_quantity
    , wo.uom_code AS uom
    , TO_CHAR(FROM_TZ(CAST(wo.planned_start_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS start_date
    , TO_CHAR(FROM_TZ(CAST(wo.closed_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS close_date_system
    , TO_CHAR(FROM_TZ(CAST(wo.canceled_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS canceled_date
    , TO_CHAR(FROM_TZ(CAST(cd.first_close_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS first_close_date
    , TO_CHAR(FROM_TZ(CAST(cd.last_close_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS last_close_date
    , TO_CHAR(FROM_TZ(CAST(hist.status_change_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS status_change_date
    , status_from.wo_status_name AS from_status
    , status_to.wo_status_name AS to_status
    , hist.reason 
    , hist.creation_date AS date_change
FROM 
    wie_wo_status_history hist
JOIN
    wie_work_orders_b wo ON hist.work_order_id = wo.work_order_id
JOIN
    inv_organization_definitions_v org ON hist.organization_id = org.organization_id
JOIN
    egp_system_items_b item ON wo.inventory_item_id = item.inventory_item_id
    AND wo.organization_id = item.organization_id
JOIN 
    wie_wo_statuses_tl status_from ON hist.old_status_id = status_from.wo_status_id 
    AND status_from.language = 'US'
JOIN 
    wie_wo_statuses_tl status_to ON hist.new_status_id = status_to.wo_status_id 
    AND status_to.language = 'US'
LEFT JOIN 
    wis_work_definitions_int wd ON wo.work_definition_id = wd.work_definition_id 
LEFT JOIN
    WO_Close_Dates cd ON wo.work_order_id = cd.work_order_id
WHERE 
	hist.status_change_date BETWEEN '__START_DATE__' AND '__END_DATE__'
ORDER BY 
    wo.work_order_number ASC
