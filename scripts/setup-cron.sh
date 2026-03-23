#!/bin/bash
# 竞猜世界 - 定时任务配置脚本
# 一键设置所有自动化任务

set -e

WORKSPACE="$HOME/.openclaw/workspace"
SCRIPTS_DIR="$WORKSPACE/scripts"
CRON_FILE="/tmp/jingcai-crontab"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# ============ 生成Crontab ============
generate_crontab() {
    cat > "$CRON_FILE" << EOF
# 竞猜世界 - 自动化任务配置
# 由CEO特别准生成

# 系统健康检查 - 每5分钟
*/5 * * * * $SCRIPTS_DIR/clawfix-daemon.sh once >> /tmp/clawfix-cron.log 2>&1

# 数据备份 - 每小时
0 * * * * $SCRIPTS_DIR/auto-backup.sh hourly >> /tmp/backup-cron.log 2>&1

# 每日备份+Git同步 - 每天2点
0 2 * * * $SCRIPTS_DIR/auto-backup.sh daily >> /tmp/backup-cron.log 2>&1

# 晨报生成和发送 - 每天8点
0 8 * * * cd $WORKSPACE && $SCRIPTS_DIR/team-workflow.sh start >> /tmp/workflow-cron.log 2>&1

# 每日复盘 - 每天22点
0 22 * * * $SCRIPTS_DIR/team-workflow.sh review >> /tmp/workflow-cron.log 2>&1

# 团队进化 - 每天2点30分（在备份后）
30 2 * * * $SCRIPTS_DIR/team-workflow.sh evolve >> /tmp/workflow-cron.log 2>&1

# 版本检查 - 每周一9点
0 9 * * 1 $SCRIPTS_DIR/version-manager.sh check >> /tmp/version-cron.log 2>&1

# 成本报告 - 每天23点
0 23 * * * $SCRIPTS_DIR/cost-control.sh stats >> /tmp/cost-cron.log 2>&1
EOF

    log "Crontab配置已生成: $CRON_FILE"
}

# ============ 安装Crontab ============
install_crontab() {
    # 备份现有crontab
    crontab -l > "$WORKSPACE/backup-crontab-$(date +%Y%m%d).txt" 2>/dev/null || true
    
    # 合并现有crontab和新配置
    {
        crontab -l 2>/dev/null | grep -v "竞猜世界" || true
        echo ""
        cat "$CRON_FILE"
    } | crontab -
    
    log "Crontab已安装"
    crontab -l | tail -20
}

# ============ 移除竞猜世界任务 ============
remove_crontab() {
    crontab -l 2>/dev/null | grep -v "竞猜世界" | crontab -
    log "竞猜世界任务已从crontab移除"
}

# ============ 显示状态 ============
show_status() {
    echo "=== 竞猜世界定时任务状态 ==="
    echo ""
    
    if crontab -l 2>/dev/null | grep -q "竞猜世界"; then
        echo "✅ 定时任务已启用"
        echo ""
        echo "当前任务:"
        crontab -l | grep -A1 "竞猜世界"
    else
        echo "❌ 定时任务未启用"
    fi
    
    echo ""
    echo "脚本状态:"
    for script in clawfix-daemon.sh auto-backup.sh team-workflow.sh version-manager.sh cost-control.sh model-router.sh discord-notify.sh; do
        if [[ -f "$SCRIPTS_DIR/$script" ]]; then
            echo "  ✅ $script"
        else
            echo "  ❌ $script (缺失)"
        fi
    done
}

# ============ 测试运行 ============
test_run() {
    log "测试运行关键脚本..."
    
    log "1. 测试系统检查..."
    $SCRIPTS_DIR/clawfix-daemon.sh once 2>&1 | head -5 || log "⚠️ 系统检查失败"
    
    log "2. 测试备份..."
    $SCRIPTS_DIR/auto-backup.sh manual 2>&1 | tail -3 || log "⚠️ 备份失败"
    
    log "3. 测试成本统计..."
    $SCRIPTS_DIR/cost-control.sh stats 2>&1 | head -5 || log "⚠️ 成本统计失败"
    
    log "测试完成"
}

# ============ 主入口 ============
main() {
    case "${1:-}" in
        install)
            generate_crontab
            install_crontab
            log "定时任务安装完成"
            ;;
        remove)
            remove_crontab
            ;;
        status)
            show_status
            ;;
        test)
            test_run
            ;;
        show)
            generate_crontab
            cat "$CRON_FILE"
            ;;
        *)
            echo "竞猜世界 - 定时任务配置"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  install    - 安装定时任务"
            echo "  remove     - 移除定时任务"
            echo "  status     - 查看状态"
            echo "  test       - 测试运行"
            echo "  show       - 显示配置（不安装）"
            echo ""
            echo "将配置的定时任务:"
            echo "  • 每5分钟: 系统健康检查"
            echo "  • 每小时:  数据备份"
            echo "  • 每天2点: 完整备份+Git同步"
            echo "  • 每天8点: 生成并发送晨报"
            echo "  • 每天22点: 每日复盘"
            echo "  • 每天2:30: 团队进化"
            echo "  • 每周一9点: 版本检查"
            echo "  • 每天23点: 成本报告"
            ;;
    esac
}

main "$@"
