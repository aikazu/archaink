#!/bin/bash
set -e

# --- Fungsi Bantuan & Tampilan ---
info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}
warning() {
    echo -e "\e[33m[PERINGATAN]\e[0m $1"
}
error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}
success() {
    echo -e "\e[32m[SUKSES]\e[0m $1"
}

# --- Fungsi Cleanup & Error Handling ---
cleanup() {
    warning "Menjalankan cleanup..."
    # Unmount semua yang ada di /mnt secara rekursif jika termount
    if mountpoint -q /mnt; then
        umount -R /mnt
        info "Semua filesystem telah di-unmount."
    fi
}

# Trap akan menjalankan fungsi cleanup jika script keluar secara tidak normal
trap cleanup EXIT ERR INT TERM

# --- Tahap 1: Pengumpulan Informasi dari Pengguna ---
info "Selamat datang di script instalasi Arch Linux."
info "Script ini akan memandu Anda melalui proses instalasi pada partisi yang sudah ada."

# 1. Pilih Partisi dengan Validasi
info "Daftar partisi yang tersedia di sistem Anda:"
lsblk -p -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT
echo ""
warning "Anda akan diminta untuk memilih partisi untuk EFI, Swap, dan Root."

while true; do
    read -p "Masukkan path partisi EFI (contoh: /dev/sda1): " EFI_PARTITION
    if lsblk -p -o NAME | grep -q "^${EFI_PARTITION}$"; then
        break
    else
        error "Partisi '${EFI_PARTITION}' tidak ditemukan. Silakan coba lagi."
    fi
done

while true; do
    read -p "Masukkan path partisi Swap (contoh: /dev/sda2): " SWAP_PARTITION
    if lsblk -p -o NAME | grep -q "^${SWAP_PARTITION}$"; then
        break
    else
        error "Partisi '${SWAP_PARTITION}' tidak ditemukan. Silakan coba lagi."
    fi
done

while true; do
    read -p "Masukkan path partisi Root (contoh: /dev/sda3): " ROOT_PARTITION
    if lsblk -p -o NAME | grep -q "^${ROOT_PARTITION}$"; then
        break
    else
        error "Partisi '${ROOT_PARTITION}' tidak ditemukan. Silakan coba lagi."
    fi
done

info "Anda telah memilih partisi berikut:"
echo "EFI:   ${EFI_PARTITION}"
echo "Swap:  ${SWAP_PARTITION}"
echo "Root:  ${ROOT_PARTITION}"
echo ""
warning "BAHAYA: Partisi-partisi ini akan DIFORMAT TOTAL!"
warning "Semua data di dalamnya akan hilang selamanya. Ini adalah kesempatan terakhir untuk membatalkan."
read -p "Ketik 'ya' untuk melanjutkan: " CONFIRM_FORMAT
if [ "$CONFIRM_FORMAT" != "ya" ]; then
    error "Instalasi dibatalkan oleh pengguna."
    exit 1
fi

# 2. Konfigurasi Pengguna dan Hostname dengan Validasi
while true; do
    read -p "Masukkan hostname untuk komputer ini (hanya huruf kecil, angka, dan '-'): " HOSTNAME
    if [[ "$HOSTNAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
        break
    else
        error "Hostname tidak valid. Hindari spasi atau karakter spesial."
    fi
done

while true; do
    read -p "Masukkan nama pengguna baru (hanya huruf kecil, tidak boleh 'root'): " USERNAME
    if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ && "$USERNAME" != "root" ]]; then
        break
    else
        error "Nama pengguna tidak valid. Gunakan huruf kecil, angka, '_', atau '-' dan jangan gunakan 'root'."
    fi
done

read -sp "Masukkan password untuk root dan pengguna baru: " PASSWORD
echo ""
read -sp "Konfirmasi password: " PASSWORD_CONFIRM
echo ""
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    error "Password tidak cocok. Silakan jalankan script lagi."
    exit 1
fi

# 3. Pilih CPU Vendor
info "Pilih vendor CPU Anda untuk instalasi microcode."
select CPU_VENDOR in "amd" "intel"; do
    if [[ "$CPU_VENDOR" == "amd" || "$CPU_VENDOR" == "intel" ]]; then
        break
    else
        warning "Pilihan tidak valid. Silakan pilih 1 untuk AMD atau 2 untuk Intel."
    fi
done

# 4. Pilih Desktop Environment
info "Pilih Desktop Environment/Window Manager yang ingin diinstal."
select DE_CHOICE in "Hyprland" "KDE-Plasma" "GNOME"; do
    case $DE_CHOICE in
        Hyprland|KDE-Plasma|GNOME)
            break;;
        *)
            warning "Pilihan tidak valid.";;
    esac
done

# 5. Pilih Driver Grafis
info "Apakah Anda ingin menginstal driver Nvidia?"
select NVIDIA_CHOICE in "ya" "tidak"; do
    if [[ "$NVIDIA_CHOICE" == "ya" || "$NVIDIA_CHOICE" == "tidak" ]]; then
        break
    else
        warning "Pilihan tidak valid."
    fi
done


# --- Tahap 2: Persiapan Sistem dari Live ISO ---
info "Memulai proses instalasi..."

# Sinkronisasi Waktu
info "Sinkronisasi waktu sistem..."
timedatectl set-ntp true

# Format Partisi
info "Memformat partisi yang dipilih..."
mkfs.fat -F32 "${EFI_PARTITION}"
mkswap "${SWAP_PARTITION}"
mkfs.ext4 "${ROOT_PARTITION}"

