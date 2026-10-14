package main

import (
	"context"

	"encoding/json"

	"log"

	"net/http"

	"strconv"

	"strings"

	"time"
)

// Register these routes in main.go after the existing warehouse routes:

// mux.HandleFunc("/api/warehouse-areas", app.warehouseAreasHandler)

// mux.HandleFunc("/api/cold-storages", app.coldStoragesHandler)

// mux.HandleFunc("/api/racks", app.racksHandler)

// mux.HandleFunc("/api/rack-levels", app.rackLevelsHandler)

// mux.HandleFunc("/api/rack-slots", app.rackSlotsHandler)

//

// This first Layout API milestone reads the existing schema only. It does not

// create or alter database tables.

func (a *App) warehouseAreasHandler(w http.ResponseWriter, r *http.Request) {

	if r.Method != http.MethodGet {

		w.Header().Set("Allow", "GET")

		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)

		return

	}

	q := strings.TrimSpace(r.URL.Query().Get("warehouse_id"))

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	query := `

        SELECT id, warehouse_id, code, name, area_type, capacity_pallet,

               description, status, created_at, updated_at

        FROM warehouse_areas`

	args := []any{}

	if q != "" {

		id, err := strconv.ParseInt(q, 10, 64)

		if err != nil || id <= 0 {

			http.Error(w, "warehouse_id tidak valid", http.StatusBadRequest)

			return

		}

		query += " WHERE warehouse_id = $1"

		args = append(args, id)

	}

	query += " ORDER BY id"

	rows, err := a.DB.Query(ctx, query, args...)

	if err != nil {

		log.Printf("Query warehouse_areas gagal: %v", err)

		http.Error(w, "Gagal mengambil data area gudang", http.StatusInternalServerError)

		return

	}

	defer rows.Close()

	result := make([]map[string]any, 0)

	for rows.Next() {

		var id, warehouseID int64

		var code, name, areaType, status string

		var capacity *int32

		var description *string

		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &warehouseID, &code, &name, &areaType, &capacity,

			&description, &status, &createdAt, &updatedAt); err != nil {

			http.Error(w, "Gagal membaca data area gudang", http.StatusInternalServerError)

			return

		}

		result = append(result, map[string]any{

			"id": id, "warehouse_id": warehouseID, "code": code, "name": name,

			"area_type": areaType, "capacity_pallet": capacity, "description": description,

			"status": status, "created_at": createdAt, "updated_at": updatedAt,
		})

	}

	if err := rows.Err(); err != nil {

		http.Error(w, "Gagal membaca data area gudang", http.StatusInternalServerError)

		return

	}

	writeJSON(w, http.StatusOK, result)

}

func (a *App) coldStoragesHandler(w http.ResponseWriter, r *http.Request) {

	if r.Method != http.MethodGet {

		w.Header().Set("Allow", "GET")

		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)

		return

	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	query := `

        SELECT cs.id, cs.warehouse_area_id, wa.warehouse_id, cs.code, cs.name,

               cs.storage_type, cs.min_temp, cs.max_temp, cs.current_temp,

               cs.capacity_pallet, cs.status, cs.created_at, cs.updated_at

        FROM cold_storages cs

        JOIN warehouse_areas wa ON wa.id = cs.warehouse_area_id

        ORDER BY cs.id`

	rows, err := a.DB.Query(ctx, query)

	if err != nil {

		log.Printf("Query cold_storages gagal: %v", err)

		http.Error(w, "Gagal mengambil data cold storage", http.StatusInternalServerError)

		return

	}

	defer rows.Close()

	result := make([]map[string]any, 0)

	for rows.Next() {

		var id, areaID, warehouseID int64

		var code, name, storageType, status string

		var minTemp, maxTemp float64

		var currentTemp *float64

		var capacity *int32

		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &areaID, &warehouseID, &code, &name, &storageType,

			&minTemp, &maxTemp, &currentTemp, &capacity, &status, &createdAt, &updatedAt); err != nil {

			http.Error(w, "Gagal membaca data cold storage", http.StatusInternalServerError)

			return

		}

		result = append(result, map[string]any{

			"id": id, "warehouse_area_id": areaID, "warehouse_id": warehouseID,

			"code": code, "name": name, "storage_type": storageType,

			"min_temp": minTemp, "max_temp": maxTemp, "current_temp": currentTemp,

			"capacity_pallet": capacity, "status": status,

			"created_at": createdAt, "updated_at": updatedAt,
		})

	}

	if err := rows.Err(); err != nil {

		http.Error(w, "Gagal membaca data cold storage", http.StatusInternalServerError)

		return

	}

	writeJSON(w, http.StatusOK, result)

}

