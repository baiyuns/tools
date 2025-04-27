#!/bin/bash

# 清空当前所有防火墙规则
echo "清空当前所有防火墙规则..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 检查并安装必要工具
echo "检查并安装必要工具..."

#!/bin/bash

# 1. 检查是否安装了 curl（使用更可靠的检测方式）
if ! command -v curl >/dev/null 2>&1; then
    echo "curl 未安装，正在安装..."
    # 检查系统的包管理工具并安装curl 
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        apt-get update && apt-get install -y curl
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS
        yum install -y curl
    else
        echo "无法识别的 Linux 发行版，请手动安装 curl。"
        command -v curl || echo "curl 确实未安装"
        exit 1
    fi
else
    echo "curl 已安装: $(command -v curl)"
fi

# 后续DDNS逻辑...

# 检查并安装 iptables
if ! command -v iptables &>/dev/null; then
    apt-get update && apt-get install -y iptables
    if [[ $? -ne 0 ]]; then
        echo "安装 iptables 失败，请检查网络。" >&2
        exit 1
    fi
fi

echo "所有必要工具安装完成。"


# 下载中国大陆 IP 列表
CN_ZONE_URL="https://www.ipdeny.com/ipblocks/data/countries/cn.zone"
CN_IP_FILE="/tmp/cn.zone"
echo "下载中国大陆 IP 列表..."
curl -o $CN_IP_FILE $CN_ZONE_URL
if [[ $? -ne 0 ]] || [[ ! -s $CN_IP_FILE ]]; then
    echo "下载中国大陆 IP 列表失败，请检查网络或 URL。" >&2
    exit 1
fi

# 设置防火墙规则
echo "设置防火墙规则..."
# 默认策略设置为拒绝
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 允许回环接口
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 允许已建立的连接和相关流量
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 加载中国大陆 IP 列表
while read -r IP; do
    [[ "$IP" =~ ^#.*$ || -z "$IP" ]] && continue # 跳过注释或空行
    iptables -A INPUT -s "$IP" -j ACCEPT
done < "$CN_IP_FILE"

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
