#!/bin/bash
# AlmaLinux 虚拟机网络桥接一键配置脚本 v4.0
# 支持：自动接口检测 | 双栈IPv4/IPv6 | 安全加固 | 日志审计

# 初始化参数
IPTABLES_FILE="/etc/sysconfig/iptables"
SYSCTL_FILE="/etc/sysctl.conf"
NETPLAN_FILE="/etc/sysconfig/network-scripts/ifcfg-vmbr0"
LOG_FILE="/var/log/vm_bridge_setup.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# 日志函数
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

# 错误处理函数
error_exit() {
    log "FATAL: $1"
    echo "操作失败，请查看 $LOG_FILE 获取详细信息"
    exit 1
}

# 检测执行权限
check_permissions() {
    if [ "$(id -u)" != "0" ]; then
        error_exit "必须使用root权限运行"
    fi

    for cmd in ip iptables iptables-save sysctl; do
        if ! command -v "$cmd" &> /dev/null; then
            error_exit "缺少必要工具: $cmd"
        fi
    done
}

# 自动检测网络接口
detect_interfaces() {
    log "检测网络接口..."
    
    # 获取公网接口（默认路由接口）
    PUBLIC_IFACE=$(ip route show default | awk '/default/ {print $5}')
    if [ -z "$PUBLIC_IFACE" ]; then
        error_exit "未检测到有效公网接口"
    fi

    # 创建虚拟桥接接口
    BRIDGE_IFACE="vmbr0"
    if ! ip link show "$BRIDGE_IFACE" &> /dev/null; then
        log "创建桥接接口 $BRIDGE_IFACE..."
        ip link add name "$BRIDGE_IFACE" type bridge
        ip link set dev "$BRIDGE_IFACE" up
    fi

    log "公网接口: $PUBLIC_IFACE"
    log "桥接接口: $BRIDGE_IFACE"
}

# 配置网络参数（替换原错误部分）
configure_network() {
    log "配置网络参数..."
    
    # IPv4设置
    nmcli con add type bridge ifname vmbr0 ipv4.addresses 10.1.1.1/24 ipv4.gateway 10.1.1.254 ipv4.dns 8.8.8.8
    nmcli con modify vmbr0 ipv4.method manual

    # IPv6设置
    nmcli con modify vmbr0 ipv6.addresses 2001:41d0:2:cf5a::1/64
    nmcli con modify vmbr0 ipv6.method manual

    # 启用IP转发
    sysctl -w net.ipv6.conf.all.forwarding=1
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

    # 应用配置
    nmcli connection up vmbr0
}

    # IPv6设置
    sysctl -w net.ipv6.conf.all.forwarding=1
    echo "net.ipv6.conf.all.forwarding=1" >> "$SYSCTL_FILE"

    # 持久化配置
    systemctl restart network
}

# 设置NAT规则
setup_nat() {
    log "配置NAT规则..."
    
    # IPv4 NAT
    iptables -t nat -A POSTROUTING -o "$PUBLIC_IFACE" -j MASQUERADE
    iptables-save > "$IPTABLES_FILE"

    # IPv6 NAT
    ip6tables -t nat -A POSTROUTING -o "$PUBLIC_IFACE" -j MASQUERADE
    ip6tables-save > "/etc/sysconfig/ip6tables"

    log "NAT规则已生效"
}

# 防火墙配置
configure_firewall() {
    log "配置防火墙..."
    
    # 基础防护规则
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A INPUT -p icmp -j ACCEPT

    # SSH访问控制
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT

    # 默认策略
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables-save > "$IPTABLES_FILE"
    log "防火墙规则已更新"
}

# 主执行流程
main() {
    trap 'error_exit "脚本异常终止"' ERR
    check_permissions
    detect_interfaces
    configure_network
    setup_nat
    configure_firewall

    log "===== 网络桥接配置成功 ====="
    echo "验证信息："
    echo "1. 桥接接口状态: ip link show $BRIDGE_IFACE"
    echo "2. NAT规则: iptables -t nat -L -n -v"
    echo "3. 系统日志: tail -f $LOG_FILE"
}

# 执行主函数
main
