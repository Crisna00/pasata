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

type inboundLineInput struct {
	SKUID         int64    `json:"sku_id"`
	PalletID      *int64   `json:"pallet_id"`
	RackSlotID    *int64   `json:"rack_slot_id"`
	BatchNo       string   `json:"batch_no"`
	ExpiryDate    string   `json:"expiry_date"`
	PackagingType string   `json:"packaging_type"`
	PackagingQty  int      `json:"packaging_qty"`
	QtyExpected   float64  `json:"qty_expected"`
	QtyReceived   float64  `json:"qty_received"`
	WeightKG      float64  `json:"weight_kg"`
	ArrivalTemp   *float64 `json:"arrival_temp"`
	Condition     string   `json:"condition"`
	Notes         string   `json:"notes"`
}
type inboundCreateInput struct {
	WarehouseID    int64              `json:"warehouse_id"`
	SupplierName   string             `json:"supplier_name"`
	ReferenceDocNo string             `json:"reference_doc_no"`
	TruckPlate     string             `json:"truck_plate"`
	DriverName     string             `json:"driver_name"`
	ArrivedAt      string             `json:"arrived_at"`
	Notes          string             `json:"notes"`
	Items          []inboundLineInput `json:"items"`
}

func inboundActorAllowed(s AuthSession) bool {
	return s.RoleCode == "SUPER_ADMIN" || s.RoleCode == "WAREHOUSE_ADMIN" || s.RoleCode == "WAREHOUSE_OPERATOR" || s.RoleCode == "WAREHOUSE_SUPERVISOR"
}
func inboundSupervisor(s AuthSession) bool {
	return s.RoleCode == "SUPER_ADMIN" || s.RoleCode == "WAREHOUSE_ADMIN" || s.RoleCode == "WAREHOUSE_SUPERVISOR"
}
func (a *App) inboundSlotsHandler(w http.ResponseWriter, r *http.Request) {
	session, ok := a.sessionFromRequest(r)
	if !ok || !inboundActorAllowed(session) {
		authError(w, http.StatusForbidden, "Role tidak memiliki akses inbound.")
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		authError(w, 405, "Method tidak diizinkan.")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	warehouseID, err := strconv.ParseInt(strings.TrimSpace(r.URL.Query().Get("warehouse_id")), 10, 64)
	if err != nil || warehouseID <= 0 {
		authError(w, 400, "warehouse_id wajib diisi.")
		return
	}
	if session.WarehouseID != nil && *session.WarehouseID != warehouseID && session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" {
		authError(w, 403, "Tidak memiliki akses ke gudang ini.")
		return
	}
	rows, err := a.DB.Query(ctx, `SELECT s.id,s.code,s.status,r.code,rl.level_number,wa.warehouse_id FROM rack_slots s JOIN rack_levels rl ON rl.id=s.rack_level_id JOIN racks r ON r.id=rl.rack_id JOIN warehouse_areas wa ON wa.id=r.warehouse_area_id WHERE wa.warehouse_id=$1 AND s.status='EMPTY' AND s.slot_number<=COALESCE(r.capacity_pallet,s.slot_number) ORDER BY r.code,rl.level_number,s.slot_number`, warehouseID)
	if err != nil {
		layoutError(w, err)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, wid int64
		var code, status, rack string
		var level int16
		if err := rows.Scan(&id, &code, &status, &rack, &level, &wid); err != nil {
			layoutError(w, err)
			return
		}
		out = append(out, map[string]any{"id": id, "code": code, "status": status, "rack_code": rack, "level_number": level, "warehouse_id": wid})
	}
	if err := rows.Err(); err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) inboundTransactionsHandler(w http.ResponseWriter, r *http.Request) {
	session, ok := a.sessionFromRequest(r)
	if !ok || !inboundActorAllowed(session) {
		authError(w, http.StatusForbidden, "Role tidak memiliki akses inbound.")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()
	switch r.Method {
	case http.MethodGet:
		rows, err := a.DB.Query(ctx, `SELECT t.id,t.transaction_no,t.warehouse_id,w.name,t.supplier_name,t.reference_doc_no,t.truck_plate,t.driver_name,t.arrived_at,t.status,t.notes,t.created_by,t.created_at,
            COALESCE((SELECT COUNT(*) FROM inbound_items i WHERE i.inbound_transaction_id=t.id),0),
            COALESCE((SELECT COUNT(*) FROM transaction_checklists c WHERE c.inbound_transaction_id=t.id AND c.is_passed IS TRUE),0),
            COALESCE((SELECT COUNT(*) FROM transaction_checklists c WHERE c.inbound_transaction_id=t.id),0)
            FROM inbound_transactions t JOIN warehouses w ON w.id=t.warehouse_id
            WHERE ($1=0 OR t.warehouse_id=$1) ORDER BY t.created_at DESC,t.id DESC`, warehouseFilter(session))
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		result := make([]map[string]any, 0)
		for rows.Next() {
			var id, wid, createdBy int64
			var no, whName, supplier, status string
			var ref, plate, driver, notes *string
			var arrived *time.Time
			var created time.Time
			var itemCount, passed, total int
			if err := rows.Scan(&id, &no, &wid, &whName, &supplier, &ref, &plate, &driver, &arrived, &status, &notes, &createdBy, &created, &itemCount, &passed, &total); err != nil {
				layoutError(w, err)
				return
			}
			result = append(result, map[string]any{"id": id, "transaction_no": no, "warehouse_id": wid, "warehouse_name": whName, "supplier_name": supplier, "reference_doc_no": ref, "truck_plate": plate, "driver_name": driver, "arrived_at": arrived, "status": status, "notes": notes, "created_by": createdBy, "created_at": created, "item_count": itemCount, "checklist_passed": passed, "checklist_total": total})
		}
		if err := rows.Err(); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, result)
	case http.MethodPost:
		var in inboundCreateInput
		if err := readAuthJSON(w, r, &in); err != nil {
			authError(w, 400, "Data inbound tidak valid: "+err.Error())
			return
		}
		if in.WarehouseID <= 0 || strings.TrimSpace(in.SupplierName) == "" || len(in.Items) == 0 {
			authError(w, 400, "Gudang, pemasok, dan minimal satu baris barang wajib diisi.")
			return
		}
		if session.WarehouseID != nil && *session.WarehouseID != in.WarehouseID && session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" {
			authError(w, 403, "Transaksi hanya boleh dibuat untuk gudang akun.")
			return
		}
		arrived := time.Now()
		if strings.TrimSpace(in.ArrivedAt) != "" {
			parsed, err := time.Parse(time.RFC3339, in.ArrivedAt)
			if err != nil {
				authError(w, 400, "Format arrived_at harus RFC3339.")
				return
			}
			arrived = parsed
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var whExists bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM warehouses WHERE id=$1 AND status='ACTIVE')`, in.WarehouseID).Scan(&whExists); err != nil {
			layoutError(w, err)
			return
		}
		if !whExists {
			authError(w, 400, "Gudang tidak ditemukan atau tidak aktif.")
			return
		}
		var txID int64
		var txNo string
		err = tx.QueryRow(ctx, `INSERT INTO inbound_transactions(transaction_no,warehouse_id,supplier_name,reference_doc_no,truck_plate,driver_name,arrived_at,status,notes,created_by) VALUES('INB-'||to_char(NOW(),'YYYYMMDD-HH24MISS')||'-'||lpad(nextval(pg_get_serial_sequence('inbound_transactions','id'))::text,5,'0'),$1,$2,$3,$4,$5,$6,'DRAFT',$7,$8) RETURNING id,transaction_no`, in.WarehouseID, strings.TrimSpace(in.SupplierName), nullString(strings.TrimSpace(in.ReferenceDocNo)), nullString(strings.ToUpper(strings.TrimSpace(in.TruckPlate))), nullString(strings.TrimSpace(in.DriverName)), arrived, nullString(strings.TrimSpace(in.Notes)), session.UserID).Scan(&txID, &txNo)
		if err != nil {
			layoutError(w, err)
			return
		}
		for _, it := range in.Items {
			if it.SKUID <= 0 || it.QtyReceived <= 0 || it.WeightKG < 0 || it.PackagingQty < 0 {
				authError(w, 400, "SKU harus dipilih, jumlah diterima harus lebih dari 0, berat dan packaging tidak boleh negatif.")
				return
			}
			pack := strings.ToUpper(strings.TrimSpace(it.PackagingType))
			if pack == "" {
				pack = "CARTON"
			}
			if pack != "CARTON" && pack != "SACK" && pack != "BOX" && pack != "OTHER" {
				authError(w, 400, "Jenis packaging tidak valid.")
				return
			}
			cond := strings.ToUpper(strings.TrimSpace(it.Condition))
			if cond == "" {
				cond = "GOOD"
			}
			if cond != "GOOD" && cond != "DAMAGED" && cond != "EXPIRED" && cond != "TEMP_DEVIATION" {
				authError(w, 400, "Kondisi barang tidak valid.")
				return
			}
			var skuActive bool
			if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM skus WHERE id=$1 AND is_active=TRUE)`, it.SKUID).Scan(&skuActive); err != nil {
				layoutError(w, err)
				return
			}
			if !skuActive {
				authError(w, 400, "SKU tidak ditemukan atau tidak aktif.")
				return
			}
			var pallet any
			if it.PalletID != nil {
				var pwh int64
				var pstatus string
				err = tx.QueryRow(ctx, `SELECT warehouse_id,status FROM pallets WHERE id=$1 FOR UPDATE`, *it.PalletID).Scan(&pwh, &pstatus)
				if err != nil {
					layoutError(w, err)
					return
				}
				if pwh != in.WarehouseID || pstatus == "INACTIVE" {
					authError(w, 400, "Pallet harus aktif dan berada di gudang transaksi.")
					return
				}
				pallet = *it.PalletID
			}
			var slot any
			if it.RackSlotID != nil {
				var slotStatus string
				var slotWarehouse int64
				err = tx.QueryRow(ctx, `SELECT s.status,wa.warehouse_id FROM rack_slots s JOIN rack_levels rl ON rl.id=s.rack_level_id JOIN racks r ON r.id=rl.rack_id JOIN warehouse_areas wa ON wa.id=r.warehouse_area_id WHERE s.id=$1 FOR UPDATE`, *it.RackSlotID).Scan(&slotStatus, &slotWarehouse)
				if err != nil {
					layoutError(w, err)
					return
				}
				if slotStatus != "EMPTY" || slotWarehouse != in.WarehouseID {
					authError(w, 409, "Slot harus kosong dan berada di gudang transaksi.")
					return
				}
				slot = *it.RackSlotID
			}
			var expiry any
			if strings.TrimSpace(it.ExpiryDate) != "" {
				d, e := time.Parse("2006-01-02", it.ExpiryDate)
				if e != nil {
					authError(w, 400, "Tanggal kedaluwarsa tidak valid.")
					return
				}
				expiry = d
			}
			_, err = tx.Exec(ctx, `INSERT INTO inbound_items(inbound_transaction_id,sku_id,pallet_id,rack_slot_id,batch_no,expiry_date,packaging_type,packaging_qty,qty_expected,qty_received,weight_kg,arrival_temp,condition,notes) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`, txID, it.SKUID, pallet, slot, nullString(strings.TrimSpace(it.BatchNo)), expiry, pack, it.PackagingQty, it.QtyExpected, it.QtyReceived, it.WeightKG, it.ArrivalTemp, cond, nullString(strings.TrimSpace(it.Notes)))
			if err != nil {
				layoutError(w, err)
				return
			}
		}
		checklist := []string{"Kesesuaian dokumen dan surat jalan", "Jumlah barang sesuai pemeriksaan", "Berat barang sudah dicatat", "Packaging dan kondisi barang diperiksa", "Batch dan tanggal kedaluwarsa dicatat"}
		for _, item := range checklist {
			if _, err = tx.Exec(ctx, `INSERT INTO transaction_checklists(inbound_transaction_id,checklist_item) VALUES($1,$2)`, txID, item); err != nil {
				layoutError(w, err)
				return
			}
		}
		if _, err = tx.Exec(ctx, `UPDATE inbound_transactions SET status='WAITING_VERIFICATION' WHERE id=$1`, txID); err != nil {
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": txID, "transaction_no": txNo, "status": "WAITING_VERIFICATION", "message": "Registrasi inbound tersimpan dan menunggu verifikasi supervisor."})
	default:
		w.Header().Set("Allow", "GET, POST")
		authError(w, 405, "Method tidak diizinkan.")
	}
}
func warehouseFilter(s AuthSession) int64 {
	if s.WarehouseID == nil || s.RoleCode == "SUPER_ADMIN" || s.RoleCode == "WAREHOUSE_ADMIN" {
		return 0
	}
	return *s.WarehouseID
}

