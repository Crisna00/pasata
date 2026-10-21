PASATA — Modul 3.6 Driver & Armada

Fitur:
- Master driver: nama, nomor polisi, jenis kendaraan, nomor telepon opsional.
- Warehouse Admin dapat menambah data dan mengaktifkan/nonaktifkan armada.
- Warehouse Operator dapat melihat dan memilih driver/armada ketika membuat outbound.
- Transaksi outbound menyimpan relasi driver dan waktu keberangkatan; daftar transaksi mengembalikan nama driver, nopol, jenis kendaraan, dan waktu keberangkatan.
- Migrasi database otomatis membuat tabel warehouse_drivers dan menambahkan driver_id/departure_time ke outbound_validation_requests.

Endpoint:
GET/POST/PATCH /api/drivers
POST /api/outbound-transactions menerima driver_id (opsional) dan departure_time dalam ISO-8601/RFC3339 (opsional).

Penting:
- Jalankan backend dengan database PostgreSQL yang sama seperti PASATA.
- Build/test Go dan Flutter belum dapat diverifikasi di lingkungan ini karena toolchain Go/Dart tidak tersedia secara offline.
- Uji tambah armada, nonaktifkan armada, pilih armada saat outbound, dan cek daftar transaksi setelah menjalankan backend.
