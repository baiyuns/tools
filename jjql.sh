#!/bin/bash
set -o errexit
set -o pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

get_disk_usage() {
    df / | awk 'NR==2 {print $5}' | sed 's/%//'
}

show_disk_status() {
    echo -e "${BLUE}=== 当前磁盘使用情况 ===${NC}"
    df -h
    echo ""
    local usage=$(get_disk_usage)
    if [[ $usage -gt 95 ]]; then
        echo -e "${RED}⚠️  危险：磁盘使用率 ${usage}% - 立即清理${NC}"
    elif [[ $usage -gt 90 ]]; then
        echo -e "${YELLOW}⚠️  警告：磁盘使用率 ${usage}% - 建议清理${NC}"
    else
        echo -e "${GREEN}✓ 磁盘使用率 ${usage}% - 正常${NC}"
    fi
    echo ""
}

emergency_cleanup() {
    local before_usage=$(get_disk_usage)
    echo -e "${RED}=== 开始紧急清理：使用率 ${before_usage}% ===${NC}"

    echo -e "${YELLOW}1. 清理系统日志...${NC}"
    journalctl --vacuum-size=10M >/dev/null 2>&1 || true
    journalctl --vacuum-time=1d >/dev/null 2>&1 || true
    find /var/log -name "*.log" -type f -exec truncate -s 0 {} \; 2>/dev/null
    find /var/log -name "*.gz" -delete 2>/dev/null
    find /var/log -name "*.1" -delete 2>/dev/null
    find /var/log -name "*.old" -delete 2>/dev/null

    echo -e "${YELLOW}2. 清理临时目录...${NC}"
    rm -rf /tmp/* /var/tmp/* 2>/dev/null

    echo -e "${YELLOW}3. 清理包缓存...${NC}"
    apt-get clean >/dev/null 2>&1 || true
    apt-get autoclean >/dev/null 2>&1 || true
    apt-get autoremove --purge -y >/dev/null 2>&1 || true
    yum clean all >/dev/null 2>&1 || true
    dnf clean all >/dev/null 2>&1 || true

    echo -e "${YELLOW}4. 清理 Docker（如有）...${NC}"
    docker system prune -af --volumes >/dev/null 2>&1 || true

    echo -e "${YELLOW}5. 清理缓存...${NC}"
    find /home/*/.cache -type f -delete 2>/dev/null
    find /root/.cache -type f -delete 2>/dev/null
    rm -rf /home/*/.mozilla /home/*/.config/google-chrome /home/*/.config/chromium 2>/dev/null

    echo -e "${YELLOW}6. 删除30天以上的大文件（排除 XrayR）...${NC}"
    find / -path "/etc/XrayR" -prune -o \
          -path "/usr/local/XrayR" -prune -o \
          -path "/var/log/XrayR" -prune -o \
          -path "/etc/systemd/system/XrayR.service" -prune -o \
          -type f -size +100M -mtime +30 -exec rm -f {} \; 2>/dev/null

    echo -e "${YELLOW}7. 清理 core dump ...${NC}"
    find / -type f \( -name "core" -o -name "core.*" -o -name "*.core" \) -delete 2>/dev/null

    echo -e "${YELLOW}8. 清理 Snap、pip、npm 缓存...${NC}"
    snap list --all | awk '/disabled/{print $1, $3}' |
    while read name rev; do
        snap remove "$name" --revision="$rev" >/dev/null 2>&1 || true
    done

    pip cache purge >/dev/null 2>&1 || true
    pip3 cache purge >/dev/null 2>&1 || true
    npm cache clean --force >/dev/null 2>&1 || true

    local after_usage=$(get_disk_usage)
    local saved=$((before_usage - after_usage))
    if [[ $saved -lt 0 ]]; then saved=0; fi
    echo -e "${GREEN}✓ 紧急清理完成：${RED}${before_usage}%${NC} → ${GREEN}${after_usage}%${NC}（节省 ${BLUE}${saved}%${NC}）"
}

find_large_files() {
    echo -e "${BLUE}=== 前20大文件（排除 XrayR） ===${NC}"
    find / -path "/etc/XrayR" -prune -o \
          -path "/usr/local/XrayR" -prune -o \
          -path "/var/log/XrayR" -prune -o \
          -type f -size +100M -print 2>/dev/null | \
          xargs -r ls -lh 2>/dev/null | sort -k5 -hr | head -20
}

manual_cleanup_guide() {
    echo -e "${BLUE}=== 手动清理建议 ===${NC}"
    echo "1. 查找大文件（排除 XrayR）："
    echo "   find / -type f -size +1G 2>/dev/null | grep -v XrayR | xargs -r ls -lh | sort -k5 -hr | head -10"
}

generate_cleanup_script() {
    cat > /usr/local/bin/auto_cleanup.sh << 'EOF'
#!/bin/bash
USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $USAGE -lt 90 ]]; then exit 0; fi
journalctl --vacuum-size=10M >/dev/null 2>&1 || true
journalctl --vacuum-time=1d >/dev/null 2>&1 || true
find /var/log -name "*.log" -type f -exec truncate -s 0 {} \; 2>/dev/null
find /var/log -name "*.gz" -delete 2>/dev/null
rm -rf /tmp/* /var/tmp/* /root/.cache/* 2>/dev/null
EOF
    chmod +x /usr/local/bin/auto_cleanup.sh
}

setup_monitoring() {
    generate_cleanup_script
    cat > /usr/local/bin/disk_monitor.sh << 'EOF'
#!/bin/bash
USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $USAGE -gt 90 ]]; then
    echo "$(date): 磁盘使用率 ${USAGE}% - 执行自动清理" >> /var/log/disk_monitor.log
    /usr/local/bin/auto_cleanup.sh >> /var/log/disk_monitor.log 2>&1
fi
EOF
    chmod +x /usr/local/bin/disk_monitor.sh
    (crontab -l 2>/dev/null | grep -v "disk_monitor.sh"; echo "*/10 * * * * /usr/local/bin/disk_monitor.sh") | crontab -
    echo -e "${GREEN}✓ 自动监控已设置：每10分钟检查一次磁盘使用率${NC}"
}

main() {
    echo -e "${BLUE}======== 紧急磁盘清理工具（保留 XrayR） ========${NC}"
    show_disk_status

    local usage=$(get_disk_usage)
    if [[ $usage -gt 95 ]]; then
        echo -e "${RED}🚨 空间严重不足！立即清理...${NC}"
        emergency_cleanup
        show_disk_status
        [[ $(get_disk_usage) -gt 85 ]] && find_large_files && manual_cleanup_guide
    elif [[ $usage -gt 90 ]]; then
        echo -e "${YELLOW}⚠️ 空间紧张，执行清理...${NC}"
        emergency_cleanup
        show_disk_status
    else
        echo -e "${GREEN}✓ 空间充足，执行常规清理...${NC}"
        emergency_cleanup
        show_disk_status
    fi

    echo ""
    read -p "是否设置自动磁盘监控？(y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_monitoring
    fi
    echo -e "\n${GREEN}✓ 清理完成！建议定期运行此脚本。${NC}"
}

main "$@"
