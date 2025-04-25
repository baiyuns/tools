#!/bin/bash
# AlmaLinux 8 母机网络一键配置脚本（终极版）

# 初始化日志记录
LOG_FILE="/var/log/nat_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "错误：必须使用 root 权限运行此脚本" >&2
  exit 1
fi

# 配置参数（用户可修改）
PRIVATE_NET="10.0.1.0/24"    # 内网子网
PUBLIC_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)  # 自动检测公网接口
GATEWAY_IP="10.0.1.1"        # 内网网关地址
DNS_SERVERS=("8.8.8.8" "114.114.114.114")  # 首选和备用 DNS

# 预检系统组件
check_dependencies() {
  local missing=()
  
  # 检测必要软件包
  for pkg in firewalld iptables-services; do
    if ! rpm -q "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done
  
  # 自动修复缺失依赖
  if [ ${#missing[@]} -gt 0 ]; then
    echo "正在安装缺失依赖: ${missing[*]}..."
    dnf install -y "${missing[@]}" || {
      echo "依赖安装失败，请手动执行: dnf install -y ${missing[@]}" >&2
      exit 3
    }
  fi
}

# 配置 DNS 解析
setup_dns() {
  # 优先尝试使用 NetworkManager 配置全局 DNS
  if systemctl is-active NetworkManager &>/dev/null; then
    echo "通过 NetworkManager 配置 DNS..."
    nmcli con mod "$PUBLIC_IFACE" ipv4.dns "${DNS_SERVERS[*]}" || true
    nmcli con up "$PUBLIC_IFACE" || true
  else
    # 备选方案: 安装并配置 dnsmasq
    if ! rpm -q dnsmasq &>/dev/null; then
      echo "正在安装 dnsmasq..."
      dnf install -y dnsmasq || {
        echo "警告：dnsmasq 安装失败，将直接修改 resolv.conf" >&2
        echo "nameserver ${DNS_SERVERS[0]}" > /etc/resolv.conf
        return
      }
    fi
    
    echo "配置 dnsmasq..."
    cat > /etc/dnsmasq.d/public_dns.conf <<EOF
server=${DNS_SERVERS[0]}
server=${DNS_SERVERS[1]}
EOF
    systemctl enable --now dnsmasq
  fi
  
  # 最终 DNS 验证
  if ! nslookup google.com &>/dev/null; then
    echo "警告：DNS 配置未完全生效，请手动检查" >&2
  fi
}

# 配置内核参数
setup_kernel() {
  echo "配置内核参数..."
  {
    echo "net.ipv4.ip_forward=1"
    echo "net.ipv4.conf.all.forwarding=1"
    echo "net.ipv6.conf.all.forwarding=1"
  } >> /etc/sysctl.conf
  sysctl -p >/dev/null
}

# 防火墙及 NAT 配置（多模式支持）
setup_firewall() {
  echo "配置防火墙规则..."
  
  # 尝试使用 firewalld
  if firewall-cmd --state &>/dev/null; then
    # 清理旧规则
    firewall-cmd --permanent --direct --remove-rules ipv4 nat POSTROUTING || true
    firewall-cmd --permanent --direct --remove-rules ipv4 filter FORWARD || true
    
    # 添加新规则
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s "$PRIVATE_NET" -o "$PUBLIC_IFACE" -j MASQUERADE
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i br0 -o "$PUBLIC_IFACE" -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i "$PUBLIC_IFACE" -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # 应用配置
    if ! firewall-cmd --reload; then
      echo "警告：firewalld 配置失败，尝试回退到 iptables" >&2
      fallback_to_iptables
    fi
  else
    echo "firewalld 未安装，使用 iptables 配置..."
    fallback_to_iptables
  fi
}

# iptables 回退方案
fallback_to_iptables() {
  echo "配置 iptables 规则..."
  # 清理旧规则
  iptables -t nat -F POSTROUTING
  iptables -t filter -F FORWARD
  
  # 添加 NAT 规则
  iptables -t nat -A POSTROUTING -s "$PRIVATE_NET" -o "$PUBLIC_IFACE" -j MASQUERADE
  
  # 添加转发规则
  iptables -A FORWARD -i br0 -o "$PUBLIC_IFACE" -j ACCEPT
  iptables -A FORWARD -i "$PUBLIC_IFACE" -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  
  # 保存规则
  if ! service iptables save; then
    echo "错误：iptables 规则保存失败" >&2
    exit 3
  fi
}

# 验证函数
validate_setup() {
  local errors=0
  
  echo -e "\n验证配置："
  
  # 检查 IP 转发
  if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    echo "[错误] IP 转发未启用"
    ((errors++))
  fi
  
  # 检查 NAT 规则
  if ! iptables -t nat -L POSTROUTING -v | grep -q MASQUERADE; then
    echo "[错误] NAT 规则未生效"
    ((errors++))
  fi
  
  # 检查 DNS 解析
  if ! nslookup google.com | grep -q 'Server:'; then
    echo "[警告] DNS 解析可能存在问题"
    ((errors++))
  fi
  
  # 总结状态
  if [ $errors -gt 0 ]; then
    echo "验证发现 $errors 个问题，请检查日志：$LOG_FILE"
    return 1
  else
    echo "所有基础检查通过 ✔"
    return 0
  fi
}

# 主执行流程
main() {
  check_dependencies
  setup_kernel
  setup_firewall
  setup_dns
  validate_setup
}

# 执行主函数
if main; then
  echo -e "\n[成功] 网络配置已完成！"
  echo "请确保所有虚拟机："
  echo "1. 网关设置为 $GATEWAY_IP"
  echo "2. DNS 设置为 ${DNS_SERVERS[*]}"
else
  echo -e "\n[错误] 配置过程中发现问题，请检查输出日志：$LOG_FILE" >&2
  exit 3
fi
