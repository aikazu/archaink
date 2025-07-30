# Skrip Instalasi Arch Linux Otomatis

Skrip ini dirancang untuk mengotomatiskan dan menyederhanakan proses instalasi Arch Linux. Fokus utamanya adalah melakukan instalasi pada **partisi yang sudah ada**, memandu pengguna melalui serangkaian pilihan interaktif di awal, lalu menjalankan sisa proses instalasi dan konfigurasi secara mandiri.

Ini adalah alat yang ideal bagi pengguna yang sudah memahami konsep partisi disk dan ingin mempercepat penyiapan sistem dasar, lingkungan desktop, dan aplikasi-aplikasi penting.

## ✨ Fitur Utama

* **Instalasi Terpandu**: Proses interaktif untuk memilih partisi EFI, Swap, dan Root, serta untuk mengatur nama host, nama pengguna, dan kata sandi.
* **Pilihan Lingkungan Desktop**: Menginstal dan mengonfigurasi secara otomatis salah satu dari lingkungan modern berikut:
    * Hyprland (Wayland tiling window manager)
    * KDE Plasma (Desktop Environment berbasis Wayland)
    * GNOME (Desktop Environment berbasis Wayland)
* **Dukungan Driver Grafis**: Menyediakan opsi mudah untuk menginstal driver proprietary Nvidia.
* **AUR Helper Siap Pakai**: Menginstal `yay` secara otomatis, membuka akses mudah ke ribuan paket di Arch User Repository (AUR).
* **Konfigurasi Sistem Cerdas**: Menangani pengaturan penting seperti zona waktu (diatur ke Asia/Jakarta), locale, pembuatan pengguna dengan hak `sudo`, dan aktivasi NetworkManager.
* **Bootloader Modern**: Menggunakan dan mengonfigurasi `systemd-boot` secara otomatis untuk proses boot yang cepat dan bersih.
* **Penanganan Kesalahan & Cleanup**: Dilengkapi dengan mekanisme `trap` yang akan secara otomatis melepaskan (unmount) semua partisi jika terjadi kesalahan atau jika pengguna membatalkan proses, menjaga sistem tetap aman.
* **Aplikasi Esensial**: Menginstal beberapa aplikasi dasar seperti browser `brave-bin`, `neofetch`, `htop`, dan lainnya agar sistem siap digunakan.

## ⚠️ PERINGATAN SANGAT PENTING

* 🛑 **RISIKO KEHILANGAN DATA**: Skrip ini akan **MEMFORMAT TOTAL** partisi Root, EFI, dan Swap yang Anda pilih. Semua data yang ada di dalamnya akan **HILANG SECARA PERMANEN**. Pastikan Anda telah mencadangkan semua data penting dan benar-benar yakin dengan partisi yang Anda pilih.
* 💾 **TIDAK MELAKUKAN PARTISI**: Skrip ini **TIDAK** dapat membuat partisi. Anda **HARUS** membuat partisi secara manual menggunakan alat seperti `cfdisk`, `fdisk`, atau `gdisk` **SEBELUM** menjalankan skrip ini.

## 📋 Prasyarat

1.  **Media Instalasi Arch Linux**: Anda harus sudah boot dari USB instalasi Arch Linux.
2.  **Koneksi Internet**: Koneksi internet yang aktif dan stabil sangat penting untuk mengunduh semua paket yang diperlukan.
3.  **Disk yang Sudah Dipartisi**: Disk target Anda harus memiliki setidaknya tiga partisi berikut:
    * Partisi Sistem EFI (contoh: `/dev/sda1`, tipe: `EFI System`, diformat sebagai FAT32).
    * Partisi Swap (contoh: `/dev/sda2`, tipe: `Linux swap`).
    * Partisi Root (contoh: `/dev/sda3`, tipe: `Linux filesystem`, diformat sebagai ext4).

## 🚀 Cara Penggunaan

1.  **Boot ke Arch Linux Live Environment**.
2.  **Hubungkan ke Internet**. Jika Anda menggunakan Wi-Fi, Anda bisa memakai `iwctl`:
    ```bash
    # Masuk ke shell interaktif iwctl
    iwctl
    # Lihat daftar perangkat nirkabel (misalnya, wlan0)
    device list
    # Pindai jaringan di sekitar
    station wlan0 scan
    # Tampilkan daftar jaringan yang ditemukan
    station wlan0 get-networks
    # Hubungkan ke jaringan Anda (ganti NAMA_SSID)
    station wlan0 connect "NAMA_SSID_ANDA"
    # Keluar dari iwctl setelah terhubung
    exit
    ```
3.  **Unduh skrip ini**. Anda bisa menggunakan `git` untuk mengkloning repositori atau `curl` untuk mengunduh filenya saja.
    ```bash
    # Opsi 1: Menggunakan curl
    curl -O https://path/to/your/raw/arch-install.sh

    # Opsi 2: Menggunakan git (jika ini adalah bagian dari repositori)
    # git clone <URL_REPO_ANDA>
    # cd <NAMA_FOLDER_REPO>
    ```
4.  **Berikan izin eksekusi** pada skrip:
    ```bash
    chmod +x arch-install.sh
    ```
5.  **Jalankan skrip** dengan hak akses root:
    ```bash
    ./arch-install.sh
    ```
6.  **Ikuti Petunjuk di Layar**: Skrip akan memandu Anda melalui setiap langkah. Baca setiap pertanyaan dengan saksama, terutama saat mengonfirmasi partisi yang akan diformat.
7.  Setelah skrip selesai, sistem akan meminta Anda untuk menekan [Enter] untuk me-reboot. Keluarkan media instalasi Anda dan selamat menikmati sistem Arch Linux yang baru!

## 🔧 Detail Konfigurasi Teknis

* **Bootloader**: Menggunakan `systemd-boot`. Konfigurasi entri boot utama dibuat di `/boot/loader/entries/arch.conf`.
* **Display Manager**:
    * `sddm` diaktifkan untuk Hyprland dan KDE Plasma (dengan tema `sddm-minesddm-theme` yang sudah diatur).
    * `gdm` diaktifkan untuk GNOME.
* **Hak Akses Sudo**: Pengguna baru yang dibuat secara otomatis ditambahkan ke grup `wheel`. Baris `%wheel ALL=(ALL:ALL) ALL` diaktifkan di `/etc/sudoers` untuk memberikan hak sudo.
* **Lokalisasi**:
    * **Zona Waktu**: Diatur secara default ke `Asia/Jakarta`.
    * **Locale**: `en_US.UTF-8` (sebagai default sistem) dan `id_ID.UTF-8` di-generate.
    * Jika Anda berada di lokasi yang berbeda, Anda dapat mengubah nilai ini di dalam skrip sebelum menjalankannya.

---
*README ini dibuat untuk skrip `arch-install.sh`. Harap gunakan dengan bijak dan dengan risiko Anda sendiri.*
