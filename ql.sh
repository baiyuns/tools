#!/bin/bash

set -e

# 自动清理脚本路径
CLEANUP_SCRIPT="/root/auto_cleanup.sh"

echo "==> 创建自动清理脚本 $CLEANUP_SCRIPT"

cat > "$CLEANUP_SCRIPT" << 'EOF'
#!/bin/bash
echo "==== $(date) 自动清理磁盘开始 ===="

apt-get clean
journalctl --vacuum-size=100M
rm -rf /tmp/*
find /var/log -type f \( -name "*.log" -o -name "*.gz" -o -name "*.1" \) -mtime +30 -exec rm -f {} \;
find $HOME -type f \( -name "*.tmp" -o -name "*.temp" -o -name "*.cache" \) -mtime +30 -exec rm -f {} \;
find / -type f -name "core" -exec rm -f {} \; 2>/dev/null

echo "==== $(date) 自动清理磁盘完成 ===="
df -h /
EOF

chmod +x "$CLEANUP_SCRIPT"

# 检测 systemd 是否存在
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
  echo "==> 检测到 systemd，使用 systemd 定时器"

  # 创建 systemd 服务文件
  cat > /etc/systemd/system/auto_cleanup.service << EOF
[Unit]
Description=自动清理磁盘空间脚本

[Service]
Type=oneshot
ExecStart=$CLEANUP_SCRIPT
EOF

  # 创建 systemd 定时器文件
  cat > /etc/systemd/system/auto_cleanup.timer << EOF
[Unit]
Description=每6小时执行自动清理磁盘空间

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable auto_cleanup.timer
  systemctl start auto_cleanup.timer
  echo "==> systemd 定时器已启用"

else
  echo "==> 未检测到 systemd，使用 cron 定时任务"

  # 写入 cron 任务，6小时执行一次
  (crontab -l 2>/dev/null; echo "0 */6 * * * $CLEANUP_SCRIPT") | crontab -

  echo "==> cron 定时任务已添加"
fi

echo "==> 完成"
