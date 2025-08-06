#!/bin/bash
# ===================================================================================
#
#          SKRIP INSTALASI ARCH LINUX OTOMATIS (UEFI)
#
#   Deskripsi: Skrip ini mengotomatiskan instalasi Arch Linux pada sistem UEFI.
#   Peringatan: Skrip ini akan MENGHAPUS DATA pada partisi yang dipilih.
#              Gunakan dengan risiko Anda sendiri. Tinjau skrip sebelum eksekusi.
#
# ===================================================================================

# Keluar segera jika ada perintah yang gagal atau variabel yang tidak disetel.
set -euo pipefail

# --- Variabel Global & Tampilan ---
# Menggunakan tput untuk warna dan gaya teks agar lebih portabel dan jelas.
BOLD=$(tput bold)
BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# --- Fungsi Logging ---
# Fungsi-fungsi ini membantu memberikan output yang terstruktur dan berwarna.
info() { echo -e "${BLUE}${BOLD}[INFO]${RESET} $1"; }
warning() { echo -e "${YELLOW}${BOLD}[PERINGATAN]${RESET} $1"; }
error() { echo -e "${RED}${BOLD}[ERROR]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUKSES]${RESET} $1"; }

# --- Fungsi Cleanup & Error Handling ---
# Fungsi ini akan selalu dijalankan saat skrip keluar, baik normal maupun karena error.
cleanup() {
    # Memastikan tidak ada proses yang berjalan di dalam chroot sebelum unmount.
    fuser -k /mnt &>/dev/null
    
    warning "Menjalankan cleanup otomatis..."
    if mountpoint -q /mnt; then
        info "Mencoba unmount semua filesystem di /mnt secara rekursif..."
        # Menggunakan umount -R (rekursif) untuk unmount yang lebih andal.
        umount -R /mnt || warning "Unmount /mnt gagal. Mungkin sudah di-unmount."
        success "Semua filesystem di /mnt telah di-unmount."
    else
        info "Tidak ada filesystem yang termount di /mnt. Cleanup tidak diperlukan."
    fi
}
# Menangkap sinyal exit, error, interupsi, dan terminasi untuk menjalankan cleanup.
trap cleanup EXIT ERR INT TERM

# --- Pemeriksaan Pra-Instalasi ---
# Memastikan lingkungan sudah siap sebelum memulai proses instalasi.
pre_install_checks() {
    info "Menjalankan pemeriksaan pra-instalasi..."
    
    # 1. Verifikasi mode boot UEFI
    if [ ! -d /sys/firmware/efi/efivars ]; then
        error "Sistem tidak di-boot dalam mode UEFI. Skrip ini hanya mendukung instalasi UEFI."
        exit 1
    fi
    success "Sistem di-boot dalam mode UEFI."

    # 2. Verifikasi koneksi internet
    if ! ping -c 1 archlinux.org &> /dev/null; then
        error "Tidak ada koneksi internet. Silakan periksa koneksi Anda dan coba lagi."
        exit 1
    fi
    success "Koneksi internet terverifikasi."
    
    # 3. Verifikasi perintah penting
    if ! command -v arch-chroot &> /dev/null; then
        error "Perintah 'arch-chroot' tidak ditemukan. Pastikan Anda menjalankan skrip ini dari Arch Linux live environment."
        exit 1
    fi
    success "Lingkungan instalasi Arch terverifikasi."
}

