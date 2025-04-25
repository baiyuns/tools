#!/bin/bash

# 防火墙配置脚本 v2.1
# 支持firewalld和iptables双模式
# 日志文件路径
LOGFILE="/var/log/firewall_setup.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# 函数：记录日志
log() {
    echo "[$TIMESTAMP] $1" | tee -a $LOGFILE
}

# 函数：检测服务状态
check_service() {
    if ! systemctl is-active --quiet $1; then
        log "错误: $1 服务未运行，尝试启动..."
        systemctl start $1
        if [ $? -ne 0 ]; then
            log "致命错误: 无法启动 $1 服务"
            exit 1
        fi
    fi
    log "$1 服务已就绪"
}

# 函数：检测防火墙类型
detect_firewall() {
    if command -v firewall-cmd &> /dev/null; then
        FIREWALL_TYPE="firewalld"
        log "检测到 firewalld 防火墙"
    elif command -v iptables &> /dev/null; then
        FIREWALL_TYPE="iptables"
        log "检测到 iptables 防火墙"
    else
        log "错误: 未找到任何防火墙工具"
        exit 1
    fi
}

# 主配置函数
configure_firewall() {
    case $FIREWALL_TYPE in
        "firewalld")
            check_service firewalld
            log "配置 firewalld 规则..."
            firewall-cmd --permanent --zone=public --add-port=22/tcp
            firewall-cmd --permanent --zone=public --add-service=http
            firewall-cmd --permanent --zone=public --add-service=https
            firewall-cmd --reload
            ;;
        "iptables")
            check_service iptables
            log "配置 iptables 规则..."
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -P INPUT DROP
            iptables -P FORWARD DROP
            iptables -A INPUT -i lo -j ACCEPT
            iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            iptables -A INPUT -p tcp --dport 80 -j ACCEPT
            iptables -A INPUT -p tcp --dport 443 -j ACCEPT
            iptables-save > /etc/sysconfig/iptables
            ;;
    esac
    log "防火墙规则配置完成"
}

# 执行流程
log "===== 防火墙配置开始 ====="
detect_firewall
configure_firewall
log "===== 防火墙配置完成 ====="

# 验证配置
log "验证防火墙状态..."
if [ "$FIREWALL_TYPE" == "firewalld" ]; then
    firewall-cmd --list-all
else
    iptables -L -n -v
fi
