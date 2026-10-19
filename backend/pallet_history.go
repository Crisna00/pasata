package main

import (
	"context"
	"net/http"
	"strconv"
	"time"
)

// palletHistoryHandler menggabungkan riwayat isi/berat dan perpindahan lokasi.
// Endpoint memakai skema yang sudah ada; tidak membutuhkan migrasi database.
func (a *App) palletHistoryHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)
		return
	}
	session, ok := a.sessionFromRequest(r)
	if !ok || session.UserID <= 0 {
		authError(w, http.StatusUnauthorized, "Sesi pengguna tidak ditemukan; silakan login kembali.")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	var filterID int64
	if raw := r.URL.Query().Get("pallet_id"); raw != "" {
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || id <= 0 {
			http.Error(w, "pallet_id tidak valid", http.StatusBadRequest)
			return
		}
		filterID = id
	}
	events := make([]map[string]any, 0, 64)
	rows, err := a.DB.Query(ctx, `
        SELECT h.id, p.id, p.pallet_code, h.action_type,
               h.qty_before, h.qty_change, h.qty_after,
               h.weight_before, h.weight_change, h.weight_after,
               h.notes, h.created_at,
               COALESCE(s.sku_code,''), COALESCE(s.name,''),
               COALESCE(u.full_name, u.username, 'Tidak tercatat')
        FROM pallet_item_histories h
        JOIN pallet_items pi ON pi.id=h.pallet_item_id
        JOIN pallets p ON p.id=pi.pallet_id
        JOIN skus s ON s.id=pi.sku_id
        LEFT JOIN users u ON u.id=h.performed_by
        WHERE ($1=0 OR p.id=$1)
        ORDER BY h.created_at DESC, h.id DESC`, filterID)
	if err != nil {
		layoutError(w, err)
		return
	}
	for rows.Next() {
		var id, palletID int64
		var code, action, skuCode, skuName, actor string
		var qtyBefore, qtyChange, qtyAfter, weightBefore, weightChange, weightAfter float64
		var notes *string
		var created time.Time
		if err := rows.Scan(&id, &palletID, &code, &action, &qtyBefore, &qtyChange, &qtyAfter, &weightBefore, &weightChange, &weightAfter, &notes, &created, &skuCode, &skuName, &actor); err != nil {
			rows.Close()
			layoutError(w, err)
			return
		}
		events = append(events, map[string]any{"event_id": "item-" + strconv.FormatInt(id, 10), "pallet_id": palletID, "pallet_code": code, "action": action, "qty_before": qtyBefore, "qty_change": qtyChange, "qty_after": qtyAfter, "weight_before": weightBefore, "weight_change": weightChange, "weight_after": weightAfter, "notes": notes, "occurred_at": created, "sku_code": skuCode, "sku_name": skuName, "actor_name": actor})
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		layoutError(w, err)
		return
	}
	rows.Close()

	moves, err := a.DB.Query(ctx, `
        SELECT m.id, p.id, p.pallet_code, m.movement_type, m.status,
               COALESCE(fs.code,''), COALESCE(ts.code,''), m.reason, m.notes,
               m.moved_at, COALESCE(u.full_name, u.username, 'Tidak tercatat')
        FROM pallet_movements m
        JOIN pallets p ON p.id=m.pallet_id
        LEFT JOIN rack_slots fs ON fs.id=m.from_slot_id
        LEFT JOIN rack_slots ts ON ts.id=m.to_slot_id
        LEFT JOIN users u ON u.id=m.moved_by
        WHERE ($1=0 OR p.id=$1)
        ORDER BY m.moved_at DESC, m.id DESC`, filterID)
	if err != nil {
		layoutError(w, err)
		return
	}
	for moves.Next() {
		var id, palletID int64
		var code, action, status, from, to, reason, actor string
		var notes *string
		var moved time.Time
		if err := moves.Scan(&id, &palletID, &code, &action, &status, &from, &to, &reason, &notes, &moved, &actor); err != nil {
			moves.Close()
			layoutError(w, err)
			return
		}
		events = append(events, map[string]any{"event_id": "move-" + strconv.FormatInt(id, 10), "pallet_id": palletID, "pallet_code": code, "action": "MOVE", "movement_type": action, "status": status, "from_location": from, "to_location": to, "description": reason, "notes": notes, "occurred_at": moved, "actor_name": actor})
	}
	if err := moves.Err(); err != nil {
		moves.Close()
		layoutError(w, err)
		return
	}
	moves.Close()

	// Sort the merged timeline by timestamp descending.
	for i := 0; i < len(events); i++ {
		for j := i + 1; j < len(events); j++ {
			ti, _ := events[i]["occurred_at"].(time.Time)
			tj, _ := events[j]["occurred_at"].(time.Time)
			if tj.After(ti) {
				events[i], events[j] = events[j], events[i]
			}
		}
	}
	writeJSON(w, http.StatusOK, events)
}