# ===================================================================================
# TAHAP 1: PENGUMPULAN INFORMASI DARI PENGGUNA
# ===================================================================================
get_user_input() {
    info "Selamat datang di skrip instalasi Arch Linux."
    warning "Pastikan Anda sudah menyiapkan partisi untuk EFI, Swap, dan Root."
    echo ""

    # Menampilkan daftar block device untuk membantu pengguna memilih.
    lsblk -p -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,LABEL
    echo "------------------------------------------------------------------"

    # Fungsi pembantu untuk memilih partisi dengan validasi.
    select_partition() {
        local partition_name=$1
        local selected_partition
        while true; do
            read -p "-> Masukkan path partisi ${partition_name} (contoh: /dev/sda1): " selected_partition
            if [ -b "${selected_partition}" ]; then
                # Menggunakan 'declare -g' untuk membuat variabel menjadi global.
                declare -g "$2=${selected_partition}"
                break
            else
                error "Path '${selected_partition}' tidak valid atau bukan block device. Silakan coba lagi."
            fi
        done
    }

    select_partition "EFI" "EFI_PARTITION"
    select_partition "Swap" "SWAP_PARTITION"
    select_partition "Root" "ROOT_PARTITION"

    read -p "-> Apakah Anda menggunakan partisi Home terpisah? (y/n): " use_home
    if [[ "$use_home" =~ ^[Yy]$ ]]; then
        select_partition "Home" "HOME_PARTITION"
    else
        HOME_PARTITION=""
    fi

    # Validasi untuk memastikan tidak ada partisi yang sama digunakan untuk peran berbeda.
    local all_partitions=("$EFI_PARTITION" "$SWAP_PARTITION" "$ROOT_PARTITION")
    [[ -n "$HOME_PARTITION" ]] && all_partitions+=("$HOME_PARTITION")
    if [ $(printf "%s\n" "${all_partitions[@]}" | sort -u | wc -l) -ne ${#all_partitions[@]} ]; then
        error "Partisi yang sama tidak boleh digunakan untuk beberapa peran. Instalasi dibatalkan."
        exit 1
    fi
    success "Semua partisi yang dipilih unik."

    # Input Hostname dengan validasi.
    while true; do
        read -p "-> Masukkan hostname: " HOSTNAME
        if [[ "$HOSTNAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
            break
        else
            error "Hostname tidak valid. Gunakan hanya huruf kecil, angka, dan hyphen (-), tanpa spasi."
        fi
    done

    # Input Username dengan validasi.
    while true; do
        read -p "-> Masukkan nama pengguna baru (huruf kecil): " USERNAME
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ && "$USERNAME" != "root" ]]; then
            break
        else
            error "Nama pengguna tidak valid. Gunakan huruf kecil, angka, underscore, atau hyphen."
        fi
    done

    # Input Password dengan konfirmasi.
    while true; do
        read -s -p "-> Masukkan password untuk root dan pengguna baru: " PASSWORD
        echo
        read -s -p "-> Konfirmasi password: " PASSWORD_CONFIRM
        echo
        if [[ "$PASSWORD" == "$PASSWORD_CONFIRM" && -n "$PASSWORD" ]]; then
            break
        else
            error "Password tidak cocok atau kosong. Silakan coba lagi."
        fi
    done

    # Pilihan Desktop Environment (DE) menggunakan 'select'.
    info "Pilih Desktop Environment:"
    PS3="   Pilihan Anda: "
    select DE_CHOICE in "Hyprland" "KDE-Plasma" "GNOME" "None"; do
        [[ -n "$DE_CHOICE" ]] && break || warning "Pilihan tidak valid."
    done

    # Pilihan driver Nvidia.
    info "Apakah Anda menggunakan kartu grafis Nvidia?"
    select NVIDIA_CHOICE in "ya" "tidak"; do
        [[ -n "$NVIDIA_CHOICE" ]] && break || warning "Pilihan tidak valid."
    done
    
    # Pilihan jenis driver Nvidia jika diperlukan.
    if [[ "$NVIDIA_CHOICE" == "ya" ]]; then
        info "Pilih jenis driver Nvidia:"
        select NVIDIA_DRIVER_TYPE in "nvidia (untuk kernel standar)" "nvidia-dkms (untuk kernel custom/lts)"; do
            [[ -n "$NVIDIA_DRIVER_TYPE" ]] && break || warning "Pilihan tidak valid."
        done
    else
        NVIDIA_DRIVER_TYPE=""
    fi

    # Opsi untuk instalasi AUR
    info "Apakah Anda ingin menginstal AUR Helper (yay) dan beberapa paket populer dari AUR?"
    warning "Paket AUR dibuat oleh komunitas dan tidak didukung secara resmi oleh Arch Linux."
    select INSTALL_AUR in "ya" "tidak"; do
        [[ -n "$INSTALL_AUR" ]] && break || warning "Pilihan tidak valid."
    done

    AUR_PACKAGES=()
    if [[ "$INSTALL_AUR" == "ya" ]]; then
        # Daftar paket AUR yang akan diinstal. Bisa dimodifikasi sesuai kebutuhan.
        AUR_PACKAGES+=("brave-bin" "code")
        # Tambahkan tema sddm jika Hyprland atau KDE Plasma dipilih
        if [[ "$DE_CHOICE" == "Hyprland" || "$DE_CHOICE" == "KDE-Plasma" ]]; then
            AUR_PACKAGES+=("sddm-astronaut-theme")
        fi
    fi

    # Ringkasan konfigurasi sebelum melanjutkan.
    info "======================================================"
    info "         RINGKASAN KONFIGURASI INSTALASI          "
    info "======================================================"
    echo " > Hostname:          ${HOSTNAME}"
    echo " > Username:          ${USERNAME}"
    echo " > Desktop:           ${DE_CHOICE}"
    echo " > Driver Nvidia:     ${NVIDIA_CHOICE}"
    [[ "$NVIDIA_CHOICE" == "ya" ]] && echo " > Jenis Driver:      ${NVIDIA_DRIVER_TYPE%% *}"
    echo " > Instalasi AUR:     ${INSTALL_AUR}"
    if [[ "$INSTALL_AUR" == "ya" ]]; then
        echo " > Paket AUR:         ${AUR_PACKAGES[*]}"
    fi
    info "------------------------------------------------------"
    info "Partisi yang akan digunakan:"
    echo " > Partisi EFI:       ${EFI_PARTITION}"
    echo " > Partisi Swap:      ${SWAP_PARTITION}"
    echo " > Partisi Root:      ${ROOT_PARTITION}"
    [[ -n "$HOME_PARTITION" ]] && echo " > Partisi Home:      ${HOME_PARTITION}"
    info "======================================================"
    
    warning "PERHATIAN: TINJAU KONFIGURASI DI ATAS DENGAN SEKSAMA."
    error "PROSES BERIKUTNYA AKAN MEMFORMAT PARTISI EFI, SWAP, DAN ROOT."
    error "SEMUA DATA PADA PARTISI TERSEBUT AKAN HILANG PERMANEN."
    
    if [[ -n "$HOME_PARTITION" ]]; then
        read -p "-> Apakah Anda ingin memformat partisi Home (${HOME_PARTITION})? (y/n): " format_home
        if [[ "$format_home" =~ ^[Yy]$ ]]; then
            FORMAT_HOME="yes"
            error "Partisi Home (${HOME_PARTITION}) JUGA AKAN DIFORMAT."
        else
            FORMAT_HOME="no"
            warning "Partisi Home (${HOME_PARTITION}) TIDAK akan diformat."
        fi
    else
        FORMAT_HOME="no"
    fi

    read -p "Ketik 'LANJUTKAN' untuk memulai instalasi: " CONFIRM_INSTALL
    if [ "$CONFIRM_INSTALL" != "LANJUTKAN" ]; then
        error "Instalasi dibatalkan oleh pengguna."
        exit 1
    fi
}

# ===================================================================================
# TAHAP 2: PERSIAPAN SISTEM DARI LIVE ISO
# ===================================================================================
prepare_system() {
    info "Memulai proses persiapan sistem..."
    
    # Sinkronisasi jam sistem.
    timedatectl set-local-rtc 1
    timedatectl set-ntp true

    info "Memformat partisi..."
    mkfs.fat -F32 -n "EFISYS" "${EFI_PARTITION}"
    mkswap -L "SWAP" "${SWAP_PARTITION}"
    mkfs.ext4 -L "ROOT" "${ROOT_PARTITION}"
    if [[ "$FORMAT_HOME" == "yes" ]]; then
        info "Memformat partisi Home..."
        mkfs.ext4 -L "HOME" "${HOME_PARTITION}"
    fi
    success "Pemformatan partisi selesai."

    info "Mounting sistem file..."
    mount "${ROOT_PARTITION}" /mnt
    mount --mkdir "${EFI_PARTITION}" /mnt/boot
    if [[ -n "$HOME_PARTITION" ]]; then
        mount --mkdir "${HOME_PARTITION}" /mnt/home
    fi
    swapon "${SWAP_PARTITION}"
    success "Sistem file berhasil di-mount."

    info "Menginstal sistem dasar Arch Linux (base, linux, linux-firmware)..."
    info "Ini mungkin memakan waktu cukup lama tergantung koneksi internet."
    pacstrap -K /mnt base linux linux-firmware nano neovim git sudo networkmanager
    success "Sistem dasar berhasil diinstal."

    info "Membuat file fstab (menggunakan UUID untuk ketahanan)..."
    genfstab -U /mnt >> /mnt/etc/fstab
    success "File fstab berhasil dibuat."
}

# ===================================================================================
# TAHAP 3: CHROOT DAN KONFIGURASI SISTEM BARU
# ===================================================================================
run_chroot_config() {
    info "Memulai konfigurasi di dalam chroot..."

    # Mengonversi array paket AUR menjadi string yang akan dilewatkan ke chroot.
    local AUR_PACKAGES_STRING="${AUR_PACKAGES[*]}"

    # Menggunakan 'Here Document' (<<EOF) untuk menjalankan serangkaian perintah di dalam chroot.
    arch-chroot /mnt /bin/bash <<EOF
# Keluar segera jika ada perintah yang gagal di dalam chroot
set -euo pipefail

# --- Fungsi Logging di dalam Chroot ---
info_chroot() { echo -e "\e[1;34m[CHROOT-INFO]\e[0m \$1"; }
warn_chroot() { echo -e "\e[1;33m[CHROOT-WARN]\e[0m \$1"; }

info_chroot "Mengatur zona waktu ke Asia/Jakarta..."
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc

info_chroot "Mengatur locale (en_US.UTF-8 dan id_ID.UTF-8)..."
sed -i '/^#en_US.UTF-8/s/^#//' /etc/locale.gen
sed -i '/^#id_ID.UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

info_chroot "Mengatur hostname dan file hosts..."
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

info_chroot "Mengatur password untuk user 'root'..."
echo "root:${PASSWORD}" | chpasswd

info_chroot "Membuat pengguna baru '${USERNAME}'..."
useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${PASSWORD}" | chpasswd
info_chroot "Memberikan hak sudo kepada grup 'wheel'..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

info_chroot "Mengaktifkan layanan NetworkManager..."
systemctl enable NetworkManager

info_chroot "Mendeteksi vendor CPU untuk instalasi microcode..."
CPU_VENDOR=\$(lscpu | grep "Vendor ID" | awk '{print \$3}')
MICROCODE_PKG=""
if [[ "\$CPU_VENDOR" == "GenuineIntel" ]]; then
    info_chroot "CPU Intel terdeteksi. Menambahkan intel-ucode."
    MICROCODE_PKG="intel-ucode"
elif [[ "\$CPU_VENDOR" == "AuthenticAMD" ]]; then
    info_chroot "CPU AMD terdeteksi. Menambahkan amd-ucode."
    MICROCODE_PKG="amd-ucode"
else
    warn_chroot "Vendor CPU tidak dapat dideteksi. Melewatkan instalasi microcode."
fi

info_chroot "Menginstal dan mengonfigurasi bootloader (systemd-boot)..."
pacman -S --noconfirm --needed \$MICROCODE_PKG
bootctl install

echo "default arch.conf" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf
echo "editor no" >> /boot/loader/loader.conf

ROOT_PARTUUID=\$(blkid -s PARTUUID -o value "${ROOT_PARTITION}")
KERNEL_OPTIONS="root=PARTUUID=\${ROOT_PARTUUID} rw"

if [[ "${NVIDIA_CHOICE}" == "ya" ]]; then
    KERNEL_OPTIONS+=" nvidia_drm.modeset=1"
fi

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /\${MICROCODE_PKG}.img
initrd  /initramfs-linux.img
options \${KERNEL_OPTIONS}
ENTRY
info_chroot "Bootloader systemd-boot berhasil dikonfigurasi."

info_chroot "Mempersiapkan daftar paket untuk diinstal..."
PKGS_TO_INSTALL=()
PKGS_TO_INSTALL+=(pipewire wireplumber pipewire-pulse pavucontrol) # Audio stack
PKGS_TO_INSTALL+=(fastfetch htop file-roller unzip p7zip man-db bash-completion) # Utilitas dasar
PKGS_TO_INSTALL+=(qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg) # Ketergantungan untuk tema SDDM

case "${DE_CHOICE}" in
    "Hyprland")
        PKGS_TO_INSTALL+=(hyprland xdg-desktop-portal-hyprland xorg-xwayland waybar kitty wofi thunar sddm qt6-wayland)
        ;;
    "KDE-Plasma")
        PKGS_TO_INSTALL+=(plasma-meta kde-applications sddm konsole dolphin)
        ;;
    "GNOME")
        PKGS_TO_INSTALL+=(gnome gnome-tweaks gdm)
        ;;
    "None")
        info_chroot "Tidak ada Desktop Environment yang dipilih."
        ;;
