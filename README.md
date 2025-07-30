Skrip Instalasi Arch Linux Otomatis
Skrip ini dirancang untuk mengotomatiskan proses instalasi Arch Linux pada partisi yang sudah ada. Tujuannya adalah untuk menyederhanakan proses instalasi dengan memandu pengguna melalui serangkaian pilihan interaktif di awal, lalu menjalankan sisa instalasi secara otomatis.

Skrip ini sangat cocok untuk pengguna yang sudah terbiasa dengan partisi manual dan ingin mempercepat proses penyiapan sistem dasar, lingkungan desktop, dan aplikasi penting.

✨ Fitur Utama
Instalasi Interaktif: Memandu pengguna untuk memilih partisi, nama host, pengguna, dan kata sandi.

Pilihan Lingkungan Desktop: Otomatis menginstal dan mengonfigurasi salah satu dari:

Hyprland (Window Manager Wayland)

KDE Plasma (Wayland)

GNOME (Wayland)

Dukungan Driver Nvidia: Pilihan untuk menginstal driver Nvidia proprietary secara otomatis.

Penyiapan AUR Helper: Menginstal yay secara otomatis untuk memudahkan manajemen paket dari Arch User Repository (AUR).

Konfigurasi Sistem Otomatis: Menangani zona waktu (diatur ke Asia/Jakarta), locale, pengguna dengan hak sudo, dan NetworkManager.

Bootloader Modern: Mengonfigurasi systemd-boot secara otomatis.

Penanganan Kesalahan: Dilengkapi dengan mekanisme cleanup untuk melepaskan (unmount) semua partisi jika terjadi kesalahan atau pembatalan, menjaga sistem tetap bersih.

Aplikasi Esensial: Menginstal aplikasi dasar seperti brave-bin, neofetch, htop, dan lainnya untuk memulai.

⚠️ Peringatan Sangat Penting
🛑 AKAN MENGHAPUS DATA: Skrip ini akan MEMFORMAT partisi Root, EFI, dan Swap yang Anda pilih. Semua data pada partisi tersebut akan HILANG SECARA PERMANEN. Pastikan Anda telah mencadangkan data penting dan memilih partisi yang benar.

💾 PARTISI TIDAK TERMASUK: Skrip ini TIDAK melakukan partisi disk. Anda HARUS membuat partisi EFI, Swap, dan Root secara manual menggunakan alat seperti cfdisk, fdisk, atau gdisk SEBELUM menjalankan skrip ini.

📋 Prasyarat
Media Instalasi Arch Linux: Anda harus boot dari USB instalasi Arch Linux yang berfungsi.

Koneksi Internet: Koneksi internet yang aktif dan stabil diperlukan untuk mengunduh paket.

Disk yang Sudah Dipartisi: Disk target Anda harus memiliki setidaknya tiga partisi berikut:

Partisi Sistem EFI (contoh: /dev/sda1, diformat sebagai FAT32).

Partisi Swap (contoh: /dev/sda2).

Partisi Root (contoh: /dev/sda3, diformat sebagai ext4).

🚀 Cara Penggunaan
Boot ke Arch Linux Live Environment.

Hubungkan ke Internet. Untuk Wi-Fi, Anda dapat menggunakan iwctl:

Bash

# Masuk ke shell iwctl
iwctl
# Daftar perangkat (misalnya, wlan0)
device list
# Pindai jaringan
station wlan0 scan
# Lihat jaringan yang tersedia
station wlan0 get-networks
# Hubungkan ke jaringan Anda
station wlan0 connect "NAMA_SSID_ANDA"
# Keluar dari iwctl
exit
Unduh skrip ini. Anda bisa menggunakan git atau curl.

Bash

# Menggunakan git (disarankan)
git clone <URL_REPO_ANDA>
cd <NAMA_FOLDER_REPO>

# Atau menggunakan curl
curl -O https://path/to/your/raw/arch-install.sh
Jadikan skrip dapat dieksekusi:

Bash

chmod +x arch-install.sh
Jalankan skrip sebagai root:

Bash

./arch-install.sh
Ikuti Petunjuk: Skrip akan meminta Anda untuk memasukkan informasi yang diperlukan. Baca setiap langkah dengan cermat, terutama saat memilih partisi.

Setelah skrip selesai, sistem akan meminta Anda untuk me-reboot. Keluarkan media instalasi dan nikmati instalasi Arch Linux baru Anda!

🔧 Detail Konfigurasi
Bootloader: Menggunakan systemd-boot. Konfigurasi dibuat di /boot/loader/entries/arch.conf.

Display Manager:

sddm untuk Hyprland dan KDE Plasma (dengan tema sddm-minesddm-theme).

gdm untuk GNOME.

Sudo: Pengguna baru yang dibuat akan ditambahkan ke grup wheel, yang secara default diberikan hak sudo.

Lokalisasi:

Zona Waktu: Asia/Jakarta.

Locale: en_US.UTF-8 (default) dan id_ID.UTF-8.

Jika Anda berada di lokasi lain, Anda mungkin ingin mengubah bagian ini di dalam skrip (chroot-setup.sh) sebelum menjalankannya.
