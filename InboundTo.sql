SELECT
	rsh.receipt_source_code
	, itoh.ordered_date AS "Order Date"
	, itol.status_lookup AS "TO Status"
	, iodv_source.organization_name AS "TO Source Org"
	, iodv_dest.organization_name AS "TO Destination Org"
	, itoh.header_number AS "TO Number"
	, itol.created_by
	, CASE itol.interface_status_lookup
			WHEN 'INT_WSH' THEN 'Interfaced to Shipping'
			WHEN 'AWT_WSH' THEN 'Awaiting interface to Shipping'
			WHEN 'ERR_WSH' THEN 'Shipping interface error'
			WHEN 'INT_OM' THEN 'Interfaced to Order Management'
			WHEN 'AWT_OM' THEN 'Awaiting interface to Order Management'
			WHEN 'ERR_OM' THEN 'Order Management interface error'
		ELSE itol.interface_status_lookup
		END AS "TO Interface Status"
	, CASE
			WHEN itol.received_qty = itol.requested_qty 
				AND itol.shipped_qty > 0 
				AND itol.delivered_qty > 0
				THEN 'Shipped and Received'
			WHEN itol.shipped_qty > 0
				AND itol.delivered_qty IS NULL
				AND itol.received_qty IS NULL THEN 'In Transit Shipped'
			WHEN itol.shipped_qty > 0
				AND itol.delivered_qty > 0
				AND itol.received_qty IS NULL THEN 'In Transit Delivered'
			WHEN itol.requested_qty > itol.shipped_qty
				AND itol.shipped_qty = itol.received_qty THEN 'Partially Shipped and Partially Received'
			WHEN itol.shipped_qty > 0
				AND itol.received_qty < itol.requested_qty THEN 'Shipped and Partially Received'
			WHEN itol.status_lookup = 'OPEN'
				AND itol.shipped_qty IS NULL THEN 'Awaiting Fulfillment'
		ELSE itol.status_lookup
		END AS "TO Fulfillment Status"
	, itol.need_by_date AS "TO Rq dlv date"
	, TO_CHAR(FROM_TZ(CAST(itoh.creation_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS "TO sch ship date"
	, TO_CHAR(FROM_TZ(CAST(wdd.last_update_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS "TO Last Update"
	, rsh.shipment_header_id 
	, rsh.shipment_num AS "Shipment Number"
	, rsh.gl_date
	, rsh.expected_receipt_date
	, rsh.shipped_date as "act shipped date"
	, rsh.attribute1 "Rcv input By"
	, CASE wdd.released_status
			WHEN 'R' THEN 'Ready to Release'
			WHEN 'S' THEN 'Released to Warehouse'
			WHEN 'Y' THEN 'Staged'
			WHEN 'C' THEN 'Shipped'
			WHEN 'B' THEN 'Backordered'
			WHEN 'N' THEN 'Not Ready for Release'
			WHEN 'D' THEN 'Cancelled'
			WHEN 'X' THEN 'Not Applicable'
		ELSE wdd.released_status
		END AS "Reserve Status"
	, wdd.batch_id AS "No PickWave"
	, wdd.source_line_number AS "TO Lines"
	--, rsl.source_document_code AS inbound_type -- Identifies PO vs TO
	, rsl.line_num "rcv Lines"
	, esi.item_number AS "Item Number"
	, rsl.item_description AS "Item Desc"
	, wdd.lot_number AS "Lot Numb"
	--, wdd.WMS_INTERFACED_FLAG AS "wms ok"
	, itol.requested_qty 
	, rsl.quantity_shipped AS "Shipped Qty"
	, rsl.quantity_received AS "Received Qty"
	, (rsl.quantity_shipped - rsl.quantity_received) AS "InT-Exp Qty"
	, rsl.uom_code
	, rsl.shipment_line_status_code AS "Status"
	-- itol
	, itol.header_id AS "Itol header"
	, itol.requested_qty
	, itol.INTERFACE_STATUS_LOOKUP 
	, itol.delivered_qty
	, itol.received_qty
FROM 
    inv_transfer_order_lines itol  -- ✅ Mulai dari TO Lines agar semua status muncul
JOIN 
    inv_transfer_order_headers itoh 
    ON itol.HEADER_ID = itoh.HEADER_ID
JOIN 
    inv_organization_definitions_v iodv_source 
    ON itol.SOURCE_ORGANIZATION_ID = iodv_source.organization_id  -- ✅ Pakai kolom yang valid
JOIN 
    inv_organization_definitions_v iodv_dest 
    ON itol.DESTINATION_ORGANIZATION_ID = iodv_dest.organization_id  -- ✅ Pakai kolom yang valid
LEFT JOIN 
    egp_system_items_b esi 
    ON itol.INVENTORY_ITEM_ID = esi.inventory_item_id 
    AND itol.DESTINATION_ORGANIZATION_ID = esi.organization_id
LEFT JOIN 
    rcv_shipment_lines rsl 
    ON itol.HEADER_ID = rsl.TRANSFER_ORDER_HEADER_ID 
    AND itol.INVENTORY_ITEM_ID = rsl.item_id
LEFT JOIN 
    rcv_shipment_headers rsh 
    ON rsl.shipment_header_id = rsh.shipment_header_id
LEFT JOIN 
    WSH_DELIVERY_DETAILS wdd 
    ON itoh.HEADER_NUMBER = wdd.sales_order_number 
    AND itol.INVENTORY_ITEM_ID = wdd.inventory_item_id
WHERE
  itoh.ordered_date >= TO_DATE('__START_DATE__', 'YYYY-MM-DD')
  AND itoh.ordered_date < TO_DATE('__END_DATE__', 'YYYY-MM-DD')
__DYNAMIC_FILTERS__
ORDER BY
wdd.source_line_id ASC
, iodv_source.organization_name
