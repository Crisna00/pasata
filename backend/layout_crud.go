package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// CRUD handlers for warehouse layout and pallet operations.
// Existing schema is reused; no DDL or re-import is required.
func layoutError(w http.ResponseWriter, err error) {
	status := http.StatusInternalServerError
	msg := "Operasi layout gagal"
	if errors.Is(err, pgx.ErrNoRows) {
		status, msg = http.StatusNotFound, "Data tidak ditemukan"
	} else if strings.Contains(strings.ToLower(err.Error()), "duplicate key") ||
		strings.Contains(strings.ToLower(err.Error()), "foreign key") ||
		strings.Contains(strings.ToLower(err.Error()), "check constraint") {
		status, msg = http.StatusConflict, "Data bentrok dengan data terkait atau melanggar aturan kapasitas"
	}
	http.Error(w, msg, status)
}
func parseID(s string) (int64, error) {
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil || id <= 0 {
		return 0, fmt.Errorf("ID tidak valid")
	}
	return id, nil
}
func jsonBody(w http.ResponseWriter, r *http.Request) (map[string]any, error) {
	var body map[string]any
	if err := decodeJSON(w, r, &body); err != nil {
		return nil, err
	}
	return body, nil
}
func strField(m map[string]any, key string) string {
	s, _ := m[key].(string)
	return strings.TrimSpace(s)
}
func intField(m map[string]any, key string, fallback int) int {
	switch v := m[key].(type) {
	case float64:
		return int(v)
	case int:
		return v
	case string:
		n, e := strconv.Atoi(v)
		if e == nil {
			return n
		}
	}
	return fallback
}

