package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"
)

func fleetCanView(role string) bool {
	return role == "SUPER_ADMIN" || role == "WAREHOUSE_ADMIN" || role == "WAREHOUSE_OPERATOR" || role == "WAREHOUSE_SUPERVISOR" || role == "MANAGER"
}
func fleetCanManage(role string) bool { return role == "SUPER_ADMIN" || role == "WAREHOUSE_ADMIN" }

// Drivers endpoint follows the normalized drivers table in Script-1(4).sql.
func (a *App) driversHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	session, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan")
		return
	}
	role := strings.ToUpper(session.RoleCode)
	if !fleetCanView(role) {
		authError(w, 403, "Akses ditolak")
		return
	}
	switch r.Method {
	case http.MethodGet:
		rows, err := a.DB.Query(ctx, `SELECT id,license_no,name,phone,license_expiry,is_active,created_at FROM drivers ORDER BY is_active DESC,name`)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id int64
			var license, name string
			var phone *string
			var expiry *time.Time
			var active bool
			var created time.Time
			if err := rows.Scan(&id, &license, &name, &phone, &expiry, &active, &created); err != nil {
				layoutError(w, err)
				return
			}
			out = append(out, map[string]any{"id": id, "license_no": license, "name": name, "phone": phone, "license_expiry": expiry, "is_active": active, "created_at": created})
		}
		if err := rows.Err(); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, out)
	case http.MethodPost:
		if !fleetCanManage(role) {
			authError(w, 403, "Hanya Warehouse Admin yang dapat mengubah data driver")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		license := strings.TrimSpace(strField(b, "license_no"))
		name := strings.TrimSpace(strField(b, "name"))
		phone := strings.TrimSpace(strField(b, "phone"))
		if license == "" || name == "" {
			authError(w, 400, "Nomor SIM dan nama driver wajib diisi")
			return
		}
		var expiry any
		if raw := strings.TrimSpace(strField(b, "license_expiry")); raw != "" {
			v, e := time.Parse("2006-01-02", raw)
			if e != nil {
				authError(w, 400, "Tanggal masa berlaku SIM tidak valid")
				return
			}
			expiry = v
		}
		var id int64
		err = a.DB.QueryRow(ctx, `INSERT INTO drivers(license_no,name,phone,license_expiry) VALUES($1,$2,$3,$4) RETURNING id`, license, name, phone, expiry).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "name": name, "message": "Data driver tersimpan"})
	case http.MethodPatch:
		if !fleetCanManage(role) {
			authError(w, 403, "Hanya Warehouse Admin yang dapat mengubah data driver")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		id, err := parseID(fmt.Sprint(b["id"]))
		if err != nil {
			authError(w, 400, "ID tidak valid")
			return
		}
		active := true
		if v, ok := b["is_active"].(bool); ok {
			active = v
		}
		res, err := a.DB.Exec(ctx, `UPDATE drivers SET is_active=$1,updated_at=NOW() WHERE id=$2`, active, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if res.RowsAffected() == 0 {
			authError(w, 404, "Driver tidak ditemukan")
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "is_active": active})
	default:
		w.Header().Set("Allow", "GET, POST, PUT, PATCH")
		authError(w, 405, "Method tidak diizinkan")
	}
}

