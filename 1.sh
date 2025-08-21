#!/bin/bash
set -e

echo "🚀 一键部署 misaka_danmu_server (零依赖版)"
read -p "⚠️ 确认要开始部署吗？输入 yes 继续: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "❌ 已取消部署"
  exit 1
fi

# 自动生成 MySQL 密码
DB_PASSWORD=$(openssl rand -base64 12)
MISAKA_PORT=7768

INSTALL_DIR="$HOME/misaka_danmu_server"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 写入 docker-compose.yaml
cat > docker-compose.yaml <<EOF
version: "3.9"

services:
  mysql:
    image: mysql:8.1.0-oracle
    container_name: danmu-mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: danmuapi
      MYSQL_USER: danmuapi
      MYSQL_PASSWORD: ${DB_PASSWORD}
      TZ: "Asia/Shanghai"
    volumes:
      - ./mysql:/var/lib/mysql
    ports:
      - "3306:3306"
    restart: always

  misaka:
    image: l429609201/misaka_danmu_server:latest
    container_name: misaka-danmu-server
    depends_on:
      - mysql
    environment:
      - PUID=1000
      - PGID=1000
      - UMASK=0022
      - DANMUAPI_DATABASE__HOST=mysql
      - DANMUAPI_DATABASE__PORT=3306
      - DANMUAPI_DATABASE__NAME=danmuapi
      - DANMUAPI_DATABASE__USER=danmuapi
      - DANMUAPI_DATABASE__PASSWORD=${DB_PASSWORD}
    volumes:
      - ./config:/app/config
    ports:
      - "${MISAKA_PORT}:${MISAKA_PORT}"
    restart: always
EOF

echo "📦 启动容器..."
docker compose up -d || docker-compose up -d

echo "⏳ 等待初始化..."
sleep 10

# 自动抓取 admin 初始密码
ADMIN_PASSWORD=$(docker logs misaka-danmu-server 2>/dev/null \
  | grep "Admin account created" \
  | awk -F'password=' '{print $2}' \
  | head -n1)

echo "✅ 部署完成！"
echo "👉 浏览器访问: http://你的服务器IP:${MISAKA_PORT}"
echo "👉 MySQL 密码: ${DB_PASSWORD}"
echo "👉 管理员用户名: admin"
echo "👉 管理员初始密码: ${ADMIN_PASSWORD}"
echo "💡 建议首次登录后立即修改密码"