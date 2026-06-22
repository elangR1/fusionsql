SELECT
    bu.bu_name,
    dha.creation_date,
    to_date(to_char(dha.creation_date, 'yyyy-mm-dd'), 'yyyy-mm-dd') AS creation_date2,
    dha.ordered_date,
    dha.order_number,
    dst_h.display_name AS order_status,
    dha.customer_po_number,
    hzp.party_name AS customer_name,
    flvht.meaning AS order_type,
    dheb.attribute_char1 AS input_by,
    dla.line_number,
    esib.item_number AS item_code,
    esit.description AS item_description,
    dla.ordered_qty AS quantity,
    dla.ordered_uom AS uom,
    dfl.request_ship_date,
    dfl.actual_ship_date,
    dst_l.display_name AS line_status,
    iou.organization_name AS io_name
FROM
    doo_headers_all dha
    JOIN doo_lines_all dla ON dha.header_id = dla.header_id
    JOIN doo_fulfill_lines_all dfl ON dla.line_id = dfl.line_id
    JOIN doo_headers_eff_b dheb ON dha.header_id = dheb.header_id
    							AND dheb.cONtext_code = 'Global'
    left JOIN egp_system_items_b esib ON dfl.inventory_item_id = esib.inventory_item_id
                                     AND dfl.inventory_organizatiON_id = esib.organizatiON_id
    left JOIN egp_system_items_tl esit ON esib.inventory_item_id = esit.inventory_item_id
                                        AND esib.organizatiON_id = esit.organizatiON_id
                                        AND esit.language = USERENV('LANG')
    left JOIN inv_organizatiON_definitiONs_v iou ON dfl.fulfill_org_id = iou.organizatiON_id
    left JOIN fun_all_business_units_v bu ON dha.org_id = bu.bu_id
    left JOIN hz_parties hzp ON dha.sold_to_party_id = hzp.party_id
    left JOIN hz_cust_accounts hca ON hzp.party_id = hca.cust_account_id
    left JOIN doo_statuses_b dsb_h ON dha.status_code = dsb_h.status_code
    left JOIN doo_statuses_tl dst_h ON dsb_h.status_id = dst_h.status_id 
                                   AND dst_h.language = userenv('lang')
    left JOIN doo_statuses_b dsb_l ON dfl.status_code = dsb_l.status_code
    left JOIN doo_statuses_tl dst_l ON dsb_l.status_id = dst_l.status_id 
                                   AND dst_l.language = USERENV('LANG')
    left JOIN fnd_lookup_values_vl flvht ON dha.order_type_code = flvht.lookup_code
                                        AND flvht.lookup_type = 'ORA_DOO_ORDER_TYPES'
                                        AND flvht.view_applicatiON_id = 0
WHERE dha.status_code <> 'doo_reference'
    AND trunc(dha.creatiON_date) BETWEEN TO_DATE('__START_DATE__', 'YYYY-MM-DD') AND TO_DATE('__END_DATE__', 'YYYY-MM-DD')
    AND dst_l.display_name NOT IN ('CANCELED','Canceled','Closed')
ORDER BY
    dha.order_number desc nulls last,
    dha.creatiON_date asc nulls last,
    dla.line_number
