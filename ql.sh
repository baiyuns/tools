#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 自动清理脚本路径
CLEANUP_SCRIPT="/usr/local/bin/auto_cleanup.sh"
LOG_FILE="/var/log/auto_cleanup.log"

# 磁盘空间阈值 (百分比)
DISK_THRESHOLD=85

log_info "==> 创建增强版自动清理脚本 $CLEANUP_SCRIPT"

cat > "$CLEANUP_SCRIPT" << 'EOF'
#!/bin/bash

# 日志配置
LOG_FILE="/var/log/auto_cleanup.log"
MAX_LOG_SIZE=10485760  # 10MB

# 日志函数
log_with_date() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 检查并轮转日志
rotate_log() {
    if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
}

# 获取磁盘使用率
get_disk_usage() {
    df / | awk 'NR==2 {print $5}' | sed 's/%//'
}

# 清理函数
cleanup_system() {
    local before_usage=$(get_disk_usage)
    log_with_date "清理前磁盘使用率: ${before_usage}%"
    
    # 1. 清理包管理器缓存
    log_with_date "清理包管理器缓存..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get clean >/dev/null 2>&1
        apt-get autoclean >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
    fi
    
    if command -v yum >/dev/null 2>&1; then
        yum clean all >/dev/null 2>&1
    fi
    
    if command -v dnf >/dev/null 2>&1; then
        dnf clean all >/dev/null 2>&1
    fi
    
    # 2. 清理系统日志
    log_with_date "清理系统日志..."
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-size=50M >/dev/null 2>&1
        journalctl --vacuum-time=7d >/dev/null 2>&1
    fi
    
    # 清理旧的日志文件
    find /var/log -type f \( -name "*.log" -o -name "*.gz" -o -name "*.1" -o -name "*.old" \) -mtime +7 -delete 2>/dev/null
    find /var/log -type f -name "*.log" -size +100M -exec truncate -s 10M {} \; 2>/dev/null
    
    # 3. 清理临时文件
    log_with_date "清理临时文件..."
    rm -rf /tmp/* 2>/dev/null
    rm -rf /var/tmp/* 2>/dev/null
    
    # 清理用户临时文件
    find /home -type f \( -name "*.tmp" -o -name "*.temp" -o -name "*.cache" \) -mtime +3 -delete 2>/dev/null
    find /root -type f \( -name "*.tmp" -o -name "*.temp" -o -name "*.cache" \) -mtime +3 -delete 2>/dev/null
    
    # 4. 清理缓存目录
    log_with_date "清理缓存目录..."
    find /home -path "*/cache/*" -type f -mtime +7 -delete 2>/dev/null
    find /root -path "*/cache/*" -type f -mtime +7 -delete 2>/dev/null
    
    # 清理浏览器缓存
    find /home -path "*/.cache/google-chrome/*" -type f -mtime +7 -delete 2>/dev/null
    find /home -path "*/.cache/firefox/*" -type f -mtime +7 -delete 2>/dev/null
    find /home -path "*/.mozilla/firefox/*/Cache*" -type f -mtime +7 -delete 2>/dev/null
    
    # 5. 清理核心转储文件
    log_with_date "清理核心转储文件..."
    find / -type f -name "core" -delete 2>/dev/null
    find / -type f -name "core.*" -delete 2>/dev/null
    
    # 6. 清理旧的内核文件
    log_with_date "清理旧内核..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get autoremove --purge -y >/dev/null 2>&1
    fi
    
    # 7. 清理Docker相关（如果存在）
    if command -v docker >/dev/null 2>&1; then
        log_with_date "清理Docker资源..."
        docker system prune -f >/dev/null 2>&1 || true
        docker image prune -f >/dev/null 2>&1 || true
    fi
    
    # 8. 清理Snap包（如果存在）
    if command -v snap >/dev/null 2>&1; then
        log_with_date "清理Snap包..."
        snap list --all | awk '/disabled/{print $1, $3}' | 
        while read snapname revision; do
            snap remove "$snapname" --revision="$revision" >/dev/null 2>&1 || true
        done
    fi
    
    # 9. 清理pip缓存
    if command -v pip >/dev/null 2>&1; then
        pip cache purge >/dev/null 2>&1 || true
    fi
    if command -v pip3 >/dev/null 2>&1; then
        pip3 cache purge >/dev/null 2>&1 || true
    fi
    
    # 10. 清理npm缓存
    if command -v npm >/dev/null 2>&1; then
        npm cache clean --force >/dev/null 2>&1 || true
    fi
    
    local after_usage=$(get_disk_usage)
    local saved=$((before_usage - after_usage))
    log_with_date "清理完成! 磁盘使用率: ${before_usage}% -> ${after_usage}% (节省: ${saved}%)"
}

# 主执行逻辑
main() {
    rotate_log
    log_with_date "==== 自动清理磁盘开始 ===="
    
    local current_usage=$(get_disk_usage)
    log_with_date "当前磁盘使用率: ${current_usage}%"
    
    # 总是执行清理，但根据使用率调整清理强度
    if [[ $current_usage -gt 90 ]]; then
        log_with_date "磁盘使用率超过90%，执行深度清理"
        cleanup_system
    elif [[ $current_usage -gt 80 ]]; then
        log_with_date "磁盘使用率超过80%，执行标准清理"
        cleanup_system
    else
        log_with_date "执行常规维护清理"
        cleanup_system
    fi
    
    # 显示磁盘状态
    log_with_date "当前磁盘状态:"
    df -h / | tail -1 | awk '{print "使用: "$3"/"$2" ("$5")"}' | tee -a "$LOG_FILE"
    
    log_with_date "==== 自动清理磁盘完成 ===="
}

# 执行主函数
main "$@"
EOF

# 设置执行权限
chmod +x "$CLEANUP_SCRIPT"

# 创建日志目录
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_info "==> 检测系统初始化系统类型..."

# 检测 systemd 是否存在并正常工作
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
    log_info "==> 检测到 systemd，配置 systemd 定时器"
    
    # 停止并删除旧的服务（如果存在）
    systemctl stop auto_cleanup.timer 2>/dev/null || true
    systemctl disable auto_cleanup.timer 2>/dev/null || true
    
    # 创建增强版 systemd 服务文件
    cat > /etc/systemd/system/auto_cleanup.service << EOF
[Unit]
Description=Enhanced Auto Disk Cleanup Service
Documentation=man:auto_cleanup
Wants=network.target
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=$CLEANUP_SCRIPT
StandardOutput=journal
StandardError=journal
TimeoutStartSec=1800
PrivateTmp=true
ProtectSystem=false
ProtectHome=false
EOF

    # 创建增强版 systemd 定时器文件
    cat > /etc/systemd/system/auto_cleanup.timer << EOF
[Unit]
Description=Enhanced Auto Disk Cleanup Timer
Documentation=man:auto_cleanup
Requires=auto_cleanup.service

[Timer]
OnBootSec=10min
OnUnitActiveSec=4h
RandomizedDelaySec=30min
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    # 重新加载并启用服务
    systemctl daemon-reload
    systemctl enable auto_cleanup.timer
    systemctl start auto_cleanup.timer
    
    log_info "==> systemd 定时器已启用 (每4小时执行一次，随机延迟30分钟)"
    log_info "==> 使用 'systemctl status auto_cleanup.timer' 查看状态"
    log_info "==> 使用 'journalctl -u auto_cleanup.service' 查看日志"

elif command -v crontab >/dev/null 2>&1; then
    log_info "==> 未检测到可用的 systemd，使用 cron 定时任务"
    
    # 移除旧的 cron 任务
    crontab -l 2>/dev/null | grep -v "$CLEANUP_SCRIPT" | crontab - 2>/dev/null || true
    
    # 添加新的 cron 任务，每4小时执行一次
    (crontab -l 2>/dev/null; echo "0 */4 * * * $CLEANUP_SCRIPT >> $LOG_FILE 2>&1") | crontab -
    
    log_info "==> cron 定时任务已添加 (每4小时执行一次)"
    log_info "==> 使用 'crontab -l' 查看当前定时任务"

else
    log_error "==> 未找到可用的定时任务系统 (systemd 或 cron)"
    log_warn "==> 请手动执行: $CLEANUP_SCRIPT"
    exit 1
fi

# 创建手动清理命令的软链接
ln -sf "$CLEANUP_SCRIPT" "/usr/local/bin/cleanup" 2>/dev/null || true

log_info "==> 安装完成!"
log_info "==> 清理脚本位置: $CLEANUP_SCRIPT"
log_info "==> 日志文件位置: $LOG_FILE"
log_info "==> 手动执行清理: cleanup 或 $CLEANUP_SCRIPT"

# 立即执行一次清理
log_info "==> 立即执行一次清理测试..."
"$CLEANUP_SCRIPT"

log_info "==> 全部配置完成!"
