#!/bin/bash 病急乱投医 出事跟我没关系！！

# 紧急磁盘清理脚本 - 用于清理超过90%的磁盘使用率
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取磁盘使用率
get_disk_usage() {
    df / | awk 'NR==2 {print $5}' | sed 's/%//'
}

# 获取最大的文件和目录
find_large_files() {
    echo -e "${BLUE}=== 查找占用空间最大的文件 (前20个) ===${NC}"
    find / -type f -size +100M 2>/dev/null | head -20 | xargs ls -lh 2>/dev/null || true
    
    echo -e "\n${BLUE}=== 查找占用空间最大的目录 (前10个) ===${NC}"
    du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10 || true
}

# 显示当前磁盘状态
show_disk_status() {
    echo -e "${BLUE}=== 当前磁盘使用情况 ===${NC}"
    df -h
    echo ""
    local usage=$(get_disk_usage)
    if [[ $usage -gt 95 ]]; then
        echo -e "${RED}⚠️  危险：磁盘使用率 ${usage}% - 立即需要清理！${NC}"
    elif [[ $usage -gt 90 ]]; then
        echo -e "${YELLOW}⚠️  警告：磁盘使用率 ${usage}% - 建议清理${NC}"
    else
        echo -e "${GREEN}✓ 磁盘使用率 ${usage}% - 正常${NC}"
    fi
    echo ""
}

# 紧急清理函数
emergency_cleanup() {
    local before_usage=$(get_disk_usage)
    echo -e "${RED}=== 开始紧急磁盘清理 (使用率: ${before_usage}%) ===${NC}"
    
    # 1. 清理系统日志 (最激进)
    echo -e "${YELLOW}清理系统日志...${NC}"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-size=10M >/dev/null 2>&1
        journalctl --vacuum-time=1d >/dev/null 2>&1
    fi
    
    # 清空所有 .log 文件但保留文件结构
    find /var/log -name "*.log" -type f -exec truncate -s 0 {} \; 2>/dev/null
    
    # 删除压缩的日志文件
    find /var/log -name "*.gz" -delete 2>/dev/null
    find /var/log -name "*.1" -delete 2>/dev/null
    find /var/log -name "*.old" -delete 2>/dev/null
    
    # 2. 清理临时文件
    echo -e "${YELLOW}清理临时文件...${NC}"
    rm -rf /tmp/* 2>/dev/null
    rm -rf /var/tmp/* 2>/dev/null
    
    # 3. 清理包管理器缓存
    echo -e "${YELLOW}清理包管理器缓存...${NC}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get clean >/dev/null 2>&1
        apt-get autoclean >/dev/null 2>&1
        apt-get autoremove --purge -y >/dev/null 2>&1
    fi
    
    if command -v yum >/dev/null 2>&1; then
        yum clean all >/dev/null 2>&1
    fi
    
    if command -v dnf >/dev/null 2>&1; then
        dnf clean all >/dev/null 2>&1
    fi
    
    # 4. 清理Docker (如果存在且占用大量空间)
    if command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}清理Docker资源...${NC}"
        docker system prune -af --volumes >/dev/null 2>&1 || true
        docker builder prune -af >/dev/null 2>&1 || true
    fi
    
    # 5. 清理大缓存目录
    echo -e "${YELLOW}清理用户缓存...${NC}"
    rm -rf /home/*/.cache/* 2>/dev/null
    rm -rf /root/.cache/* 2>/dev/null
    
    # 清理浏览器缓存
    rm -rf /home/*/.mozilla/firefox/*/Cache* 2>/dev/null
    rm -rf /home/*/.cache/google-chrome/* 2>/dev/null
    rm -rf /home/*/.cache/chromium/* 2>/dev/null
    
    # 6. 清理核心转储和崩溃文件
    echo -e "${YELLOW}清理核心转储文件...${NC}"
    find / -name "core" -type f -delete 2>/dev/null
    find / -name "core.*" -type f -delete 2>/dev/null
    find / -name "*.core" -type f -delete 2>/dev/null
    
    # 7. 清理编译缓存
    rm -rf /home/*/.ccache/* 2>/dev/null
    rm -rf /root/.ccache/* 2>/dev/null
    
    # 8. 清理pip/NPM缓存
    echo -e "${YELLOW}清理编程语言缓存...${NC}"
    if command -v pip >/dev/null 2>&1; then
        pip cache purge >/dev/null 2>&1 || true
    fi
    if command -v pip3 >/dev/null 2>&1; then
        pip3 cache purge >/dev/null 2>&1 || true
    fi
    if command -v npm >/dev/null 2>&1; then
        npm cache clean --force >/dev/null 2>&1 || true
    fi
    
    # 9. 清理Snap包缓存
    if command -v snap >/dev/null 2>&1; then
        echo -e "${YELLOW}清理Snap包...${NC}"
        snap list --all | awk '/disabled/{print $1, $3}' | 
        while read snapname revision; do
            snap remove "$snapname" --revision="$revision" >/dev/null 2>&1 || true
        done
    fi
    
    # 10. 删除旧的下载文件
    echo -e "${YELLOW}清理下载目录...${NC}"
    find /home/*/Downloads -type f -mtime +30 -size +100M -delete 2>/dev/null || true
    find /root/Downloads -type f -mtime +30 -size +100M -delete 2>/dev/null || true
    
    local after_usage=$(get_disk_usage)
    local saved=$((before_usage - after_usage))
    echo -e "${GREEN}✓ 紧急清理完成！${NC}"
    echo -e "磁盘使用率: ${RED}${before_usage}%${NC} → ${GREEN}${after_usage}%${NC} (节省: ${BLUE}${saved}%${NC})"
}

