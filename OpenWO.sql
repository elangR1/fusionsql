SELECT 
    org.organization_name AS inventory_organization_name
    , wo.work_order_number AS work_order_name
    , wd.work_definition_header_name AS process_name
    , item.item_number AS Item
    , wo.planned_start_quantity AS planned_quantity
    , wo.completed_quantity AS actual_output_quantity
    , wo.uom_code AS uom
    , TO_CHAR(FROM_TZ(CAST(wo.planned_start_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS Start_date
    , TO_CHAR(FROM_TZ(CAST(wo.closed_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS Close_date
    , TO_CHAR(FROM_TZ(CAST(wo.canceled_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS Canceled_date
    , TO_CHAR(FROM_TZ(CAST(hist.status_change_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS Status_change_date
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
-- Status Joins for history
JOIN wie_wo_statuses_tl status_from ON hist.old_status_id = status_from.wo_status_id 
    AND status_from.language = 'US'
JOIN wie_wo_statuses_tl status_to ON hist.new_status_id = status_to.wo_status_id 
    AND status_to.language = 'US'
-- Join to CURRENT WO status - only include Released and Completed
JOIN wie_wo_statuses_tl cur_status ON wo.work_order_status_id = cur_status.wo_status_id 
    AND cur_status.language = 'US'
    AND UPPER(cur_status.wo_status_name) IN ('RELEASED', 'COMPLETED')
-- Optional Work Definition Join for "Process Name"
LEFT JOIN wis_work_definitions_int wd ON wo.work_definition_id = wd.work_definition_id 
WHERE 
    -- hist.status_change_date BETWEEN TO_DATE('__START_DATE__', 'YYYY-MM-DD') AND TO_DATE('__END_DATE__', 'YYYY-MM-DD')
    hist.status_change_date BETWEEN '__START_DATE__' AND '__END_DATE__'
ORDER BY 
    wo.work_order_number ASC
