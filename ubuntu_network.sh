#!/bin/bash

# Script thiết lập Static IP cho Ubuntu 22.04 - Chạy qua Curl
# URL: https://raw.githubusercontent.com/nguyenvuonganh-dev/Command/refs/heads/main/ubuntu_network.sh
# Sử dụng: curl -sSL https://your-url/setup-static-ip.sh | sudo bash

set -e  # Dừng script nếu có lỗi

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Hàm in thông báo
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Hàm kiểm tra root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Script này cần chạy với quyền root!"
        echo "Sử dụng: sudo bash <(curl -sSL URL)"
        exit 1
    fi
}

# Hàm kiểm tra Ubuntu 22.04
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Không phải hệ thống Ubuntu!"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "22.04" ]]; then
        log_warn "Script được thiết kế cho Ubuntu 22.04"
        read -p "Tiếp tục? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Hàm hiển thị thông tin mạng
show_network_info() {
    echo ""
    echo "════════════════════════════════════════════════════"
    echo "THÔNG TIN MẠNG HIỆN TẠI"
    echo "════════════════════════════════════════════════════"
    
    # Interface
    echo "Các interface có sẵn:"
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo | sed 's/^/  /'
    
    # IP hiện tại
    echo -e "\nĐịa chỉ IP hiện tại:"
    ip -o -4 addr show | awk '{print "  " $2 ": " $4}'
    
    # Gateway
    echo -e "\nGateway mặc định:"
    ip route | grep default | awk '{print "  " $3}'
    
    echo "════════════════════════════════════════════════════"
    echo ""
}

