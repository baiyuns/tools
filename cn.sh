#!/bin/bash

# 安装指定软件包（如果未安装）
install_if_missing() {
    local package=$1
    if ! command -v "$package" >/dev/null 2>&1; then
        echo "$package 未安装，正在安装..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y "$package"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "$package"
        else
            echo "无法识别的 Linux 发行版，请手动安装 $package。"
            exit 1
        fi
    else
        echo "$package 已安装：$(command -v "$package")"
    fi
}

# 安装必要软件
install_if_missing "curl"
install_if_missing "ipset"
install_if_missing "wget"

# 文件下载函数
download_file() {
    local url=$1
    local file=$2
    echo "下载 $file..."
    if ! wget -q -O "/tmp/$file" "$url"; then
        echo "下载 $file 失败！"
        exit 1
    fi
    if [ ! -s "/tmp/$file" ]; then
        echo "下载的 $file 为空文件！"
        exit 1
    fi
}

# 下载所有IP列表文件
download_file "https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chnroute.txt" "chnroute.txt"
download_file "https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chn_ip.txt" "chn_ip.txt"
download_file "https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chnroute_v6.txt" "chnroute_v6.txt"
download_file "https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chn_ip_v6.txt" "chn_ip_v6.txt"

# 创建ipset集合
create_ipset() {
    local set_name=$1
    local family=$2
    local files=("${@:3}")
    
    ipset destroy "$set_name" 2>/dev/null
    if ! ipset create "$set_name" hash:net family "$family" maxelem 1000000; then
        echo "创建 ipset 集合 $set_name 失败！"
        exit 1
    fi
    
    echo "合并加载文件到 $set_name..."
    for file in "${files[@]}"; do
        sed "s/^/add $set_name /" "/tmp/$file" | ipset restore -f
    done
}

# 创建IPv4/IPv6集合
create_ipset "china_ips" "inet4" "chnroute.txt" "chn_ip.txt"
create_ipset "china_ips_v6" "inet6" "chnroute_v6.txt" "chn_ip_v6.txt"

# 防火墙配置
configure_firewall() {
    # 备份当前规则
    iptables-save > /tmp/iptables.backup
    ip6tables-save > /tmp/ip6tables.backup

    # IPv4规则
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # 基础规则
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # 特殊放行SSH(22端口)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT

    # 允许中国大陆IP访问所有端口
    iptables -A INPUT -m set --match-set china_ips src -j ACCEPT

    # IPv6规则
    ip6tables -F
    ip6tables -X
    ip6tables -t nat -F
    ip6tables -t nat -X
    ip6tables -t mangle -F
    ip6tables -t mangle -X
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT ACCEPT

    # IPv6基础规则
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # 特殊放行SSH(22端口)
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

    # 允许中国大陆IPv6访问所有端口
    ip6tables -A INPUT -m set --match-set china_ips_v6 src -j ACCEPT
}

# 测试连接
test_connection() {
    echo "测试IPv4连接..."
    if ! curl -4 -s --retry 3 --connect-timeout 10 https://ip.sb >/dev/null; then
        echo "IPv4连接测试失败！"
        return 1
    fi

    echo "测试IPv6连接..."
    if ! curl -6 -s --retry 3 --connect-timeout 10 https://ip.sb >/dev/null; then
        echo "IPv6连接测试失败！"
        return 1
    fi
    return 0
}

# 执行配置
configure_firewall

# 连接测试
if test_connection; then
    echo "防火墙规则测试通过，已生效！"
    echo "当前策略："
    echo "1. SSH(22端口)允许所有IP访问"
    echo "2. 其他入站端口仅允许中国大陆IP访问"
    echo "3. 出站流量不受限制"
    echo "4. 规则备份文件：/tmp/iptables.backup 和 /tmp/ip6tables.backup"
else
    echo "连接测试失败，正在恢复原规则..."
    iptables-restore < /tmp/iptables.backup
    ip6tables-restore < /tmp/ip6tables.backup
    exit 1
fi

echo "配置完成！建议通过SSH和新开端口进行访问测试。"
