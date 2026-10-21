package main

import (
	"net/http"
	"strconv"
	"strings"
)

func (a *App) userManageAllowed(w http.ResponseWriter, r *http.Request) (AuthSession, bool) {
	s, ok := a.sessionFromRequest(r)
	if !ok {
		authError(w, 401, "Login diperlukan.")
		return s, false
	}
	var allowed bool
	err := a.DB.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM role_permissions rp JOIN permissions p ON p.id=rp.permission_id WHERE rp.role_id=$1 AND p.code='user.manage')`, s.RoleID).Scan(&allowed)
	if err != nil || !allowed {
		authError(w, 403, "Hanya pengguna dengan izin user.manage boleh mengelola user.")
		return s, false
	}
	return s, true
}

func (a *App) usersHandler(w http.ResponseWriter, r *http.Request) {
	s, ok := a.userManageAllowed(w, r)
	if !ok {
		return
	}
	switch r.Method {
	case http.MethodGet:
		q := strings.TrimSpace(r.URL.Query().Get("q"))
		rows, err := a.DB.Query(r.Context(), `SELECT u.id,u.username,u.email,u.full_name,u.phone,u.role_id,ro.code,ro.name,u.warehouse_id,u.is_active,u.created_at,u.last_login_at FROM users u JOIN roles ro ON ro.id=u.role_id WHERE ($1='' OR u.username ILIKE '%'||$1||'%' OR u.email ILIKE '%'||$1||'%' OR u.full_name ILIKE '%'||$1||'%' OR CAST(u.id AS TEXT) ILIKE '%'||$1||'%') ORDER BY u.id`, q)
		if err != nil {
			authError(w, 500, "Gagal memuat daftar user.")
			return
		}
		defer rows.Close()
		out := make([]map[string]any, 0)
		for rows.Next() {
			var id, roleID int64
			var username, email, fullName, roleCode, roleName string
			var phone *string
			var warehouseID *int64
			var active bool
			var createdAt interface{}
			var lastLogin interface{}
			if err := rows.Scan(&id, &username, &email, &fullName, &phone, &roleID, &roleCode, &roleName, &warehouseID, &active, &createdAt, &lastLogin); err != nil {
				authError(w, 500, "Gagal membaca data user.")
				return
			}
			out = append(out, map[string]any{"id": id, "username": username, "email": email, "full_name": fullName, "phone": phone, "role_id": roleID, "role_code": roleCode, "role_name": roleName, "warehouse_id": warehouseID, "is_active": active, "created_at": createdAt, "last_login_at": lastLogin})
		}
		if rows.Err() != nil {
			authError(w, 500, "Gagal membaca data user.")
			return
		}
		writeJSON(w, 200, out)
	case http.MethodPatch:
		var in struct {
			ID       int64   `json:"id"`
			Username *string `json:"username"`
			Email    *string `json:"email"`
			FullName *string `json:"full_name"`
			Password *string `json:"password"`
			RoleID   *int64  `json:"role_id"`
			IsActive *bool   `json:"is_active"`
		}
		if readAuthJSON(w, r, &in) != nil || in.ID <= 0 {
			authError(w, 400, "Data perubahan user tidak valid.")
			return
		}
		if in.ID == s.UserID && in.IsActive != nil && !*in.IsActive {
			authError(w, 400, "Akun yang sedang digunakan tidak dapat dinonaktifkan.")
			return
		}
		tx, err := a.DB.Begin(r.Context())
		if err != nil {
			authError(w, 500, "Gagal memulai perubahan user.")
			return
		}
		defer tx.Rollback(r.Context())
		if in.Username != nil {
			v := strings.TrimSpace(*in.Username)
			if v == "" {
				authError(w, 400, "Username tidak boleh kosong.")
				return
			}
			if _, err = tx.Exec(r.Context(), `UPDATE users SET username=$1 WHERE id=$2`, v, in.ID); err != nil {
				authError(w, 409, "Username sudah digunakan atau tidak valid.")
				return
			}
		}
		if in.Email != nil {
			v := strings.ToLower(strings.TrimSpace(*in.Email))
			if v == "" {
				authError(w, 400, "Email tidak boleh kosong.")
				return
			}
			if _, err = tx.Exec(r.Context(), `UPDATE users SET email=$1 WHERE id=$2`, v, in.ID); err != nil {
				authError(w, 409, "Email sudah digunakan atau tidak valid.")
				return
			}
		}
		if in.FullName != nil {
			if _, err = tx.Exec(r.Context(), `UPDATE users SET full_name=$1 WHERE id=$2`, strings.TrimSpace(*in.FullName), in.ID); err != nil {
				authError(w, 500, "Gagal mengubah nama user.")
				return
			}
		}
		if in.RoleID != nil {
			if _, err = tx.Exec(r.Context(), `UPDATE users SET role_id=$1 WHERE id=$2 AND EXISTS(SELECT 1 FROM roles WHERE id=$1 AND is_active=TRUE)`, *in.RoleID, in.ID); err != nil {
				authError(w, 400, "Role tidak valid.")
				return
			}
		}
		if in.IsActive != nil {
			if _, err = tx.Exec(r.Context(), `UPDATE users SET is_active=$1 WHERE id=$2`, *in.IsActive, in.ID); err != nil {
				authError(w, 500, "Gagal mengubah status user.")
				return
			}
		}
		if in.Password != nil {
			if len(*in.Password) < 8 {
				authError(w, 400, "Password baru minimal 8 karakter.")
				return
			}
			hash, e := hashPassword(*in.Password)
			if e != nil {
				authError(w, 500, "Gagal mengamankan password.")
				return
			}
			if _, err = tx.Exec(r.Context(), `UPDATE users SET password_hash=$1 WHERE id=$2`, hash, in.ID); err != nil {
				authError(w, 500, "Gagal mengganti password.")
				return
			}
		}
		if err = tx.Commit(r.Context()); err != nil {
			authError(w, 500, "Perubahan user gagal disimpan.")
			return
		}
		writeJSON(w, 200, map[string]any{"message": "Data user berhasil diperbarui."})
	case http.MethodDelete:
		id, err := strconv.ParseInt(strings.TrimPrefix(r.URL.Path, "/api/users/"), 10, 64)
		if err != nil || id <= 0 {
			authError(w, 400, "ID user tidak valid.")
			return
		}
		if id == s.UserID {
			authError(w, 400, "Tidak dapat menghapus/nonaktifkan akun sendiri.")
			return
		}
		tag, err := a.DB.Exec(r.Context(), `UPDATE users SET is_active=FALSE WHERE id=$1`, id)
		if err != nil {
			authError(w, 500, "Gagal menonaktifkan user.")
			return
		}
		if tag.RowsAffected() == 0 {
			authError(w, 404, "User tidak ditemukan.")
			return
		}
		writeJSON(w, 200, map[string]string{"message": "User dinonaktifkan. Data transaksi tetap dipertahankan untuk audit."})
	default:
		authError(w, 405, "Method tidak diizinkan.")
	}
}
