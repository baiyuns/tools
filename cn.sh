#!/bin/bash
set -eo pipefail

# 配置参数
IPSET_V4="china_ips_v4"
IPSET_V6="china_ips_v6"
V4_CIDR_URL="https://github.com/mayaxcn/china-ip-list/raw/master/chnroute.txt"
V6_CIDR_URL="https://github.com/mayaxcn/china-ip-list/raw/master/chnroute_v6.txt"
V4_IP_URL="https://github.com/mayaxcn/china-ip-list/raw/master/chn_ip.txt"
V6_IP_URL="https://github.com/mayaxcn/china-ip-list/raw/master/chn_ip_v6.txt"
LOCK_FILE="/tmp/ipset_update.lock"

# CIDR正则表达式
V4_CIDR_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
V6_CIDR_REGEX='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}/[0-9]{1,3}$'

# 初始化环境
init() {
    # 防止并发执行
    if [ -e "$LOCK_FILE" ]; then
        echo "另一个更新进程正在运行中..."
        exit 1
    fi
    touch "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; exit' EXIT TERM INT

    # 创建临时目录
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT
}

# 安装依赖
install_deps() {
    local pkgs=("curl" "ipset")
    for pkg in "${pkgs[@]}"; do
        if ! command -v "$pkg" >/dev/null; then
            echo "安装依赖: $pkg..."
            if command -v apt-get >/dev/null; then
                apt-get update && apt-get install -y "$pkg"
            elif command -v yum >/dev/null; then
                yum install -y "$pkg"
            else
                echo "错误：不支持的包管理器"
                exit 1
            fi
        fi
    done
}

# 安全下载并转换文件
prepare_file() {
    local url=$1
    local file=$2
    local type=$3  # v4或v6

    echo "下载 $file..."
    if ! curl -sSL --retry 3 --connect-timeout 30 "$url" -o "$WORK_DIR/$file.raw"; then
        echo "错误：下载失败 $url"
        exit 1
    fi

    # 转换单个IP为CIDR格式
    if [[ "$file" == *"ip.txt" ]]; then
        echo "转换单个IP到CIDR格式..."
        if [ "$type" == "v4" ]; then
            sed -e 's/$//32' "$WORK_DIR/$file.raw" > "$WORK_DIR/$file"
        else
            sed -e 's/$//128' "$WORK_DIR/$file.raw" > "$WORK_DIR/$file"
        fi
    else
        mv "$WORK_DIR/$file.raw" "$WORK_DIR/$file"
    fi

    # 格式验证
    local regex=$([ "$type" == "v4" ] && echo "$V4_CIDR_REGEX" || echo "$V6_CIDR_REGEX")
    if grep -qvE "$regex" "$WORK_DIR/$file"; then
        echo "错误：检测到非标准CIDR格式 $file"
        echo "第一个错误行示例:"
        grep -vE "$regex" "$WORK_DIR/$file" | head -n 1
        exit 1
    fi

    # 去重排序
    sort -u "$WORK_DIR/$file" -o "$WORK_DIR/$file.sorted"
    mv "$WORK_DIR/$file.sorted" "$WORK_DIR/$file"
}

# 管理ipset集合
manage_ipset() {
    local set_name=$1
    local family=$2
    local file=$3

    # 清理旧数据
    if ipset list -n | grep -qw "$set_name"; then
        echo "更新集合 $set_name..."
        ipset flush "$set_name"
    else
        echo "创建集合 $set_name..."
        ipset create "$set_name" hash:net family "$family" maxelem 1000000
    fi

    # 批量导入数据
    echo "加载 $file 到 $set_name..."
    sed "s/^/add $set_name /" "$WORK_DIR/$file" | ipset restore -exist 2>&1 | grep -vE "(already added|element is the same)"

    # 验证条目数
    local count=$(ipset list "$set_name" | grep -c "^add")
    if [ "$count" -lt 100 ]; then
        echo "错误：集合条目数异常 ($count)"
        exit 1
    fi
    echo "成功加载 $count 条规则到 $set_name"
}

# 配置防火墙（保持原有优化逻辑）
configure_firewall() {
    # ...（同之前优化版本）
}

# 连接测试（保持原有优化逻辑）
connection_test() {
    # ...（同之前优化版本）
}

# 主流程
main() {
    init
    install_deps

    # 下载并处理文件
    prepare_file "$V4_CIDR_URL" "chnroute.txt" "v4"
    prepare_file "$V6_CIDR_URL" "chnroute_v6.txt" "v6"
    prepare_file "$V4_IP_URL" "chn_ip.txt" "v4"
    prepare_file "$V6_IP_URL" "chn_ip_v6.txt" "v6"

    # 合并文件
    cat "$WORK_DIR/chnroute.txt" "$WORK_DIR/chn_ip.txt" > "$WORK_DIR/merged_v4.txt"
    cat "$WORK_DIR/chnroute_v6.txt" "$WORK_DIR/chn_ip_v6.txt" > "$WORK_DIR/merged_v6.txt"

    # 管理IP集合
    manage_ipset "$IPSET_V4" "inet4" "merged_v4.txt"
    manage_ipset "$IPSET_V6" "inet6" "merged_v6.txt"

    # 配置防火墙
    configure_firewall

    # 最终测试
    if connection_test; then
        echo "配置成功！当前策略："
        echo "- SSH(22)端口开放所有IP访问"
        echo "- 其他入站端口仅允许中国大陆IP"
        echo "- 出站流量无限制"
        echo "- 规则备份位置: $WORK_DIR"
    else
        echo "错误：连接测试失败，正在恢复原规则..."
        iptables-restore < "$WORK_DIR/iptables.backup"
        ip6tables-restore < "$WORK_DIR/ip6tables.backup"
        exit 1
    fi
}

main "$@"
