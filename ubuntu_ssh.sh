#!/bin/bash

# Script tự động cấu hình SSH cho Ubuntu 22.04
# Cho phép đăng nhập bằng password
# https://raw.githubusercontent.com/nguyenvuonganh-dev/Command/refs/heads/main/ubuntu_ssh.sh
echo "Bắt đầu cấu hình SSH..."

# Cập nhật hệ thống và cài đặt openssh-server
echo "Cập nhật hệ thống và cài đặt OpenSSH Server..."
sudo apt update
sudo apt install openssh-server -y

# Sao lưu file cấu hình SSH gốc
echo "Sao lưu file cấu hình SSH..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Chỉnh sửa file cấu hình SSH
echo "Cấu hình SSH để cho phép đăng nhập bằng password..."
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config

# Kiểm tra và thêm cấu hình nếu không tồn tại
if ! grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config; then
    echo "PasswordAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
fi

if ! grep -q "ChallengeResponseAuthentication yes" /etc/ssh/sshd_config; then
    echo "ChallengeResponseAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
fi

# Mở cổng SSH trên firewall (nếu UFW được cài đặt)
echo "Mở cổng SSH trên firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw allow ssh
    echo "UFW đã được cấu hình để cho phép SSH"
else
    echo "UFW không được cài đặt, bỏ qua cấu hình firewall"
fi

# Khởi động lại dịch vụ SSH
echo "Khởi động lại dịch vụ SSH..."
sudo systemctl restart ssh

# Hiển thị trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ SSH..."
sudo systemctl status ssh --no-pager

# Hiển thị địa chỉ IP để kết nối
echo ""
echo "==================== THÔNG TIN KẾT NỐI ===================="
echo "SSH đã được cấu hình thành công!"
echo "Để kết nối, sử dụng lệnh:"
echo "ssh username@$(hostname -I | awk '{print $1}')"
echo "Hoặc:"
echo "ssh username@$(curl -s ifconfig.me)"
echo ""
echo "Lưu ý quan trọng:"
echo "1. Đảm bảo mật khẩu người dùng đủ mạnh"
echo "2. Khuyến nghị sử dụng SSH keys thay vì password cho môi trường production"
echo "3. File cấu hình gốc được sao lưu tại: /etc/ssh/sshd_config.backup"
echo "=========================================================="
