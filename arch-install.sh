#!/bin/bash
# ===================================================================================
#         SKRIP INSTALASI ARCH LINUX OTOMATIS (VERSI ROBUST)
# ===================================================================================
# Deskripsi:
# Skrip ini mengotomatiskan instalasi Arch Linux pada partisi yang sudah ada.
# Ditingkatkan untuk modularitas, keamanan, dan fleksibilitas yang lebih baik.
#
# Peringatan:
# Skrip ini akan MENGHAPUS SEMUA DATA pada partisi yang Anda pilih.
# Gunakan dengan risiko Anda sendiri. Selalu backup data penting terlebih dahulu.
# ===================================================================================

# Keluar segera jika ada perintah yang gagal
set -e

# --- Fungsi Bantuan & Tampilan ---
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
warning() { echo -e "\e[33m[PERINGATAN]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
success() { echo -e "\e[32m[SUKSES]\e[0m $1"; }

# --- Fungsi Cleanup & Error Handling ---
cleanup() {
    warning "Menjalankan cleanup..."
    if mount | grep -q ' on /mnt'; then
        info "Mencoba unmount /mnt secara rekursif..."
        umount -R /mnt || warning "Unmount /mnt gagal, mungkin sudah di-unmount."
        success "Semua filesystem di /mnt telah di-unmount."
    else
        info "Tidak ada filesystem yang termount di /mnt. Cleanup tidak diperlukan."
    fi
}
trap cleanup EXIT ERR INT TERM

# --- Pemeriksaan Pra-Instalasi ---
pre_install_checks() {
    info "Menjalankan pemeriksaan pra-instalasi..."
    # 1. Periksa mode boot (harus UEFI)
    if [ ! -d /sys/firmware/efi/efivars ]; then
        error "Sistem tidak di-boot dalam mode UEFI."
        error "Skrip ini hanya mendukung instalasi UEFI dengan systemd-boot."
        exit 1
    fi
    success "Sistem di-boot dalam mode UEFI."

    # 2. Periksa koneksi internet
    if ! ping -c 3 archlinux.org &> /dev/null; then
        error "Tidak ada koneksi internet. Silakan periksa koneksi Anda."
        exit 1
    fi
    success "Koneksi internet terverifikasi."
}


# ===================================================================================
# TAHAP 1: PENGUMPULAN INFORMASI DARI PENGGUNA
# ===================================================================================
get_user_input() {
    info "Selamat datang di skrip instalasi Arch Linux yang disempurnakan."
    warning "Pastikan Anda sudah memiliki partisi untuk EFI, Swap, Root, dan (opsional) Home."
    echo ""

    lsblk -p -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT
    echo ""

    # Validasi input partisi yang lebih andal
    select_partition() {
        local partition_name=$1
        local partition_var=$2
        local selected_partition
        while true; do
            read -p "Masukkan path partisi ${partition_name} (contoh: /dev/sda1): " selected_partition
            # Menggunakan test -b untuk memeriksa apakah file adalah block device (cara paling andal)
            if [ -b "${selected_partition}" ]; then
                eval "$partition_var='${selected_partition}'"
                break
            else
                error "Path '${selected_partition}' tidak valid atau bukan block device. Silakan coba lagi."
            fi
        done
    }

    select_partition "EFI" "EFI_PARTITION"
    select_partition "Swap" "SWAP_PARTITION"
    select_partition "Root" "ROOT_PARTITION"

    read -p "Apakah Anda menggunakan partisi Home terpisah? (y/n): " use_home
    if [[ "$use_home" == "y" || "$use_home" == "Y" ]]; then
        select_partition "Home" "HOME_PARTITION"
    else
        HOME_PARTITION=""
    fi

    # Validasi bahwa semua partisi unik
    local all_partitions=("$EFI_PARTITION" "$SWAP_PARTITION" "$ROOT_PARTITION")
    [[ -n "$HOME_PARTITION" ]] && all_partitions+=("$HOME_PARTITION")
    if [ $(printf "%s\n" "${all_partitions[@]}" | sort | uniq -d | wc -l) -ne 0 ]; then
        error "Partisi yang sama tidak boleh digunakan untuk beberapa peran. Instalasi dibatalkan."
        exit 1
    fi
    success "Semua partisi yang dipilih unik."

    while true; do
        read -p "Masukkan hostname: " HOSTNAME
        [[ "$HOSTNAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && break || error "Hostname tidak valid."
    done

    while true; do
        read -p "Masukkan nama pengguna baru (huruf kecil): " USERNAME
        [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ && "$USERNAME" != "root" ]] && break || error "Nama pengguna tidak valid."
    done

    while true; do
        read -sp "Masukkan password untuk root dan pengguna baru: " pass
        echo
        read -sp "Konfirmasi password: " pass_confirm
        echo
        [[ "$pass" == "$pass_confirm" && -n "$pass" ]] && break || error "Password tidak cocok atau kosong."
    done
    PASSWORD="$pass"

    info "Pilih vendor CPU Anda:"
    select CPU_VENDOR in "amd" "intel"; do [[ -n "$CPU_VENDOR" ]] && break || warning "Pilihan tidak valid."; done

    info "Pilih Desktop Environment:"
    select DE_CHOICE in "Hyprland" "KDE-Plasma" "GNOME"; do [[ -n "$DE_CHOICE" ]] && break || warning "Pilihan tidak valid."; done

    info "Apakah Anda ingin menginstal driver Nvidia?"
    select NVIDIA_CHOICE in "ya" "tidak"; do [[ -n "$NVIDIA_CHOICE" ]] && break || warning "Pilihan tidak valid."; done
    
    if [[ "$NVIDIA_CHOICE" == "ya" ]]; then
        info "Pilih jenis driver Nvidia:"
        select NVIDIA_DRIVER_TYPE in "nvidia (untuk kernel standar)" "nvidia-dkms (untuk kernel custom/lts)"; do [[ -n "$NVIDIA_DRIVER_TYPE" ]] && break || warning "Pilihan tidak valid."; done
    fi

    info "Pilih browser web:"
    select BROWSER_CHOICE in "brave" "firefox" "none"; do [[ -n "$BROWSER_CHOICE" ]] && break || warning "Pilihan tidak valid."; done

    # --- Layar Konfirmasi Akhir ---
    info "======================================================"
    info "         RINGKASAN KONFIGURASI INSTALASI          "
    info "======================================================"
    echo " > Hostname:          ${HOSTNAME}"
    echo " > Username:          ${USERNAME}"
    echo " > CPU Vendor:        ${CPU_VENDOR}"
    echo " > Desktop:           ${DE_CHOICE}"
    echo " > Driver Nvidia:     ${NVIDIA_CHOICE}"
    [[ "$NVIDIA_CHOICE" == "ya" ]] && echo " > Jenis Driver:      ${NVIDIA_DRIVER_TYPE}"
    echo " > Browser:           ${BROWSER_CHOICE}"
    info "------------------------------------------------------"
    info "Partisi yang akan digunakan:"
    echo " > Partisi EFI:       ${EFI_PARTITION}"
    echo " > Partisi Swap:      ${SWAP_PARTITION}"
    echo " > Partisi Root:      ${ROOT_PARTITION}"
    [[ -n "$HOME_PARTITION" ]] && echo " > Partisi Home:      ${HOME_PARTITION}"
    info "======================================================"
    
    warning "BAHAYA: TINJAU KONFIGURASI DI ATAS DENGAN SEKSAMA."
    warning "Partisi EFI, Swap, dan Root akan DIFORMAT TOTAL. Data akan hilang."
    read -p "Ketik 'LANJUT' untuk memulai instalasi: " CONFIRM_FORMAT
    if [ "$CONFIRM_FORMAT" != "LANJUT" ]; then
        error "Instalasi dibatalkan oleh pengguna."
        exit 1
    fi
}

# ===================================================================================
# TAHAP 2: PERSIAPAN SISTEM DARI LIVE ISO
# ===================================================================================
prepare_system() {
    info "Memulai proses persiapan sistem..."
    timedatectl set-ntp true

    info "Memformat partisi..."
    mkfs.fat -F32 "${EFI_PARTITION}"
    mkswap "${SWAP_PARTITION}"
    mkfs.ext4 "${ROOT_PARTITION}"
    if [[ -n "$HOME_PARTITION" ]]; then
        read -p "Apakah Anda ingin memformat partisi Home ${HOME_PARTITION}? (y/n): " format_home
        if [[ "$format_home" == "y" || "$format_home" == "Y" ]]; then
            info "Memformat partisi Home..."
            mkfs.ext4 "${HOME_PARTITION}"
        else
            warning "Partisi Home tidak diformat."
        fi
    fi

    info "Mounting sistem file..."
    mount "${ROOT_PARTITION}" /mnt
    mkdir -p /mnt/boot
    mount "${EFI_PARTITION}" /mnt/boot
    if [[ -n "$HOME_PARTITION" ]]; then
        mkdir -p /mnt/home
        mount "${HOME_PARTITION}" /mnt/home
    fi
    swapon "${SWAP_PARTITION}"

    info "Menginstal sistem dasar Arch Linux. Ini mungkin memakan waktu..."
    pacstrap -K /mnt base linux linux-firmware nano neovim git sudo networkmanager

    info "Membuat fstab (menggunakan UUID untuk ketahanan)..."
    genfstab -U /mnt >> /mnt/etc/fstab
    success "Persiapan sistem selesai."
}

# ===================================================================================
# TAHAP 3: CHROOT DAN KONFIGURASI SISTEM BARU
# ===================================================================================
chroot_configuration() {
    set -e 

    info_chroot() { echo -e "\e[36m[CHROOT]\e[0m $1"; }

    info_chroot "Mengatur zona waktu ke Asia/Jakarta..."
    ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
    hwclock --systohc

    info_chroot "Mengatur locale (en_US dan id_ID)..."
    sed -i '/^#en_US.UTF-8/s/^#//' /etc/locale.gen
    sed -i '/^#id_ID.UTF-8/s/^#//' /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    info_chroot "Mengatur hostname..."
    echo "${HOSTNAME}" > /etc/hostname
    cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

    info_chroot "Mengatur password root..."
    echo "root:${PASSWORD}" | chpasswd

    info_chroot "Membuat pengguna ${USERNAME}..."
    useradd -m -G wheel -s /bin/bash "${USERNAME}"
    echo "${USERNAME}:${PASSWORD}" | chpasswd
    info_chroot "Memberikan hak sudo kepada grup 'wheel'..."
    echo "%wheel ALL=(ALL:ALL) ALL" | tee /etc/sudoers.d/wheel > /dev/null

    info_chroot "Mengaktifkan NetworkManager..."
    systemctl enable NetworkManager

    info_chroot "Menginstal microcode untuk ${CPU_VENDOR}..."
    pacman -S --noconfirm --needed "${CPU_VENDOR}-ucode"

    info_chroot "Menginstal dan mengonfigurasi bootloader (systemd-boot)..."
    bootctl --path=/boot install

    echo "default arch.conf" > /boot/loader/loader.conf
    echo "timeout 3" >> /boot/loader/loader.conf
    echo "editor no" >> /boot/loader/loader.conf

    ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${ROOT_PARTITION}")
    KERNEL_OPTIONS="root=PARTUUID=${ROOT_PARTUUID} rw"
    
    if [[ "$NVIDIA_CHOICE" == "ya" ]]; then
        KERNEL_OPTIONS+=" nvidia_drm.modeset=1"
    fi

    cat <<BOOT_ENTRY > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /${CPU_VENDOR}-ucode.img
initrd  /initramfs-linux.img
options ${KERNEL_OPTIONS}
BOOT_ENTRY
    info_chroot "Bootloader berhasil dikonfigurasi."

    PKGS=()
    AUR_PKGS=()
    PKGS+=(pipewire wireplumber pipewire-pulse pavucontrol)

    case "$DE_CHOICE" in
        "Hyprland")
            PKGS+=(hyprland xdg-desktop-portal-hyprland xorg-xwayland waybar kitty wofi thunar thunar-archive-plugin ttf-jetbrains-mono-nerd noto-fonts-emoji sddm)
            AUR_PKGS+=(sddm-theme-corners-git)
            ;;
        "KDE-Plasma")
            PKGS+=(plasma-meta kde-applications sddm konsole dolphin)
            ;;
        "GNOME")
            PKGS+=(gnome gnome-tweaks gdm)
            ;;
    esac

    if [[ "$NVIDIA_CHOICE" == "ya" ]]; then
        if [[ "$NVIDIA_DRIVER_TYPE" == "nvidia-dkms"* ]]; then
            PKGS+=(linux-headers nvidia-dkms nvidia-utils nvidia-settings)
        else
            PKGS+=(nvidia nvidia-utils nvidia-settings)
        fi
    fi
    
    case "$BROWSER_CHOICE" in
        "brave")
            AUR_PKGS+=(brave-bin)
            ;;
        "firefox")
            PKGS+=(firefox)
            ;;
    esac

    PKGS+=(neofetch htop file-roller unzip p7zip)

    info_chroot "Menginstal paket-paket yang dipilih: ${PKGS[*]}"
    pacman -S --noconfirm --needed "${PKGS[@]}"

    if [ ${#AUR_PKGS[@]} -gt 0 ]; then
        info_chroot "Mempersiapkan instalasi paket dari AUR..."
        info_chroot "Menginstal 'base-devel' untuk membangun paket AUR..."
        pacman -S --noconfirm --needed base-devel
        
        sudo -u "${USERNAME}" bash <<USER_SETUP
set -e
info_chroot_user() { echo -e "\e[36m[CHROOT-USER]\e[0m \$1"; }
cd /home/"${USERNAME}"
info_chroot_user "Mengkloning dan menginstal yay (AUR Helper)..."
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay
info_chroot_user "Menginstal paket AUR: ${AUR_PKGS[*]}"
yay -S --noconfirm --needed "${AUR_PKGS[@]}"
USER_SETUP
        info_chroot "'base-devel' tetap terinstal di sistem."
    fi

    info_chroot "Mengaktifkan Display Manager..."
    if [[ "$DE_CHOICE" == "Hyprland" || "$DE_CHOICE" == "KDE-Plasma" ]]; then
        systemctl enable sddm
        if [[ "$DE_CHOICE" == "Hyprland" && " ${AUR_PKGS[*]} " =~ " sddm-theme-corners-git " ]]; then
            mkdir -p /etc/sddm.conf.d
            echo -e "[Theme]\nCurrent=corners" > /etc/sddm.conf.d/theme.conf
            info_chroot "Tema SDDM 'corners' telah diaktifkan."
        fi
    elif [[ "$DE_CHOICE" == "GNOME" ]]; then
        systemctl enable gdm
    fi

    info_chroot "Konfigurasi di dalam chroot selesai."
}

# ===================================================================================
#                                 EKSEKUSI SKRIP
# ===================================================================================
main() {
    pre_install_checks
    get_user_input
    prepare_system
    
    info "Menyalin konfigurasi ke sistem baru dan masuk ke chroot..."
    export EFI_PARTITION SWAP_PARTITION ROOT_PARTITION HOME_PARTITION \
           HOSTNAME USERNAME PASSWORD CPU_VENDOR DE_CHOICE NVIDIA_CHOICE NVIDIA_DRIVER_TYPE \
           BROWSER_CHOICE
    export -f chroot_configuration

    arch-chroot /mnt /bin/bash -c "chroot_configuration"

    trap - EXIT ERR INT TERM 
    cleanup 

    success "======================================================"
    success "         INSTALASI ARCH LINUX TELAH SELESAI!          "
    success "======================================================"
    info "Sistem akan di-reboot dalam 10 detik."
    info "Keluarkan media instalasi Anda sekarang."
    info "Login dengan pengguna: ${USERNAME}"
    
    sleep 10
    reboot
}

main
