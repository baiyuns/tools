#!/bin/bash
echo "[1] 关闭并删除 swapfile..."
swapoff /swapfile && rm -f /swapfile

echo "[2] 删除旧内核..."
apt-get remove --purge -y linux-image-5.4.0-196-generic || true
update-grub

echo "[3] 清理 Snap..."
snap list --all | awk '/disabled/{print $1, $3}' | while read name rev; do
  snap remove "$name" --revision="$rev"
done
rm -rf /var/lib/snapd/cache/*
rm -rf /var/lib/snapd/snaps/*.snap
rm -rf /snap/*

echo "[4] 清理 APT 缓存..."
apt-get clean
rm -f /var/cache/apt/*.bin

echo "[5] 删除文档和源码（可选）..."
rm -rf /usr/share/doc/*
rm -rf /usr/src/*

echo "[完成] 请执行 'df -h' 查看空间释放情况。"
