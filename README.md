# Banana Panic Lab

Prototipe game teka-teki kooperatif 3D untuk **Godot 4.3+**, dibuat sebagai proyek orisinal. Tiga pemain harus menjinakkan bom dalam tiga menit. Masing-masing hanya memiliki sebagian informasi:

| Peran | Bisa melihat | Bisa melakukan |
| --- | --- | --- |
| Teknisi | Letak kabel, bentuk simbol, posisi saklar; tanpa warna dan angka seri | Menekan modul bom, mengetik pesan |
| Pengamat | Warna kabel, simbol, angka seri, warna sinyal | Mengetik pesan dan menjelaskan petunjuk visual |
| Pemandu | Aturan dalam manual; tanpa panel bom | Mengirim isyarat dari pilihan yang tersedia |

Host menjalankan logika puzzle. Klien hanya menerima data yang sesuai perannya. Tiga modul yang harus dituntaskan berurutan adalah kabel, simbol, dan saklar. Tiga kesalahan atau waktu habis mengakhiri ronde.

## Menjalankan proyek

1. Buka folder repo ini lewat **Godot Project Manager → Import → `project.godot`**.
2. Tekan **F6/F5** untuk menjalankan adegan/proyek.
3. Pilih **Latihan Solo** untuk bermain sendiri. Tukar peran di panel kanan untuk membaca petunjuk, kemudian kembali ke Teknisi untuk mengoperasikan bom.

## Bermain 3 pemain melalui LAN

1. Jalankan game pada tiga komputer dalam jaringan lokal yang sama, atau tiga instance di satu komputer.
2. Komputer pertama pilih **Host LAN**. Ia otomatis menjadi **Teknisi**.
3. Dua pemain lain isi alamat IPv4 lokal komputer host dan klik **Gabung LAN**. Urutannya mendapat peran **Pengamat**, lalu **Pemandu**.
4. Host klik **Mulai Misi** setelah tiga pemain tersambung.
5. Jika uji di satu komputer, gunakan alamat `127.0.0.1`. Pastikan firewall mengizinkan **UDP 24570** untuk LAN.

Game memakai `ENetMultiplayerPeer`, sehingga koneksi internet lintas jaringan memerlukan pengaturan UDP/VPN di luar proyek. Belum ada matchmaking, voice chat, animasi karakter, atau level kampanye. Tampilan karakter, meja, ruangan, dan panel bom dibangun dari primitive 3D tanpa aset berlisensi pihak lain.

## Struktur

- `project.godot` — konfigurasi proyek dan renderer Compatibility.
- `scenes/main.tscn` — adegan utama.
- `scripts/main.gd` — UI, ruangan 3D, lobby LAN, RPC, timer, dan validasi aksi di host.
- `scripts/rules.gd` — aturan dan pembangkitan puzzle.

## Rencana pengembangan

1. Uji bermain tiga perangkat; lengkapi indikator koneksi dan sinkronisasi ketika pemain terputus.
2. Ganti primitive 3D dengan model dan animasi buatan sendiri, kamera interaktif, serta interaksi langsung di objek 3D.
3. Tambahkan komunikasi suara dengan batasan sesuai peran, audio dan animasi bom, serta aksesibilitas warna.
4. Buat beberapa jenis modul, lingkungan, progres kampanye, dan pengujian multiplayer otomatis.

Proyek ini mengambil inspirasi mekanik kerja sama dengan informasi yang terbagi dari [BOMBANANA!](https://store.steampowered.com/app/4656000/BOMBANANA/). Kode, judul prototipe, aturan puzzle, dan visual di repo ini dibuat sendiri; tidak memakai aset game rujukan.
