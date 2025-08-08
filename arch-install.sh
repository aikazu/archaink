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

set -euo pipefail

# --- Variabel Global & Tampilan ---
BOLD=$(tput bold)
BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# --- Fungsi Logging ---
info() { echo -e "${BLUE}${BOLD}[INFO]${RESET} $1"; }
warning() { echo -e "${YELLOW}${BOLD}[PERINGATAN]${RESET} $1"; }
error() { echo -e "${RED}${BOLD}[ERROR]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUKSES]${RESET} $1"; }

# --- Fungsi Cleanup & Error Handling ---
cleanup() {
    warning "Menjalankan cleanup otomatis..."
    if mountpoint -q /mnt; then
        info "Mencoba unmount semua filesystem di /mnt secara rekursif..."
        if umount -R /mnt; then
            success "Semua filesystem di /mnt telah di-unmount."
        else
            warning "Unmount /mnt gagal. Mungkin sudah di-unmount atau sedang digunakan."
        fi
    else
        info "Tidak ada filesystem yang termount di /mnt. Cleanup tidak diperlukan."
    fi
}
trap cleanup EXIT ERR INT TERM

# --- Pemeriksaan Pra-Instalasi ---
pre_install_checks() {
    info "Menjalankan pemeriksaan pra-instalasi..."

    # 0. Harus root
    if [ "$(id -u)" -ne 0 ]; then
        error "Skrip harus dijalankan sebagai root."
        exit 1
    fi

    # 1. Verifikasi mode boot UEFI
    if [ ! -d /sys/firmware/efi/efivars ]; then
        error "Sistem tidak di-boot dalam mode UEFI. Skrip ini hanya mendukung instalasi UEFI."
        exit 1
    fi
    success "Sistem di-boot dalam mode UEFI."

    # 2. Verifikasi koneksi internet
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        error "Tidak ada koneksi internet. Silakan periksa koneksi Anda dan coba lagi."
        exit 1
    fi
    success "Koneksi internet terverifikasi."

    # 3. Verifikasi perintah penting
    if ! command -v arch-chroot &>/dev/null; then
        error "Perintah 'arch-chroot' tidak ditemukan. Jalankan skrip ini dari Arch Linux live environment."
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

    lsblk -p -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,LABEL
    echo "------------------------------------------------------------------"

    select_partition() {
        local partition_name=$1
        local selected_partition
        while true; do
            read -p "-> Masukkan path partisi ${partition_name} (contoh: /dev/sda1): " selected_partition
            if [ -b "${selected_partition}" ]; then
                if [[ $(lsblk -dno TYPE "${selected_partition}") == "part" ]]; then
                    if findmnt -rn -S "${selected_partition}" &>/dev/null; then
                        error "Partisi ${selected_partition} sedang termount. Unmount terlebih dahulu."
                    else
                        declare -g "$2"="${selected_partition}"
                        break
                    fi
                else
                    error "'${selected_partition}' bukan sebuah partisi. Pilih partisi (contoh: /dev/sda1), bukan disk (contoh: /dev/sda)."
                fi
            else
                error "Path '${selected_partition}' tidak valid atau bukan block device. Silakan coba lagi."
            fi
        done
    }

    select_partition "EFI" "EFI_PARTITION"
    select_partition "Swap" "SWAP_PARTITION"
    select_partition "Root" "ROOT_PARTITION"

    read -p "-> Apakah Anda menggunakan partisi Home terpisah? (y/n): " use_home
    if [[ "${use_home}" =~ ^[Yy]$ ]]; then
        select_partition "Home" "HOME_PARTITION"
    else
        HOME_PARTITION=""
    fi

    # Pastikan partisi unik
    local all_partitions=("${EFI_PARTITION}" "${SWAP_PARTITION}" "${ROOT_PARTITION}")
    [[ -n "${HOME_PARTITION}" ]] && all_partitions+=("${HOME_PARTITION}")
    if [ "$(printf "%s\n" "${all_partitions[@]}" | sort -u | wc -l)" -ne "${#all_partitions[@]}" ]; then
        error "Partisi yang sama tidak boleh digunakan untuk beberapa peran. Instalasi dibatalkan."
        exit 1
    fi
    success "Semua partisi yang dipilih unik."

    # Hostname
    while true; do
        read -p "-> Masukkan hostname: " HOSTNAME
        if [[ "${HOSTNAME}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
            break
        else
            error "Hostname tidak valid. Gunakan huruf kecil, angka, dan hyphen (-), tanpa spasi."
        fi
    done

    # Username
    while true; do
        read -p "-> Masukkan nama pengguna baru (huruf kecil): " USERNAME
        if [[ "${USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ && "${USERNAME}" != "root" ]]; then
            break
        else
            error "Nama pengguna tidak valid. Gunakan huruf kecil, angka, underscore, atau hyphen."
        fi
    done

    # Password (root dan user)
    while true; do
        read -s -p "-> Masukkan password untuk root dan pengguna baru: " PASSWORD
        echo
        read -s -p "-> Konfirmasi password: " PASSWORD_CONFIRM
        echo
        if [[ "${PASSWORD}" == "${PASSWORD_CONFIRM}" && -n "${PASSWORD}" ]]; then
            break
        else
            error "Password tidak cocok atau kosong. Silakan coba lagi."
        fi
    done

    # Desktop Environment
    info "Pilih Desktop Environment:"
    PS3="   Pilihan Anda: "
    select DE_CHOICE in "Hyprland" "KDE-Plasma" "GNOME" "None"; do
        [[ -n "${DE_CHOICE}" ]] && break || warning "Pilihan tidak valid."
    done

    # Nvidia
    info "Apakah Anda menggunakan kartu grafis Nvidia?"
    select NVIDIA_CHOICE in "ya" "tidak"; do
        [[ -n "${NVIDIA_CHOICE}" ]] && break || warning "Pilihan tidak valid."
    done
    if [[ "${NVIDIA_CHOICE}" == "ya" ]]; then
        info "Pilih jenis driver Nvidia:"
        select NVIDIA_DRIVER_TYPE in "nvidia (untuk kernel standar)" "nvidia-dkms (untuk kernel custom/lts)"; do
            [[ -n "${NVIDIA_DRIVER_TYPE}" ]] && break || warning "Pilihan tidak valid."
        done
    else
        NVIDIA_DRIVER_TYPE=""
    fi

    # Dual boot (RTC)
    info "Apakah sistem ini dual boot dengan Windows? (Jika ya, RTC akan diatur ke local time)"
    select DUALBOOT in "ya" "tidak"; do
        [[ -n "${DUALBOOT}" ]] && break || warning "Pilihan tidak valid."
    done

    # AUR
    info "Apakah Anda ingin menginstal AUR Helper (yay) dan paket AUR populer?"
    warning "Paket AUR dibuat oleh komunitas dan tidak didukung resmi oleh Arch Linux."
    select INSTALL_AUR in "ya" "tidak"; do
        [[ -n "${INSTALL_AUR}" ]] && break || warning "Pilihan tidak valid."
    done
    AUR_PACKAGES=()
    if [[ "${INSTALL_AUR}" == "ya" ]]; then
        # nerd-fonts (AUR) untuk menginstal seluruh kumpulan Nerd Fonts (ukuran sangat besar)
        AUR_PACKAGES+=("nerd-fonts")
        AUR_PACKAGES+=("brave-bin" "visual-studio-code-bin")
        if [[ "${DE_CHOICE}" == "Hyprland" || "${DE_CHOICE}" == "KDE-Plasma" ]]; then
            AUR_PACKAGES+=("sddm-astronaut-theme")
        fi
    fi

    # Ringkasan
    info "======================================================"
    info "         RINGKASAN KONFIGURASI INSTALASI          "
    info "======================================================"
    echo " > Hostname:          ${HOSTNAME}"
    echo " > Username:          ${USERNAME}"
    echo " > Desktop:           ${DE_CHOICE}"
    echo " > Driver Nvidia:     ${NVIDIA_CHOICE}"
    [[ "${NVIDIA_CHOICE}" == "ya" ]] && echo " > Jenis Driver:      ${NVIDIA_DRIVER_TYPE%% *}"
    echo " > Dual Boot Windows: ${DUALBOOT}"
    echo " > Instalasi AUR:     ${INSTALL_AUR}"
    if [[ "${INSTALL_AUR}" == "ya" ]]; then
        echo " > Paket AUR:         ${AUR_PACKAGES[*]}"
        warning "Paket 'nerd-fonts' akan menginstal banyak font (unduhan besar, proses lama)."
    else
        warning "AUR tidak dipilih. Paket 'nerd-fonts' tidak akan diinstal."
    fi
    info "------------------------------------------------------"
    info "Partisi yang akan digunakan:"
    echo " > Partisi EFI:       ${EFI_PARTITION}"
    echo " > Partisi Swap:      ${SWAP_PARTITION}"
    echo " > Partisi Root:      ${ROOT_PARTITION}"
    [[ -n "${HOME_PARTITION}" ]] && echo " > Partisi Home:      ${HOME_PARTITION}"
    info "======================================================"

    warning "PERHATIAN: TINJAU KONFIGURASI DI ATAS DENGAN SEKSAMA."
    error "PROSES BERIKUTNYA AKAN MEMFORMAT PARTISI EFI, SWAP, DAN ROOT."
    error "SEMUA DATA PADA PARTISI TERSEBUT AKAN HILANG PERMANEN."

    if [[ -n "${HOME_PARTITION}" ]]; then
        read -p "-> Apakah Anda ingin memformat partisi Home (${HOME_PARTITION})? (y/n): " format_home
        if [[ "${format_home}" =~ ^[Yy]$ ]]; then
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
    if [ "${CONFIRM_INSTALL}" != "LANJUTKAN" ]; then
        error "Instalasi dibatalkan oleh pengguna."
        exit 1
    fi
}

# ===================================================================================
# TAHAP 2: PERSIAPAN SISTEM DARI LIVE ISO
# ===================================================================================
prepare_system() {
    info "Memulai proses persiapan sistem..."

    # Sinkronisasi jam (tanpa memaksa RTC local time di live environment)
    timedatectl set-ntp true

    info "Memformat partisi..."
    mkfs.fat -F32 -n "EFISYS" "${EFI_PARTITION}"
    mkswap -L "SWAP" "${SWAP_PARTITION}"
    mkfs.ext4 -L "ROOT" "${ROOT_PARTITION}"
    if [[ "${FORMAT_HOME}" == "yes" ]]; then
        info "Memformat partisi Home..."
        mkfs.ext4 -L "HOME" "${HOME_PARTITION}"
    fi
    success "Pemformatan partisi selesai."

    info "Mounting sistem file..."
    mount "${ROOT_PARTITION}" /mnt
    mount --mkdir "${EFI_PARTITION}" /mnt/boot
    if [[ -n "${HOME_PARTITION}" ]]; then
        mount --mkdir "${HOME_PARTITION}" /mnt/home
    fi
    swapon "${SWAP_PARTITION}"
    success "Sistem file berhasil di-mount."

    info "Menginstal sistem dasar Arch Linux..."
    pacstrap -K /mnt base linux linux-firmware nano neovim git sudo networkmanager
    success "Sistem dasar berhasil diinstal."

    info "Membuat file fstab (UUID)..."
    genfstab -U /mnt >> /mnt/etc/fstab
    success "File fstab berhasil dibuat."
}

# ===================================================================================
# TAHAP 3: CHROOT DAN KONFIGURASI SISTEM BARU
# ===================================================================================
run_chroot_config() {
    info "Memulai konfigurasi di dalam chroot..."

    local AUR_PACKAGES_STRING="${AUR_PACKAGES[*]}"

    arch-chroot /mnt /usr/bin/env \
        HOSTNAME_VAL="${HOSTNAME}" \
        USERNAME_VAL="${USERNAME}" \
        PASSWORD_VAL="${PASSWORD}" \
        DE_CHOICE="${DE_CHOICE}" \
        NVIDIA_CHOICE="${NVIDIA_CHOICE}" \
        NVIDIA_DRIVER_TYPE="${NVIDIA_DRIVER_TYPE}" \
        INSTALL_AUR="${INSTALL_AUR}" \
        AUR_PACKAGES_STRING="${AUR_PACKAGES_STRING}" \
        ROOT_PART="${ROOT_PARTITION}" \
        DUALBOOT="${DUALBOOT}" \
        /bin/bash -s <<'CHROOT'
set -euo pipefail

info_chroot() { echo -e "\e[1;34m[CHROOT-INFO]\e[0m $1"; }
warn_chroot() { echo -e "\e[1;33m[CHROOT-WARN]\e[0m $1"; }

# Zona waktu dan waktu sistem
info_chroot "Mengatur zona waktu ke Asia/Jakarta..."
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc
systemctl enable systemd-timesyncd || true

# Atur RTC ke local time bila dual boot Windows
if [ "${DUALBOOT}" = "ya" ]; then
    info_chroot "Dual boot terdeteksi. Mengatur RTC ke local time."
    timedatectl set-local-rtc 1 --adjust-system-clock
else
    info_chroot "Bukan dual boot. Mengatur RTC ke UTC (default)."
    timedatectl set-local-rtc 0 --adjust-system-clock
fi

# Locale
info_chroot "Mengatur locale (en_US.UTF-8 dan id_ID.UTF-8)..."
sed -i 's/^#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\(id_ID\.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname & hosts
info_chroot "Mengatur hostname dan file hosts..."
echo "${HOSTNAME_VAL}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME_VAL}.localdomain ${HOSTNAME_VAL}
HOSTS

# Akun dan sudo
info_chroot "Mengatur password root dan membuat user '${USERNAME_VAL}'..."
echo "root:${PASSWORD_VAL}" | chpasswd
useradd -m -G wheel -s /bin/bash "${USERNAME_VAL}"
echo "${USERNAME_VAL}:${PASSWORD_VAL}" | chpasswd

info_chroot "Memberikan hak sudo kepada grup 'wheel'..."
install -m 440 -o root -g root /dev/stdin /etc/sudoers.d/wheel <<'SUDOERS'
%wheel ALL=(ALL:ALL) ALL
SUDOERS

# Pacman tuning
sed -i -E 's/^#?Color/Color/' /etc/pacman.conf || true
sed -i -E 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf || true

# NetworkManager
systemctl enable NetworkManager

# Microcode
info_chroot "Mendeteksi vendor CPU untuk instalasi microcode..."
CPU_VENDOR=$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2}')
MICROCODE_PKG=""
MICROCODE_IMG=""
if [ "${CPU_VENDOR}" = "GenuineIntel" ]; then
    info_chroot "CPU Intel terdeteksi. Menambahkan intel-ucode."
    MICROCODE_PKG="intel-ucode"
    MICROCODE_IMG="intel-ucode.img"
elif [ "${CPU_VENDOR}" = "AuthenticAMD" ]; then
    info_chroot "CPU AMD terdeteksi. Menambahkan amd-ucode."
    MICROCODE_PKG="amd-ucode"
    MICROCODE_IMG="amd-ucode.img"
else
    warn_chroot "Vendor CPU tidak dapat dideteksi. Melewatkan instalasi microcode."
fi
if [ -n "${MICROCODE_PKG}" ]; then
    pacman -S --noconfirm --needed "${MICROCODE_PKG}"
fi

# systemd-boot
info_chroot "Menginstal dan mengonfigurasi systemd-boot..."
bootctl install

install -d /boot/loader/entries
cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
editor no
EOF

ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${ROOT_PART}")
KERNEL_OPTIONS="root=PARTUUID=${ROOT_PARTUUID} rw"
if [ "${NVIDIA_CHOICE}" = "ya" ]; then
    KERNEL_OPTIONS+=" nvidia_drm.modeset=1"
fi

{
    echo "title   Arch Linux"
    echo "linux   /vmlinuz-linux"
    if [ -n "${MICROCODE_IMG}" ]; then
        echo "initrd  /${MICROCODE_IMG}"
    fi
    echo "initrd  /initramfs-linux.img"
    echo "options ${KERNEL_OPTIONS}"
} > /boot/loader/entries/arch.conf
info_chroot "Bootloader systemd-boot berhasil dikonfigurasi."

# Paket
info_chroot "Mempersiapkan daftar paket untuk diinstal..."
PKGS_TO_INSTALL=(
    pipewire wireplumber pipewire-pulse pavucontrol
    fastfetch htop file-roller unzip p7zip man-db bash-completion
    xdg-user-dirs
    qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
)

case "${DE_CHOICE}" in
    "Hyprland")
        PKGS_TO_INSTALL+=(hyprland xdg-desktop-portal-hyprland xorg-xwayland waybar kitty wofi thunar qt6-wayland sddm)
        ;;
    "KDE-Plasma")
        PKGS_TO_INSTALL+=(plasma-meta kde-applications sddm konsole dolphin xdg-desktop-portal-kde qt6-wayland)
        ;;
    "GNOME")
        PKGS_TO_INSTALL+=(gnome gnome-tweaks gdm)
        ;;
    "None")
        ;;
