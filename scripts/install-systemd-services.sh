#!/bin/bash
# 竞猜世界 - 本地系统服务安装脚本
# 实现开机自动运行，锁屏后继续工作

set -e

WORKSPACE="$HOME/.openclaw/workspace"
SERVICE_DIR="$HOME/.config/systemd/user"
LOG_DIR="$WORKSPACE/logs"

mkdir -p "$SERVICE_DIR" "$LOG_DIR"

# ============ 颜色 ============
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# ============ 创建情报搜集服务 ============
create_radar_service() {
    log "创建雷达（情报官）服务..."
    
    cat > "$SERVICE_DIR/jingcai-radar.service" << EOF
[Unit]
Description=竞猜世界 - 雷达（情报官）- 每15分钟搜集Polymarket数据
After=network.target

[Service]
Type=oneshot
ExecStart=$WORKSPACE/agents/radar/collect-intelligence.sh polymarket
StandardOutput=append:$LOG_DIR/radar.log
StandardError=append:$LOG_DIR/radar-error.log
Environment="HOME=$HOME"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
WorkingDirectory=$WORKSPACE

[Install]
WantedBy=default.target
EOF

    # 创建定时器（每15分钟）
    cat > "$SERVICE_DIR/jingcai-radar.timer" << EOF
[Unit]
Description=竞猜世界 - 雷达定时器 - 每15分钟运行

[Timer]
OnBootSec=1min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    log "雷达服务已创建"
}

# ============ 创建分析服务 ============
create_suanpan_service() {
    log "创建算盘（分析师）服务..."
    
    cat > "$SERVICE_DIR/jingcai-suanpan.service" << EOF
[Unit]
Description=竞猜世界 - 算盘（分析师）- 每小时分析赔率
After=network.target jingcai-radar.service

[Service]
Type=oneshot
ExecStart=$WORKSPACE/agents/suanpan/analyze-odds.sh all
StandardOutput=append:$LOG_DIR/suanpan.log
StandardError=append:$LOG_DIR/suanpan-error.log
Environment="HOME=$HOME"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
WorkingDirectory=$WORKSPACE

[Install]
WantedBy=default.target
EOF

    # 创建定时器（每小时）
    cat > "$SERVICE_DIR/jingcai-suanpan.timer" << EOF
[Unit]
Description=竞猜世界 - 算盘定时器 - 每小时运行

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    log "算盘服务已创建"
}

# ============ 创建晨报服务 ============
create_morning_report_service() {
    log "创建晨报服务..."
    
    cat > "$SERVICE_DIR/jingcai-morning-report.service" << EOF
[Unit]
Description=竞猜世界 - 每日晨报 - 早上8点发送
After=network.target

[Service]
Type=oneshot
ExecStart=$WORKSPACE/scripts/team-workflow.sh start
StandardOutput=append:$LOG_DIR/morning-report.log
StandardError=append:$LOG_DIR/morning-report-error.log
Environment="HOME=$HOME"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
WorkingDirectory=$WORKSPACE

[Install]
WantedBy=default.target
EOF

    # 创建定时器（每天8点）
    cat > "$SERVICE_DIR/jingcai-morning-report.timer" << EOF
[Unit]
Description=竞猜世界 - 晨报定时器 - 每天8点

[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    log "晨报服务已创建"
}

# ============ 启用所有服务 ============
enable_services() {
    log "启用所有服务..."
    
    systemctl --user daemon-reload
    
    # 启用雷达
    systemctl --user enable jingcai-radar.timer
    systemctl --user start jingcai-radar.timer
    
    # 启用算盘
    systemctl --user enable jingcai-suanpan.timer
    systemctl --user start jingcai-suanpan.timer
    
    # 启用晨报
    systemctl --user enable jingcai-morning-report.timer
    systemctl --user start jingcai-morning-report.timer
    
    log "所有服务已启用"
}

# ============ 检查状态 ============
check_status() {
    echo ""
    echo "=== 服务状态 ==="
    echo ""
    
    echo "定时器状态:"
    systemctl --user list-timers --all | grep jingcai || echo "无定时器"
    
    echo ""
    echo "服务状态:"
    systemctl --user status jingcai-radar.timer --no-pager 2>/dev/null || echo "雷达定时器未运行"
    systemctl --user status jingcai-suanpan.timer --no-pager 2>/dev/null || echo "算盘定时器未运行"
    systemctl --user status jingcai-morning-report.timer --no-pager 2>/dev/null || echo "晨报定时器未运行"
}

# ============ 停止服务 ============
stop_services() {
    log "停止所有服务..."
    
    systemctl --user stop jingcai-radar.timer 2>/dev/null || true
    systemctl --user stop jingcai-suanpan.timer 2>/dev/null || true
    systemctl --user stop jingcai-morning-report.timer 2>/dev/null || true
    
    log "所有服务已停止"
}

# ============ 卸载服务 ============
uninstall_services() {
    log "卸载所有服务..."
    
    stop_services
    
    rm -f "$SERVICE_DIR"/jingcai-*.service
    rm -f "$SERVICE_DIR"/jingcai-*.timer
    
    systemctl --user daemon-reload
    
    log "所有服务已卸载"
}

# ============ 查看日志 ============
view_logs() {
    echo "=== 最近日志 ==="
    echo ""
    
    for log in radar suanpan morning-report; do
        if [[ -f "$LOG_DIR/$log.log" ]]; then
            echo "--- $log ---"
            tail -10 "$LOG_DIR/$log.log"
            echo ""
        fi
    done
}

# ============ 主入口 ============
main() {
    echo "========================================"
    echo "   竞猜世界 - 系统服务管理"
    echo "========================================"
    echo ""
    
    case "${1:-install}" in
        install)
            log "安装竞猜世界系统服务..."
            create_radar_service
            create_suanpan_service
            create_morning_report_service
            enable_services
            check_status
            echo ""
            log "✅ 安装完成！"
            echo ""
            echo "服务说明:"
            echo "  • 雷达: 每15分钟搜集Polymarket数据"
            echo "  • 算盘: 每小时分析赔率"
            echo "  • 晨报: 每天8点发送报告"
            echo ""
            echo "特点:"
            echo "  ✓ 开机自动启动"
            echo "  ✓ 锁屏后继续运行"
            echo "  ✓ 崩溃自动重启"
            echo "  ✓ 日志自动记录"
            ;;
        status)
            check_status
            ;;
        logs)
            view_logs
            ;;
        stop)
            stop_services
            ;;
        start)
            enable_services
            ;;
        restart)
            stop_services
            sleep 2
            enable_services
            ;;
        uninstall)
            uninstall_services
            ;;
        *)
            echo "竞猜世界 - 系统服务管理"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  install     - 安装并启动服务（默认）"
            echo "  status      - 查看服务状态"
            echo "  logs        - 查看日志"
            echo "  stop        - 停止服务"
            echo "  start       - 启动服务"
            echo "  restart     - 重启服务"
            echo "  uninstall   - 卸载服务"
            ;;
    esac
}

main "$@"
