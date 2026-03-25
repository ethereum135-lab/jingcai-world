#!/bin/bash
# 竞猜世界 - OpenClaw Gateway系统服务安装脚本
# 实现锁屏/注销后依然运行

set -e

SERVICE_NAME="openclaw-gateway"
SERVICE_FILE="$HOME/.config/systemd/user/$SERVICE_NAME.service"

# 检测OpenClaw安装路径
detect_openclaw() {
    if command -v openclaw &> /dev/null; then
        echo "$(which openclaw)"
    elif [[ -f "$HOME/openclaw/target/release/openclaw" ]]; then
        echo "$HOME/openclaw/target/release/openclaw"
    elif [[ -f "$HOME/.cargo/bin/openclaw" ]]; then
        echo "$HOME/.cargo/bin/openclaw"
    else
        echo ""
    fi
}

# 创建系统服务
create_service() {
    local openclaw_path=$(detect_openclaw)
    
    if [[ -z "$openclaw_path" ]]; then
        echo "错误: 未找到OpenClaw安装路径"
        exit 1
    fi
    
    echo "OpenClaw路径: $openclaw_path"
    
    # 创建用户systemd目录
    mkdir -p "$HOME/.config/systemd/user"
    
    # 创建服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=OpenClaw Gateway - 竞猜世界
After=network.target

[Service]
Type=simple
ExecStart=$openclaw_path gateway start
ExecStop=$openclaw_path gateway stop
Restart=always
RestartSec=5
Environment="HOME=$HOME"
Environment="PATH=$PATH"
WorkingDirectory=$HOME

[Install]
WantedBy=default.target
EOF

    echo "服务文件已创建: $SERVICE_FILE"
}

# 启用并启动服务
enable_service() {
    # 重新加载systemd
    systemctl --user daemon-reload
    
    # 启用服务（开机自启）
    systemctl --user enable "$SERVICE_NAME"
    
    # 停止旧服务（如果存在）
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    
    # 启动服务
    systemctl --user start "$SERVICE_NAME"
    
    echo "服务已启动"
}

# 检查状态
check_status() {
    echo "=== 服务状态 ==="
    systemctl --user status "$SERVICE_NAME" --no-pager || true
    
    echo ""
    echo "=== 进程检查 ==="
    pgrep -f "openclaw-gateway" && echo "Gateway进程运行中" || echo "Gateway进程未运行"
}

# 查看日志
view_logs() {
    journalctl --user -u "$SERVICE_NAME" -n 50 --no-pager
}

# 停止服务
stop_service() {
    systemctl --user stop "$SERVICE_NAME"
    echo "服务已停止"
}

# 重启服务
restart_service() {
    systemctl --user restart "$SERVICE_NAME"
    echo "服务已重启"
}

# 卸载服务
uninstall_service() {
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload
    echo "服务已卸载"
}

# 主入口
main() {
    case "${1:-}" in
        install)
            echo "安装OpenClaw Gateway系统服务..."
            create_service
            enable_service
            check_status
            echo ""
            echo "✅ 安装完成！"
            echo "现在可以锁屏，服务会继续运行"
            ;;
        status)
            check_status
            ;;
        logs)
            view_logs
            ;;
        restart)
            restart_service
            ;;
        stop)
            stop_service
            ;;
        uninstall)
            uninstall_service
            ;;
        *)
            echo "竞猜世界 - OpenClaw Gateway系统服务管理"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  install     - 安装并启动服务（锁屏继续运行）"
            echo "  status      - 查看服务状态"
            echo "  logs        - 查看服务日志"
            echo "  restart     - 重启服务"
            echo "  stop        - 停止服务"
            echo "  uninstall   - 卸载服务"
            echo ""
            echo "安装后:"
            echo "  1. 可以锁屏/注销，服务继续运行"
            echo "  2. 开机自动启动"
            echo "  3. 崩溃自动重启"
            ;;
    esac
}

main "$@"
