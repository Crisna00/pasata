package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
)

const passwordIterations = 120000

type AuthSession struct {
	UserID      int64  `json:"id"`
	Username    string `json:"username"`
	FullName    string `json:"full_name"`
	Email       string `json:"email"`
	RoleID      int64  `json:"role_id"`
	RoleCode    string `json:"role_code"`
	RoleName    string `json:"role_name"`
	WarehouseID *int64 `json:"warehouse_id,omitempty"`
}
type authContextKey struct{}

func (a *App) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions || r.URL.Path == "/api/health" || strings.HasPrefix(r.URL.Path, "/api/auth/") {
			next.ServeHTTP(w, r)
			return
		}
		token := bearerToken(r)
		if token == "" {
			writeJSON(w, 401, map[string]string{"error": "Login diperlukan."})
			return
		}
		a.SessionsMu.RLock()
		session, ok := a.Sessions[token]
		a.SessionsMu.RUnlock()
		if !ok {
			writeJSON(w, 401, map[string]string{"error": "Sesi tidak valid atau sudah berakhir. Silakan login kembali."})
			return
		}
		var active bool
		err := a.DB.QueryRow(r.Context(), `SELECT is_active FROM users WHERE id=$1`, session.UserID).Scan(&active)
		if err != nil || !active {
			a.SessionsMu.Lock()
			delete(a.Sessions, token)
			a.SessionsMu.Unlock()
			writeJSON(w, 401, map[string]string{"error": "Akun tidak aktif atau tidak ditemukan."})
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), authContextKey{}, session)))
	})
}
func bearerToken(r *http.Request) string {
	h := strings.TrimSpace(r.Header.Get("Authorization"))
	if len(h) > 7 && strings.EqualFold(h[:7], "Bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return ""
}
func (a *App) sessionFromRequest(r *http.Request) (AuthSession, bool) {
	s, ok := r.Context().Value(authContextKey{}).(AuthSession)
	return s, ok
}
func authError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
func readAuthJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return errors.New("hanya satu objek JSON diperbolehkan")
	}
	return nil
}
func derivePassword(password, salt string, iterations int) []byte {
	saltBytes, _ := hex.DecodeString(salt)
	block := append(append([]byte{}, saltBytes...), 0, 0, 0, 1)
	mac := hmac.New(sha256.New, []byte(password))
	_, _ = mac.Write(block)
	u := mac.Sum(nil)
	out := append([]byte{}, u...)
	for i := 1; i < iterations; i++ {
		mac = hmac.New(sha256.New, []byte(password))
		_, _ = mac.Write(u)
		u = mac.Sum(nil)
		for j := range out {
			out[j] ^= u[j]
		}
	}
	return out
}
func hashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	saltHex := hex.EncodeToString(salt)
	hash := derivePassword(password, saltHex, passwordIterations)
	return fmt.Sprintf("pbkdf2_sha256$%d$%s$%s", passwordIterations, saltHex, hex.EncodeToString(hash)), nil
}
func verifyPassword(password, encoded string) bool {
	p := strings.Split(encoded, "$")
	if len(p) != 4 || p[0] != "pbkdf2_sha256" {
		return false
	}
	it, err := strconv.Atoi(p[1])
	if err != nil || it < 10000 || it > 1000000 {
		return false
	}
	expected, err := hex.DecodeString(p[3])
	if err != nil {
		return false
	}
	actual := derivePassword(password, p[2], it)
	return len(actual) == len(expected) && subtle.ConstantTimeCompare(actual, expected) == 1
}
func (a *App) authBootstrapHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		authError(w, 405, "Method tidak diizinkan.")
		return
	}
	var count int
	if err := a.DB.QueryRow(r.Context(), `SELECT COUNT(*) FROM users`).Scan(&count); err != nil {
		authError(w, 500, "Gagal memeriksa status akun.")
		return
	}
	writeJSON(w, 200, map[string]any{"needs_first_admin": count == 0})
}
func (a *App) authLoginHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		authError(w, 405, "Method tidak diizinkan.")
		return
	}
	var in struct {
		Identifier string `json:"identifier"`
		Password   string `json:"password"`
	}
	if readAuthJSON(w, r, &in) != nil {
		authError(w, 400, "Data login tidak valid.")
		return
	}
	identifier := strings.TrimSpace(in.Identifier)
	if identifier == "" || in.Password == "" {
		authError(w, 400, "Username/email dan password wajib diisi.")
		return
	}
	var s AuthSession
	var hash string
	var active bool
	err := a.DB.QueryRow(r.Context(), `SELECT u.id,u.username,u.full_name,u.email,u.role_id,ro.code,ro.name,u.warehouse_id,u.password_hash,u.is_active FROM users u JOIN roles ro ON ro.id=u.role_id WHERE lower(u.username)=lower($1) OR lower(u.email)=lower($1)`, identifier).Scan(&s.UserID, &s.Username, &s.FullName, &s.Email, &s.RoleID, &s.RoleCode, &s.RoleName, &s.WarehouseID, &hash, &active)
	if err != nil || !active || !verifyPassword(in.Password, hash) {
		authError(w, 401, "Username/email atau password salah, atau akun tidak aktif.")
		return
	}
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		authError(w, 500, "Gagal membuat sesi.")
		return
	}
	token := hex.EncodeToString(tokenBytes)
	a.SessionsMu.Lock()
	a.Sessions[token] = s
	a.SessionsMu.Unlock()
	_, _ = a.DB.Exec(r.Context(), `UPDATE users SET last_login_at=NOW() WHERE id=$1`, s.UserID)
	writeJSON(w, 200, map[string]any{"token": token, "user": s})
}
func (a *App) authRegisterHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		authError(w, 405, "Method tidak diizinkan.")
		return
	}
	var in struct {
		Username    string `json:"username"`
		Email       string `json:"email"`
		FullName    string `json:"full_name"`
		Phone       string `json:"phone"`
		Password    string `json:"password"`
		RoleID      int64  `json:"role_id"`
		WarehouseID *int64 `json:"warehouse_id"`
	}
	if readAuthJSON(w, r, &in) != nil {
		authError(w, 400, "Format pendaftaran tidak valid.")
		return
	}
	in.Username = strings.TrimSpace(in.Username)
	in.Email = strings.TrimSpace(strings.ToLower(in.Email))
	in.FullName = strings.TrimSpace(in.FullName)
	in.Phone = strings.TrimSpace(in.Phone)
	if in.Username == "" || in.Email == "" || in.FullName == "" || len(in.Password) < 8 {
		authError(w, 400, "Nama, username, email wajib diisi dan password minimal 8 karakter.")
		return
	}
	var userCount int
	if err := a.DB.QueryRow(r.Context(), `SELECT COUNT(*) FROM users`).Scan(&userCount); err != nil {
		authError(w, 500, "Gagal memeriksa pengguna.")
		return
	}
	roleID := in.RoleID
	if userCount == 0 {
		if err := a.DB.QueryRow(r.Context(), `SELECT id FROM roles WHERE code='SUPER_ADMIN' AND is_active=TRUE`).Scan(&roleID); err != nil {
			authError(w, 500, "Role SUPER_ADMIN tidak ditemukan. Pastikan data roles tersedia.")
			return
		}
	} else {
		token := bearerToken(r)
		a.SessionsMu.RLock()
		session, ok := a.Sessions[token]
		a.SessionsMu.RUnlock()
		if token == "" || !ok {
			authError(w, 401, "Login admin diperlukan untuk membuat akun.")
			return
		}
		var canManage bool
		err := a.DB.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM role_permissions rp JOIN permissions p ON p.id=rp.permission_id WHERE rp.role_id=$1 AND p.code='user.manage')`, session.RoleID).Scan(&canManage)
		if err != nil || !canManage {
			authError(w, 403, "Hanya admin yang memiliki izin user.manage boleh membuat akun.")
			return
		}
		if roleID <= 0 {
			authError(w, 400, "Role pengguna wajib dipilih.")
			return
		}
	}
	var roleCode string
	if err := a.DB.QueryRow(r.Context(), `SELECT code FROM roles WHERE id=$1 AND is_active=TRUE`, roleID).Scan(&roleCode); err != nil {
		authError(w, 400, "Role tidak valid atau tidak aktif.")
		return
	}
	passwordHash, err := hashPassword(in.Password)
	if err != nil {
		authError(w, 500, "Gagal mengamankan password.")
		return
	}
	var newID int64
	err = a.DB.QueryRow(r.Context(), `INSERT INTO users(role_id,warehouse_id,username,email,password_hash,full_name,phone) VALUES($1,$2,$3,$4,$5,$6,NULLIF($7,'')) RETURNING id`, roleID, in.WarehouseID, in.Username, in.Email, passwordHash, in.FullName, in.Phone).Scan(&newID)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			authError(w, 409, "Username atau email sudah digunakan.")
		} else {
			authError(w, 500, "Gagal membuat pengguna. Periksa role dan data yang diisi.")
		}
		return
	}
	writeJSON(w, 201, map[string]any{"message": "Akun berhasil dibuat.", "user_id": newID, "role_code": roleCode})
}
func (a *App) authLogoutHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		authError(w, 405, "Method tidak diizinkan.")
		return
	}
	token := bearerToken(r)
	if token != "" {
		a.SessionsMu.Lock()
		delete(a.Sessions, token)
		a.SessionsMu.Unlock()
	}
	writeJSON(w, 200, map[string]string{"message": "Logout berhasil."})
}
func (a *App) authMeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		authError(w, 405, "Method tidak diizinkan.")
		return
	}
	token := bearerToken(r)
	a.SessionsMu.RLock()
	s, ok := a.Sessions[token]
	a.SessionsMu.RUnlock()
	if token == "" || !ok {
		authError(w, 401, "Sesi tidak valid.")
		return
	}
	writeJSON(w, 200, s)
}
func (a *App) authRolesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		authError(w, 405, "Method tidak diizinkan.")
		return
	}
	token := bearerToken(r)
	a.SessionsMu.RLock()
	s, ok := a.Sessions[token]
	a.SessionsMu.RUnlock()
	if !ok {
		authError(w, 401, "Login diperlukan.")
		return
	}
	var canManage bool
	if err := a.DB.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM role_permissions rp JOIN permissions p ON p.id=rp.permission_id WHERE rp.role_id=$1 AND p.code='user.manage')`, s.RoleID).Scan(&canManage); err != nil || !canManage {
		authError(w, 403, "Hanya admin yang boleh melihat pilihan role.")
		return
	}
	rows, err := a.DB.Query(r.Context(), `SELECT id,code,name,description FROM roles WHERE is_active=TRUE ORDER BY CASE code WHEN 'SUPER_ADMIN' THEN 1 WHEN 'WAREHOUSE_ADMIN' THEN 2 WHEN 'WAREHOUSE_OPERATOR' THEN 3 WHEN 'WAREHOUSE_SUPERVISOR' THEN 4 WHEN 'MANAGER' THEN 5 ELSE 6 END`)
	if err != nil {
		authError(w, 500, "Gagal memuat daftar role.")
		return
	}
	defer rows.Close()
	roles := make([]map[string]any, 0)
	for rows.Next() {
		var id int64
		var code, name string
		var description *string
		if err := rows.Scan(&id, &code, &name, &description); err != nil {
			authError(w, 500, "Gagal membaca role.")
			return
		}
		roles = append(roles, map[string]any{"id": id, "code": code, "name": name, "description": description})
	}
	if rows.Err() != nil {
		authError(w, 500, "Gagal membaca daftar role.")
		return
	}
	writeJSON(w, 200, roles)
}
