package main

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// monitoringSummaryHandler reports counts from actual rack_slots rows; it never estimates slots from rack metadata.
func (a *App) monitoringSummaryHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	var total, empty, occupied, unavailable, quarantine, maintenance, moving int64
	var capacityKg float64
	err := a.DB.QueryRow(ctx, `
		SELECT COUNT(*),
		       COUNT(*) FILTER (WHERE status='EMPTY'),
		       COUNT(*) FILTER (WHERE status='OCCUPIED'),
		       COUNT(*) FILTER (WHERE status='UNAVAILABLE'),
		       COUNT(*) FILTER (WHERE status='QUARANTINE'),
		       COUNT(*) FILTER (WHERE status='MAINTENANCE'),
	       COUNT(*) FILTER (WHERE status='MOVING'),
	       COALESCE(SUM(capacity_kg) FILTER (WHERE status <> 'UNAVAILABLE'),0)
		FROM rack_slots`).Scan(&total, &empty, &occupied, &unavailable, &quarantine, &maintenance, &moving, &capacityKg)
	if err != nil {
		layoutError(w, err)
		return
	}
	usable := total - unavailable - quarantine - maintenance - moving
	utilization := 0.0
	if usable > 0 {
		utilization = float64(occupied) / float64(usable) * 100
	}
	var activePallets, placedPallets, unplacedPallets int64
	err = a.DB.QueryRow(ctx, `SELECT COUNT(*) FILTER (WHERE status <> 'INACTIVE'), COUNT(*) FILTER (WHERE current_slot_id IS NOT NULL AND status <> 'INACTIVE'), COUNT(*) FILTER (WHERE current_slot_id IS NULL AND status <> 'INACTIVE') FROM pallets`).Scan(&activePallets, &placedPallets, &unplacedPallets)
	if err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"total_slots": total, "usable_slots": usable, "empty_slots": empty,
		"occupied_slots": occupied, "unavailable_slots": unavailable,
		"quarantine_slots": quarantine, "maintenance_slots": maintenance, "moving_slots": moving,
		"utilization_percent": round2(utilization), "registered_capacity_kg": round2(capacityKg),
		"active_pallets": activePallets, "placed_pallets": placedPallets, "unplaced_pallets": unplacedPallets,
		"source": "rack_slots actual database rows",
	})
}

// monitoringFIFOHandler lists remaining stock by actual received_at, grouped in FIFO order per SKU.
func (a *App) monitoringFIFOHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	rows, err := a.DB.Query(ctx, `
		SELECT pi.id, pi.pallet_id, p.pallet_code, pi.sku_id, s.sku_code, s.name,
		       pi.batch_no, pi.received_at, pi.expiry_date, pi.quantity, pi.weight_kg,
		       GREATEST(0,FLOOR(EXTRACT(EPOCH FROM (NOW()-pi.received_at))/86400))::int AS age_days,
		       ROW_NUMBER() OVER (PARTITION BY pi.sku_id ORDER BY pi.received_at,pi.id) AS fifo_rank,
		       COALESCE(sl.code,'') AS slot_code, COALESCE(r.code,'') AS rack_code,
		       COALESCE(wa.name,'') AS area_name
		FROM pallet_items pi
		JOIN skus s ON s.id=pi.sku_id
		JOIN pallets p ON p.id=pi.pallet_id
		LEFT JOIN rack_slots sl ON sl.id=p.current_slot_id
		LEFT JOIN rack_levels rl ON rl.id=sl.rack_level_id
		LEFT JOIN racks r ON r.id=rl.rack_id
		LEFT JOIN warehouse_areas wa ON wa.id=r.warehouse_area_id
		WHERE pi.status='AVAILABLE' AND pi.quantity>0
		ORDER BY s.sku_code,pi.received_at,pi.id`)
	if err != nil {
		layoutError(w, err)
		return
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var id, palletID, skuID int64
		var code, skuCode, skuName, slotCode, rackCode, areaName string
		var batch *string
		var received time.Time
		var expiry *time.Time
		var quantity, weight float64
		var ageDays int
		var fifoRank int64
		if err := rows.Scan(&id, &palletID, &code, &skuID, &skuCode, &skuName, &batch, &received, &expiry, &quantity, &weight, &ageDays, &fifoRank, &slotCode, &rackCode, &areaName); err != nil {
			layoutError(w, err)
			return
		}
		out = append(out, map[string]any{
			"id": id, "pallet_id": palletID, "pallet_code": code, "sku_id": skuID,
			"sku_code": skuCode, "sku_name": skuName, "batch_no": batch,
			"received_at": received, "expiry_date": expiry, "quantity": quantity,
			"weight_kg": weight, "age_days": ageDays, "fifo_rank": fifoRank,
			"slot_code": slotCode, "rack_code": rackCode, "area_name": areaName,
		})
	}
	if err := rows.Err(); err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// slotRecommendationsHandler returns candidates for one existing pallet and explains the constraints used.
