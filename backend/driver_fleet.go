package main

import (
	"context"
	"net/http"
	"strings"
	"time"
)

func (a *App) ensureDriverFleetSchema(ctx context.Context) error {
	_, err := a.DB.Exec(ctx, `CREATE TABLE IF NOT EXISTS warehouse_drivers (
  id BIGSERIAL PRIMARY KEY,
  driver_name TEXT NOT NULL,
  plate_number TEXT NOT NULL UNIQUE,
  vehicle_type TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
 )`)
	if err != nil {
		return err
	}
	return nil
}

func (a *App) driversHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	if err := a.ensureDriverFleetSchema(ctx); err != nil {
		layoutError(w, err)
		return
	}
	session, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan")
		return
	}
	role := strings.ToUpper(session.RoleCode)
	if role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" && role != "WAREHOUSE_OPERATOR" {
		authError(w, 403, "Akses ditolak")
		return
	}
	switch r.Method {
	case http.MethodGet:
		rows, err := a.DB.Query(ctx, `SELECT id,driver_name,plate_number,vehicle_type,phone,active,created_at FROM warehouse_drivers ORDER BY active DESC,driver_name`)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id int64
			var name, plate, kind, phone string
			var active bool
			var created time.Time
			if err := rows.Scan(&id, &name, &plate, &kind, &phone, &active, &created); err != nil {
				layoutError(w, err)
				return
			}
			out = append(out, map[string]any{"id": id, "driver_name": name, "plate_number": plate, "vehicle_type": kind, "phone": phone, "active": active, "created_at": created})
		}
		writeJSON(w, 200, out)
	case http.MethodPost:
		if role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" {
			authError(w, 403, "Hanya Warehouse Admin yang dapat mengubah data armada")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		name := strings.TrimSpace(strField(b, "driver_name"))
		plate := strings.ToUpper(strings.TrimSpace(strField(b, "plate_number")))
		kind := strings.TrimSpace(strField(b, "vehicle_type"))
		phone := strings.TrimSpace(strField(b, "phone"))
		if name == "" || plate == "" || kind == "" {
			authError(w, 400, "Nama driver, nomor polisi, dan jenis kendaraan wajib diisi")
			return
		}
		var id int64
		err = a.DB.QueryRow(ctx, `INSERT INTO warehouse_drivers(driver_name,plate_number,vehicle_type,phone) VALUES($1,$2,$3,$4) RETURNING id`, name, plate, kind, phone).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "message": "Data driver dan armada tersimpan"})
	case http.MethodPatch:
		if role != "SUPER_ADMIN" && role != "WAREHOUSE_ADMIN" {
			authError(w, 403, "Hanya Warehouse Admin yang dapat mengubah data armada")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		id, err := parseID(strField(b, "id"))
		if err != nil {
			authError(w, 400, "ID tidak valid")
			return
		}
		active := true
		if v, ok := b["active"].(bool); ok {
			active = v
		}
		res, err := a.DB.Exec(ctx, `UPDATE warehouse_drivers SET active=$1 WHERE id=$2`, active, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if res.RowsAffected() == 0 {
			authError(w, 404, "Driver tidak ditemukan")
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "active": active})
	default:
		w.Header().Set("Allow", "GET, POST, PATCH")
		authError(w, 405, "Method tidak diizinkan")
	}
}
