package main

import (
	"context"

	"encoding/json"

	"errors"

	"log"

	"net/http"

	"os"

	"strconv"

	"strings"

	"sync"

	"time"

	"github.com/jackc/pgx/v5"

	"github.com/joho/godotenv"

	"github.com/jackc/pgx/v5/pgxpool"
)

type App struct {
	DB         *pgxpool.Pool
	Sessions   map[string]AuthSession
	SessionsMu sync.RWMutex
}

type Warehouse struct {
	ID int64 `json:"id"`

	Code string `json:"code"`

	Name string `json:"name"`

	Address *string `json:"address"`

	City *string `json:"city"`

	Phone *string `json:"phone"`

	CapacityPallet int `json:"capacity_pallet"`

	Status string `json:"status"`

	CreatedAt time.Time `json:"created_at"`

	UpdatedAt time.Time `json:"updated_at"`
}

type WarehouseInput struct {
	Code string `json:"code"`

	Name string `json:"name"`

	Address *string `json:"address"`

	City *string `json:"city"`

	Phone *string `json:"phone"`

	CapacityPallet int `json:"capacity_pallet"`

	Status string `json:"status"`
}

func main() {

	if err := godotenv.Load(); err != nil {
		log.Println("File .env tidak ditemukan, menggunakan environment variable sistem")
	}
	databaseURL := os.Getenv("DATABASE_URL")

	if databaseURL == "" {

		log.Fatal("DATABASE_URL belum diatur")

	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)

	defer cancel()

	db, err := pgxpool.New(ctx, databaseURL)

	if err != nil {

		log.Fatalf("Gagal membuat koneksi database: %v", err)

	}

	defer db.Close()

	if err := db.Ping(ctx); err != nil {

		log.Fatalf("Gagal terhubung ke PostgreSQL: %v", err)

	}

	log.Println("Berhasil terhubung ke PostgreSQL!")

	app := &App{DB: db, Sessions: make(map[string]AuthSession)}

	mux := http.NewServeMux()

	mux.HandleFunc("/api/health", app.healthHandler)
	mux.HandleFunc("/api/auth/bootstrap", app.authBootstrapHandler)
	mux.HandleFunc("/api/auth/login", app.authLoginHandler)
	mux.HandleFunc("/api/auth/register", app.authRegisterHandler)
	mux.HandleFunc("/api/auth/logout", app.authLogoutHandler)
	mux.HandleFunc("/api/auth/me", app.authMeHandler)
	mux.HandleFunc("/api/auth/roles", app.authRolesHandler)

	mux.HandleFunc("/api/warehouses", app.warehousesHandler)

	mux.HandleFunc("/api/warehouses/", app.warehouseDetailHandler)

	mux.HandleFunc("/api/warehouse-areas", app.warehouseAreasHandler)
	mux.HandleFunc("/api/warehouse-areas/", app.warehouseAreasHandler)

	mux.HandleFunc("/api/cold-storages", app.coldStoragesHandler)
	mux.HandleFunc("/api/cold-storages/", app.coldStoragesHandler)

	mux.HandleFunc("/api/racks", app.racksHandler)

	mux.HandleFunc("/api/rack-levels", app.rackLevelsHandler)

	mux.HandleFunc("/api/rack-slots", app.rackSlotsHandler)
	mux.HandleFunc("/api/racks/", app.racksHandler)
	mux.HandleFunc("/api/rack-levels/", app.rackLevelsHandler)
	mux.HandleFunc("/api/rack-slots/", app.rackSlotsHandler)
	mux.HandleFunc("/api/pallets", app.palletsCRUD)
	mux.HandleFunc("/api/pallets/", app.palletDetailCRUD)
	mux.HandleFunc("/api/skus", app.skusHandler)
	mux.HandleFunc("/api/skus/", app.skusHandler)
	mux.HandleFunc("/api/pallet-items", app.palletItemsHandler)
	mux.HandleFunc("/api/pallet-item-outbound", app.palletItemOutboundHandler)
	mux.HandleFunc("/api/pallet-move", app.movePallet)
	mux.HandleFunc("/api/monitoring/summary", app.monitoringSummaryHandler)
	mux.HandleFunc("/api/monitoring/fifo", app.monitoringFIFOHandler)
	mux.HandleFunc("/api/slot-recommendations", app.slotRecommendationsHandler)
	mux.HandleFunc("/api/pallet-movements", app.palletMovementsHandler)
	mux.HandleFunc("/api/pallet-history", app.palletHistoryHandler)

	server := &http.Server{

		Addr: ":8080",

		Handler: cors(app.authMiddleware(mux)),

		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Println("Pasata API berjalan di http://localhost:8080")

	log.Fatal(server.ListenAndServe())

}

func (a *App) healthHandler(w http.ResponseWriter, r *http.Request) {

	if r.Method != http.MethodGet {

		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)

		return

	}

	writeJSON(w, http.StatusOK, map[string]string{

		"status": "ok",

		"app": "Pasata API",
	})

}

