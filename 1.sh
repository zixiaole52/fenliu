bash -c "$(cat <<'EOF'
#!/bin/bash
set -euo pipefail

# 彩色输出函数
info() { echo -e "\033[34mℹ️ $*\033[0m"; }
success() { echo -e "\033[32m✅ $*\033[0m"; }
warning() { echo -e "\033[33m⚠️ $*\033[0m"; }
error() { echo -e "\033[31m❌ $*\033[0m" >&2; exit 1; }

info "一键部署 misaka_danmu_server (增强版)"

# 调整依赖检测逻辑：允许手动确认
check_dependency() {
  local cmd=$1
  if ! command -v "$cmd" &> /dev/null; then
    warning "未自动检测到 $cmd，但可能已安装"
    read -p "确认已安装 $cmd 并希望继续？(y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      error "请安装 $cmd 后重试"
    fi
  fi
}

# 检测 Docker
check_dependency docker

# 检测 Docker Compose（兼容两种命令格式）
if ! (docker compose version &> /dev/null || docker-compose version &> /dev/null); then
  warning "未自动检测到 docker compose 或 docker-compose"
  read -p "确认已安装 Docker Compose 并希望继续？(y/N): " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    error "请安装 Docker Compose 后重试"
  fi
fi

# 用户配置（支持自定义）
info "请确认部署配置（直接回车使用默认值）"
read -p "服务端口 (默认: 7768): " MISAKA_PORT
MISAKA_PORT=${MISAKA_PORT:-7768}
read -p "安装目录 (默认: ~/misaka_danmu_server): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-"$HOME/misaka_danmu_server"}

# 最终确认步骤
info "即将开始部署，配置信息如下："
echo "  服务端口: $MISAKA_PORT"
echo "  安装目录: $INSTALL_DIR"
read -p "请输入 'yes' 确认部署（其他内容将取消）: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  error "用户取消部署"
fi

# 检查目录是否存在
if [ -d "$INSTALL_DIR" ]; then
  read -p "目录 $INSTALL_DIR 已存在，是否覆盖？(y/N): " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    error "用户取消部署"
  fi
  rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

# 生成随机密码
DB_PASSWORD=$(openssl rand -base64 12)

# 写入 docker-compose
cat > docker-compose.yaml <<EOC
version: "3"
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
    restart: always
    networks:
      - misaka-network
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
    networks:
      - misaka-network
networks:
  misaka-network:
EOC

# 启动服务
info "启动容器中..."
if docker compose version &> /dev/null; then
  docker compose up -d
else
  docker-compose up -d
fi

# 智能等待服务就绪
info "等待服务初始化（最多60秒）..."
for i in {1..30}; do
  if docker logs misaka-danmu-server 2>/dev/null | grep "Admin account created" &> /dev/null; then
    break
  fi
  if [ $i -eq 30 ]; then
    error "服务启动超时，请检查日志排查问题"
  fi
  sleep 2
done

# 获取关键信息
ADMIN_PASSWORD=$(docker logs misaka-danmu-server 2>/dev/null | grep "Admin account created" | awk -F'password=' '{print $2}' | head -n1)
SERVER_IP=$(curl -s icanhazip.com || curl -s ifconfig.me || echo "127.0.0.1")

# 保存信息到文件
cat > "$INSTALL_DIR/登录信息.txt" <<EOL
访问地址: http://${SERVER_IP}:${MISAKA_PORT}
MySQL密码: ${DB_PASSWORD}
管理员账号: admin
管理员初始密码: ${ADMIN_PASSWORD}
EOL

# 输出结果
success "部署完成！"
echo "----------------------------------------"
echo "访问地址: http://${SERVER_IP}:${MISAKA_PORT}"
echo "管理员账号: admin"
echo "管理员密码: ${ADMIN_PASSWORD}"
echo "----------------------------------------"
warning "关键信息已保存到 $INSTALL_DIR/登录信息.txt"
warning "建议登录后立即修改管理员密码"
info "常用命令:"
info "  停止服务: cd $INSTALL_DIR && docker compose down"
info "  启动服务: cd $INSTALL_DIR && docker compose up -d"
info "  查看日志: cd $INSTALL_DIR && docker compose logs -f misaka"
EOF
)'