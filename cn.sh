#!/bin/bash
set -eo pipefail

# 配置参数
IPSET_V4="china_ips_v4"
IPSET_V6="china_ips_v6"
CIDR_URL_V4="https://github.com/mayaxcn/china-ip-list/raw/master/chnroute.txt"
CIDR_URL_V6="https://github.com/mayaxcn/china-ip-list/raw/master/chnroute_v6.txt"
LOCK_FILE="/tmp/ipset.lock"

# 获取IPset版本
IPSET_VERSION=$(ipset --version | awk '{print $NF}' | cut -d'.' -f2)
[ -z "$IPSET_VERSION" ] && IPSET_VERSION=0

# 根据版本选择family参数
if [ "$IPSET_VERSION" -ge 11 ]; then
    V4_FAMILY="inet4"
    V6_FAMILY="inet6"
else
    V4_FAMILY="inet"
    V6_FAMILY="inet6"
fi

# 带颜色日志函数
log() {
    local level=$1; shift
    local color=""
    case $level in
        "INFO") color='\033[32m' ;;
        "WARN") color='\033[33m' ;;
        "ERROR") color='\033[31m' ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S') ${level}]${NC} $*"
}
NC='\033[0m'

# 安全创建集合
safe_create_set() {
    local set_name=$1
    local family=$2
    local file=$3

    # 清理旧集合
    if ipset list -n | grep -q "^${set_name}$"; then
        log "INFO" "清理旧集合 ${set_name}..."
        iptables-save | grep -v "match-set ${set_name}" | iptables-restore
        ipset destroy "${set_name}" 2>/dev/null || true
    fi

    # 创建新集合
    log "INFO" "创建集合 ${set_name} (family: ${family})..."
    if ! ipset create "${set_name}" hash:net family "${family}" maxelem 2000000; then
        log "ERROR" "集合创建失败，请检查："
        echo "1. 内核是否加载模块: sudo modprobe ip_set_hash_net"
        echo "2. 是否具有root权限"
        exit 1
    fi

    # 导入数据
    log "INFO" "导入数据到 ${set_name}..."
    sed "s/^/add ${set_name} /" "${file}" | ipset restore -exist 2>&1 | grep -v "already added"

    # 验证条目
    local count=$(ipset list "${set_name}" | grep -c "^add")
    [ "$count" -lt 1000 ] && log "ERROR" "条目数异常" && exit 1
    log "INFO" "成功加载 ${count} 条规则"
}

# 主流程
main() {
    # 检查root权限
    [ "$(id -u)" -ne 0 ] && log "ERROR" "需要root权限运行" && exit 1

    # 创建临时目录
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "${WORK_DIR}"' EXIT

    # 下载CIDR文件
    log "INFO" "下载CIDR列表..."
    curl -fsSL --retry 3 -o "${WORK_DIR}/v4.txt" "${CIDR_URL_V4}"
    curl -fsSL --retry 3 -o "${WORK_DIR}/v6.txt" "${CIDR_URL_V6}"

    # 处理IPv4
    safe_create_set "${IPSET_V4}" "${V4_FAMILY}" "${WORK_DIR}/v4.txt"

    # 处理IPv6
    safe_create_set "${IPSET_V6}" "${V6_FAMILY}" "${WORK_DIR}/v6.txt"

    # 配置防火墙规则（示例）
    iptables -A INPUT -m set --match-set "${IPSET_V4}" src -j ACCEPT
    ip6tables -A INPUT -m set --match-set "${IPSET_V6}" src -j ACCEPT

    log "INFO" "${GREEN}配置成功！"
}

main "$@"