# Hàm backup cấu hình
backup_config() {
    local backup_dir="/etc/netplan/backup"
    mkdir -p "$backup_dir"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    for config in /etc/netplan/*.yaml; do
        if [[ -f "$config" ]]; then
            cp "$config" "$backup_dir/$(basename "$config")_$timestamp.backup"
        fi
    done
    
    log_success "Đã backup cấu hình vào $backup_dir"
}

# Hàm chọn interface
select_interface() {
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_error "Không tìm thấy interface mạng!"
        exit 1
    fi
    
    echo "Chọn interface mạng:"
    for i in "${!interfaces[@]}"; do
        local ip_addr=$(ip -o -4 addr show dev "${interfaces[$i]}" | awk '{print $4}' | head -1)
        echo "  $((i+1))) ${interfaces[$i]} ${ip_addr:-[Không có IP]}"
    done
    
    local choice
    while true; do
        read -p "Nhập số (1-${#interfaces[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#interfaces[@]} ]]; then
            SELECTED_INTERFACE="${interfaces[$((choice-1))]}"
            break
        fi
        log_error "Lựa chọn không hợp lệ!"
    done
    
    log_info "Đã chọn interface: $SELECTED_INTERFACE"
}

# Hàm thiết lập DHCP
setup_dhcp() {
    log_info "Thiết lập DHCP cho $SELECTED_INTERFACE..."
    
    # Tìm file netplan
    local netplan_file=$(find /etc/netplan -name "*.yaml" | head -1)
    [[ -z "$netplan_file" ]] && netplan_file="/etc/netplan/01-network-manager-all.yaml"
    
    # Tạo config DHCP
    cat > "$netplan_file" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $SELECTED_INTERFACE:
      dhcp4: true
      dhcp6: true
EOF
    
    # Áp dụng
    netplan apply
    log_success "Đã thiết lập DHCP cho $SELECTED_INTERFACE"
    
    # Hiển thị IP mới
    sleep 3
    echo "IP mới: $(ip -o -4 addr show dev $SELECTED_INTERFACE | awk '{print $4}')"
}

# Hàm thiết lập Static IP
setup_static_ip() {
    echo ""
    log_info "Nhập thông tin Static IP cho $SELECTED_INTERFACE"
    echo "────────────────────────────────────────────────────"
    
    # Lấy thông tin hiện tại để gợi ý
    local current_ip=$(ip -o -4 addr show dev "$SELECTED_INTERFACE" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1)
    local current_gateway=$(ip route | grep default | grep "$SELECTED_INTERFACE" | awk '{print $3}' | head -1)
    
    # Nhập thông tin
    read -p "Địa chỉ IP (ví dụ: 192.168.1.100) [${current_ip:-192.168.1.100}]: " static_ip
    static_ip=${static_ip:-${current_ip:-192.168.1.100}}
    
    read -p "Prefix (ví dụ: 24) [24]: " prefix
    prefix=${prefix:-24}
    
    read -p "Gateway (ví dụ: 192.168.1.1) [${current_gateway:-192.168.1.1}]: " gateway
    gateway=${gateway:-${current_gateway:-192.168.1.1}}
    
    read -p "DNS servers (cách nhau bằng dấu phẩy) [8.8.8.8,8.8.4.4]: " dns_servers
    dns_servers=${dns_servers:-8.8.8.8,8.8.4.4}
    
    # Tạo file netplan
    local netplan_file=$(find /etc/netplan -name "*.yaml" | head -1)
    [[ -z "$netplan_file" ]] && netplan_file="/etc/netplan/01-network-manager-all.yaml"
    
    # Chuyển đổi DNS servers
    local dns_array=()
    IFS=',' read -ra dns_array <<< "$dns_servers"
    local dns_yaml=""
    for dns in "${dns_array[@]}"; do
        dns_yaml="$dns_yaml\n        - $dns"
    done
    
    # Tạo config
    cat > "$netplan_file" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $SELECTED_INTERFACE:
      dhcp4: no
      dhcp6: no
      addresses:
        - $static_ip/$prefix
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses: [$dns_servers]
EOF
    
    log_info "Đã tạo cấu hình Netplan"
    echo "────────────────────────────────────────────────────"
    cat "$netplan_file"
    echo "────────────────────────────────────────────────────"
    
    # Xác nhận áp dụng
    read -p "Áp dụng cấu hình này? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        backup_config
        netplan apply
        log_success "Đã áp dụng cấu hình Static IP"
        
        # Kiểm tra kết nối
        sleep 2
        echo ""
        log_info "Kiểm tra kết nối..."
        
        if ping -c 2 -W 1 "$gateway" &>/dev/null; then
            log_success "✓ Kết nối đến Gateway thành công"
        else
            log_warn "⚠ Không thể ping đến Gateway"
        fi
        
        if ping -c 2 -W 1 8.8.8.8 &>/dev/null; then
            log_success "✓ Kết nối Internet thành công"
        else
            log_warn "⚠ Không thể kết nối Internet"
        fi
        
        echo ""
        log_success "Thiết lập hoàn tất!"
        echo "Interface: $SELECTED_INTERFACE"
        echo "IP Address: $static_ip/$prefix"
        echo "Gateway: $gateway"
        echo "DNS: $dns_servers"
    else
        log_warn "Không áp dụng cấu hình"
    fi
}

# Hàm chính
main() {
    clear
    echo "╔══════════════════════════════════════════════════╗"
    echo "║    THIẾT LẬP MẠNG CHO UBUNTU 22.04               ║"
    echo "║    Script chạy qua Curl                          ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    # Kiểm tra
    check_root
    check_ubuntu_version
    
    # Hiển thị thông tin mạng
    show_network_info
    
    # Chọn interface
    select_interface
    
    # Menu lựa chọn
    echo ""
    echo "Chọn chế độ cấu hình:"
    echo "  1) Thiết lập Static IP"
    echo "  2) Thiết lập DHCP"
    echo "  3) Chỉ xem thông tin, không thay đổi"
    
    local choice
    while true; do
        read -p "Nhập lựa chọn (1-3): " choice
        case $choice in
            1)
                setup_static_ip
                break
                ;;
            2)
                setup_dhcp
                break
                ;;
            3)
                log_info "Thoát script"
                exit 0
                ;;
            *)
                log_error "Lựa chọn không hợp lệ!"
                ;;
        esac
    done
    
    echo ""
    log_info "Lưu ý:"
    echo "  - File cấu hình: /etc/netplan/*.yaml"
    echo "  - Backup được lưu tại: /etc/netplan/backup/"
    echo "  - Nếu mất kết nối, khởi động lại máy hoặc khôi phục từ backup"
}

# Bắt đầu script
main