# 手动清理大文件
manual_cleanup_guide() {
    echo -e "${BLUE}=== 手动清理建议 ===${NC}"
    echo "如果自动清理后空间仍不足，请考虑手动删除以下类型的文件："
    echo ""
    echo "1. 查找大文件 (>1GB):"
    echo "   find / -type f -size +1G 2>/dev/null | head -10"
    echo ""
    echo "2. 查找占用空间最大的目录:"
    echo "   du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10"
    echo ""
    echo "3. 常见可删除的大文件位置:"
    echo "   - /var/log/ (日志文件)"
    echo "   - /tmp/ (临时文件)"
    echo "   - /home/*/Downloads/ (下载文件)"
    echo "   - /opt/ (可选软件)"
    echo "   - /usr/src/ (源代码)"
    echo ""
    echo "4. 删除不需要的软件包:"
    echo "   apt list --installed | grep -i [软件名]"
    echo "   apt remove [软件包名]"
}

# 设置自动清理任务
setup_monitoring() {
    echo -e "${BLUE}=== 设置磁盘监控 ===${NC}"
    
    # 创建磁盘监控脚本
    cat > /usr/local/bin/disk_monitor.sh << 'EOF'
#!/bin/bash
USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $USAGE -gt 90 ]]; then
    echo "$(date): 磁盘使用率 ${USAGE}% - 执行自动清理" >> /var/log/disk_monitor.log
    /usr/local/bin/auto_cleanup.sh >> /var/log/disk_monitor.log 2>&1
fi
EOF
    
    chmod +x /usr/local/bin/disk_monitor.sh
    
    # 添加到cron，每10分钟检查一次
    (crontab -l 2>/dev/null | grep -v "disk_monitor.sh"; echo "*/10 * * * * /usr/local/bin/disk_monitor.sh") | crontab -
    
    echo -e "${GREEN}✓ 磁盘监控已设置 (每10分钟检查一次，使用率>90%时自动清理)${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}=================== 紧急磁盘清理工具 ===================${NC}"
    
    # 显示当前状态
    show_disk_status
    
    local current_usage=$(get_disk_usage)
    
    if [[ $current_usage -gt 95 ]]; then
        echo -e "${RED}🚨 磁盘空间严重不足！立即执行紧急清理...${NC}"
        emergency_cleanup
        show_disk_status
        
        # 如果还是很高，显示大文件
        if [[ $(get_disk_usage) -gt 85 ]]; then
            find_large_files
            manual_cleanup_guide
        fi
        
    elif [[ $current_usage -gt 90 ]]; then
        echo -e "${YELLOW}⚠️  磁盘空间不足，执行清理...${NC}"
        emergency_cleanup
        show_disk_status
        
    else
        echo -e "${GREEN}✓ 磁盘空间充足，执行常规清理...${NC}"
        emergency_cleanup
        show_disk_status
    fi
    
    # 设置监控
    echo ""
    read -p "是否设置自动磁盘监控？(y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_monitoring
    fi
    
    echo -e "\n${GREEN}✓ 清理完成！${NC}"
    echo -e "建议定期运行此脚本或设置自动清理任务。"
}

# 执行主函数
main "$@"