// Vehicles endpoint follows the normalized vehicles table in Script-1(4).sql.
func (a *App) vehiclesHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	session, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan")
		return
	}
	role := strings.ToUpper(session.RoleCode)
	if !fleetCanView(role) {
		authError(w, 403, "Akses ditolak")
		return
	}
	switch r.Method {
	case http.MethodGet:
		rows, err := a.DB.Query(ctx, `SELECT id,plate_number,vehicle_type,capacity_kg,is_refrigerated,status,created_at FROM vehicles ORDER BY plate_number`)
		if err != nil {
			layoutError(w, err)
			return
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id int64
			var plate string
			var kind *string
			var capacity *float64
			var refrigerated bool
			var status string
			var created time.Time
			if err := rows.Scan(&id, &plate, &kind, &capacity, &refrigerated, &status, &created); err != nil {
				layoutError(w, err)
				return
			}
			out = append(out, map[string]any{"id": id, "plate_number": plate, "vehicle_type": kind, "capacity_kg": capacity, "is_refrigerated": refrigerated, "status": status, "created_at": created})
		}
		if err := rows.Err(); err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 200, out)
	case http.MethodPost:
		if !fleetCanManage(role) {
			authError(w, 403, "Hanya Warehouse Admin yang dapat mengubah data kendaraan")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		plate := strings.ToUpper(strings.TrimSpace(strField(b, "plate_number")))
		if plate == "" {
			authError(w, 400, "Nomor polisi wajib diisi")
			return
		}
		kind := strings.TrimSpace(strField(b, "vehicle_type"))
		var capacity any
		if v, ok := numberField(b, "capacity_kg"); ok {
			if v < 0 {
				authError(w, 400, "Kapasitas tidak boleh negatif")
				return
			}
			capacity = v
		}
		refrigerated := true
		if v, ok := b["is_refrigerated"].(bool); ok {
			refrigerated = v
		}
		status := strings.ToUpper(strings.TrimSpace(strField(b, "status")))
		if status == "" {
			status = "AVAILABLE"
		}
		if status != "AVAILABLE" && status != "ON_DELIVERY" && status != "MAINTENANCE" && status != "INACTIVE" {
			authError(w, 400, "Status kendaraan tidak valid")
			return
		}
		var id int64
		err = a.DB.QueryRow(ctx, `INSERT INTO vehicles(plate_number,vehicle_type,capacity_kg,is_refrigerated,status) VALUES($1,$2,$3,$4,$5) RETURNING id`, plate, nullString(kind), capacity, refrigerated, status).Scan(&id)
		if err != nil {
			layoutError(w, err)
			return
		}
		writeJSON(w, 201, map[string]any{"id": id, "plate_number": plate, "message": "Data kendaraan tersimpan"})
	case http.MethodPut:
		if !fleetCanManage(role) {
			authError(w, 403, "Hanya Warehouse Admin yang dapat mengubah data kendaraan")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		id, err := parseID(fmt.Sprint(b["id"]))
		if err != nil {
			authError(w, 400, "ID kendaraan tidak valid")
			return
		}
		plate := strings.ToUpper(strings.TrimSpace(strField(b, "plate_number")))
		if plate == "" {
			authError(w, 400, "Nomor polisi wajib diisi")
			return
		}
		kind := strings.TrimSpace(strField(b, "vehicle_type"))
		var capacity any
		if v, ok := numberField(b, "capacity_kg"); ok {
			if v < 0 {
				authError(w, 400, "Kapasitas tidak boleh negatif")
				return
			}
			capacity = v
		}
		refrigerated := true
		switch v := b["is_refrigerated"].(type) {
		case bool:
			refrigerated = v
		case string:
			refrigerated = strings.EqualFold(strings.TrimSpace(v), "true")
		}
		status := strings.ToUpper(strings.TrimSpace(strField(b, "status")))
		if status == "" {
			status = "AVAILABLE"
		}
		if status != "AVAILABLE" && status != "ON_DELIVERY" && status != "MAINTENANCE" && status != "INACTIVE" {
			authError(w, 400, "Status kendaraan tidak valid")
			return
		}
		res, err := a.DB.Exec(ctx, `UPDATE vehicles SET plate_number=$1,vehicle_type=$2,capacity_kg=$3,is_refrigerated=$4,status=$5,updated_at=NOW() WHERE id=$6`, plate, nullString(kind), capacity, refrigerated, status, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if res.RowsAffected() == 0 {
			authError(w, 404, "Kendaraan tidak ditemukan")
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "plate_number": plate, "is_refrigerated": refrigerated, "status": status, "message": "Data kendaraan berhasil diperbarui"})
	case http.MethodPatch:
		if !fleetCanManage(role) {
			authError(w, 403, "Hanya Warehouse Admin yang dapat mengubah data kendaraan")
			return
		}
		b, err := jsonBody(w, r)
		if err != nil {
			authError(w, 400, err.Error())
			return
		}
		id, err := parseID(fmt.Sprint(b["id"]))
		if err != nil {
			authError(w, 400, "ID tidak valid")
			return
		}
		status := strings.ToUpper(strings.TrimSpace(strField(b, "status")))
		if status == "" {
			status = "INACTIVE"
		}
		if status != "AVAILABLE" && status != "ON_DELIVERY" && status != "MAINTENANCE" && status != "INACTIVE" {
			authError(w, 400, "Status kendaraan tidak valid")
			return
		}
		res, err := a.DB.Exec(ctx, `UPDATE vehicles SET status=$1,updated_at=NOW() WHERE id=$2`, status, id)
		if err != nil {
			layoutError(w, err)
			return
		}
		if res.RowsAffected() == 0 {
			authError(w, 404, "Kendaraan tidak ditemukan")
			return
		}
		writeJSON(w, 200, map[string]any{"id": id, "status": status})
	default:
		w.Header().Set("Allow", "GET, POST, PATCH")
		authError(w, 405, "Method tidak diizinkan")
	}
}