func (a *App) racksHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet || r.URL.Path != "/api/racks" {
		a.racksCRUD(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	query := `

        SELECT id, warehouse_area_id, cold_storage_id, code, name, grid_row, grid_col,

               capacity_pallet, status, created_at, updated_at

        FROM racks`

	args := []any{}

	where := []string{}

	if raw := strings.TrimSpace(r.URL.Query().Get("area_id")); raw != "" {

		id, err := strconv.ParseInt(raw, 10, 64)

		if err != nil || id <= 0 {

			http.Error(w, "area_id tidak valid", http.StatusBadRequest)

			return

		}

		args = append(args, id)

		where = append(where, "warehouse_area_id = $"+strconv.Itoa(len(args)))

	}

	if raw := strings.TrimSpace(r.URL.Query().Get("cold_storage_id")); raw != "" {

		id, err := strconv.ParseInt(raw, 10, 64)

		if err != nil || id <= 0 {

			http.Error(w, "cold_storage_id tidak valid", http.StatusBadRequest)

			return

		}

		args = append(args, id)

		where = append(where, "cold_storage_id = $"+strconv.Itoa(len(args)))

	}

	if len(where) > 0 {

		query += " WHERE " + strings.Join(where, " AND ")

	}

	query += " ORDER BY grid_row NULLS LAST, grid_col NULLS LAST, id"

	rows, err := a.DB.Query(ctx, query, args...)

	if err != nil {

		log.Printf("Query racks gagal: %v", err)

		http.Error(w, "Gagal mengambil data rak", http.StatusInternalServerError)

		return

	}

	defer rows.Close()

	result := make([]map[string]any, 0)

	for rows.Next() {

		var id, areaID int64

		var coldStorageID *int64

		var code, status string

		var name *string

		var gridRow, gridCol *int16

		var capacity *int32

		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &areaID, &coldStorageID, &code, &name, &gridRow,

			&gridCol, &capacity, &status, &createdAt, &updatedAt); err != nil {

			http.Error(w, "Gagal membaca data rak", http.StatusInternalServerError)

			return

		}

		result = append(result, map[string]any{

			"id": id, "warehouse_area_id": areaID, "cold_storage_id": coldStorageID,

			"code": code, "name": name, "grid_row": gridRow, "grid_col": gridCol,

			"capacity_pallet": capacity, "status": status,

			"created_at": createdAt, "updated_at": updatedAt,
		})

	}

	if err := rows.Err(); err != nil {

		http.Error(w, "Gagal membaca data rak", http.StatusInternalServerError)

		return

	}

	writeJSON(w, http.StatusOK, result)

}