func (a *App) slotRecommendationsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)
		return
	}
	palletID, err := parseID(r.URL.Query().Get("pallet_id"))
	if err != nil {
		http.Error(w, "pallet_id wajib diisi dan harus berupa ID numerik", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	var warehouseID int64
	var totalWeight float64
	var itemCount, storageTypeCount int64
	var storageType string
	err = a.DB.QueryRow(ctx, `
		SELECT p.warehouse_id,COALESCE(SUM(pi.weight_kg),0),COUNT(pi.id),
		       COUNT(DISTINCT s.storage_type),COALESCE(MIN(s.storage_type),'')
		FROM pallets p
		LEFT JOIN pallet_items pi ON pi.pallet_id=p.id AND pi.status='AVAILABLE' AND pi.quantity>0
		LEFT JOIN skus s ON s.id=pi.sku_id
		WHERE p.id=$1 AND p.status <> 'INACTIVE'
		GROUP BY p.id`, palletID).Scan(&warehouseID, &totalWeight, &itemCount, &storageTypeCount, &storageType)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "no rows") {
			http.Error(w, "Pallet tidak ditemukan atau tidak aktif", http.StatusNotFound)
		} else {
			layoutError(w, err)
		}
		return
	}
	if itemCount == 0 {
		http.Error(w, "Isi pallet belum memiliki stok aktif; rekomendasi area penyimpanan belum dapat ditentukan", http.StatusConflict)
		return
	}
	if storageTypeCount != 1 {
		http.Error(w, "SKU dalam pallet memiliki tipe penyimpanan berbeda; pisahkan terlebih dahulu", http.StatusConflict)
		return
	}
	if storageType != "AMBIENT" && storageType != "CHILLED" && storageType != "FROZEN" {
		http.Error(w, "Tipe penyimpanan SKU tidak valid", http.StatusConflict)
		return
	}
	rows, err := a.DB.Query(ctx, `
		WITH area_density AS (
		 SELECT wa.id AS area_id,
		        COUNT(sl.id) FILTER (WHERE sl.status='OCCUPIED')::numeric AS occupied,
		        NULLIF(COUNT(sl.id) FILTER (WHERE sl.status NOT IN ('UNAVAILABLE','QUARANTINE','MAINTENANCE','MOVING')),0)::numeric AS usable
		 FROM warehouse_areas wa
		 LEFT JOIN racks r ON r.warehouse_area_id=wa.id
		 LEFT JOIN rack_levels rl ON rl.rack_id=r.id
		 LEFT JOIN rack_slots sl ON sl.rack_level_id=rl.id
		 GROUP BY wa.id
		)
		SELECT sl.id,sl.code,r.code,rl.level_number,sl.slot_number,wa.name,wa.area_type,
		       COALESCE(ad.occupied/NULLIF(ad.usable,0)*100,0)::float8 AS density_pct,
		       sl.capacity_kg,rl.max_weight_kg,level_load.current_weight
		FROM rack_slots sl
		JOIN rack_levels rl ON rl.id=sl.rack_level_id
		JOIN racks r ON r.id=rl.rack_id
		JOIN warehouse_areas wa ON wa.id=r.warehouse_area_id
		JOIN area_density ad ON ad.area_id=wa.id
		LEFT JOIN LATERAL (
		  SELECT COALESCE(SUM(pi.weight_kg),0)::float8 AS current_weight
		  FROM rack_slots other_sl JOIN pallets other_p ON other_p.current_slot_id=other_sl.id
		  LEFT JOIN pallet_items pi ON pi.pallet_id=other_p.id AND pi.status='AVAILABLE' AND pi.quantity>0
		  WHERE other_sl.rack_level_id=rl.id AND other_p.id<>$4
		) level_load ON TRUE
		WHERE wa.warehouse_id=$1 AND wa.status='ACTIVE' AND r.status='ACTIVE'
		  AND wa.area_type=$2 AND sl.status='EMPTY'
		  AND sl.capacity_kg IS NOT NULL AND sl.capacity_kg >= $3
		  AND (rl.max_weight_kg IS NULL OR level_load.current_weight + $3 <= rl.max_weight_kg)
		ORDER BY density_pct ASC,rl.level_number ASC,sl.slot_number ASC
		LIMIT 10`, warehouseID, storageType, totalWeight, palletID)
	if err != nil {
		layoutError(w, err)
		return
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var slotID int64
		var slotCode, rackCode, areaName, areaType string
		var level, slotNumber int
		var density float64
		var slotCapacity, levelCapacity *float64
		var levelCurrentWeight float64
		if err := rows.Scan(&slotID, &slotCode, &rackCode, &level, &slotNumber, &areaName, &areaType, &density, &slotCapacity, &levelCapacity, &levelCurrentWeight); err != nil {
			layoutError(w, err)
			return
		}
		out = append(out, map[string]any{
			"slot_id": slotID, "slot_code": slotCode, "rack_code": rackCode,
			"level_number": level, "slot_number": slotNumber, "area_name": areaName,
			"area_type": areaType, "area_utilization_percent": round2(density),
			"slot_capacity_kg": slotCapacity, "level_capacity_kg": levelCapacity,
			"level_current_weight_kg": round2(levelCurrentWeight),
			"reason":                  fmt.Sprintf("Slot kosong, area %s sesuai SKU, berat pallet %.2f kg; beban level saat ini %.2f kg; utilisasi area %.2f%%", areaType, totalWeight, levelCurrentWeight, density),
		})
	}
	if err := rows.Err(); err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"pallet_id": palletID, "storage_type": storageType, "total_weight_kg": round2(totalWeight),
		"recommendations": out, "count": len(out),
		"message": recommendationMessage(len(out)),
	})
}

