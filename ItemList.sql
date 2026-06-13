SELECT
esi.inventory_item_id
, esi.item_number AS "Item Code"
, esi.description AS "Item Description"
, ium.UNIT_OF_MEASURE AS "Primary UOM"
, ioc.CONVERSION_RATE 
, esi.secondary_uom_code AS "Secondary UOM"
, iocc.TO_UOM_CODE 
, iocc.CONVERSION_RATE AS "intraclass conv"
, esi.secondary_uom_code AS "Secondary UOM2"
, ics.item_class_name
, ecv.category_code
, ecv.category_name
, iodv.organization_code
, iodv.organization_name AS "Organization Name"
, gcc.CONCATENATED_SEGMENTS AS "SALES Account"
, esi.planner_code
, esi.qty_rcv_exception_code AS "Overreceipt Action"
, esi.qty_rcv_tolerance AS "Overreceipt Tolerance %"
, esi.qty_rcv_tolerance 
, esi.created_by 
, esi.creation_date
, esi.last_update_date
, esi.enabled_flag 
, CASE WHEN esi.lot_control_code = 2 THEN 'Full Lot Control' ELSE 'No Control' END AS "Lot Control Status"
, esi.lot_status_enabled
, esi.lot_split_enabled
, NULL AS "Item Template"
, NULL AS "Assigned Category IDs"
, esi.INVENTORY_ITEM_STATUS_CODE AS "Item Status Code"
, esi.inventory_item_status_code AS "Item Status"
, esi.customer_order_enabled_flag AS "Orderable"
FROM
  EGP_SYSTEM_ITEMS_V esi
LEFT JOIN
  GL_CODE_COMBINATIONS gcc ON gcc.code_combination_id = esi.sales_account
JOIN
  EGP_ITEM_CLASSES_VL ics ON esi.item_catalog_group_id = ics.item_class_id 
JOIN
  INV_UNITS_OF_MEASURE_VL ium ON esi.primary_uom_code = ium.uom_code
JOIN 
  inv_organization_definitions_v iodv ON iodv.organization_id = esi.organization_id
LEFT JOIN
  inv_uom_conversions ioc ON esi.inventory_item_id = ioc.inventory_item_id
  AND esi.primary_uom_code = ioc.uom_code
LEFT JOIN
  inv_uom_class_conversions iocc ON esi.inventory_item_id = iocc.inventory_item_id
  AND ioc.uom_class = iocc.from_uom_class
LEFT JOIN egp_item_cat_assignments eica 
    ON esi.inventory_item_id = eica.inventory_item_id
    AND esi.organization_id = eica.organization_id
LEFT JOIN EGP_CATEGORIES_VL ecv 
    ON eica.category_id = ecv.category_id
WHERE
 esi.ORGANIZATION_ID IS NOT NULL
 AND esi.LAST_UPDATE_DATE >= TO_DATE('__START_DATE__', 'YYYY-MM-DD HH24:MI:SS')
 AND esi.LAST_UPDATE_DATE < TO_DATE('__END_DATE__', 'YYYY-MM-DD HH24:MI:SS')
 __DYNAMIC_FILTERS__
ORDER BY
    esi.item_number, 
    iodv.organization_code, 
    ecv.category_name