func (a *App) warehousesHandler(w http.ResponseWriter, r *http.Request) {

	switch r.Method {

	case http.MethodGet:

		a.listWarehouses(w, r)

	case http.MethodPost:

		a.createWarehouse(w, r)

	default:

		w.Header().Set("Allow", "GET, POST")

		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)

	}

}

func (a *App) listWarehouses(w http.ResponseWriter, r *http.Request) {

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	rows, err := a.DB.Query(ctx, `



        SELECT id, code, name, address, city, phone,



               capacity_pallet, status, created_at, updated_at



        FROM warehouses



        ORDER BY id



    `)

	if err != nil {

		log.Printf("Query warehouses gagal: %v", err)

		http.Error(w, "Gagal mengambil data gudang", http.StatusInternalServerError)

		return

	}

	defer rows.Close()

	warehouses := make([]Warehouse, 0)

	for rows.Next() {

		var item Warehouse

		if err := rows.Scan(

			&item.ID, &item.Code, &item.Name, &item.Address,

			&item.City, &item.Phone, &item.CapacityPallet,

			&item.Status, &item.CreatedAt, &item.UpdatedAt,
		); err != nil {

			log.Printf("Gagal membaca data gudang: %v", err)

			http.Error(w, "Gagal membaca data gudang", http.StatusInternalServerError)

			return

		}

		warehouses = append(warehouses, item)

	}

	if err := rows.Err(); err != nil {

		http.Error(w, "Gagal membaca data gudang", http.StatusInternalServerError)

		return

	}

	writeJSON(w, http.StatusOK, warehouses)

}

