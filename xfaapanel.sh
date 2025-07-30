#!/bin/bash

echo "==> 更新系统依赖..."
apt update
apt install -y python3 python3-pip python3-venv build-essential

echo "==> 清理旧 pyenv..."
rm -rf /www/server/panel/pyenv

echo "==> 重建 pyenv 环境..."
cd /www/server/panel || exit 1
python3 -m venv pyenv
source pyenv/bin/activate

echo "==> 安装核心依赖..."
pip install --upgrade pip
pip install requests psutil idna certifi flask chardet pyOpenSSL

echo "==> 退出虚拟环境..."
deactivate

echo "==> 测试面板是否可用..."
python3 /www/server/panel/BT-Panel.py &