# Mount Partisi
info "Mounting sistem file..."
swapon "${SWAP_PARTITION}"
mount "${ROOT_PARTITION}" /mnt
mkdir -p /mnt/boot
mount "${EFI_PARTITION}" /mnt/boot

# Instalasi Sistem Dasar
info "Menginstal sistem dasar Arch Linux. Ini mungkin memakan waktu..."
pacstrap -K /mnt base base-devel linux linux-firmware nano git networkmanager

# Buat fstab
info "Membuat fstab..."
genfstab -U /mnt >> /mnt/etc/fstab


# --- Tahap 3: Chroot dan Konfigurasi Sistem Baru ---
info "Menyalin konfigurasi ke sistem baru dan masuk ke chroot..."

# Dapatkan PARTUUID untuk bootloader
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${ROOT_PARTITION}")

# Membuat script chroot
cat <<CHROOT_SCRIPT > /mnt/chroot-setup.sh
#!/bin/bash
set -e

# --- Fungsi Bantuan ---
info_chroot() {
    echo -e "\e[34m[CHROOT]\e[0m \$1"
}

# --- Konfigurasi Sistem ---
info_chroot "Mengatur zona waktu ke Asia/Jakarta..."
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc

info_chroot "Mengatur locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "id_ID.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

info_chroot "Mengatur hostname..."
echo "${HOSTNAME}" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# --- Pengguna dan Password ---
info_chroot "Mengatur password root..."
echo "root:${PASSWORD}" | chpasswd

info_chroot "Membuat pengguna ${USERNAME}..."
useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${PASSWORD}" | chpasswd

info_chroot "Memberikan hak sudo kepada grup wheel..."
sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers

# --- Layanan dan Bootloader ---
info_chroot "Mengaktifkan NetworkManager..."
systemctl enable NetworkManager

info_chroot "Menginstal microcode untuk ${CPU_VENDOR}..."
pacman -S --noconfirm ${CPU_VENDOR}-ucode

info_chroot "Menginstal dan mengonfigurasi bootloader (systemd-boot)..."
bootctl --path=/boot install

echo "default arch" > /boot/loader/loader.conf
cat <<BOOT_ENTRY > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /${CPU_VENDOR}-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=${ROOT_PARTUUID} rw
BOOT_ENTRY

# --- Instalasi Lingkungan Desktop dan Aplikasi (sebagai user) ---
info_chroot "Mempersiapkan instalasi AUR Helper dan GUI..."
pacman -S --noconfirm sudo --needed git

# Script untuk dijalankan oleh user
cat <<USER_SCRIPT > /home/${USERNAME}/user-setup.sh
#!/bin/bash
set -e

cd /tmp
info_chroot "Menginstal yay (AUR Helper)..."
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd /tmp
rm -rf yay # Membersihkan sisa instalasi yay

info_chroot "Menginstal Desktop Environment: ${DE_CHOICE}..."
if [ "${DE_CHOICE}" == "Hyprland" ]; then
    yay -S --noconfirm hyprland xdg-desktop-portal-hyprland xorg-xwayland waybar kitty rofi thunar thunar-archive-plugin thunar-volman network-manager-applet pipewire wireplumber pipewire-pulse ttf-jetbrains-mono-nerd ttf-font-awesome sddm sddm-minesddm-theme
elif [ "${DE_CHOICE}" == "KDE-Plasma" ]; then
    yay -S --noconfirm plasma kde-applications sddm sddm-minesddm-theme
elif [ "${DE_CHOICE}" == "GNOME" ]; then
    yay -S --noconfirm gnome gnome-tweaks gdm
fi

if [ "${NVIDIA_CHOICE}" == "ya" ]; then
    info_chroot "Menginstal driver Nvidia..."
    yay -S --noconfirm nvidia nvidia-utils nvidia-settings
    if [ "${DE_CHOICE}" == "Hyprland" ]; then
        info_chroot "Menerapkan konfigurasi Nvidia untuk Wayland..."
        echo "WLR_NO_HARDWARE_CURSORS=1" | sudo tee -a /etc/environment
    fi
fi

info_chroot "Menginstal aplikasi dasar..."
yay -S --noconfirm brave-bin file-roller pavucontrol neofetch htop unzip

rm /home/${USERNAME}/user-setup.sh
USER_SCRIPT

chown ${USERNAME}:${USERNAME} /home/${USERNAME}/user-setup.sh
chmod +x /home/${USERNAME}/user-setup.sh

sudo -u ${USERNAME} /home/${USERNAME}/user-setup.sh

# --- Finalisasi ---
info_chroot "Mengaktifkan Display Manager..."
if [ "${DE_CHOICE}" == "Hyprland" ] || [ "${DE_CHOICE}" == "KDE-Plasma" ]; then
    systemctl enable sddm
    # Mengatur tema SDDM secara otomatis
    mkdir -p /etc/sddm.conf.d
    echo -e "[Theme]\nCurrent=minesddm" > /etc/sddm.conf.d/theme.conf
else
    systemctl enable gdm
fi

info_chroot "Konfigurasi di dalam chroot selesai."

CHROOT_SCRIPT

# Jalankan script di dalam chroot
arch-chroot /mnt /bin/bash chroot-setup.sh

# --- Tahap 4: Selesai ---
# Hapus trap sebelum unmount normal
trap - EXIT ERR INT TERM
cleanup

success "Instalasi Selesai!"
success "Sistem akan di-reboot sekarang. Keluarkan media instalasi."
read -p "Tekan [Enter] untuk reboot..."
reboot