func (a *App) palletMovementsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	query := `SELECT pm.id,pm.pallet_id,p.pallet_code,pm.from_slot_id,COALESCE(fs.code,''),pm.to_slot_id,COALESCE(ts.code,''),
	                 pm.movement_type,pm.status,COALESCE(pm.reason,''),pm.moved_at,pm.confirmed_at,pm.moved_by,COALESCE(u.full_name,'')
	          FROM pallet_movements pm JOIN pallets p ON p.id=pm.pallet_id
	          LEFT JOIN rack_slots fs ON fs.id=pm.from_slot_id LEFT JOIN rack_slots ts ON ts.id=pm.to_slot_id
	          LEFT JOIN users u ON u.id=pm.moved_by`
	args := []any{}
	if raw := strings.TrimSpace(r.URL.Query().Get("pallet_id")); raw != "" {
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || id <= 0 {
			http.Error(w, "pallet_id tidak valid", 400)
			return
		}
		query += ` WHERE pm.pallet_id=$1`
		args = append(args, id)
	}
	query += ` ORDER BY pm.moved_at DESC,pm.id DESC LIMIT 500`
	rows, err := a.DB.Query(ctx, query, args...)
	if err != nil {
		layoutError(w, err)
		return
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var id, palletID int64
		var fromID, toID, movedBy *int64
		var fromCode, toCode, reason, actor string
		var palletCode, movementType, status string
		var movedAt time.Time
		var confirmedAt *time.Time
		if err := rows.Scan(&id, &palletID, &palletCode, &fromID, &fromCode, &toID, &toCode, &movementType, &status, &reason, &movedAt, &confirmedAt, &movedBy, &actor); err != nil {
			layoutError(w, err)
			return
		}
		out = append(out, map[string]any{"id": id, "pallet_id": palletID, "pallet_code": palletCode, "from_slot_id": fromID, "from_slot_code": fromCode, "to_slot_id": toID, "to_slot_code": toCode, "movement_type": movementType, "status": status, "reason": reason, "moved_at": movedAt, "confirmed_at": confirmedAt, "moved_by": movedBy, "moved_by_name": actor})
	}
	if err := rows.Err(); err != nil {
		layoutError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func round2(v float64) float64 { return float64(int64(v*100+0.5)) / 100 }
func recommendationMessage(count int) string {
	if count == 0 {
		return "Tidak ada slot yang memenuhi semua aturan kapasitas dan tipe penyimpanan."
	}
	return fmt.Sprintf("Ditemukan %d kandidat. Periksa rekomendasi dan konfirmasi sebelum penempatan.", count)
}