func (a *App) inboundTransactionActionHandler(w http.ResponseWriter, r *http.Request) {
	session, ok := a.sessionFromRequest(r)
	if !ok || !inboundActorAllowed(session) {
		authError(w, 403, "Role tidak memiliki akses inbound.")
		return
	}
	rest := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/inbound-transactions/"), "/")
	parts := strings.Split(rest, "/")
	if len(parts) < 2 {
		authError(w, 404, "Endpoint inbound tidak ditemukan.")
		return
	}
	id, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || id <= 0 {
		authError(w, 400, "ID transaksi tidak valid.")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	switch parts[1] {
	case "reject":
		if r.Method != http.MethodPost {
			authError(w, http.StatusMethodNotAllowed, "Gunakan POST untuk menolak inbound.")
			return
		}
		if !inboundSupervisor(session) {
			authError(w, http.StatusForbidden, "Hanya Warehouse Supervisor/Admin yang dapat menolak inbound.")
			return
		}
		var body struct {
			Reason string `json:"reason"`
		}
		if err := readAuthJSON(w, r, &body); err != nil || strings.TrimSpace(body.Reason) == "" {
			authError(w, http.StatusBadRequest, "Alasan penolakan wajib diisi.")
			return
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var warehouseID int64
		var status string
		if err = tx.QueryRow(ctx, `SELECT warehouse_id,status FROM inbound_transactions WHERE id=$1 FOR UPDATE`, id).Scan(&warehouseID, &status); err != nil {
			layoutError(w, err)
			return
		}
		if status != "WAITING_VERIFICATION" {
			authError(w, http.StatusConflict, "Transaksi harus berstatus WAITING_VERIFICATION untuk ditolak.")
			return
		}
		if session.WarehouseID != nil && *session.WarehouseID != warehouseID && session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" {
			authError(w, http.StatusForbidden, "Tidak memiliki akses ke gudang transaksi.")
			return
		}
		_, err = tx.Exec(ctx, `UPDATE inbound_transactions SET status='REJECTED', notes=concat_ws(E'\n',NULLIF(notes,''),'Alasan penolakan: ' || $1), validated_by=$2, validated_at=NOW(), updated_at=NOW() WHERE id=$3`, strings.TrimSpace(body.Reason), session.UserID, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"message": "Inbound ditolak.", "status": "REJECTED"})
	case "checklist":
		if r.Method != http.MethodPut {
			authError(w, 405, "Gunakan PUT untuk checklist.")
			return
		}
		var body struct {
			Items []struct {
				ID       int64  `json:"id"`
				IsPassed bool   `json:"is_passed"`
				Notes    string `json:"notes"`
			} `json:"items"`
		}
		if err := readAuthJSON(w, r, &body); err != nil {
			authError(w, 400, "Checklist tidak valid.")
			return
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var warehouseID int64
		var status string
		if err = tx.QueryRow(ctx, `SELECT warehouse_id,status FROM inbound_transactions WHERE id=$1 FOR UPDATE`, id).Scan(&warehouseID, &status); err != nil {
			layoutError(w, err)
			return
		}
		if status != "DRAFT" && status != "WAITING_VERIFICATION" {
			authError(w, 409, "Checklist tidak bisa diubah pada status transaksi ini.")
			return
		}
		if session.WarehouseID != nil && *session.WarehouseID != warehouseID && session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" {
			authError(w, 403, "Tidak memiliki akses ke gudang transaksi.")
			return
		}
		for _, item := range body.Items {
			tag, err := tx.Exec(ctx, `UPDATE transaction_checklists SET is_passed=$1,checked_by=$2,checked_at=NOW(),notes=$3,updated_at=NOW() WHERE id=$4 AND inbound_transaction_id=$5`, item.IsPassed, session.UserID, nullString(strings.TrimSpace(item.Notes)), item.ID, id)
			if err != nil {
				layoutError(w, err)
				return
			}
			if tag.RowsAffected() == 0 {
				authError(w, 404, "Item checklist tidak ditemukan pada transaksi ini.")
				return
			}
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, map[string]any{"message": "Checklist inbound disimpan."})
	case "approve":
		if r.Method != http.MethodPost {
			authError(w, 405, "Gunakan POST untuk approval.")
			return
		}
		if !inboundSupervisor(session) {
			authError(w, 403, "Hanya Warehouse Supervisor/Admin yang dapat menyetujui inbound.")
			return
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var warehouseID int64
		var status string
		if err = tx.QueryRow(ctx, `SELECT warehouse_id,status FROM inbound_transactions WHERE id=$1 FOR UPDATE`, id).Scan(&warehouseID, &status); err != nil {
			layoutError(w, err)
			return
		}
		if status != "WAITING_VERIFICATION" {
			authError(w, 409, "Transaksi harus berstatus WAITING_VERIFICATION.")
			return
		}
		if session.WarehouseID != nil && *session.WarehouseID != warehouseID && session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" {
			authError(w, 403, "Tidak memiliki akses ke gudang transaksi.")
			return
		}
		var total, passed int
		if err = tx.QueryRow(ctx, `SELECT COUNT(*),COUNT(*) FILTER(WHERE is_passed IS TRUE) FROM transaction_checklists WHERE inbound_transaction_id=$1`, id).Scan(&total, &passed); err != nil {
			layoutError(w, err)
			return
		}
		if total == 0 || total != passed {
			authError(w, 409, "Semua item checklist harus dinyatakan lolos sebelum approval.")
			return
		}
		rows, err := tx.Query(ctx, `SELECT id,sku_id,pallet_id,rack_slot_id,batch_no,expiry_date,packaging_type,packaging_qty,qty_received,weight_kg,condition FROM inbound_items WHERE inbound_transaction_id=$1 ORDER BY id FOR UPDATE`, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		type rowItem struct {
			id, sku      int64
			pallet, slot *int64
			batch        *string
			expiry       *time.Time
			pack         string
			packQty      int
			qty, weight  float64
			condition    string
		}
		items := []rowItem{}
		for rows.Next() {
			var x rowItem
			if err = rows.Scan(&x.id, &x.sku, &x.pallet, &x.slot, &x.batch, &x.expiry, &x.pack, &x.packQty, &x.qty, &x.weight, &x.condition); err != nil {
				rows.Close()
				layoutError(w, err)
				return
			}
			items = append(items, x)
		}
		rows.Close()
		if err = rows.Err(); err != nil {
			layoutError(w, err)
			return
		}
		for _, x := range items {
			if x.pallet == nil {
				authError(w, 409, "Semua barang harus ditetapkan ke pallet sebelum approval.")
				return
			}
			var pwh int64
			var pstatus string
			var currentSlot *int64
			if err = tx.QueryRow(ctx, `SELECT warehouse_id,status,current_slot_id FROM pallets WHERE id=$1 FOR UPDATE`, *x.pallet).Scan(&pwh, &pstatus, &currentSlot); err != nil {
				layoutError(w, err)
				return
			}
			if pwh != warehouseID || pstatus == "INACTIVE" {
				authError(w, 409, "Pallet tidak valid untuk gudang transaksi.")
				return
			}
			if x.qty <= 0 || x.weight < 0 || x.packQty < 0 {
				authError(w, 409, "Validasi gagal: qty harus lebih dari 0 dan berat/packaging tidak boleh negatif.")
				return
			}
			var skuActive bool
			if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM skus WHERE id=$1 AND is_active=TRUE)`, x.sku).Scan(&skuActive); err != nil {
				layoutError(w, err)
				return
			}
			if !skuActive {
				authError(w, 409, "SKU tidak ditemukan atau sudah tidak aktif.")
				return
			}
			if x.slot != nil {
				var slotStatus string
				var slotWarehouse int64
				err = tx.QueryRow(ctx, `SELECT s.status,wa.warehouse_id FROM rack_slots s JOIN rack_levels rl ON rl.id=s.rack_level_id JOIN racks r ON r.id=rl.rack_id JOIN warehouse_areas wa ON wa.id=r.warehouse_area_id WHERE s.id=$1 FOR UPDATE`, *x.slot).Scan(&slotStatus, &slotWarehouse)
				if err != nil {
					layoutError(w, err)
					return
				}
				if slotWarehouse != warehouseID {
					authError(w, 409, "Slot tujuan harus berada di gudang transaksi.")
					return
				}
				if slotStatus != "EMPTY" && (currentSlot == nil || *currentSlot != *x.slot) {
					authError(w, 409, "Slot tujuan tidak lagi kosong.")
					return
				}
			}
			var piID int64
			err = tx.QueryRow(ctx, `INSERT INTO pallet_items(pallet_id,sku_id,inbound_item_id,batch_no,received_at,expiry_date,packaging_type,initial_quantity,quantity,initial_packaging_qty,packaging_qty,initial_weight_kg,weight_kg,status) VALUES($1,$2,$3,$4,NOW(),$5,$6,$7,$7,$8,$8,$9,$9,'AVAILABLE') RETURNING id`, *x.pallet, x.sku, x.id, x.batch, x.expiry, x.pack, x.qty, x.packQty, x.weight).Scan(&piID)
			if err != nil {
				layoutError(w, err)
				return
			}
			_, err = tx.Exec(ctx, `INSERT INTO pallet_item_histories(pallet_item_id,action_type,qty_before,qty_change,qty_after,weight_before,weight_change,weight_after,reference_type,reference_id,performed_by,notes) VALUES($1,'INBOUND',0,$2,$2,0,$3,$3,'INBOUND',$4,$5,'Gateway Inbound approved')`, piID, x.qty, x.weight, id, session.UserID)
			if err != nil {
				layoutError(w, err)
				return
			}
			if x.slot != nil {
				_, err = tx.Exec(ctx, `UPDATE rack_slots SET status='OCCUPIED',updated_at=NOW() WHERE id=$1`, *x.slot)
				if err != nil {
					layoutError(w, err)
					return
				}
				_, err = tx.Exec(ctx, `UPDATE pallets SET current_slot_id=$1,status='STORED',updated_at=NOW() WHERE id=$2`, *x.slot, *x.pallet)
			} else {
				_, err = tx.Exec(ctx, `UPDATE pallets SET status='UNPLACED',current_slot_id=NULL,updated_at=NOW() WHERE id=$1`, *x.pallet)
			}
			if err != nil {
				layoutError(w, err)
				return
			}
			if x.slot != nil {
				_, err = tx.Exec(ctx, `INSERT INTO pallet_movements(pallet_id,to_slot_id,movement_type,status,reason,moved_by,confirmed_at,notes) VALUES($1,$2,'PUTAWAY','CONFIRMED','Inbound putaway',$3,NOW(),'Lokasi ditetapkan saat approval inbound')`, *x.pallet, *x.slot, session.UserID)
				if err != nil {
					layoutError(w, err)
					return
				}
			}
		}
		_, err = tx.Exec(ctx, `UPDATE inbound_transactions SET status='COMPLETED',validated_by=$1,validated_at=NOW(),completed_at=NOW(),updated_at=NOW() WHERE id=$2`, session.UserID, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, map[string]any{"message": "Inbound disetujui; stok dan riwayat pallet diperbarui.", "status": "COMPLETED"})
	case "detail":
		if r.Method != http.MethodGet {
			authError(w, 405, "Gunakan GET.")
			return
		}
		var wid int64
		err := a.DB.QueryRow(ctx, `SELECT warehouse_id FROM inbound_transactions WHERE id=$1`, id).Scan(&wid)
		if err != nil {
			layoutError(w, err)
			return
		}
		if session.WarehouseID != nil && *session.WarehouseID != wid && session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" {
			authError(w, 403, "Tidak memiliki akses ke gudang transaksi.")
			return
		}
		items, err := a.DB.Query(ctx, `SELECT i.id,i.sku_id,s.sku_code,s.name,i.pallet_id,p.pallet_code,i.rack_slot_id,rs.code AS slot_code,i.batch_no,i.expiry_date,i.packaging_type,i.packaging_qty,i.qty_expected,i.qty_received,i.weight_kg,i.arrival_temp,i.condition,i.notes FROM inbound_items i JOIN skus s ON s.id=i.sku_id LEFT JOIN pallets p ON p.id=i.pallet_id LEFT JOIN rack_slots rs ON rs.id=i.rack_slot_id WHERE i.inbound_transaction_id=$1 ORDER BY i.id`, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer items.Close()
		out := []map[string]any{}
		for items.Next() {
			var iid, sid int64
			var sc, name, pack, cond string
			var pid, slot *int64
			var pc, slotCode, batch, notes *string
			var expiry *time.Time
			var packQty int
			var expected, received, weight float64
			var temp *float64
			if err = items.Scan(&iid, &sid, &sc, &name, &pid, &pc, &slot, &slotCode, &batch, &expiry, &pack, &packQty, &expected, &received, &weight, &temp, &cond, &notes); err != nil {
				layoutError(w, err)
				return
			}
			out = append(out, map[string]any{"id": iid, "sku_id": sid, "sku_code": sc, "sku_name": name, "pallet_id": pid, "pallet_code": pc, "rack_slot_id": slot, "slot_code": slotCode, "batch_no": batch, "expiry_date": expiry, "packaging_type": pack, "packaging_qty": packQty, "qty_expected": expected, "qty_received": received, "weight_kg": weight, "arrival_temp": temp, "condition": cond, "notes": notes})
		}
		if err = items.Err(); err != nil {
			layoutError(w, err)
			return
		}
		cr, err := a.DB.Query(ctx, `SELECT id,checklist_item,is_passed,checked_by,checked_at,notes FROM transaction_checklists WHERE inbound_transaction_id=$1 ORDER BY id`, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer cr.Close()
		checks := []map[string]any{}
		for cr.Next() {
			var cid int64
			var label string
			var passed *bool
			var by *int64
			var at *time.Time
			var notes *string
			if err = cr.Scan(&cid, &label, &passed, &by, &at, &notes); err != nil {
				layoutError(w, err)
				return
			}
			checks = append(checks, map[string]any{"id": cid, "checklist_item": label, "is_passed": passed, "checked_by": by, "checked_at": at, "notes": notes})
		}
		writeJSON(w, 200, map[string]any{"items": out, "checklist": checks})
	default:
		authError(w, 404, "Aksi inbound tidak dikenal.")
	}
}

var _ = fmt.Sprint
var _ = pgx.ErrNoRows
