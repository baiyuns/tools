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

# 带时间戳的日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    case $level in
        "INFO") echo -e "${GREEN}[${timestamp} INFO]${NC} ${message}" ;;
        "WARN") echo -e "${YELLOW}[${timestamp} WARN]${NC} ${message}" ;;
        "ERROR") echo -e "${RED}[${timestamp} ERROR]${NC} ${message}" >&2 ;;
    esac
}

# 带超时的命令执行
run_with_timeout() {
    local timeout=$1
    local cmd=$2
    if ! timeout ${timeout} bash -c "${cmd}"; then
        log "ERROR" "命令执行超时: ${cmd}"
        return 1
    fi
    return 0
}

# 安全清理集合
safe_clean_set() {
    local set_name=$1
    log "INFO" "开始清理集合 ${set_name}"
    
    # 清理防火墙规则
    log "INFO" "移除关联的iptables规则..."
    run_with_timeout 30 "iptables-save | grep -v 'match-set ${set_name}' | iptables-restore"
    run_with_timeout 30 "ip6tables-save | grep -v 'match-set ${set_name}' | ip6tables-restore"

    # 分步清理集合
    log "INFO" "清空集合内容..."
    run_with_timeout 60 "ipset flush ${set_name} || true"
    
    log "INFO" "销毁集合..."
    run_with_timeout 30 "ipset destroy ${set_name} || true"
    
    log "INFO" "验证清理结果..."
    if ipset list -n | grep -q "^${set_name}$"; then
        log "ERROR" "集合 ${set_name} 清理失败"
        return 1
    fi
    log "INFO" "清理完成"
    sleep 2
}

# 主流程
main() {
    log "INFO" "初始化工作目录..."
    work_dir=$(mktemp -d)
    trap 'rm -rf "${work_dir}"' EXIT

    log "INFO" "下载CIDR列表..."
    curl -sSL --retry 3 -o "${work_dir}/v4.txt" "${CIDR_URL_V4}"
    curl -sSL --retry 3 -o "${work_dir}/v6.txt" "${CIDR_URL_V6}"

    # 处理IPv4集合
    safe_clean_set "${IPSET_V4}"
    
    log "INFO" "创建新集合 ${IPSET_V4}..."
    run_with_timeout 30 "ipset create ${IPSET_V4} hash:net family inet4 maxelem 2000000"
    
    log "INFO" "导入数据..."
    sed "s/^/add ${IPSET_V4} /" "${work_dir}/v4.txt" | run_with_timeout 300 "ipset restore -exist"
    
    log "INFO" "当前集合条目数: $(ipset list ${IPSET_V4} | grep -c '^add')"

    # 重复上述流程处理IPv6...
}

main "$@"
