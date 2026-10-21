PASATA — Modul 3.5 Draft & Pending Transaction

Perubahan:
- Operator dapat menyimpan transaksi outbound sebagai DRAFT tanpa checklist lengkap.
- Draft dapat dikirim menjadi PENDING / Waiting Verification.
- Supervisor dapat approve atau reject transaksi PENDING.
- Reject wajib menyertakan alasan dan stok tidak berubah.
- Approve tetap memvalidasi stok/FIFO, mengurangi stok sekali, serta mencatat histori; status menjadi APPROVED.
- Operator dapat menandai transaksi APPROVED sebagai COMPLETED.
- Layar Review outbound menampilkan daftar status transaksi dan tindakan sesuai status.
- Tombol Gateway Outbound: Simpan Draft dan Kirim verifikasi.
- Inbound dan modul lain dipertahankan dari basis proyek yang ada.

PENTING:
- Jalankan backend dari folder proyek seperti biasa; ensureOutboundValidationSchema melakukan migrasi status ke DRAFT/PENDING/APPROVED/REJECTED/COMPLETED otomatis.
- Status Draft saat ini dibuat sebagai transaksi baru. Fitur edit isi draft yang sudah tersimpan belum ditambahkan.
- Status Completed adalah penanda penyelesaian setelah approval; pengurangan stok terjadi saat approve saja.
- Validasi build tidak dapat dijalankan di lingkungan pembuat: Go toolchain memerlukan unduhan jaringan dan Dart SDK tidak tersedia. Jalankan `go test ./...` dan `flutter analyze` di lingkungan proyek sebelum demo.
