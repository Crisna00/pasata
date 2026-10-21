PASATA - perbaikan inbound/outbound

PENTING: Paket ini memakai main.dart terbaru yang tersedia pada sesi (versi 15:47, berisi InboundPage), bukan main.dart lama yang ikut ZIP sebelumnya.

Perubahan backend: tabel antrean approval outbound diganti dari outbound_transactions menjadi outbound_validation_requests agar tidak bertabrakan dengan tabel transaksi outbound lama yang mungkin sudah ada di database. Stok tetap hanya dikurangi saat approve; reject tidak mengurangi stok. layoutError menulis error database sebenarnya ke terminal Go.

Pasang semua file Go dalam folder ini bersama-sama. Pertahankan file .env dan database yang sudah ada; jangan reset database. Ganti lib/main.dart dengan main.dart ini hanya setelah membuat cadangan.

Jalankan backend dari folder berisi go.mod dengan go run . . Lalu jalankan Flutter seperti biasa.

Catatan: saya tidak dapat menjalankan build Flutter/Go terhadap database lokal pengguna di sini; uji dan periksa log terminal jika masih ada error.


Tambahan UI: Gateway Outbound kini memiliki bagian Riwayat outbound di bawah form. Setiap transaksi dapat dibuka untuk melihat jumlah/berat keluar, pallet/lokasi/batch, waktu pengajuan/keputusan, catatan, status, dan user ID pengaju/pemutus. Riwayat dimuat dari GET /api/outbound-transactions dan dapat diperbarui dengan tombol refresh.
