# PASATA Web

Frontend React + Vite untuk PASATA Warehouse & Cold Storage Management. Frontend berkomunikasi dengan backend Go melalui REST API; frontend tidak terhubung langsung ke PostgreSQL.

## Menjalankan frontend

1. Pastikan PostgreSQL dan backend Go berjalan pada `http://localhost:8080`.
2. Buka terminal pada folder `pasata-web`.
3. Jalankan:

```bash
npm install
npm run dev
```

4. Buka URL Vite yang ditampilkan (biasanya `http://localhost:5173`).

Konfigurasi API bisa diubah melalui `.env` frontend berdasarkan `.env.example`:

```env
VITE_API_BASE_URL=http://localhost:8080/api
```

## Database

Gunakan `database/Script-1(4).sql` pada paket utama sebagai acuan skema. Jalankan skrip tersebut hanya pada database baru/kosong; skrip membuat tabel dan memasukkan data contoh.

## Penyesuaian integrasi yang dilakukan

- `GET /pallet-items` membutuhkan `pallet_id`; web kini mengumpulkan isi pallet dengan meminta item per pallet.
- Formulir inbound mengikuti nilai yang diizinkan database: kemasan `CARTON`, `SACK`, `BOX`, `OTHER`; kondisi `GOOD`, `DAMAGED`, `EXPIRED`, `TEMP_DEVIATION`.
- Validasi inbound menampilkan konfirmasi checklist satu per satu sebelum meminta approval.
- API outbound memakai `outbound_transactions` dan `outbound_items` sesuai SQL, dengan status `DRAFT`, `WAITING_VERIFICATION`, `APPROVED`, `REJECTED`, dan `COMPLETED`.
- Driver dan kendaraan dipisahkan ke tabel `drivers` dan `vehicles`; endpoint kendaraan tersedia di `/api/vehicles`.
- Status slot yang bisa diubah manual dibatasi ke `EMPTY` dan `UNAVAILABLE`; status `OCCUPIED` ditetapkan sistem.

## Catatan

- Login/register dan hak akses tetap diperiksa oleh backend.
- Form inbound saat ini memasukkan satu baris SKU per transaksi.
- UI meminta ID gudang, pallet, slot, dan SKU pada beberapa formulir. Gunakan ID yang tersedia di tabel master.
- Build produksi dan pengujian end-to-end belum dikonfirmasi terhadap database PostgreSQL aktif pada lingkungan ini. Kode frontend sudah diperiksa untuk sintaks JSX; kode Go sudah diformat dan diperiksa sintaksnya.
- Jangan memasukkan file `.env` berisi kredensial ke ZIP atau GitHub. Gunakan `backend/.env.example` sebagai template, lalu isi kredensial lokal secara terpisah.
