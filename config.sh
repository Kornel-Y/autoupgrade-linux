#!/bin/bash


set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Unattended Upgrades Setup ===${NC}\n"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
fi

setup_debian() {
    echo -e "${YELLOW}Detected: Debian-based system${NC}"
    
    if dpkg -l | grep -q unattended-upgrades; then
        echo -e "${GREEN}✓ unattended-upgrades sudah terinstall${NC}"
    else
        echo "Installing unattended-upgrades..."
        apt-get update && apt-get install -y unattended-upgrades
    fi
    
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
    
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
}

setup_rhel() {
    echo -e "${YELLOW}Detected: RHEL-based system${NC}"
    
    if rpm -q dnf-automatic &>/dev/null || rpm -q yum-cron &>/dev/null; then
        echo -e "${GREEN}✓ Auto-update sudah terinstall${NC}"
    else
        echo "Installing dnf-automatic/yum-cron..."
        if command -v dnf &>/dev/null; then
            dnf install -y dnf-automatic
            SERVICE="dnf-automatic.timer"
        else
            yum install -y yum-cron
            SERVICE="yum-cron"
        fi
    fi
    
    if [ -f /etc/dnf/automatic.conf ]; then
        sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
        systemctl enable --now dnf-automatic.timer
    elif [ -f /etc/yum/yum-cron.conf ]; then
        sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf
        systemctl enable --now yum-cron
    fi
}