esac

if [[ "${NVIDIA_CHOICE}" == "ya" ]]; then
    if [[ "${NVIDIA_DRIVER_TYPE}" == "nvidia-dkms"* ]]; then
        PKGS_TO_INSTALL+=(linux-headers nvidia-dkms nvidia-utils lib32-nvidia-utils)
    else
        PKGS_TO_INSTALL+=(nvidia nvidia-utils lib32-nvidia-utils)
    fi
fi

PKGS_TO_INSTALL+=(noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra nerd-fonts)

info_chroot "Menyinkronkan database paket dan menginstal paket tambahan..."
pacman -Syu --noconfirm --needed "\${PKGS_TO_INSTALL[@]}"

# --- Instalasi AUR (jika dipilih) ---
if [[ "${INSTALL_AUR}" == "ya" ]]; then
    info_chroot "Mempersiapkan instalasi paket AUR sebagai pengguna '${USERNAME}'..."
    # Install dependencies needed to build packages. base-devel is crucial.
    pacman -S --noconfirm --needed base-devel

    # Create a temporary script to be run as the new user
    cat > /home/${USERNAME}/install_aur.sh <<'AUR_SCRIPT'
#!/bin/bash
set -euo pipefail

echo "[AUR-HELPER] Memulai instalasi yay (AUR Helper)..."
cd /tmp
git clone https://aur.archlinux.org/yay.git
chown -R ${USERNAME}:${USERNAME} /tmp/yay
cd yay
# Build and install yay. makepkg needs to be run as a non-root user.
makepkg -si --noconfirm
cd /
rm -rf /tmp/yay

