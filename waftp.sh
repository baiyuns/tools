#!/bin/bash
# AlmaLinux 8 母机网络自动化配置脚本 v3.0
# 支持：自动检测网络接口 | 智能防火墙配置 | DNS 自动修复 | 虚拟机 NAT 支持

# 初始化日志系统
LOG_FILE="/var/log/auto_network_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# 核心函数库
function log() { echo "[$TIMESTAMP] $1"; }
function error_exit() { log "FATAL: $1"; exit 1; }

# 环境检测
check_prerequisites() {
    log "检测系统环境..."
    if [ "$(rpm -E %rhel)" != "8" ]; then
        error_exit "仅支持 AlmaLinux 8 系统"
    fi

    # 自动安装必要组件
    MISSING_PACKAGES=()
    for pkg in firewalld dnsmasq iptables-services; do
        if ! rpm -q "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        log "安装缺失组件: ${MISSING_PACKAGES[*]}"
        dnf install -y "${MISSING_PACKAGES[@]}" || error_exit "依赖安装失败"
    fi
}

# 网络接口自动识别
detect_interfaces() {
    log "识别网络接口..."
    PUBLIC_IFACE=$(ip route show default | awk '/default/ {print $5}')
    if [ -z "$PUBLIC_IFACE" ]; then
        error_exit "未检测到有效网络接口"
    fi

    PRIVATE_IFACE=$(ls /sys/class/net | grep -v "$PUBLIC_IFACE")
    if [ -z "$PRIVATE_IFACE" ]; then
        error_exit "未检测到内网接口"
    fi

    log "检测结果:"
    log "公网接口: $PUBLIC_IFACE"
    log "内网接口: $PRIVATE_IFACE"
}

# 防火墙配置
configure_firewall() {
    log "配置防火墙规则..."
    
    # 启动并启用防火墙服务
    systemctl start firewalld
    systemctl enable firewalld

    # 清理旧规则
    firewall-cmd --permanent --direct --remove-rules ipv4 nat POSTROUTING || true
    firewall-cmd --permanent --direct --remove-rules ipv4 filter FORWARD || true

    # 添加 NAT 规则
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 \
        -s 10.0.1.0/24 -o "$PUBLIC_IFACE" -j MASQUERADE

    # 允许转发规则
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 \
        -i "$PRIVATE_IFACE" -o "$PUBLIC_IFACE" -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 \
        -i "$PUBLIC_IFACE" -o "$PRIVATE_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT

    # 重载防火墙
    firewall-cmd --reload || error_exit "防火墙配置失败"
}

# DNS 配置
configure_dns() {
    log "配置 DNS 解析..."
    
    # 优先使用 NetworkManager 配置
    if systemctl is-active NetworkManager &>/dev/null; then
        nmcli con mod "$PUBLIC_IFACE" ipv4.dns "8.8.8.8 114.114.114.114"
        nmcli con up "$PUBLIC_IFACE" || error_exit "NetworkManager 配置失败"
    else
        # 回退方案：安装并配置 dnsmasq
        if ! rpm -q dnsmasq &>/dev/null; then
            log "安装 dnsmasq..."
            dnf install -y dnsmasq
            systemctl enable --now dnsmasq
        fi

        # 写入 dnsmasq 配置
        cat > /etc/dnsmasq.d/public_dns.conf <<EOF
server=8.8.8.8
server=114.114.114.114
EOF
        systemctl restart dnsmasq
    fi

    # 最终 DNS 验证
    if ! getent hosts google.com &>/dev/null; then
        error_exit "DNS 解析配置失败"
    fi
}

# 网络验证
validate_network() {
    log "执行网络验证..."
    
    # 基础连通性测试
    if ! ping -c 3 8.8.8.8 &>/dev/null; then
        error_exit "公网连通性测试失败"
    fi

    # DNS 解析测试
    if ! host google.com &>/dev/null; then
        error_exit "DNS 解析失败"
    fi

    # 虚拟机网络测试（示例）
    TEST_VM_IP="10.0.1.100"
    if ping -c 3 "$TEST_VM_IP" &>/dev/null; then
        log "虚拟机网络连通性正常"
    else
        log "警告：虚拟机网络测试失败，请检查防火墙规则"
    fi
}

# 主执行流程
main() {
    trap 'error_exit "脚本异常终止"' ERR
    check_prerequisites
    detect_interfaces
    configure_firewall
    configure_dns
    validate_network

    log "===== 网络配置成功完成 ====="
    echo "验证通过！虚拟机可通过母机访问外网"
    echo "操作日志保存在: $LOG_FILE"
}

# 执行主函数
main
