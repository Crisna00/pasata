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
		if slotsPerLevel < 1 || slotsPerLevel > 4 || levels < 1 || levels > 50 {
			http.Error(w, "Slot per level maksimal 4 dan level harus 1-50", 400)
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
		if code == "" || cap < 1 || cap > 4 {
			http.Error(w, "Kode wajib diisi dan slot per level harus 1-4", 400)
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
		// Lock the rack row so two edits cannot reconcile its slots at the same time.
		var lockedRackID int64
		err = tx.QueryRow(ctx, `SELECT id FROM racks WHERE id=$1 FOR UPDATE`, id).Scan(&lockedRackID)
		if errors.Is(err, pgx.ErrNoRows) {
			http.NotFound(w, r)
			return
		}
		if err != nil {
			layoutError(w, err)
			return
		}
		// Reconcile existing levels before updating rack metadata. capacity_pallet is
		// the number of slots on EACH level, not the total rack capacity.
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
			// If an excess slot still contains a pallet, ask the user to move it first.
			var blockedSlotCode string
			err = tx.QueryRow(ctx, `
				SELECT s.code
				FROM rack_slots s
				LEFT JOIN pallets p ON p.current_slot_id=s.id
				WHERE s.rack_level_id=$1 AND s.slot_number>$2
				  AND (p.id IS NOT NULL OR s.status='OCCUPIED')
				ORDER BY s.slot_number LIMIT 1`, level.id, cap).Scan(&blockedSlotCode)
			if err != nil && !errors.Is(err, pgx.ErrNoRows) {
				layoutError(w, err)
				return
			}
			if err == nil {
				http.Error(w, fmt.Sprintf("Pindahkan barang dari slot %s dulu, lalu simpan lagi.", blockedSlotCode), http.StatusConflict)
				return
			}

			// Keep historical slots for audit, but hide them from active layout.
			// Slots with no movement history can be deleted normally.
			_, err = tx.Exec(ctx, `
				UPDATE rack_slots s SET status='UNAVAILABLE'
				WHERE s.rack_level_id=$1 AND s.slot_number>$2
				  AND EXISTS (SELECT 1 FROM pallet_movements pm WHERE pm.from_slot_id=s.id OR pm.to_slot_id=s.id)`, level.id, cap)
			if err != nil {
				layoutError(w, err)
				return
			}
			_, err = tx.Exec(ctx, `
				DELETE FROM rack_slots s
				WHERE s.rack_level_id=$1 AND s.slot_number>$2 AND s.status <> 'UNAVAILABLE'
				  AND NOT EXISTS (SELECT 1 FROM pallet_movements pm WHERE pm.from_slot_id=s.id OR pm.to_slot_id=s.id)`, level.id, cap)
			if err != nil {
				layoutError(w, err)
				return
			}

			// If capacity is increased again, reuse preserved historical slots.
			for slot := 1; slot <= cap; slot++ {
				var slotID int64
				err = tx.QueryRow(ctx, `SELECT id FROM rack_slots WHERE rack_level_id=$1 AND slot_number=$2`, level.id, slot).Scan(&slotID)
				if errors.Is(err, pgx.ErrNoRows) {
					slotCode := fmt.Sprintf("%s-L%d-S%02d", code, level.number, slot)
					err = tx.QueryRow(ctx, `INSERT INTO rack_slots(rack_level_id,slot_number,code,status) VALUES($1,$2,$3,'EMPTY') RETURNING id`, level.id, slot, slotCode).Scan(&slotID)
				} else if err == nil {
					_, err = tx.Exec(ctx, `UPDATE rack_slots SET status='EMPTY' WHERE id=$1 AND status='UNAVAILABLE' AND NOT EXISTS (SELECT 1 FROM pallets WHERE current_slot_id=$1)`, slotID)
				}
				if err != nil {
					layoutError(w, err)
					return
				}
			}
		}
		_, err = tx.Exec(ctx, `UPDATE racks SET code=$1,name=$2,capacity_pallet=$3,status=$4 WHERE id=$5`, code, nullString(name), cap, status, id)
		if err != nil {
			layoutError(w, err)
			return
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
		maxWeight, hasMaxWeight := numberField(b, "max_weight_kg")
		if hasMaxWeight && maxWeight < 0 {
			http.Error(w, "max_weight_kg tidak boleh negatif", 400)
			return
		}
		var maxWeightArg any
		if hasMaxWeight {
			maxWeightArg = maxWeight
		}
		if level < 1 || level > 50 || slots < 0 || slots > 4 {
			http.Error(w, "Level harus 1-50 dan jumlah slot maksimal 4", 400)
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
		err = tx.QueryRow(ctx, `INSERT INTO rack_levels(rack_id,code,level_number,max_weight_kg) VALUES($1,$2,$3,$4) RETURNING id`, rackID, code, level, maxWeightArg).Scan(&levelID)
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
	case http.MethodPut:
		idText := strings.TrimPrefix(r.URL.Path, "/api/rack-levels/")
		id, err := parseID(idText)
		if err != nil {
			http.Error(w, "ID level tidak valid", 400)
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		maxWeight, ok := numberField(b, "max_weight_kg")
		if !ok || maxWeight < 0 {
			http.Error(w, "max_weight_kg harus angka 0 atau lebih", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		// Saving a level limit can optionally apply the same default to each slot
		// on that level. This avoids the confusing state where the level has a
		// limit but every destination slot still has NULL capacity_kg.
		applyToSlots, _ := b["apply_to_slots"].(bool)
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var currentWeight float64
		err = tx.QueryRow(ctx, `SELECT COALESCE(SUM(pi.weight_kg),0) FROM rack_slots sl LEFT JOIN pallets p ON p.current_slot_id=sl.id LEFT JOIN pallet_items pi ON pi.pallet_id=p.id AND pi.status='AVAILABLE' AND pi.quantity>0 WHERE sl.rack_level_id=$1`, id).Scan(&currentWeight)
		if err != nil {
			layoutError(w, err)
			return
		}
		if maxWeight < currentWeight {
			http.Error(w, fmt.Sprintf("Batas level %.2f kg lebih kecil daripada total berat isi pallet %.2f kg", maxWeight, currentWeight), 409)
			return
		}
		tag, err := tx.Exec(ctx, `UPDATE rack_levels SET max_weight_kg=$1,updated_at=NOW() WHERE id=$2`, maxWeight, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			http.NotFound(w, r)
			return
		}
		updatedSlots := int64(0)
		if applyToSlots {
			// The level total is checked above, so assigning the same limit to each
			// slot cannot understate the already-stored load on an individual slot.
			slotTag, err := tx.Exec(ctx, `UPDATE rack_slots SET capacity_kg=$1,updated_at=NOW() WHERE rack_level_id=$2`, maxWeight, id)
			if err != nil {
				layoutError(w, err)
				return
			}
			updatedSlots = slotTag.RowsAffected()
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "max_weight_kg": maxWeight, "apply_to_slots": applyToSlots, "updated_slots": updatedSlots})
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
		w.Header().Set("Allow", "GET, POST, PUT, DELETE")
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
		capacityKg, hasCapacity := numberField(b, "capacity_kg")
		if hasCapacity && capacityKg < 0 {
			http.Error(w, "capacity_kg tidak boleh negatif", 400)
			return
		}
		var capacityArg any
		if hasCapacity {
			capacityArg = capacityKg
		}
		if count < 1 || count > 4 {
			http.Error(w, "slot_count maksimal 4", 400)
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
		var existingCount int
		err = a.DB.QueryRow(ctx, `SELECT COUNT(*) FROM rack_slots WHERE rack_level_id=$1`, levelID).Scan(&existingCount)
		if err != nil {
			layoutError(w, err)
			return
		}
		if existingCount+count > 4 {
			http.Error(w, "Maksimal 4 slot per level. Hapus slot kosong lama terlebih dahulu.", http.StatusConflict)
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
			if _, err = tx.Exec(ctx, `INSERT INTO rack_slots(rack_level_id,slot_number,code,status,capacity_kg) VALUES($1,$2,$3,'EMPTY',$4)`, levelID, n, code, capacityArg); err != nil {
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
		if status != "" && status != "EMPTY" && status != "UNAVAILABLE" && status != "QUARANTINE" && status != "MAINTENANCE" {
			http.Error(w, "Status slot harus EMPTY, UNAVAILABLE, QUARANTINE, atau MAINTENANCE. Status OCCUPIED ditentukan oleh sistem.", 400)
			return
		}
		var capacityArg any
		if raw, exists := b["capacity_kg"]; exists && raw != nil {
			capacity, ok := numberField(b, "capacity_kg")
			if !ok || capacity < 0 {
				http.Error(w, "capacity_kg harus angka 0 atau lebih", 400)
				return
			}
			capacityArg = capacity
		}
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		var occupied bool
		err = a.DB.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pallets WHERE current_slot_id=$1)`, id).Scan(&occupied)
		if err != nil {
			layoutError(w, err)
			return
		}
		if occupied && status != "" {
			http.Error(w, "Status slot tidak dapat diubah selama ditempati pallet", 409)
			return
		}
		if capacityArg != nil {
			var currentWeight float64
			err = a.DB.QueryRow(ctx, `SELECT COALESCE(SUM(pi.weight_kg),0) FROM pallets p LEFT JOIN pallet_items pi ON pi.pallet_id=p.id AND pi.status='AVAILABLE' AND pi.quantity>0 WHERE p.current_slot_id=$1`, id).Scan(&currentWeight)
			if err != nil {
				layoutError(w, err)
				return
			}
			if capValue, ok := capacityArg.(float64); ok && occupied && capValue < currentWeight {
				http.Error(w, fmt.Sprintf("Kapasitas %.2f kg lebih kecil daripada berat isi pallet %.2f kg", capValue, currentWeight), 409)
				return
			}
		}
		if status == "EMPTY" && occupied {
			http.Error(w, "Slot masih ditempati pallet", 409)
			return
		}
		if status == "" && capacityArg == nil {
			http.Error(w, "Tidak ada perubahan yang dikirim", 400)
			return
		}
		var tagRows int64
		if status != "" && capacityArg != nil {
			tag, e := a.DB.Exec(ctx, `UPDATE rack_slots SET status=$1,capacity_kg=$2,updated_at=NOW() WHERE id=$3 AND status <> 'OCCUPIED'`, status, capacityArg, id)
			if e != nil {
				layoutError(w, e)
				return
			}
			tagRows = tag.RowsAffected()
		} else if status != "" {
			tag, e := a.DB.Exec(ctx, `UPDATE rack_slots SET status=$1,updated_at=NOW() WHERE id=$2 AND status <> 'OCCUPIED'`, status, id)
			if e != nil {
				layoutError(w, e)
				return
			}
			tagRows = tag.RowsAffected()
		} else {
			tag, e := a.DB.Exec(ctx, `UPDATE rack_slots SET capacity_kg=$1,updated_at=NOW() WHERE id=$2`, capacityArg, id)
			if e != nil {
				layoutError(w, e)
				return
			}
			tagRows = tag.RowsAffected()
		}
		if tagRows == 0 {
			http.Error(w, "Slot tidak ditemukan atau statusnya dikelola sistem", 409)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "status": status, "capacity_kg": capacityArg})
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
		session, ok := a.sessionFromRequest(r)
		if !ok || (session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" && session.RoleCode != "WAREHOUSE_OPERATOR") {
			http.Error(w, "Role tidak memiliki izin registrasi pallet", http.StatusForbidden)
			return
		}
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
func (a *App) palletDetailCRUD(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		w.Header().Set("Allow", "PUT")
		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)
		return
	}
	session, ok := a.sessionFromRequest(r)
	if !ok || (session.RoleCode != "SUPER_ADMIN" && session.RoleCode != "WAREHOUSE_ADMIN" && session.RoleCode != "WAREHOUSE_OPERATOR") {
		http.Error(w, "Role tidak memiliki izin mengubah pallet", http.StatusForbidden)
		return
	}
	idText := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/pallets/"), "/")
	id, err := parseID(idText)
	if err != nil {
		http.Error(w, "ID pallet tidak valid", http.StatusBadRequest)
		return
	}
	b, err := jsonBody(w, r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	condition := strings.ToUpper(strField(b, "condition"))
	status := strings.ToUpper(strField(b, "status"))
	if condition != "GOOD" && condition != "NEEDS_REPAIR" && condition != "DAMAGED" {
		http.Error(w, "Kondisi pallet tidak valid", http.StatusBadRequest)
		return
	}
	if status != "EMPTY" && status != "UNPLACED" && status != "STORED" && status != "INACTIVE" {
		http.Error(w, "Status pallet tidak valid atau harus melalui proses perpindahan", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	var slotID *int64
	err = a.DB.QueryRow(ctx, `SELECT current_slot_id FROM pallets WHERE id=$1`, id).Scan(&slotID)
	if err != nil {
		layoutError(w, err)
		return
	}
	if slotID != nil && status != "STORED" {
		http.Error(w, "Pallet masih menempati slot. Pindahkan pallet melalui Layout Pallet terlebih dahulu sebelum mengubah statusnya.", http.StatusConflict)
		return
	}
	if slotID == nil && status == "STORED" {
		http.Error(w, "Pallet belum memiliki slot; status STORED hanya dapat ditetapkan melalui Layout Pallet.", http.StatusConflict)
		return
	}
	_, err = a.DB.Exec(ctx, `UPDATE pallets SET condition=$1,status=$2,updated_at=NOW() WHERE id=$3`, condition, status, id)
	if err != nil {
		layoutError(w, err)
		return
	}
	// Return canonical values for the client; no pallet code or location can be changed here.
	var palletID, warehouseID int64
	var code, actualStatus, actualCondition string
	var currentSlot *int64
	var created time.Time
	err = a.DB.QueryRow(ctx, `SELECT id,pallet_code,warehouse_id,current_slot_id,status,condition,created_at FROM pallets WHERE id=$1`, id).Scan(&palletID, &code, &warehouseID, &currentSlot, &actualStatus, &actualCondition, &created)
	if err != nil {
		layoutError(w, err)
		return
	}
	out := map[string]any{"id": palletID, "pallet_code": code, "warehouse_id": warehouseID, "current_slot_id": currentSlot, "status": actualStatus, "condition": actualCondition, "created_at": created}
	writeJSON(w, http.StatusOK, out)
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
	reason := strings.TrimSpace(strField(b, "reason"))
	if reason == "" {
		http.Error(w, "Alasan perpindahan wajib diisi", http.StatusBadRequest)
		return
	}
	slotID, err := parseID(fmt.Sprint(b["to_slot_id"]))
	if err != nil {
		http.Error(w, "to_slot_id tidak valid", 400)
		return
	}
	session, ok := a.sessionFromRequest(r)
	if !ok || session.UserID <= 0 {
		authError(w, http.StatusUnauthorized, "Sesi pengguna tidak ditemukan; silakan login kembali.")
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
	if strings.EqualFold(palletStatus, "INACTIVE") || strings.EqualFold(palletStatus, "DISABLED") {
		http.Error(w, "Pallet tidak aktif dan tidak dapat dipindahkan", http.StatusConflict)
		return
	}
	if fromSlot != nil && *fromSlot == slotID {
		http.Error(w, "Pallet sudah berada di slot tujuan", http.StatusConflict)
		return
	}
	var slotStatus, rackStatus, areaType string
	var slotWarehouse, destinationLevelID int64
	var slotCapacity, levelCapacity *float64
	err = tx.QueryRow(ctx, `SELECT s.status,wa.warehouse_id,r.status,wa.area_type,s.capacity_kg,rl.max_weight_kg,rl.id FROM rack_slots s JOIN rack_levels rl ON rl.id=s.rack_level_id JOIN racks r ON r.id=rl.rack_id JOIN warehouse_areas wa ON wa.id=r.warehouse_area_id WHERE s.id=$1 FOR UPDATE OF s,r,rl`, slotID).Scan(&slotStatus, &slotWarehouse, &rackStatus, &areaType, &slotCapacity, &levelCapacity, &destinationLevelID)
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
	var totalWeight float64
	var itemCount int
	var storageTypeCount int
	var storageType string
	err = tx.QueryRow(ctx, `SELECT COALESCE(SUM(pi.weight_kg),0),COUNT(pi.id),COUNT(DISTINCT s.storage_type),COALESCE(MIN(s.storage_type),'') FROM pallet_items pi JOIN skus s ON s.id=pi.sku_id WHERE pi.pallet_id=$1 AND pi.status='AVAILABLE' AND pi.quantity>0`, palletID).Scan(&totalWeight, &itemCount, &storageTypeCount, &storageType)
	if err != nil {
		layoutError(w, err)
		return
	}
	if itemCount > 0 && slotCapacity == nil {
		http.Error(w, "Kapasitas berat slot tujuan belum diatur. Atur kapasitas Kg slot sebelum menempatkan pallet berisi barang.", 409)
		return
	}
	if slotCapacity != nil && totalWeight > *slotCapacity {
		http.Error(w, fmt.Sprintf("Berat pallet %.2f kg melebihi kapasitas slot %.2f kg", totalWeight, *slotCapacity), 409)
		return
	}
	var otherLevelWeight float64
	err = tx.QueryRow(ctx, `SELECT COALESCE(SUM(pi.weight_kg),0) FROM rack_slots sl JOIN pallets p ON p.current_slot_id=sl.id LEFT JOIN pallet_items pi ON pi.pallet_id=p.id AND pi.status='AVAILABLE' AND pi.quantity>0 WHERE sl.rack_level_id=$1 AND p.id<>$2`, destinationLevelID, palletID).Scan(&otherLevelWeight)
	if err != nil {
		layoutError(w, err)
		return
	}
	if levelCapacity != nil && otherLevelWeight+totalWeight > *levelCapacity {
		http.Error(w, fmt.Sprintf("Total berat level setelah penempatan %.2f kg melebihi batas %.2f kg", otherLevelWeight+totalWeight, *levelCapacity), 409)
		return
	}
	if itemCount > 0 && storageTypeCount > 1 {
		http.Error(w, "Pallet berisi SKU dengan tipe penyimpanan berbeda. Pisahkan isi pallet sebelum penempatan.", 409)
		return
	}
	if itemCount > 0 {
		wantArea := map[string]string{"AMBIENT": "AMBIENT", "CHILLED": "CHILLED", "FROZEN": "FROZEN"}[storageType]
		if wantArea != "" && areaType != wantArea {
			http.Error(w, "Tipe area tujuan tidak sesuai dengan tipe penyimpanan SKU: "+storageType, 409)
			return
		}
	}
	if fromSlot != nil {
		var sourceStatus string
		err = tx.QueryRow(ctx, `SELECT status FROM rack_slots WHERE id=$1 FOR UPDATE`, *fromSlot).Scan(&sourceStatus)
		if err != nil {
			layoutError(w, err)
			return
		}
		if sourceStatus == "EMPTY" {
			http.Error(w, "Status slot asal EMPTY padahal pallet masih menunjuk ke slot tersebut. Periksa konsistensi data sebelum memindahkan.", 409)
			return
		}
	}
	if fromSlot != nil {
		if _, err = tx.Exec(ctx, `UPDATE rack_slots SET status='EMPTY',updated_at=NOW() WHERE id=$1`, *fromSlot); err != nil {
			layoutError(w, err)
			return
		}
	}
	_, err = tx.Exec(ctx, `UPDATE rack_slots SET status='OCCUPIED',updated_at=NOW() WHERE id=$1`, slotID)
	if err != nil {
		layoutError(w, err)
		return
	}
	_, err = tx.Exec(ctx, `UPDATE pallets SET current_slot_id=$1,status='STORED',updated_at=NOW() WHERE id=$2`, slotID, palletID)
	if err != nil {
		layoutError(w, err)
		return
	}
	movementType := "PUTAWAY"
	if fromSlot != nil {
		movementType = "RELOCATION"
	}
	_, err = tx.Exec(ctx, `INSERT INTO pallet_movements(pallet_id,from_slot_id,to_slot_id,movement_type,status,reason,moved_by,moved_at,confirmed_at) VALUES($1,$2,$3,$4,'CONFIRMED',$5,$6,NOW(),NOW())`, palletID, fromSlot, slotID, movementType, reason, session.UserID)
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

// warehouseAreasCRUD adds and edits areas using the existing database schema.
func (a *App) warehouseAreasCRUD(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		warehouseID, err := parseID(fmt.Sprint(b["warehouse_id"]))
		code, name := strField(b, "code"), strField(b, "name")
		areaType := strings.ToUpper(strField(b, "area_type"))
		status := strings.ToUpper(strField(b, "status"))
		if err != nil || code == "" || name == "" {
			http.Error(w, "warehouse_id, code, dan name wajib diisi", http.StatusBadRequest)
			return
		}
		if !validAreaType(areaType) {
			http.Error(w, "area_type tidak valid", http.StatusBadRequest)
			return
		}
		if status == "" {
			status = "ACTIVE"
		}
		if !validLayoutStatus(status) {
			http.Error(w, "status tidak valid", http.StatusBadRequest)
			return
		}
		capacity := intField(b, "capacity_pallet", -1)
		if capacity < -1 {
			http.Error(w, "capacity_pallet tidak boleh negatif", http.StatusBadRequest)
			return
		}
		var capacityArg any
		if capacity >= 0 {
			capacityArg = capacity
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		var id int64
		err = a.DB.QueryRow(ctx, `INSERT INTO warehouse_areas(warehouse_id,code,name,area_type,capacity_pallet,description,status)
			VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`, warehouseID, code, name, areaType, capacityArg, nullString(strField(b, "description")), status).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"id": id, "warehouse_id": warehouseID, "code": code, "name": name, "area_type": areaType, "capacity_pallet": capacityArg, "status": status})
	case http.MethodPut, http.MethodDelete:
		id, err := parseID(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/warehouse-areas/"), "/"))
		if err != nil {
			http.Error(w, "ID area tidak valid", http.StatusBadRequest)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		if r.Method == http.MethodDelete {
			tag, e := a.DB.Exec(ctx, `UPDATE warehouse_areas SET status='INACTIVE',updated_at=NOW() WHERE id=$1`, id)
			if e != nil {
				layoutError(w, e)
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
		warehouseID, err := parseID(fmt.Sprint(b["warehouse_id"]))
		code, name := strField(b, "code"), strField(b, "name")
		areaType, status := strings.ToUpper(strField(b, "area_type")), strings.ToUpper(strField(b, "status"))
		if err != nil || code == "" || name == "" {
			http.Error(w, "warehouse_id, code, dan name wajib diisi", 400)
			return
		}
		if !validAreaType(areaType) || !validLayoutStatus(status) {
			http.Error(w, "area_type atau status tidak valid", 400)
			return
		}
		capacity := intField(b, "capacity_pallet", -1)
		if capacity < -1 {
			http.Error(w, "capacity_pallet tidak boleh negatif", 400)
			return
		}
		var capArg any
		if capacity >= 0 {
			capArg = capacity
		}
		tag, err := a.DB.Exec(ctx, `UPDATE warehouse_areas SET warehouse_id=$1,code=$2,name=$3,area_type=$4,capacity_pallet=$5,description=$6,status=$7,updated_at=NOW() WHERE id=$8`,
			warehouseID, code, name, areaType, capArg, nullString(strField(b, "description")), status, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			http.NotFound(w, r)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "warehouse_id": warehouseID, "code": code, "name": name, "area_type": areaType, "capacity_pallet": capArg, "status": status})
	default:
		w.Header().Set("Allow", "GET, POST, PUT, DELETE")
		http.Error(w, "Method tidak diizinkan", 405)
	}
}

func (a *App) coldStoragesCRUD(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		areaID, err := parseID(fmt.Sprint(b["warehouse_area_id"]))
		code, name := strField(b, "code"), strField(b, "name")
		kind := strings.ToUpper(strField(b, "storage_type"))
		status := strings.ToUpper(strField(b, "status"))
		minTemp, minOK := numberField(b, "min_temp")
		maxTemp, maxOK := numberField(b, "max_temp")
		if err != nil || code == "" || name == "" || !minOK || !maxOK {
			http.Error(w, "warehouse_area_id, code, name, min_temp, max_temp wajib diisi", 400)
			return
		}
		if kind != "CHILLED" && kind != "FROZEN" {
			http.Error(w, "storage_type harus CHILLED atau FROZEN", 400)
			return
		}
		if minTemp > maxTemp {
			http.Error(w, "min_temp tidak boleh lebih besar dari max_temp", 400)
			return
		}
		if status == "" {
			status = "ACTIVE"
		}
		if !validLayoutStatus(status) {
			http.Error(w, "status tidak valid", 400)
			return
		}
		capacity := intField(b, "capacity_pallet", -1)
		if capacity < -1 {
			http.Error(w, "capacity_pallet tidak boleh negatif", 400)
			return
		}
		var capArg any
		if capacity >= 0 {
			capArg = capacity
		}
		current, currentOK := numberField(b, "current_temp")
		var currentArg any
		if currentOK {
			currentArg = current
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		var id int64
		err = a.DB.QueryRow(ctx, `INSERT INTO cold_storages(warehouse_area_id,code,name,storage_type,min_temp,max_temp,current_temp,capacity_pallet,status)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`, areaID, code, name, kind, minTemp, maxTemp, currentArg, capArg, status).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "warehouse_area_id": areaID, "code": code, "name": name, "storage_type": kind, "min_temp": minTemp, "max_temp": maxTemp, "current_temp": currentArg, "capacity_pallet": capArg, "status": status})
	case http.MethodPut, http.MethodDelete:
		id, err := parseID(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/cold-storages/"), "/"))
		if err != nil {
			http.Error(w, "ID cold storage tidak valid", 400)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		if r.Method == http.MethodDelete {
			tag, e := a.DB.Exec(ctx, `UPDATE cold_storages SET status='INACTIVE',updated_at=NOW() WHERE id=$1`, id)
			if e != nil {
				layoutError(w, e)
				return
			}
			if tag.RowsAffected() == 0 {
				http.NotFound(w, r)
				return
			}
			w.WriteHeader(204)
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		areaID, err := parseID(fmt.Sprint(b["warehouse_area_id"]))
		code, name := strField(b, "code"), strField(b, "name")
		kind, status := strings.ToUpper(strField(b, "storage_type")), strings.ToUpper(strField(b, "status"))
		minTemp, minOK := numberField(b, "min_temp")
		maxTemp, maxOK := numberField(b, "max_temp")
		if err != nil || code == "" || name == "" || !minOK || !maxOK {
			http.Error(w, "Data cold storage wajib belum lengkap", 400)
			return
		}
		if (kind != "CHILLED" && kind != "FROZEN") || !validLayoutStatus(status) || minTemp > maxTemp {
			http.Error(w, "storage_type, status, atau rentang suhu tidak valid", 400)
			return
		}
		capacity := intField(b, "capacity_pallet", -1)
		if capacity < -1 {
			http.Error(w, "capacity_pallet tidak boleh negatif", 400)
			return
		}
		var capArg any
		if capacity >= 0 {
			capArg = capacity
		}
		current, currentOK := numberField(b, "current_temp")
		var currentArg any
		if currentOK {
			currentArg = current
		}
		tag, err := a.DB.Exec(ctx, `UPDATE cold_storages SET warehouse_area_id=$1,code=$2,name=$3,storage_type=$4,min_temp=$5,max_temp=$6,current_temp=$7,capacity_pallet=$8,status=$9,updated_at=NOW() WHERE id=$10`,
			areaID, code, name, kind, minTemp, maxTemp, currentArg, capArg, status, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			http.NotFound(w, r)
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "warehouse_area_id": areaID, "code": code, "name": name, "storage_type": kind, "min_temp": minTemp, "max_temp": maxTemp, "current_temp": currentArg, "capacity_pallet": capArg, "status": status})
	default:
		w.Header().Set("Allow", "GET, POST, PUT, DELETE")
		http.Error(w, "Method tidak diizinkan", 405)
	}
}

// skusHandler manages Master SKU and supplies SKU data to pallet-content forms.
func (a *App) skusHandler(w http.ResponseWriter, r *http.Request) {
	path := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/skus"), "/")
	var id int64
	if path != "" {
		parsed, err := parseID(path)
		if err != nil {
			http.Error(w, "ID SKU tidak valid", http.StatusBadRequest)
			return
		}
		id = parsed
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	switch r.Method {
	case http.MethodGet:
		rows, err := a.DB.Query(ctx, `SELECT id,sku_code,barcode,name,category,unit,storage_type,min_temp,max_temp,weight_per_unit,shelf_life_days,is_active,created_at,updated_at FROM skus ORDER BY name,sku_code`)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		out := make([]map[string]any, 0)
		for rows.Next() {
			var sid int64
			var code, name, unit, storage string
			var barcode, category *string
			var minTemp, maxTemp, weight *float64
			var shelf *int
			var active bool
			var created, updated time.Time
			if err := rows.Scan(&sid, &code, &barcode, &name, &category, &unit, &storage, &minTemp, &maxTemp, &weight, &shelf, &active, &created, &updated); err != nil {
				layoutError(w, err)
				return
			}
			out = append(out, map[string]any{"id": sid, "sku_code": code, "barcode": barcode, "name": name, "category": category, "unit": unit, "storage_type": storage, "min_temp": minTemp, "max_temp": maxTemp, "weight_per_unit": weight, "shelf_life_days": shelf, "is_active": active, "created_at": created, "updated_at": updated})
		}
		if err := rows.Err(); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, out)
	case http.MethodPost, http.MethodPut:
		if r.Method == http.MethodPut && id == 0 {
			http.Error(w, "ID SKU wajib untuk edit", 400)
			return
		}
		if r.Method == http.MethodPost && id != 0 {
			http.Error(w, "Gunakan POST /api/skus untuk tambah SKU", 400)
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			http.Error(w, "JSON tidak valid", 400)
			return
		}
		code, name, unit, storage := strings.ToUpper(strField(b, "sku_code")), strField(b, "name"), strings.ToUpper(strField(b, "unit")), strings.ToUpper(strField(b, "storage_type"))
		if code == "" || name == "" {
			http.Error(w, "sku_code dan name wajib diisi", 400)
			return
		}
		if unit == "" {
			unit = "KG"
		}
		if storage == "" {
			storage = "FROZEN"
		}
		if unit != "KG" && unit != "PCS" && unit != "CARTON" && unit != "SACK" && unit != "BOX" && unit != "PACK" {
			http.Error(w, "unit tidak valid", 400)
			return
		}
		if storage != "AMBIENT" && storage != "CHILLED" && storage != "FROZEN" {
			http.Error(w, "storage_type tidak valid", 400)
			return
		}
		nullableString := func(key string) any {
			v := strField(b, key)
			if v == "" {
				return nil
			}
			return v
		}
		nullableNumber := func(key string) (any, error) {
			raw, exists := b[key]
			if !exists || raw == nil || strings.TrimSpace(fmt.Sprint(raw)) == "" {
				return nil, nil
			}
			n, ok := numberField(b, key)
			if !ok {
				return nil, fmt.Errorf("%s harus berupa angka", key)
			}
			return n, nil
		}
		minTemp, err := nullableNumber("min_temp")
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		maxTemp, err := nullableNumber("max_temp")
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		weight, err := nullableNumber("weight_per_unit")
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if minTemp != nil && maxTemp != nil && minTemp.(float64) > maxTemp.(float64) {
			http.Error(w, "min_temp tidak boleh lebih besar dari max_temp", 400)
			return
		}
		if weight != nil && weight.(float64) < 0 {
			http.Error(w, "weight_per_unit tidak boleh negatif", 400)
			return
		}
		var shelf any
		if raw, exists := b["shelf_life_days"]; exists && raw != nil && strings.TrimSpace(fmt.Sprint(raw)) != "" {
			n, ok := numberField(b, "shelf_life_days")
			if !ok || n < 0 || n != float64(int(n)) {
				http.Error(w, "shelf_life_days harus bilangan bulat nol atau lebih", 400)
				return
			}
			shelf = int(n)
		}
		active := true
		if v, exists := b["is_active"]; exists {
			if flag, ok := v.(bool); ok {
				active = flag
			}
		}
		var resultID int64
		var query string
		args := []any{code, nullableString("barcode"), name, nullableString("category"), unit, storage, minTemp, maxTemp, weight, shelf, active}
		if r.Method == http.MethodPost {
			query = `INSERT INTO skus(sku_code,barcode,name,category,unit,storage_type,min_temp,max_temp,weight_per_unit,shelf_life_days,is_active) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`
			err = a.DB.QueryRow(ctx, query, args...).Scan(&resultID)
		} else {
			args = append(args, id)
			query = `UPDATE skus SET sku_code=$1,barcode=$2,name=$3,category=$4,unit=$5,storage_type=$6,min_temp=$7,max_temp=$8,weight_per_unit=$9,shelf_life_days=$10,is_active=$11,updated_at=NOW() WHERE id=$12 RETURNING id`
			err = a.DB.QueryRow(ctx, query, args...).Scan(&resultID)
		}
		if err != nil {
			layoutError(w, err)
			return
		}
		status := http.StatusOK
		if r.Method == http.MethodPost {
			status = http.StatusCreated
		}
		writeJSON(w, status, map[string]any{"id": resultID, "sku_code": code, "name": name, "unit": unit, "storage_type": storage, "is_active": active})
	case http.MethodDelete:
		if id == 0 {
			http.Error(w, "ID SKU wajib", 400)
			return
		}
		tag, err := a.DB.Exec(ctx, `UPDATE skus SET is_active=FALSE,updated_at=NOW() WHERE id=$1 AND is_active=TRUE`, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			http.Error(w, "SKU tidak ditemukan atau sudah nonaktif", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"id": id, "is_active": false, "message": "SKU dinonaktifkan; data historis dipertahankan"})
	default:
		w.Header().Set("Allow", "GET, POST, PUT, DELETE")
		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)
	}
}

// palletItemsHandler lists and adds stock contents to pallets.
func (a *App) palletItemsHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	switch r.Method {
	case http.MethodGet:
		palletID, err := parseID(r.URL.Query().Get("pallet_id"))
		if err != nil {
			http.Error(w, "pallet_id wajib diisi", 400)
			return
		}
		rows, err := a.DB.Query(ctx, `SELECT pi.id,pi.pallet_id,pi.sku_id,s.sku_code,s.name,s.unit,pi.batch_no,pi.received_at,pi.expiry_date,pi.initial_quantity,pi.quantity,pi.initial_weight_kg,pi.weight_kg,pi.packaging_type,pi.initial_packaging_qty,pi.packaging_qty,pi.status FROM pallet_items pi JOIN skus s ON s.id=pi.sku_id WHERE pi.pallet_id=$1 ORDER BY pi.received_at,pi.id`, palletID)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		out := make([]map[string]any, 0)
		for rows.Next() {
			var id, pid, sid int64
			var code, name, unit, pack, status string
			var batch *string
			var received time.Time
			var expiry *time.Time
			var initialQty, qty, initialWeight, weight float64
			var initialPackQty, packQty int
			if err := rows.Scan(&id, &pid, &sid, &code, &name, &unit, &batch, &received, &expiry, &initialQty, &qty, &initialWeight, &weight, &pack, &initialPackQty, &packQty, &status); err != nil {
				layoutError(w, err)
				return
			}
			out = append(out, map[string]any{"id": id, "pallet_id": pid, "sku_id": sid, "sku_code": code, "sku_name": name, "unit": unit, "batch_no": batch, "received_at": received, "expiry_date": expiry, "initial_quantity": initialQty, "quantity": qty, "initial_weight_kg": initialWeight, "weight_kg": weight, "packaging_type": pack, "initial_packaging_qty": initialPackQty, "packaging_qty": packQty, "status": status})
		}
		if err := rows.Err(); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, out)
	case http.MethodPost:
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
		skuID, err := parseID(fmt.Sprint(b["sku_id"]))
		if err != nil {
			http.Error(w, "sku_id tidak valid", 400)
			return
		}
		qty, ok := numberField(b, "quantity")
		if !ok || qty <= 0 {
			http.Error(w, "quantity harus lebih dari 0", 400)
			return
		}
		weight, ok := numberField(b, "weight_kg")
		if !ok || weight < 0 {
			http.Error(w, "weight_kg harus 0 atau lebih", 400)
			return
		}
		pack := strings.ToUpper(strField(b, "packaging_type"))
		if pack == "" {
			pack = "CARTON"
		}
		if pack != "CARTON" && pack != "SACK" && pack != "BOX" && pack != "OTHER" {
			http.Error(w, "packaging_type tidak valid", 400)
			return
		}
		batch := nullString(strField(b, "batch_no"))
		receivedAt := time.Now()
		if raw := strField(b, "received_at"); raw != "" {
			parsed, e := time.Parse(time.RFC3339, raw)
			if e != nil {
				http.Error(w, "received_at tidak valid", 400)
				return
			}
			receivedAt = parsed
		}
		var expiry any
		if raw := strField(b, "expiry_date"); raw != "" {
			parsed, e := time.Parse("2006-01-02", raw)
			if e != nil {
				http.Error(w, "expiry_date tidak valid", 400)
				return
			}
			expiry = parsed
		}
		packQty := intField(b, "packaging_qty", 0)
		if packQty < 0 {
			http.Error(w, "packaging_qty tidak boleh negatif", 400)
			return
		}
		tx, err := a.DB.Begin(ctx)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer tx.Rollback(ctx)
		var exists bool
		err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pallets WHERE id=$1 AND status<>'INACTIVE')`, palletID).Scan(&exists)
		if err != nil {
			layoutError(w, err)
			return
		}
		if !exists {
			http.Error(w, "Pallet tidak ditemukan atau nonaktif", 404)
			return
		}
		var id int64
		err = tx.QueryRow(ctx, `INSERT INTO pallet_items(pallet_id,sku_id,batch_no,received_at,expiry_date,packaging_type,initial_quantity,quantity,initial_packaging_qty,packaging_qty,initial_weight_kg,weight_kg,status) VALUES($1,$2,$3,$4,$5,$6,$7,$7,$8,$8,$9,$9,'AVAILABLE') RETURNING id`, palletID, skuID, batch, receivedAt, expiry, pack, qty, packQty, weight).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		_, err = tx.Exec(ctx, `INSERT INTO pallet_item_histories(pallet_item_id,action_type,qty_before,qty_change,qty_after,weight_before,weight_change,weight_after,reference_type,notes) VALUES($1,'CONTENT_UPDATE',0,$2,$2,0,$3,$3,'MANUAL','Isi pallet ditambahkan melalui UI PASATA')`, id, qty, weight)
		if err != nil {
			layoutError(w, err)
			return
		}
		if err = tx.Commit(ctx); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "pallet_id": palletID, "sku_id": skuID, "quantity": qty, "weight_kg": weight, "status": "AVAILABLE"})
	default:
		w.Header().Set("Allow", "GET, POST")
		http.Error(w, "Method tidak diizinkan", 405)
	}
}

func validLayoutStatus(s string) bool { return s == "ACTIVE" || s == "INACTIVE" || s == "MAINTENANCE" }
func validAreaType(s string) bool {
	switch s {
	case "AMBIENT", "CHILLED", "FROZEN", "DOCK", "STAGING", "AISLE":
		return true
	}
	return false
}
func numberField(m map[string]any, key string) (float64, bool) {
	switch v := m[key].(type) {
	case float64:
		return v, true
	case int:
		return float64(v), true
	case string:
		n, e := strconv.ParseFloat(strings.TrimSpace(v), 64)
		return n, e == nil
	default:
		return 0, false
	}
}

// palletItemOutboundHandler records a partial outbound atomically and writes history.
func (a *App) palletItemOutboundHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		http.Error(w, "Method tidak diizinkan", 405)
		return
	}
	session, ok := a.sessionFromRequest(r)
	if !ok {
		http.Error(w, "Login diperlukan", 401)
		return
	}
	role := strings.ToUpper(session.RoleCode)
	if role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" && role != "WAREHOUSE_OPERATOR" && role != "WAREHOUSE_SUPERVISOR" {
		http.Error(w, "Role tidak memiliki akses barang keluar", 403)
		return
	}
	b, err := jsonBody(w, r)
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	itemID, err := parseID(fmt.Sprint(b["pallet_item_id"]))
	if err != nil {
		http.Error(w, "pallet_item_id tidak valid", 400)
		return
	}
	qty, ok := numberField(b, "quantity")
	if !ok || qty <= 0 {
		http.Error(w, "quantity harus lebih dari 0", 400)
		return
	}
	weight, ok := numberField(b, "weight_kg")
	if !ok || weight < 0 {
		http.Error(w, "weight_kg harus 0 atau lebih", 400)
		return
	}
	notes := strField(b, "notes")
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		layoutError(w, err)
		return
	}
	defer tx.Rollback(ctx)
	var palletID int64
	var qtyBefore, weightBefore float64
	var packQty int
	err = tx.QueryRow(ctx, `SELECT pallet_id,quantity,weight_kg,packaging_qty FROM pallet_items WHERE id=$1 AND status='AVAILABLE' FOR UPDATE`, itemID).Scan(&palletID, &qtyBefore, &weightBefore, &packQty)
	if err != nil {
		if err == pgx.ErrNoRows {
			http.Error(w, "Isi pallet tidak ditemukan atau stok habis", 404)
		} else {
			layoutError(w, err)
		}
		return
	}
	if qty > qtyBefore {
		http.Error(w, "Jumlah keluar melebihi stok tersisa", 409)
		return
	}
	if weight > weightBefore+0.0001 {
		http.Error(w, "Berat keluar melebihi berat tersisa", 409)
		return
	}
	qtyAfter := qtyBefore - qty
	weightAfter := weightBefore - weight
	if qtyAfter < 0.005 {
		qtyAfter = 0
	}
	if weightAfter < 0.005 {
		weightAfter = 0
	}
	status := "AVAILABLE"
	if qtyAfter == 0 {
		status = "DEPLETED"
	}
	_, err = tx.Exec(ctx, `UPDATE pallet_items SET quantity=$1,weight_kg=$2,status=$3,updated_at=NOW() WHERE id=$4`, qtyAfter, weightAfter, status, itemID)
	if err != nil {
		layoutError(w, err)
		return
	}
	_, err = tx.Exec(ctx, `INSERT INTO pallet_item_histories(pallet_item_id,action_type,qty_before,qty_change,qty_after,weight_before,weight_change,weight_after,reference_type,performed_by,notes) VALUES($1,'OUTBOUND',$2,$3,$4,$5,$6,$7,'MANUAL',$8,$9)`, itemID, qtyBefore, -qty, qtyAfter, weightBefore, -weight, weightAfter, session.UserID, nullString(notes))
	if err != nil {
		layoutError(w, err)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"pallet_item_id": itemID, "pallet_id": palletID, "quantity_before": qtyBefore, "quantity_out": qty, "quantity_after": qtyAfter, "weight_before": weightBefore, "weight_out": weight, "weight_after": weightAfter, "status": status})
}
