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

# 安装 curl 和 ipset
install_if_missing "curl"
install_if_missing "ipset"

# 下载中国大陆 IP 列表
echo "下载中国大陆 IP 列表..."
wget -q -O /tmp/chnroute.txt https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chnroute.txt
wget -q -O /tmp/chn_ip.txt https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chn_ip.txt
wget -q -O /tmp/chn_ip_v6.txt https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chn_ip_v6.txt
wget -q -O /tmp/chnroute_v6.txt https://raw.githubusercontent.com/mayaxcn/china-ip-list/master/chnroute_v6.txt

# 创建 ipset 集合，如果已经存在则销毁旧集合并重新创建
echo "创建 ipset 集合..."
ipset destroy china_ips 2>/dev/null
ipset create china_ips hash:net maxelem 1000000

# 加载中国大陆 IP 列表到 ipset（避免重复添加）
echo "加载中国大陆 IP 列表到 ipset..."
for ip in $(cat /tmp/chnroute.txt); do
    if ! ipset test china_ips "$ip" &>/dev/null; then
        ipset add china_ips "$ip"
    fi
done

# 设置防火墙规则
echo "设置防火墙规则..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 允许回环接口
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 允许已建立的连接和相关流量
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 允许中国大陆 IP 地址
iptables -A INPUT -m set --match-set china_ips src -j ACCEPT

# 测试连接，避免锁死服务器
echo "测试防火墙规则..."
curl -s https://ip.sb > /dev/null
if [[ $? -ne 0 ]]; then
    echo "测试失败，请检查防火墙规则。" >&2
    exit 1
else
    echo "防火墙规则设置成功，仅允许中国大陆 IP 访问。"
fi

echo "完成！请测试服务器功能以确保一切正常。"
