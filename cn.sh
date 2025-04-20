#!/bin/bash
set -eo pipefail

# 定义资源地址
CHNROUTE_V4_URL="https://github.com/mayaxcn/china-ip-list/raw/master/chnroute.txt"

# 安装依赖 :cite[2]
install_deps() {
    for pkg in curl ipset; do
        if ! command -v $pkg >/dev/null; then
            if command -v apt-get >/dev/null; then
                apt-get update && apt-get install -y $pkg
            elif command -v yum >/dev/null; then
                yum install -y $pkg
            else
                echo "不支持的包管理器，请手动安装 $pkg"
                exit 1
            fi
        fi
    done
}

# 下载CIDR列表
download_cidrs() {
    local url=$1
    local file=$2
    echo "下载 $file..."
    
    if ! curl -sSL --retry 3 --connect-timeout 30 "$url" -o "/tmp/$file"; then
        echo "下载失败: $url"
        exit 1
    fi

    if [ ! -s "/tmp/$file" ]; then
        echo "文件为空: $file"
        exit 1
    fi

    # 验证CIDR格式 :cite[2]
    if grep -qvE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$' "/tmp/$file"; then
        echo "检测到非标准CIDR格式: $file"
        exit 1
    fi
}

# 创建ipset集合
create_ipset() {
    local set_name=$1
    local family=$2
    local file=$3

    if ! ipset list "$set_name" &>/dev/null; then
        if ! ipset create "$set_name" hash:net family "$family" maxelem 1000000; then
            echo "创建ipset集合失败: $set_name"
            exit 1
        fi
    else
        echo "ipset集合已存在: $set_name"
    fi

    echo "导入 $file 到 $set_name..."
    sort -u "/tmp/$file" | while read -r cidr; do
        ipset add "$set_name" "$cidr" -exist
    done
}


# 配置防火墙规则
configure_firewall() {
    # 备份当前规则
    iptables-save > /tmp/iptables.backup
    ip6tables-save > /tmp/ip6tables.backup

    # IPv4规则
    iptables -F
    iptables -P INPUT DROP
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH放行
    iptables -A INPUT -m set --match-set china_ips_v4 src -j ACCEPT

    # IPv6规则
    ip6tables -F
    ip6tables -P INPUT DROP
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH放行
    ip6tables -A INPUT -m set --match-set china_ips_v6 src -j ACCEPT
}

# 主流程
main() {
    install_deps
    download_cidrs "$CHNROUTE_V4_URL" "chnroute.txt"
    download_cidrs "$CHNROUTE_V6_URL" "chnroute_v6.txt"

    create_ipset "china_ips_v4" "inet4" "chnroute.txt"
    create_ipset "china_ips_v6" "inet6" "chnroute_v6.txt"

    configure_firewall

    echo "测试连接..."
    if ! curl -4 -s --retry 2 --connect-timeout 10 https://ip.sb >/dev/null || \
       ! curl -6 -s --retry 2 --connect-timeout 10 https://ip.sb >/dev/null; then
        echo "测试失败，恢复规则..."
        iptables-restore < /tmp/iptables.backup
        ip6tables-restore < /tmp/ip6tables.backup
        exit 1
    fi

    echo "配置成功！规则已生效："
    echo "- SSH(22端口)允许所有IP访问"
    echo "- 其他入站端口仅允许中国IP访问:cite[2]"
    echo "- 出站流量无限制"
    echo "- 规则备份文件: /tmp/iptables.backup /tmp/ip6tables.backup"
}

main "$@"