esac

if [ "${NVIDIA_CHOICE}" = "ya" ]; then
    if [[ "${NVIDIA_DRIVER_TYPE}" == nvidia-dkms* ]]; then
        PKGS_TO_INSTALL+=(linux-headers nvidia-dkms nvidia-utils lib32-nvidia-utils)
    else
        PKGS_TO_INSTALL+=(nvidia nvidia-utils lib32-nvidia-utils)
    fi
fi

info_chroot "Menginstal paket tambahan..."
pacman -Syu --noconfirm --needed "${PKGS_TO_INSTALL[@]}"

# AUR (yay)
if [ "${INSTALL_AUR}" = "ya" ]; then
    info_chroot "Menyiapkan yay dan paket AUR untuk user '${USERNAME_VAL}'..."
    pacman -S --noconfirm --needed base-devel git
    if [ -n "${AUR_PACKAGES_STRING}" ]; then
        info_chroot "Menginstal paket AUR: ${AUR_PACKAGES_STRING}"
        su - "${USERNAME_VAL}" -c "set -euo pipefail; cd \"\$(mktemp -d)\"; git clone https://aur.archlinux.org/yay.git; cd yay; makepkg -si --noconfirm; yay -S --noconfirm --needed ${AUR_PACKAGES_STRING}; yay -Sc --noconfirm || true"
    else
        su - "${USERNAME_VAL}" -c "set -euo pipefail; cd \"\$(mktemp -d)\"; git clone https://aur.archlinux.org/yay.git; cd yay; makepkg -si --noconfirm; yay -Sc --noconfirm || true"
    fi
    info_chroot "Instalasi paket AUR selesai."
fi

# Display Manager
info_chroot "Mengaktifkan Display Manager..."
if [[ "${DE_CHOICE}" == "Hyprland" || "${DE_CHOICE}" == "KDE-Plasma" ]]; then
    systemctl enable sddm
    if [[ "${INSTALL_AUR}" == "ya" && -d /usr/share/sddm/themes/sddm-astronaut-theme ]]; then
        mkdir -p /etc/sddm.conf.d
        echo -e "[Theme]\nCurrent=sddm-astronaut-theme" > /etc/sddm.conf.d/theme.conf
        echo -e "[General]\nInputMethod=qtvirtualkeyboard" > /etc/sddm.conf.d/virtualkbd.conf
        info_chroot "Tema SDDM dan keyboard virtual telah dikonfigurasi."
    fi
elif [ "${DE_CHOICE}" == "GNOME" ]; then
    systemctl enable gdm
fi

# Direktori user standar
xdg-user-dirs-update || true

info_chroot "Konfigurasi di dalam chroot selesai."
CHROOT

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

    read -p "Tekan [Enter] untuk reboot sekarang, atau Ctrl+C untuk keluar ke shell..." _
    reboot
}

main
