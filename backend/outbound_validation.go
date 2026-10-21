package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Outbound validation: requests remain PENDING until a warehouse supervisor decides.
func (a *App) ensureOutboundValidationSchema(ctx context.Context) error {
	_, err := a.DB.Exec(ctx, `CREATE TABLE IF NOT EXISTS outbound_validation_requests (
  id BIGSERIAL PRIMARY KEY,
  transaction_no TEXT NOT NULL UNIQUE,
  pallet_item_id BIGINT NOT NULL REFERENCES pallet_items(id),
  quantity NUMERIC(18,4) NOT NULL CHECK(quantity > 0),
  weight_kg NUMERIC(18,4) NOT NULL CHECK(weight_kg >= 0),
  notes TEXT NOT NULL DEFAULT '',
  checklist JSONB NOT NULL DEFAULT '[]'::jsonb,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED')),
  requested_by BIGINT,
  decided_by BIGINT,
  decision_note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at TIMESTAMPTZ
 )`)
	return err
}
func (a *App) outboundTransactionsHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	if err := a.ensureOutboundValidationSchema(ctx); err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	session, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan")
		return
	}
	switch r.Method {
	case http.MethodGet:
		rows, err := a.DB.Query(ctx, `SELECT t.id,t.transaction_no,t.pallet_item_id,t.quantity,t.weight_kg,t.notes,t.checklist,t.status,t.requested_by,t.decided_by,t.decision_note,t.created_at,t.decided_at,pi.sku_id,COALESCE(s.sku_code,''),COALESCE(s.name,''),pi.pallet_id,pi.quantity AS available_quantity,pi.weight_kg AS available_weight,COALESCE(pi.batch_no,''),COALESCE(pi.received_at,NOW()) FROM outbound_validation_requests t JOIN pallet_items pi ON pi.id=t.pallet_item_id LEFT JOIN skus s ON s.id=pi.sku_id ORDER BY t.created_at DESC`)
		if err != nil {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id, itemID, skuID, palletID int64
			var reqBy, decBy *int64
			var no, notes, status, decision, code, name, batch string
			var qty, weight, availQty, availWeight float64
			var checklist []byte
			var created time.Time
			var decided *time.Time
			var received time.Time
			if err := rows.Scan(&id, &no, &itemID, &qty, &weight, &notes, &checklist, &status, &reqBy, &decBy, &decision, &created, &decided, &skuID, &code, &name, &palletID, &availQty, &availWeight, &batch, &received); err != nil {
				log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
				return
			}
			var ck any
			_ = json.Unmarshal(checklist, &ck)
			out = append(out, map[string]any{"id": id, "transaction_no": no, "pallet_item_id": itemID, "quantity": qty, "weight_kg": weight, "notes": notes, "checklist": ck, "status": status, "requested_by": reqBy, "decided_by": decBy, "decision_note": decision, "created_at": created, "decided_at": decided, "sku_id": skuID, "sku_code": code, "sku_name": name, "pallet_id": palletID, "available_quantity": availQty, "available_weight": availWeight, "batch_no": batch, "received_at": received})
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
		checklist := b["checklist"]
		arr, ok := checklist.([]any)
		if !ok || len(arr) == 0 {
			authError(w, 400, "Checklist outbound wajib diisi")
			return
		}
		for _, v := range arr {
			m, ok := v.(map[string]any)
			if !ok || m["passed"] != true {
				authError(w, 400, "Semua checklist outbound harus lolos sebelum diajukan")
				return
			}
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var skuID int64
		var availableQty, availableWeight float64
		var received time.Time
		err = tx.QueryRow(ctx, `SELECT sku_id,quantity,weight_kg,COALESCE(received_at,NOW()) FROM pallet_items WHERE id=$1 AND status='AVAILABLE' FOR UPDATE`, itemID).Scan(&skuID, &availableQty, &availableWeight, &received)
		if err != nil {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		if qty > availableQty || weight > availableWeight+0.0001 {
			authError(w, 409, "Quantity/weight melebihi stok tersedia")
			return
		}
		var fifoID int64
		err = tx.QueryRow(ctx, `SELECT id FROM pallet_items WHERE sku_id=$1 AND status='AVAILABLE' AND quantity>0 ORDER BY received_at NULLS LAST,id LIMIT 1`, skuID).Scan(&fifoID)
		if err == nil && fifoID != itemID {
			authError(w, 409, fmt.Sprintf("Validasi FIFO gagal: pallet_item_id %d harus dikeluarkan lebih dahulu", fifoID))
			return
		}
		if err != nil && err != pgx.ErrNoRows {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		raw, _ := json.Marshal(checklist)
		no := fmt.Sprintf("OUT-%s-%d", time.Now().Format("20060102-150405"), itemID)
		var id int64
		err = tx.QueryRow(ctx, `INSERT INTO outbound_validation_requests(transaction_no,pallet_item_id,quantity,weight_kg,notes,checklist,requested_by) VALUES($1,$2,$3,$4,$5,$6::jsonb,$7) RETURNING id`, no, itemID, qty, weight, strField(b, "notes"), string(raw), session.UserID).Scan(&id)
		if err != nil {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "transaction_no": no, "status": "PENDING", "message": "Pengajuan outbound menunggu validasi Warehouse Supervisor"})
	default:
		w.Header().Set("Allow", "GET, POST")
		authError(w, 405, "Method tidak diizinkan")
	}
}
func (a *App) outboundTransactionActionHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	if err := a.ensureOutboundValidationSchema(ctx); err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	session, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan")
		return
	}
	role := strings.ToUpper(session.RoleCode)
	if role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" && role != "WAREHOUSE_SUPERVISOR" {
		authError(w, 403, "Hanya Warehouse Supervisor yang dapat memutuskan outbound")
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
	if action != "approve" && action != "reject" {
		authError(w, 404, "Aksi tidak dikenal")
		return
	}
	b, err := jsonBody(w, r)
	if err != nil {
		authError(w, 400, err.Error())
		return
	}
	decisionNote := strField(b, "reason")
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	defer tx.Rollback(ctx)
	var itemID int64
	var qty, weight float64
	var status string
	err = tx.QueryRow(ctx, `SELECT pallet_item_id,quantity,weight_kg,status FROM outbound_validation_requests WHERE id=$1 FOR UPDATE`, id).Scan(&itemID, &qty, &weight, &status)
	if err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	if status != "PENDING" {
		authError(w, 409, "Transaksi sudah diputuskan dan tidak dapat diubah lagi")
		return
	}
	if action == "reject" {
		if strings.TrimSpace(decisionNote) == "" {
			authError(w, 400, "Alasan reject wajib diisi")
			return
		}
		_, err = tx.Exec(ctx, `UPDATE outbound_validation_requests SET status='REJECTED',decided_by=$1,decision_note=$2,decided_at=NOW() WHERE id=$3`, session.UserID, decisionNote, id)
		if err != nil {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "status": "REJECTED"})
		return
	}
	var skuID int64
	var beforeQty, beforeWeight float64
	var received time.Time
	err = tx.QueryRow(ctx, `SELECT sku_id,quantity,weight_kg,COALESCE(received_at,NOW()) FROM pallet_items WHERE id=$1 AND status='AVAILABLE' FOR UPDATE`, itemID).Scan(&skuID, &beforeQty, &beforeWeight, &received)
	if err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	if qty > beforeQty || weight > beforeWeight+0.0001 {
		authError(w, 409, "Stok berubah; quantity/weight harus divalidasi ulang")
		return
	}
	var fifoID int64
	err = tx.QueryRow(ctx, `SELECT id FROM pallet_items WHERE sku_id=$1 AND status='AVAILABLE' AND quantity>0 ORDER BY received_at NULLS LAST,id LIMIT 1`, skuID).Scan(&fifoID)
	if err == nil && fifoID != itemID {
		authError(w, 409, fmt.Sprintf("Approval ditolak: FIFO belum terpenuhi; item %d harus keluar lebih dahulu", fifoID))
		return
	}
	if err != nil && err != pgx.ErrNoRows {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	afterQty := beforeQty - qty
	afterWeight := beforeWeight - weight
	if afterQty < 0.005 {
		afterQty = 0
	}
	if afterWeight < 0.005 {
		afterWeight = 0
	}
	newStatus := "AVAILABLE"
	if afterQty == 0 {
		newStatus = "DEPLETED"
	}
	if _, err = tx.Exec(ctx, `UPDATE pallet_items SET quantity=$1,weight_kg=$2,status=$3,updated_at=NOW() WHERE id=$4`, afterQty, afterWeight, newStatus, itemID); err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	if _, err = tx.Exec(ctx, `INSERT INTO pallet_item_histories(pallet_item_id,action_type,qty_before,qty_change,qty_after,weight_before,weight_change,weight_after,reference_type,performed_by,notes) VALUES($1,'OUTBOUND',$2,$3,$4,$5,$6,$7,'OUTBOUND_TRANSACTION',$8,$9)`, itemID, beforeQty, -qty, afterQty, beforeWeight, -weight, afterWeight, session.UserID, nullString(decisionNote)); err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	if _, err = tx.Exec(ctx, `UPDATE outbound_validation_requests SET status='APPROVED',decided_by=$1,decision_note=$2,decided_at=NOW() WHERE id=$3`, session.UserID, decisionNote, id); err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		log.Printf("[OUTBOUND VALIDATION] database/transaction error: %v", err)
			layoutError(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"id": id, "status": "APPROVED", "quantity_after": afterQty, "weight_after": afterWeight})
}
