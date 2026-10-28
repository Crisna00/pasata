package main

import (
	"context"
	"fmt"
	
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Outbound API menggunakan tabel outbound_transactions dan outbound_items sesuai Script-1(4).sql.
func (a *App) outboundTransactionsHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()
	session, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan")
		return
	}
	switch r.Method {
	case http.MethodGet:
		rows, err := a.DB.Query(ctx, `
SELECT t.id,t.transaction_no,t.warehouse_id,t.customer_name,t.destination_address,t.reference_doc_no,
       t.scheduled_at,t.shipped_at,t.status,t.notes,t.created_by,t.validated_by,t.validated_at,t.reject_reason,t.created_at,
       oi.id,oi.sku_id,COALESCE(s.sku_code,''),COALESCE(s.name,''),oi.pallet_item_id,
       COALESCE(pi.pallet_id,0),COALESCE(p.pallet_code,''),oi.outbound_type,oi.packaging_type,oi.packaging_qty,
       oi.qty_requested,oi.qty_picked,oi.weight_kg,oi.is_fifo_compliant,oi.fifo_note,
       COALESCE(d.name,''),COALESCE(v.plate_number,''),m.departure_at
FROM outbound_transactions t
LEFT JOIN outbound_items oi ON oi.outbound_transaction_id=t.id
LEFT JOIN skus s ON s.id=oi.sku_id
LEFT JOIN pallet_items pi ON pi.id=oi.pallet_item_id
LEFT JOIN pallets p ON p.id=pi.pallet_id
LEFT JOIN manifest_outbounds mo ON mo.outbound_transaction_id=t.id
LEFT JOIN manifests m ON m.id=mo.manifest_id
LEFT JOIN drivers d ON d.id=m.driver_id
LEFT JOIN vehicles v ON v.id=m.vehicle_id
WHERE ($1=0 OR t.warehouse_id=$1)
ORDER BY t.created_at DESC,t.id DESC,oi.id`, warehouseFilter(session))
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id, wid, createdBy, itemID, skuID int64
			var validatedBy, palletItemID *int64
			var no, customer, status string
			var destination, refDoc, notes, rejectReason, skuCode, skuName, palletCode, fifoNote, driverName, plate *string
			var scheduled, shipped, validated, departure *time.Time
			var created time.Time
			var palletID int64
			var outType, packType *string
			var packQty int
			var requested, picked, weight float64
			var fifo bool
			if err := rows.Scan(&id, &no, &wid, &customer, &destination, &refDoc, &scheduled, &shipped, &status, &notes, &createdBy, &validatedBy, &validated, &rejectReason, &created, &itemID, &skuID, &skuCode, &skuName, &palletItemID, &palletID, &palletCode, &outType, &packType, &packQty, &requested, &picked, &weight, &fifo, &fifoNote, &driverName, &plate, &departure); err != nil {
				layoutError(w, err)
				return
			}
			out = append(out, map[string]any{"id": id, "transaction_no": no, "warehouse_id": wid, "customer_name": customer, "destination_address": destination, "reference_doc_no": refDoc, "scheduled_at": scheduled, "shipped_at": shipped, "status": status, "notes": notes, "created_by": createdBy, "validated_by": validatedBy, "validated_at": validated, "reject_reason": rejectReason, "created_at": created, "outbound_item_id": itemID, "sku_id": skuID, "sku_code": skuCode, "sku_name": skuName, "pallet_item_id": palletItemID, "pallet_id": palletID, "pallet_code": palletCode, "outbound_type": outType, "packaging_type": packType, "packaging_qty": packQty, "quantity": requested, "qty_requested": requested, "qty_picked": picked, "weight_kg": weight, "is_fifo_compliant": fifo, "fifo_note": fifoNote, "driver_name": driverName, "plate_number": plate, "departure_time": departure})
		}
		if err := rows.Err(); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, out)
	case http.MethodPost:
		role := strings.ToUpper(session.RoleCode)
		if role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" && role != "WAREHOUSE_OPERATOR" && role != "WAREHOUSE_SUPERVISOR" {
			authError(w, 403, "Role tidak memiliki akses pengajuan outbound")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		itemID, err := parseID(fmt.Sprint(b["pallet_item_id"]))
		if err != nil {
			authError(w, 400, "pallet_item_id tidak valid")
			return
		}
		qty, ok := numberField(b, "quantity")
		if !ok || qty <= 0 {
			authError(w, 400, "quantity harus lebih dari 0")
			return
		}
		weight, ok := numberField(b, "weight_kg")
		if !ok || weight < 0 {
			authError(w, 400, "weight_kg tidak valid")
			return
		}
		warehouseID, err := parseID(fmt.Sprint(b["warehouse_id"]))
		if err != nil {
			authError(w, 400, "warehouse_id wajib diisi")
			return
		}
		customer := strings.TrimSpace(strField(b, "customer_name"))
		if customer == "" {
			authError(w, 400, "customer_name wajib diisi")
			return
		}
		if session.WarehouseID != nil && *session.WarehouseID != warehouseID && role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" {
			authError(w, 403, "Transaksi hanya boleh dibuat untuk gudang akun")
			return
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var skuID, palletWarehouseID int64
		var availableQty, availableWeight float64
		var itemStatus string
		err = tx.QueryRow(ctx, `SELECT pi.sku_id,pi.quantity,pi.weight_kg,pi.status,p.warehouse_id FROM pallet_items pi JOIN pallets p ON p.id=pi.pallet_id WHERE pi.id=$1 FOR UPDATE OF pi`, itemID).Scan(&skuID, &availableQty, &availableWeight, &itemStatus, &palletWarehouseID)
		if err != nil {
			if err == pgx.ErrNoRows {
				authError(w, 404, "Isi pallet tidak ditemukan")
				return
			}
			layoutError(w, err)
			return
		}
		if itemStatus != "AVAILABLE" || qty > availableQty || weight > availableWeight+0.0001 {
			authError(w, 409, "Stok tidak tersedia atau jumlah/berat melebihi stok")
			return
		}
		if palletWarehouseID != warehouseID {
			authError(w, 400, "Gudang transaksi tidak sesuai dengan gudang pallet")
			return
		}
		status := strings.ToUpper(strings.TrimSpace(strField(b, "status")))
		if status == "" {
			status = "DRAFT"
		}
		if status != "DRAFT" && status != "WAITING_VERIFICATION" {
			authError(w, 400, "Status awal harus DRAFT atau WAITING_VERIFICATION")
			return
		}
		no := fmt.Sprintf("OUT-%s-%d", time.Now().Format("20060102-150405"), time.Now().UnixNano()%100000)
		var destination, refDoc, notes any
		if v := strings.TrimSpace(strField(b, "destination_address")); v != "" {
			destination = v
		}
		if v := strings.TrimSpace(strField(b, "reference_doc_no")); v != "" {
			refDoc = v
		}
		if v := strings.TrimSpace(strField(b, "notes")); v != "" {
			notes = v
		}
		var scheduled any
		if v := strings.TrimSpace(strField(b, "scheduled_at")); v != "" {
			parsed, e := time.Parse(time.RFC3339, v)
			if e != nil {
				authError(w, 400, "scheduled_at harus format RFC3339")
				return
			}
			scheduled = parsed
		}
		var id int64
		err = tx.QueryRow(ctx, `INSERT INTO outbound_transactions(transaction_no,warehouse_id,customer_name,destination_address,reference_doc_no,scheduled_at,status,notes,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`, no, warehouseID, customer, destination, refDoc, scheduled, status, notes, session.UserID).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		outType := strings.ToUpper(strField(b, "outbound_type"))
		if outType != "FULL" {
			outType = "PARTIAL"
		}
		pack := strings.ToUpper(strField(b, "packaging_type"))
		if pack == "" {
			pack = "CARTON"
		}
		if pack != "CARTON" && pack != "SACK" && pack != "BOX" && pack != "OTHER" {
			authError(w, 400, "packaging_type tidak valid")
			return
		}
		packQty := intField(b, "packaging_qty", 0)
		if packQty < 0 {
			authError(w, 400, "packaging_qty tidak boleh negatif")
			return
		}
		_, err = tx.Exec(ctx, `INSERT INTO outbound_items(outbound_transaction_id,sku_id,pallet_item_id,outbound_type,packaging_type,packaging_qty,qty_requested,qty_picked,weight_kg,is_fifo_compliant,notes) VALUES($1,$2,$3,$4,$5,$6,$7,0,$8,TRUE,$9)`, id, skuID, itemID, outType, pack, packQty, qty, weight, notes)
		if err != nil {
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "transaction_no": no, "status": status, "message": "Draft outbound tersimpan"})
	default:
		w.Header().Set("Allow", "GET, POST")
		authError(w, 405, "Method tidak diizinkan")
	}
}