setup_arch() {
    echo -e "${YELLOW}Detected: Arch-based system${NC}"
    
    if pacman -Qi systemd-timer &>/dev/null; then
        echo -e "${GREEN}✓ Menggunakan systemd timer${NC}"
    else
        echo "Setup systemd timer untuk auto-update..."
    fi
    
    cat > /etc/systemd/system/arch-autoupdate.service <<'EOF'
[Unit]
Description=Arch Linux Auto Update
[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Syu --noconfirm
EOF
    
    cat > /etc/systemd/system/arch-autoupdate.timer <<'EOF'
[Unit]
Description=Daily Arch Update
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable --now arch-autoupdate.timer
}

test_debian() {
    echo -e "\n${BLUE}=== Testing Debian/Ubuntu Setup ===${NC}"
    
    echo -e "\n${YELLOW}1. Cek package installation:${NC}"
    if dpkg -l | grep -q unattended-upgrades; then
        echo -e "${GREEN}✓ unattended-upgrades terinstall${NC}"
    else
        echo -e "${RED}✗ unattended-upgrades TIDAK terinstall${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}2. Cek file konfigurasi:${NC}"
    if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        echo -e "${GREEN}✓ /etc/apt/apt.conf.d/50unattended-upgrades ada${NC}"
    else
        echo -e "${RED}✗ File konfigurasi utama TIDAK ada${NC}"
    fi
    
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
        echo -e "${GREEN}✓ /etc/apt/apt.conf.d/20auto-upgrades ada${NC}"
    else
        echo -e "${RED}✗ File auto-upgrades TIDAK ada${NC}"
    fi
    
    echo -e "\n${YELLOW}3. Cek service status:${NC}"
    if systemctl is-active --quiet unattended-upgrades; then
        echo -e "${GREEN}✓ Service unattended-upgrades AKTIF${NC}"
    else
        echo -e "${RED}✗ Service TIDAK aktif${NC}"
    fi
    
    if systemctl is-enabled --quiet unattended-upgrades; then
        echo -e "${GREEN}✓ Service unattended-upgrades ENABLED${NC}"
    else
        echo -e "${RED}✗ Service TIDAK enabled${NC}"
    fi
    
    echo -e "\n${YELLOW}4. Dry run test (simulasi):${NC}"
    echo "Running: unattended-upgrade --dry-run --debug"
    unattended-upgrade --dry-run --debug 2>&1 | tail -10
    
    echo -e "\n${YELLOW}5. Cek log terakhir:${NC}"
    if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
        echo "Last 5 lines from log:"
        tail -5 /var/log/unattended-upgrades/unattended-upgrades.log
    else
        echo -e "${YELLOW}Log file belum ada (normal untuk instalasi baru)${NC}"
    fi
}

test_rhel() {
    echo -e "\n${BLUE}=== Testing RHEL/Fedora Setup ===${NC}"
    
    echo -e "\n${YELLOW}1. Cek package installation:${NC}"
    if rpm -q dnf-automatic &>/dev/null; then
        echo -e "${GREEN}✓ dnf-automatic terinstall${NC}"
        PACKAGE="dnf-automatic"
        TIMER="dnf-automatic.timer"
    elif rpm -q yum-cron &>/dev/null; then
        echo -e "${GREEN}✓ yum-cron terinstall${NC}"
        PACKAGE="yum-cron"
        TIMER="yum-cron"
    else
        echo -e "${RED}✗ Auto-update package TIDAK terinstall${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}2. Cek konfigurasi:${NC}"
    if [ -f /etc/dnf/automatic.conf ]; then
        echo "apply_updates setting:"
        grep "apply_updates" /etc/dnf/automatic.conf
    elif [ -f /etc/yum/yum-cron.conf ]; then
        echo "apply_updates setting:"
        grep "apply_updates" /etc/yum/yum-cron.conf
    fi
    
    echo -e "\n${YELLOW}3. Cek service status:${NC}"
    if systemctl is-active --quiet $TIMER; then
        echo -e "${GREEN}✓ $TIMER AKTIF${NC}"
    else
        echo -e "${RED}✗ Timer TIDAK aktif${NC}"
    fi
    
    if systemctl is-enabled --quiet $TIMER; then
        echo -e "${GREEN}✓ $TIMER ENABLED${NC}"
    else
        echo -e "${RED}✗ Timer TIDAK enabled${NC}"
    fi
    
    echo -e "\n${YELLOW}4. Cek jadwal timer:${NC}"
    systemctl list-timers $TIMER --no-pager
}

test_arch() {
    echo -e "\n${BLUE}=== Testing Arch Setup ===${NC}"
    
    echo -e "\n${YELLOW}1. Cek file service:${NC}"
    if [ -f /etc/systemd/system/arch-autoupdate.service ]; then
        echo -e "${GREEN}✓ arch-autoupdate.service ada${NC}"
    else
        echo -e "${RED}✗ Service file TIDAK ada${NC}"
    fi
    
    if [ -f /etc/systemd/system/arch-autoupdate.timer ]; then
        echo -e "${GREEN}✓ arch-autoupdate.timer ada${NC}"
    else
        echo -e "${RED}✗ Timer file TIDAK ada${NC}"
    fi
    
    echo -e "\n${YELLOW}2. Cek timer status:${NC}"
    if systemctl is-active --quiet arch-autoupdate.timer; then
        echo -e "${GREEN}✓ Timer AKTIF${NC}"
    else
        echo -e "${RED}✗ Timer TIDAK aktif${NC}"
    fi
    
    if systemctl is-enabled --quiet arch-autoupdate.timer; then
        echo -e "${GREEN}✓ Timer ENABLED${NC}"
    else
        echo -e "${RED}✗ Timer TIDAK enabled${NC}"
    fi
    
    echo -e "\n${YELLOW}3. Cek jadwal timer:${NC}"
    systemctl list-timers arch-autoupdate.timer --no-pager
    
    echo -e "\n${YELLOW}4. Cek log terakhir:${NC}"
    journalctl -u arch-autoupdate.service -n 10 --no-pager
}

case $DISTRO in
    ubuntu|debian|linuxmint|pop)
        setup_debian
        test_debian
        ;;
    rhel|centos|fedora|rocky|almalinux)
        setup_rhel
        test_rhel
        ;;
    arch|manjaro)
        setup_arch
        test_arch
        ;;
    *)
        echo -e "${RED}Distro tidak dikenali: $DISTRO${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}✓ Setup dan testing selesai!${NC}"
echo -e "${BLUE}Auto-update aktif dan akan berjalan otomatis.${NC}"