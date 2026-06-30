SELECT
	rsh.receipt_source_code
	, itoh.ordered_date AS Order_Date
	, itol.status_lookup AS TO_Status
	, iodv_source.organization_name AS TO_Source_Org
	, iodv_dest.organization_name AS TO_Destination_Org
	, itoh.header_number AS TO_Number
	, itol.created_by
	, CASE itol.interface_status_lookup
			WHEN 'INT_WSH' THEN 'Interfaced to Shipping'
			WHEN 'AWT_WSH' THEN 'Awaiting interface to Shipping'
			WHEN 'ERR_WSH' THEN 'Shipping interface error'
			WHEN 'INT_OM' THEN 'Interfaced to Order Management'
			WHEN 'AWT_OM' THEN 'Awaiting interface to Order Management'
			WHEN 'ERR_OM' THEN 'Order Management interface error'
		ELSE itol.interface_status_lookup
		END AS TO_Interface_Status
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
		END AS TO_Fulfillment_Status
	, itol.need_by_date AS TO_Rq_dlv_date
	, TO_CHAR(FROM_TZ(CAST(itoh.creation_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS TO_sch_ship_date
	, TO_CHAR(FROM_TZ(CAST(wdd.last_update_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS TO_last_update
	, rsh.shipment_header_id 
	, rsh.shipment_num AS Shipment_Number
	, rsh.gl_date
	, rsh.expected_receipt_date
	, rsh.shipped_date AS Act_shipped_date
	, rsh.attribute1 AS Rcv_input_By
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
		END AS Reserve_Status
	, wdd.batch_id AS No_PickWave
	, wdd.source_line_number AS TO_Lines
	--, rsl.source_document_code AS inbound_type -- Identifies PO vs TO
	, rsl.line_num AS rcv_lines
	, esi.item_number AS item_number
	, rsl.item_description AS item_desc
	, wdd.lot_number AS lot_number
	--, wdd.WMS_INTERFACED_FLAG AS "wms ok"
	, rsl.requested_amount 
	, rsl.quantity_shipped AS shipped_qty
	, rsl.quantity_received AS received_qty
	, (rsl.quantity_shipped - rsl.quantity_received) AS intransit_exp_qty
	, rsl.uom_code
	, rsl.shipment_line_status_code AS status
	-- itol
	, itol.header_id AS itol_header
	, itol.requested_qty AS itol_rq_qty
	, itol.interface_status_lookup
	, itol.delivered_qty
	, itol.received_qty
	, TO_CHAR(FROM_TZ(CAST(itol.creation_date AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Jakarta', 'YY/MM/DD HH24:MI') AS to_creation_date
FROM 
    inv_transfer_order_lines itol
JOIN 
    inv_transfer_order_headers itoh 
    ON itol.header_id = itoh.header_id
JOIN 
    inv_organization_definitions_v iodv_source 
    ON itol.source_organization_id = iodv_source.organization_id
JOIN 
    inv_organization_definitions_v iodv_dest 
    ON itol.destination_organization_id = iodv_dest.organization_id
LEFT JOIN 
    egp_system_items_b esi
    ON itol.inventory_item_id = esi.inventory_item_id 
    AND itol.destination_organization_id = esi.organization_id
LEFT JOIN 
    rcv_shipment_lines rsl 
    ON itol.header_id = rsl.transfer_order_header_id 
    AND itol.inventory_item_id = rsl.item_id
LEFT JOIN 
    rcv_shipment_headers rsh 
    ON rsl.shipment_header_id = rsh.shipment_header_id
LEFT JOIN 
    wsh_delivery_details wdd 
    ON itoh.header_number = wdd.sales_order_number 
    AND itol.inventory_item_id = wdd.inventory_item_id
WHERE
  -- itoh.ordered_date BETWEEN '__START_DATE__' AND '__END_DATE__'
  --  itol.creation_date BETWEEN '__START_DATE__' AND '__END_DATE__
  -- itoh.ordered_date BETWEEN TO_DATE('__START_DATE__', 'YYYY-MM-DD') AND TO_DATE('__END_DATE__', 'YYYY-MM-DD') + 1
  itol.creation_date BETWEEN TO_DATE('__START_DATE__', 'YYYY-MM-DD') AND TO_DATE('__END_DATE__', 'YYYY-MM-DD') + 1
ORDER BY
wdd.source_line_id ASC
, iodv_source.organization_name