func (a *App) outboundTransactionActionHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	session, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan")
		return
	}
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/outbound-transactions/"), "/"), "/")
	if len(parts) != 2 {
		authError(w, 404, "Endpoint outbound tidak ditemukan")
		return
	}
	id, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || id <= 0 {
		authError(w, 400, "ID transaksi tidak valid")
		return
	}
	action := strings.ToLower(parts[1])
	role := strings.ToUpper(session.RoleCode)
	isSupervisor := role == "SUPER_ADMIN" || role == "WAREHOUSE_ADMIN" || role == "WAREHOUSE_SUPERVISOR"
	isOperator := role == "SUPER_ADMIN" || role == "WAREHOUSE_ADMIN" || role == "WAREHOUSE_OPERATOR"
	if action == "submit" || action == "complete" {
		if !isOperator {
			authError(w, 403, "Aksi hanya untuk Warehouse Operator")
			return
		}
		from, to := "DRAFT", "WAITING_VERIFICATION"
		query := `UPDATE outbound_transactions SET status=$1 WHERE id=$2 AND status=$3`
		if action == "complete" {
			from, to = "APPROVED", "COMPLETED"
			query = `UPDATE outbound_transactions SET status=$1,completed_at=NOW(),shipped_at=COALESCE(shipped_at,NOW()),updated_at=NOW() WHERE id=$2 AND status=$3`
		}
		res, e := a.DB.Exec(ctx, query, to, id, from)
		if e != nil {
			layoutError(w, e)
			return
		}
		if res.RowsAffected() == 0 {
			authError(w, 409, "Status transaksi tidak sesuai untuk aksi ini")
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "status": to})
		return
	}
	if !isSupervisor {
		authError(w, 403, "Hanya Warehouse Supervisor yang dapat memutuskan outbound")
		return
	}
	if action != "approve" && action != "reject" {
		authError(w, 404, "Aksi tidak dikenal")
		return
	}
	b, err := jsonBody(w, r)
	if err != nil {
		authError(w, 400, err.Error())
		return
	}
	reason := strings.TrimSpace(strField(b, "reason"))
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		layoutError(w, err)
		return
	}
	defer tx.Rollback(ctx)
	var status string
	var warehouseID int64
	err = tx.QueryRow(ctx, `SELECT status,warehouse_id FROM outbound_transactions WHERE id=$1 FOR UPDATE`, id).Scan(&status, &warehouseID)
	if err != nil {
		if err == pgx.ErrNoRows {
			authError(w, 404, "Transaksi outbound tidak ditemukan")
			return
		}
		layoutError(w, err)
		return
	}
	if session.WarehouseID != nil && *session.WarehouseID != warehouseID && role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" {
		authError(w, 403, "Tidak memiliki akses ke gudang transaksi")
		return
	}
	if status != "WAITING_VERIFICATION" {
		authError(w, 409, "Transaksi harus berstatus WAITING_VERIFICATION untuk diputuskan")
		return
	}
	if action == "reject" {
		if reason == "" {
			authError(w, 400, "Alasan penolakan wajib diisi")
			return
		}
		_, err = tx.Exec(ctx, `UPDATE outbound_transactions SET status='REJECTED',validated_by=$1,validated_at=NOW(),reject_reason=$2,updated_at=NOW() WHERE id=$3`, session.UserID, reason, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "status": "REJECTED"})
		return
	}
	rows, err := tx.Query(ctx, `SELECT oi.id,oi.pallet_item_id,oi.qty_requested,oi.weight_kg,pi.sku_id,pi.quantity,pi.weight_kg,pi.received_at FROM outbound_items oi JOIN pallet_items pi ON pi.id=oi.pallet_item_id WHERE oi.outbound_transaction_id=$1 FOR UPDATE OF pi`, id)
	if err != nil {
		layoutError(w, err)
		return
	}
	type line struct {
		outboundItemID, itemID, skuID        int64
		qty, weight, beforeQty, beforeWeight float64
		received                             time.Time
	}
	lines := []line{}
	for rows.Next() {
		var l line
		if e := rows.Scan(&l.outboundItemID, &l.itemID, &l.qty, &l.weight, &l.skuID, &l.beforeQty, &l.beforeWeight, &l.received); e != nil {
			rows.Close()
			layoutError(w, e)
			return
		}
		lines = append(lines, l)
	}
	rows.Close()
	if len(lines) == 0 {
		authError(w, 409, "Transaksi tidak memiliki item outbound")
		return
	}
	for _, l := range lines {
		if l.qty > l.beforeQty || l.weight > l.beforeWeight+0.0001 {
			authError(w, 409, "Stok berubah; kuantitas/berat perlu diperiksa ulang")
			return
		}
		var fifoID int64
		e := tx.QueryRow(ctx, `SELECT id FROM pallet_items WHERE sku_id=$1 AND status='AVAILABLE' AND quantity>0 ORDER BY received_at NULLS LAST,id LIMIT 1`, l.skuID).Scan(&fifoID)
		if e == nil && fifoID != l.itemID {
			authError(w, 409, fmt.Sprintf("Validasi FIFO gagal: item pallet %d harus dikeluarkan lebih dahulu", fifoID))
			return
		}
		if e != nil && e != pgx.ErrNoRows {
			layoutError(w, e)
			return
		}
	}
	for _, l := range lines {
		afterQty := l.beforeQty - l.qty
		afterWeight := l.beforeWeight - l.weight
		if afterQty < 0.005 {
			afterQty = 0
		}
		if afterWeight < 0.005 {
			afterWeight = 0
		}
		itemStatus := "AVAILABLE"
		if afterQty == 0 {
			itemStatus = "DEPLETED"
		}
		if _, err = tx.Exec(ctx, `UPDATE pallet_items SET quantity=$1,weight_kg=$2,status=$3,updated_at=NOW() WHERE id=$4`, afterQty, afterWeight, itemStatus, l.itemID); err != nil {
			layoutError(w, err)
			return
		}
		if _, err = tx.Exec(ctx, `UPDATE outbound_items SET qty_picked=qty_requested,is_fifo_compliant=TRUE,updated_at=NOW() WHERE id=$1`, l.outboundItemID); err != nil {
			layoutError(w, err)
			return
		}
		if _, err = tx.Exec(ctx, `INSERT INTO pallet_item_histories(pallet_item_id,action_type,qty_before,qty_change,qty_after,weight_before,weight_change,weight_after,reference_type,reference_id,performed_by,notes) VALUES($1,'OUTBOUND',$2,$3,$4,$5,$6,$7,'OUTBOUND_TRANSACTION',$8,$9,$10)`, l.itemID, l.beforeQty, -l.qty, afterQty, l.beforeWeight, -l.weight, afterWeight, id, session.UserID, nullString(reason)); err != nil {
			layoutError(w, err)
			return
		}
	}
	if _, err = tx.Exec(ctx, `UPDATE outbound_transactions SET status='APPROVED',validated_by=$1,validated_at=NOW(),updated_at=NOW() WHERE id=$2`, session.UserID, id); err != nil {
		layoutError(w, err)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"id": id, "status": "APPROVED"})
}