func (a *App) racksCRUD(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		areaID, err := parseID(fmt.Sprint(b["warehouse_area_id"]))
		if err != nil {
			http.Error(w, "warehouse_area_id wajib diisi", 400)
			return
		}
		code, name := strField(b, "code"), strField(b, "name")
		if code == "" {
			http.Error(w, "Kode rak wajib diisi", 400)
			return
		}
		// capacity_pallet means slots PER LEVEL, not total rack capacity.
		slotsPerLevel := intField(b, "capacity_pallet", 8)
		levels := intField(b, "level_count", 4)
		if slotsPerLevel < 1 || slotsPerLevel > 500 || levels < 1 || levels > 50 {
			http.Error(w, "Slot per level harus 1-500 dan level harus 1-50", 400)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var rackID int64
		err = tx.QueryRow(ctx, `INSERT INTO racks(warehouse_area_id,code,name,capacity_pallet,status) VALUES($1,$2,$3,$4,'ACTIVE') RETURNING id`, areaID, code, nullString(name), slotsPerLevel).Scan(&rackID)
		if err != nil {
			layoutError(w, err)
			return
		}
		for level := 1; level <= levels; level++ {
			var levelID int64
			err = tx.QueryRow(ctx, `INSERT INTO rack_levels(rack_id,code,level_number) VALUES($1,$2,$3) RETURNING id`, rackID, fmt.Sprintf("%s-L%d", code, level), level).Scan(&levelID)
			if err != nil {
				layoutError(w, err)
				return
			}
			for slot := 1; slot <= slotsPerLevel; slot++ {
				slotCode := fmt.Sprintf("%s-L%d-S%02d", code, level, slot)
				_, err = tx.Exec(ctx, `INSERT INTO rack_slots(rack_level_id,slot_number,code,status) VALUES($1,$2,$3,'EMPTY')`, levelID, slot, slotCode)
				if err != nil {
					layoutError(w, err)
					return
				}
			}
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"id": rackID, "code": code, "name": name, "capacity_pallet": slotsPerLevel, "slots_per_level": slotsPerLevel, "level_count": levels})
	case http.MethodPut, http.MethodDelete:
		idText := strings.TrimPrefix(r.URL.Path, "/api/racks/")
		idText = strings.TrimSuffix(idText, "/")
		id, err := parseID(idText)
		if err != nil {
			http.Error(w, "ID rak tidak valid", 400)
			return
		}
		if r.Method == http.MethodDelete {
			ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
			defer cancel()
			tag, err := a.DB.Exec(ctx, `UPDATE racks SET status='INACTIVE' WHERE id=$1`, id)
			if err != nil {
				layoutError(w, err)
				return
			}
			if tag.RowsAffected() == 0 {
				http.NotFound(w, r)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		name, code := strField(b, "name"), strField(b, "code")
		cap := intField(b, "capacity_pallet", 0) // slots per level
		status := strField(b, "status")
		if code == "" || cap < 1 || cap > 500 {
			http.Error(w, "Kode wajib diisi dan slot per level harus 1-500", 400)
			return
		}
		if status == "" {
			status = "ACTIVE"
		}
		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		_, err = tx.Exec(ctx, `UPDATE racks SET code=$1,name=$2,capacity_pallet=$3,status=$4 WHERE id=$5`, code, nullString(name), cap, status, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		// Reconcile existing levels: capacity_pallet is the number of slots on EACH level.
		rows, err := tx.Query(ctx, `SELECT id, level_number FROM rack_levels WHERE rack_id=$1 ORDER BY level_number`, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		type levelInfo struct {
			id     int64
			number int
		}
		var levels []levelInfo
		for rows.Next() {
			var li levelInfo
			if err = rows.Scan(&li.id, &li.number); err != nil {
				rows.Close()
				layoutError(w, err)
				return
			}
			levels = append(levels, li)
		}
		if err = rows.Err(); err != nil {
			rows.Close()
			layoutError(w, err)
			return
		}
		rows.Close()
		for _, level := range levels {
			var current int
			err = tx.QueryRow(ctx, `SELECT COALESCE(MAX(slot_number),0) FROM rack_slots WHERE rack_level_id=$1`, level.id).Scan(&current)
			if err != nil {
				layoutError(w, err)
				return
			}
			for slot := current + 1; slot <= cap; slot++ {
				slotCode := fmt.Sprintf("%s-L%d-S%02d", code, level.number, slot)
				_, err = tx.Exec(ctx, `INSERT INTO rack_slots(rack_level_id,slot_number,code,status) VALUES($1,$2,$3,'EMPTY')`, level.id, slot, slotCode)
				if err != nil {
					layoutError(w, err)
					return
				}
			}
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "code": code, "name": name, "capacity_pallet": cap, "slots_per_level": cap, "status": status})
	default:
		w.Header().Set("Allow", "GET, POST, PUT, DELETE")
		http.Error(w, "Method tidak diizinkan", 405)
	}
}
func nullString(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.TrimSpace(s)
}

func (a *App) rackLevelsCRUD(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		rackID, err := parseID(fmt.Sprint(b["rack_id"]))
		if err != nil {
			http.Error(w, "rack_id wajib diisi", 400)
			return
		}
		level := intField(b, "level_number", 0)
		slots := intField(b, "slot_count", 0)
		code := strField(b, "code")
		if level < 1 || level > 50 || slots < 0 || slots > 500 {
			http.Error(w, "Level atau jumlah slot tidak valid", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		if code == "" {
			code = fmt.Sprintf("L%d", level)
		}
		var levelID int64
		err = tx.QueryRow(ctx, `INSERT INTO rack_levels(rack_id,code,level_number) VALUES($1,$2,$3) RETURNING id`, rackID, code, level).Scan(&levelID)
		if err != nil {
			layoutError(w, err)
			return
		}
		for i := 1; i <= slots; i++ {
			slotCode := fmt.Sprintf("R%d-L%d-S%02d", rackID, level, i)
			if _, err = tx.Exec(ctx, `INSERT INTO rack_slots(rack_level_id,slot_number,code,status) VALUES($1,$2,$3,'EMPTY')`, levelID, i, slotCode); err != nil {
				layoutError(w, err)
				return
			}
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": levelID, "rack_id": rackID, "level_number": level, "slot_count": slots})
	case http.MethodDelete:
		idText := strings.TrimPrefix(r.URL.Path, "/api/rack-levels/")
		id, err := parseID(idText)
		if err != nil {
			http.Error(w, "ID level tidak valid", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		var occupied bool
		err = a.DB.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM rack_slots s JOIN pallets p ON p.current_slot_id=s.id WHERE s.rack_level_id=$1)`, id).Scan(&occupied)
		if err != nil {
			layoutError(w, err)
			return
		}
		if occupied {
			http.Error(w, "Level masih berisi pallet; pindahkan pallet terlebih dahulu", 409)
			return
		}
		tag, err := a.DB.Exec(ctx, `DELETE FROM rack_levels WHERE id=$1`, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(204)
	default:
		w.Header().Set("Allow", "GET, POST, DELETE")
		http.Error(w, "Method tidak diizinkan", 405)
	}
}
func (a *App) rackSlotsCRUD(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		levelID, err := parseID(fmt.Sprint(b["rack_level_id"]))
		if err != nil {
			http.Error(w, "rack_level_id wajib diisi", 400)
			return
		}
		count := intField(b, "slot_count", 1)
		if count < 1 || count > 500 {
			http.Error(w, "slot_count harus 1-500", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		var rackCode string
		var level int
		err = a.DB.QueryRow(ctx, `SELECT r.code,rl.level_number FROM rack_levels rl JOIN racks r ON r.id=rl.rack_id WHERE rl.id=$1`, levelID).Scan(&rackCode, &level)
		if err != nil {
			layoutError(w, err)
			return
		}
		var max int
		err = a.DB.QueryRow(ctx, `SELECT COALESCE(MAX(slot_number),0) FROM rack_slots WHERE rack_level_id=$1`, levelID).Scan(&max)
		if err != nil {
			layoutError(w, err)
			return
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		for i := 1; i <= count; i++ {
			n := max + i
			code := fmt.Sprintf("%s-L%d-S%02d", rackCode, level, n)
			if _, err = tx.Exec(ctx, `INSERT INTO rack_slots(rack_level_id,slot_number,code,status) VALUES($1,$2,$3,'EMPTY')`, levelID, n, code); err != nil {
				layoutError(w, err)
				return
			}
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"rack_level_id": levelID, "added_slots": count})
	case http.MethodPut:
		idText := strings.TrimPrefix(r.URL.Path, "/api/rack-slots/")
		id, err := parseID(idText)
		if err != nil {
			http.Error(w, "ID slot tidak valid", 400)
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		status := strings.ToUpper(strField(b, "status"))
		if status != "EMPTY" && status != "UNAVAILABLE" {
			http.Error(w, "Status slot hanya dapat diubah menjadi EMPTY atau UNAVAILABLE", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		tag, err := a.DB.Exec(ctx, `UPDATE rack_slots SET status=$1 WHERE id=$2 AND NOT EXISTS(SELECT 1 FROM pallets WHERE current_slot_id=$2)`, status, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			http.Error(w, "Slot tidak ditemukan atau masih ditempati pallet", 409)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "status": status})
	case http.MethodDelete:
		idText := strings.TrimPrefix(r.URL.Path, "/api/rack-slots/")
		id, err := parseID(idText)
		if err != nil {
			http.Error(w, "ID slot tidak valid", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		tag, err := a.DB.Exec(ctx, `DELETE FROM rack_slots WHERE id=$1 AND status='EMPTY' AND NOT EXISTS(SELECT 1 FROM pallets WHERE current_slot_id=$1)`, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			http.Error(w, "Slot tidak ditemukan atau belum kosong", 409)
			return
		}
		w.WriteHeader(204)
	default:
		w.Header().Set("Allow", "GET, POST, PUT, DELETE")
		http.Error(w, "Method tidak diizinkan", 405)
	}
}
func (a *App) palletsCRUD(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		rows, err := a.DB.Query(ctx, `SELECT p.id,p.pallet_code,p.warehouse_id,p.current_slot_id,p.status,p.condition,p.created_at,
			s.code AS slot_code,rl.level_number,r.code AS rack_code
			FROM pallets p LEFT JOIN rack_slots s ON s.id=p.current_slot_id
			LEFT JOIN rack_levels rl ON rl.id=s.rack_level_id LEFT JOIN racks r ON r.id=rl.rack_id
			ORDER BY p.created_at,p.id`)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		result := make([]map[string]any, 0)
		for rows.Next() {
			var id, wid int64
			var code, status, condition string
			var slotID *int64
			var created time.Time
			var slotCode, rackCode *string
			var level *int16
			if err := rows.Scan(&id, &code, &wid, &slotID, &status, &condition, &created, &slotCode, &level, &rackCode); err != nil {
				layoutError(w, err)
				return
			}
			result = append(result, map[string]any{"id": id, "pallet_code": code, "warehouse_id": wid, "current_slot_id": slotID, "status": status, "condition": condition, "created_at": created, "slot_code": slotCode, "level_number": level, "rack_code": rackCode})
		}
		writeJSON(w, 200, result)
	case http.MethodPost:
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		code := strField(b, "pallet_code")
		wid, err := parseID(fmt.Sprint(b["warehouse_id"]))
		if err != nil || code == "" {
			http.Error(w, "Kode pallet dan warehouse_id wajib diisi", 400)
			return
		}
		condition := strings.ToUpper(strField(b, "condition"))
		if condition == "" {
			condition = "GOOD"
		}
		if condition != "GOOD" && condition != "NEEDS_REPAIR" && condition != "DAMAGED" {
			http.Error(w, "condition tidak valid", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		var id int64
		err = a.DB.QueryRow(ctx, `INSERT INTO pallets(pallet_code,warehouse_id,status,condition) VALUES($1,$2,'UNPLACED',$3) RETURNING id`, code, wid, condition).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "pallet_code": code, "warehouse_id": wid, "status": "UNPLACED", "condition": condition})
	default:
		w.Header().Set("Allow", "GET, POST")
		http.Error(w, "Method tidak diizinkan", 405)
	}
}
func (a *App) movePallet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		http.Error(w, "Method tidak diizinkan", 405)
		return
	}
	b, err := jsonBody(w, r)
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	palletID, err := parseID(fmt.Sprint(b["pallet_id"]))
	if err != nil {
		http.Error(w, "pallet_id tidak valid", 400)
		return
	}
	slotID, err := parseID(fmt.Sprint(b["to_slot_id"]))
	if err != nil {
		http.Error(w, "to_slot_id tidak valid", 400)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		layoutError(w, err)
		return
	}
	defer tx.Rollback(ctx)
	var warehouseID int64
	var fromSlot *int64
	var palletStatus string
	err = tx.QueryRow(ctx, `SELECT warehouse_id,current_slot_id,status FROM pallets WHERE id=$1 FOR UPDATE`, palletID).Scan(&warehouseID, &fromSlot, &palletStatus)
	if err != nil {
		layoutError(w, err)
		return
	}
	var slotStatus, rackStatus string
	var slotWarehouse int64
	err = tx.QueryRow(ctx, `SELECT s.status,wa.warehouse_id,r.status FROM rack_slots s JOIN rack_levels rl ON rl.id=s.rack_level_id JOIN racks r ON r.id=rl.rack_id JOIN warehouse_areas wa ON wa.id=r.warehouse_area_id WHERE s.id=$1 FOR UPDATE OF s,r`, slotID).Scan(&slotStatus, &slotWarehouse, &rackStatus)
	if err != nil {
		layoutError(w, err)
		return
	}
	if rackStatus != "ACTIVE" {
		http.Error(w, "Rak tujuan tidak aktif atau sedang pemeliharaan", 409)
		return
	}
	if slotStatus != "EMPTY" {
		http.Error(w, "Slot tujuan tidak kosong", 409)
		return
	}
	if warehouseID != slotWarehouse {
		http.Error(w, "Pallet dan slot harus berada di gudang yang sama", 409)
		return
	}
	_, err = tx.Exec(ctx, `UPDATE rack_slots SET status='EMPTY' WHERE id=$1`, fromSlot)
	if err != nil {
		layoutError(w, err)
		return
	}
	_, err = tx.Exec(ctx, `UPDATE rack_slots SET status='OCCUPIED' WHERE id=$1`, slotID)
	if err != nil {
		layoutError(w, err)
		return
	}
	_, err = tx.Exec(ctx, `UPDATE pallets SET current_slot_id=$1,status='STORED' WHERE id=$2`, slotID, palletID)
	if err != nil {
		layoutError(w, err)
		return
	}
	movementType := "PUTAWAY"
	if fromSlot != nil {
		movementType = "RELOCATION"
	}
	_, err = tx.Exec(ctx, `INSERT INTO pallet_movements(pallet_id,from_slot_id,to_slot_id,movement_type,status,reason,confirmed_at) VALUES($1,$2,$3,$4,'CONFIRMED','Perpindahan melalui Layout Pallet',NOW())`, palletID, fromSlot, slotID, movementType)
	if err != nil {
		layoutError(w, err)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"message": "Perpindahan pallet berhasil disimpan", "pallet_id": palletID, "to_slot_id": slotID, "status": "STORED"})
}