func (a *App) rackLevelsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet || r.URL.Path != "/api/rack-levels" {
		a.rackLevelsCRUD(w, r)
		return
	}

	raw := strings.TrimSpace(r.URL.Query().Get("rack_id"))

	if raw == "" {

		http.Error(w, "Parameter rack_id wajib diisi", http.StatusBadRequest)

		return

	}

	rackID, err := strconv.ParseInt(raw, 10, 64)

	if err != nil || rackID <= 0 {

		http.Error(w, "rack_id tidak valid", http.StatusBadRequest)

		return

	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	rows, err := a.DB.Query(ctx, `

        SELECT id, rack_id, code, level_number, max_weight_kg, created_at, updated_at

        FROM rack_levels WHERE rack_id = $1 ORDER BY level_number`, rackID)

	if err != nil {

		log.Printf("Query rack_levels gagal: %v", err)

		http.Error(w, "Gagal mengambil level rak", http.StatusInternalServerError)

		return

	}

	defer rows.Close()

	result := make([]map[string]any, 0)

	for rows.Next() {

		var id, parentID int64

		var code *string

		var level int16

		var maxWeight *float64

		var createdAt, updatedAt time.Time

		if err := rows.Scan(&id, &parentID, &code, &level, &maxWeight, &createdAt, &updatedAt); err != nil {

			http.Error(w, "Gagal membaca level rak", http.StatusInternalServerError)

			return

		}

		result = append(result, map[string]any{

			"id": id, "rack_id": parentID, "code": code, "level_number": level,

			"max_weight_kg": maxWeight, "created_at": createdAt, "updated_at": updatedAt,
		})

	}

	if err := rows.Err(); err != nil {

		http.Error(w, "Gagal membaca level rak", http.StatusInternalServerError)

		return

	}

	writeJSON(w, http.StatusOK, result)

}

func (a *App) rackSlotsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet || r.URL.Path != "/api/rack-slots" {
		a.rackSlotsCRUD(w, r)
		return
	}

	raw := strings.TrimSpace(r.URL.Query().Get("rack_level_id"))

	if raw == "" {

		http.Error(w, "Parameter rack_level_id wajib diisi", http.StatusBadRequest)

		return

	}

	levelID, err := strconv.ParseInt(raw, 10, 64)

	if err != nil || levelID <= 0 {

		http.Error(w, "rack_level_id tidak valid", http.StatusBadRequest)

		return

	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	rows, err := a.DB.Query(ctx, `

        SELECT s.id, s.rack_level_id, s.slot_number, s.code, s.capacity_kg,
               CASE WHEN p.id IS NOT NULL THEN 'OCCUPIED' ELSE s.status END,
               s.created_at, s.updated_at, p.id, p.pallet_code, p.status
        FROM rack_slots s LEFT JOIN pallets p ON p.current_slot_id=s.id
        WHERE s.rack_level_id = $1 ORDER BY s.slot_number`, levelID)

	if err != nil {

		log.Printf("Query rack_slots gagal: %v", err)

		http.Error(w, "Gagal mengambil slot rak", http.StatusInternalServerError)

		return

	}

	defer rows.Close()

	result := make([]map[string]any, 0)

	for rows.Next() {

		var id, parentID int64

		var slotNumber int16

		var code, status string

		var capacity *float64

		var createdAt, updatedAt time.Time
		var palletID *int64
		var palletCode, palletStatus *string

		if err := rows.Scan(&id, &parentID, &slotNumber, &code, &capacity, &status, &createdAt, &updatedAt, &palletID, &palletCode, &palletStatus); err != nil {

			http.Error(w, "Gagal membaca slot rak", http.StatusInternalServerError)

			return

		}

		result = append(result, map[string]any{

			"id": id, "rack_level_id": parentID, "slot_number": slotNumber,

			"code": code, "capacity_kg": capacity, "status": status,

			"created_at": createdAt, "updated_at": updatedAt,
			"pallet_id": palletID, "pallet_code": palletCode, "pallet_status": palletStatus,
		})

	}

	if err := rows.Err(); err != nil {

		http.Error(w, "Gagal membaca slot rak", http.StatusInternalServerError)

		return

	}

	writeJSON(w, http.StatusOK, result)

}

// Keep this compile-time reference so accidental unused imports are caught

// during editing; all handlers return JSON using the existing writeJSON helper.

var _ = json.Valid