func (a *App) createWarehouse(w http.ResponseWriter, r *http.Request) {

	var input WarehouseInput

	if err := decodeJSON(w, r, &input); err != nil {

		http.Error(w, err.Error(), http.StatusBadRequest)

		return

	}

	input.Code = strings.TrimSpace(input.Code)

	input.Name = strings.TrimSpace(input.Name)

	input.Status = strings.ToUpper(strings.TrimSpace(input.Status))

	if input.Code == "" || input.Name == "" {

		http.Error(w, "code dan name wajib diisi", http.StatusBadRequest)

		return

	}

	if input.CapacityPallet < 0 {

		http.Error(w, "capacity_pallet tidak boleh negatif", http.StatusBadRequest)

		return

	}

	if input.Status == "" {

		input.Status = "ACTIVE"

	}

	if input.Status != "ACTIVE" &&

		input.Status != "INACTIVE" &&

		input.Status != "MAINTENANCE" {

		http.Error(w, "status harus ACTIVE, INACTIVE, atau MAINTENANCE", http.StatusBadRequest)

		return

	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	var item Warehouse

	err := a.DB.QueryRow(ctx, `



        INSERT INTO warehouses



            (code, name, address, city, phone, capacity_pallet, status)



        VALUES ($1, $2, $3, $4, $5, $6, $7)



        RETURNING id, code, name, address, city, phone,



                  capacity_pallet, status, created_at, updated_at



    `,

		input.Code, input.Name, input.Address, input.City,

		input.Phone, input.CapacityPallet, input.Status,
	).Scan(

		&item.ID, &item.Code, &item.Name, &item.Address,

		&item.City, &item.Phone, &item.CapacityPallet,

		&item.Status, &item.CreatedAt, &item.UpdatedAt,
	)

	if err != nil {

		log.Printf("Gagal menambah gudang: %v", err)

		http.Error(w, "Gagal menambah gudang. Periksa kode gudang dan data input.", http.StatusConflict)

		return

	}

	writeJSON(w, http.StatusCreated, item)

}

func (a *App) warehouseDetailHandler(w http.ResponseWriter, r *http.Request) {

	idText := strings.TrimPrefix(r.URL.Path, "/api/warehouses/")

	if idText == "" || strings.Contains(idText, "/") {

		http.NotFound(w, r)

		return

	}

	id, err := strconv.ParseInt(idText, 10, 64)

	if err != nil || id <= 0 {

		http.Error(w, "ID gudang tidak valid", http.StatusBadRequest)

		return

	}

	switch r.Method {

	case http.MethodGet:

		a.getWarehouse(w, r, id)

	case http.MethodPut:

		a.updateWarehouse(w, r, id)

	case http.MethodDelete:

		a.deleteWarehouse(w, r, id)

	default:

		w.Header().Set("Allow", "GET, PUT, DELETE")

		http.Error(w, "Method tidak diizinkan", http.StatusMethodNotAllowed)

	}

}

func (a *App) getWarehouse(w http.ResponseWriter, r *http.Request, id int64) {

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	var item Warehouse

	err := a.DB.QueryRow(ctx, `



        SELECT id, code, name, address, city, phone,



               capacity_pallet, status, created_at, updated_at



        FROM warehouses



        WHERE id = $1



    `, id).Scan(

		&item.ID, &item.Code, &item.Name, &item.Address,

		&item.City, &item.Phone, &item.CapacityPallet,

		&item.Status, &item.CreatedAt, &item.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {

		http.Error(w, "Gudang tidak ditemukan", http.StatusNotFound)

		return

	}

	if err != nil {

		http.Error(w, "Gagal mengambil data gudang", http.StatusInternalServerError)

		return

	}

	writeJSON(w, http.StatusOK, item)

}

func (a *App) updateWarehouse(w http.ResponseWriter, r *http.Request, id int64) {

	var input WarehouseInput

	if err := decodeJSON(w, r, &input); err != nil {

		http.Error(w, err.Error(), http.StatusBadRequest)

		return

	}

	input.Code = strings.TrimSpace(input.Code)

	input.Name = strings.TrimSpace(input.Name)

	input.Status = strings.ToUpper(strings.TrimSpace(input.Status))

	if input.Code == "" || input.Name == "" {

		http.Error(w, "code dan name wajib diisi", http.StatusBadRequest)

		return

	}

	if input.CapacityPallet < 0 {

		http.Error(w, "capacity_pallet tidak boleh negatif", http.StatusBadRequest)

		return

	}

	if input.Status != "ACTIVE" &&

		input.Status != "INACTIVE" &&

		input.Status != "MAINTENANCE" {

		http.Error(w, "status harus ACTIVE, INACTIVE, atau MAINTENANCE", http.StatusBadRequest)

		return

	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	var item Warehouse

	err := a.DB.QueryRow(ctx, `



        UPDATE warehouses



        SET code = $1,



            name = $2,



            address = $3,



            city = $4,



            phone = $5,



            capacity_pallet = $6,



            status = $7



        WHERE id = $8



        RETURNING id, code, name, address, city, phone,



                  capacity_pallet, status, created_at, updated_at



    `,

		input.Code, input.Name, input.Address, input.City,

		input.Phone, input.CapacityPallet, input.Status, id,
	).Scan(

		&item.ID, &item.Code, &item.Name, &item.Address,

		&item.City, &item.Phone, &item.CapacityPallet,

		&item.Status, &item.CreatedAt, &item.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {

		http.Error(w, "Gudang tidak ditemukan", http.StatusNotFound)

		return

	}

	if err != nil {

		log.Printf("Gagal mengubah gudang: %v", err)

		http.Error(w, "Gagal mengubah gudang. Periksa kode dan data input.", http.StatusConflict)

		return

	}

	writeJSON(w, http.StatusOK, item)

}

func (a *App) deleteWarehouse(w http.ResponseWriter, r *http.Request, id int64) {

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)

	defer cancel()

	tag, err := a.DB.Exec(ctx, `



        DELETE FROM warehouses



        WHERE id = $1



    `, id)

	if err != nil {

		log.Printf("Gagal menghapus gudang: %v", err)

		http.Error(w, "Gudang tidak dapat dihapus; periksa data yang terkait", http.StatusConflict)

		return

	}

	if tag.RowsAffected() == 0 {

		http.Error(w, "Gudang tidak ditemukan", http.StatusNotFound)

		return

	}

	w.WriteHeader(http.StatusNoContent)

}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) error {

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)

	decoder := json.NewDecoder(r.Body)

	decoder.DisallowUnknownFields()

	if err := decoder.Decode(target); err != nil {

		return errors.New("format JSON tidak valid atau field tidak dikenal")

	}

	return nil

}

func writeJSON(w http.ResponseWriter, status int, data any) {

	w.Header().Set("Content-Type", "application/json")

	w.WriteHeader(status)

	if err := json.NewEncoder(w).Encode(data); err != nil {

		log.Printf("Gagal mengirim JSON: %v", err)

	}

}

// cors mengizinkan request dari Flutter Web yang berjalan di localhost.

func cors(next http.Handler) http.Handler {

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		origin := r.Header.Get("Origin")

		if strings.HasPrefix(origin, "http://localhost:") ||

			strings.HasPrefix(origin, "http://127.0.0.1:") {

			w.Header().Set("Access-Control-Allow-Origin", origin)

			w.Header().Add("Vary", "Origin")

		}

		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")

		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {

			w.WriteHeader(http.StatusNoContent)

			return

		}

		next.ServeHTTP(w, r)

	})

}
