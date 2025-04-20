#!/bin/bash
set -eo pipefail

# 配置参数
IPSET_V4="china_ips_v4"
IPSET_V6="china_ips_v6"
CIDR_URL_V4="https://github.com/mayaxcn/china-ip-list/raw/master/chnroute.txt"
CIDR_URL_V6="https://github.com/mayaxcn/china-ip-list/raw/master/chnroute_v6.txt"
LOCK_FILE="/tmp/ipset.lock"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 带颜色输出函数
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 安全初始化集合
safe_ipset() {
    local set_name=$1
    local family=$2
    local file=$3
    
    # 清理旧集合
    if ipset list -n | grep -q "^${set_name}$"; then
        info "清理旧集合 ${set_name}..."
        iptables-save | grep -v "match-set ${set_name}" | iptables-restore
        ip6tables-save | grep -v "match-set ${set_name}" | ip6tables-restore
        ipset flush "${set_name}" 2>/dev/null || true
        ipset destroy "${set_name}" 2>/dev/null || true
        sleep 1
    fi

    # 创建新集合
    info "创建新集合 ${set_name}..."
    if ! ipset create "${set_name}" hash:net family "${family}" maxelem 2000000 2>/dev/null; then
        error "集合创建失败，请检查内核模块是否加载 (lsmod | grep ip_set)"
        exit 1
    fi

    # 批量导入数据（忽略重复条目）
    info "导入数据到 ${set_name}..."
    sed "s/^/add ${set_name} /" "${file}" | ipset restore -exist 2>&1 | grep -vE "(already added|element is the same)" || true

    # 验证结果
    local count=$(ipset list "${set_name}" | grep -c "^add")
    if [ "${count}" -lt 1000 ]; then
        error "集合条目数异常，请检查源文件"
        exit 1
    fi
    info "成功加载 ${count} 条规则"
}

# 主流程
main() {
    # 创建锁文件
    exec 9>"${LOCK_FILE}"
    if ! flock -n 9; then
        error "已有另一个实例在运行中"
        exit 1
    fi

    # 创建临时工作区
    local work_dir
    work_dir=$(mktemp -d)
    trap 'rm -rf "${work_dir}"; flock -u 9' EXIT

    # 下载CIDR文件
    info "下载IPv4列表..."
    curl -sSL --retry 3 --connect-timeout 30 "${CIDR_URL_V4}" -o "${work_dir}/v4.txt"
    info "下载IPv6列表..."
    curl -sSL --retry 3 --connect-timeout 30 "${CIDR_URL_V6}" -o "${work_dir}/v6.txt"

    # 处理IPv4
    safe_ipset "${IPSET_V4}" "inet4" "${work_dir}/v4.txt"

    # 处理IPv6
    safe_ipset "${IPSET_V6}" "inet6" "${work_dir}/v6.txt"

    # 配置防火墙规则
    info "配置防火墙..."
    iptables -F INPUT
    iptables -P INPUT DROP
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -m set --match-set "${IPSET_V4}" src -j ACCEPT

    ip6tables -F INPUT
    ip6tables -P INPUT DROP
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT
    ip6tables -A INPUT -m set --match-set "${IPSET_V6}" src -j ACCEPT

    info "${GREEN}配置成功！规则说明："
    echo -e "• SSH端口(22)对所有IP开放\n• 其他入站端口仅允许中国大陆IP\n• 出站流量无限制${NC}"
}

main "$@"