echo "[AUR-HELPER] Menginstal paket AUR yang dipilih..."
# Convert the space-separated string back to an array
AUR_PKGS_ARRAY=(${AUR_PACKAGES_TO_INSTALL})
if [ \${#AUR_PKGS_ARRAY[@]} -gt 0 ]; then
    yay -S --noconfirm --needed "\${AUR_PKGS_ARRAY[@]}"
else
    echo "[AUR-HELPER] Tidak ada paket AUR yang dipilih untuk diinstal."
fi

echo "[AUR-HELPER] Membersihkan cache build yang tidak diperlukan..."
yay -Sc --noconfirm

echo "[AUR-HELPER] Instalasi dan cleanup paket AUR selesai."
AUR_SCRIPT

    # Set correct ownership for the script
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}/install_aur.sh
    chmod +x /home/${USERNAME}/install_aur.sh

    info_chroot "Menjalankan skrip instalasi AUR sebagai pengguna '${USERNAME}'..."
    # This is the secure part: run the script as the non-root user
    su - "${USERNAME}" -c "AUR_PACKAGES_TO_INSTALL='${AUR_PACKAGES_STRING}' /home/${USERNAME}/install_aur.sh"
    
    # Clean up the script
    rm /home/${USERNAME}/install_aur.sh
fi

info_chroot "Mengaktifkan Display Manager..."
if [[ "${DE_CHOICE}" == "Hyprland" || "${DE_CHOICE}" == "KDE-Plasma" ]]; then
    systemctl enable sddm
    # Konfigurasi tema SDDM jika Hyprland/KDE dan instalasi AUR dipilih
    if [[ ( "${DE_CHOICE}" == "Hyprland" || "${DE_CHOICE}" == "KDE-Plasma" ) && "${INSTALL_AUR}" == "ya" ]]; then
        info_chroot "Mengonfigurasi tema SDDM 'sddm-astronaut-theme'..."
        echo -e "[Theme]\nCurrent=sddm-astronaut-theme" > /etc/sddm.conf
        mkdir -p /etc/sddm.conf.d
        echo -e "[General]\nInputMethod=qtvirtualkeyboard" > /etc/sddm.conf.d/virtualkbd.conf
        info_chroot "Tema SDDM dan keyboard virtual telah dikonfigurasi."
    fi
elif [[ "${DE_CHOICE}" == "GNOME" ]]; then
    systemctl enable gdm
fi

info_chroot "Konfigurasi di dalam chroot selesai."
EOF
    success "Konfigurasi chroot berhasil diselesaikan."
}

# ===================================================================================
#                                 FUNGSI UTAMA
# ===================================================================================
main() {
    pre_install_checks
    get_user_input
    prepare_system
    run_chroot_config

    success "======================================================"
    success "         INSTALASI ARCH LINUX TELAH SELESAI!          "
    success "======================================================"
    info "Sistem siap untuk di-reboot. Keluarkan media instalasi Anda."
    info "Setelah reboot, login dengan pengguna: ${BOLD}${USERNAME}${RESET}"
    
    read -p "Tekan [Enter] untuk reboot sekarang, atau Ctrl+C untuk keluar ke shell..."
    reboot
}

# Jalankan fungsi utama skrip
main
