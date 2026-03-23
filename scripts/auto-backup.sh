#!/bin/bash
# 竞猜世界 - 自动备份脚本
# 本地备份，零Token成本
# 建议每小时运行一次

set -e

# ============ 配置 ============
WORKSPACE="$HOME/.openclaw/workspace"
BACKUP_DIR="$HOME/.openclaw/backups"
REMOTE_GIT="${JINGCAI_GIT_REPO:-}"  # 可选：远程Git仓库
RETENTION_DAYS=30  # 保留30天

# 备份内容
BACKUP_ITEMS=(
    "$WORKSPACE/SOUL.md"
    "$WORKSPACE/IDENTITY.md"
    "$WORKSPACE/USER.md"
    "$WORKSPACE/AGENTS.md"
    "$WORKSPACE/MEMORY.md"
    "$WORKSPACE/memory/"
    "$WORKSPACE/scripts/"
    "$WORKSPACE/logs/"
    "$HOME/.openclaw/skills/"
    "$HOME/.openclaw/clawfix.conf"
)

# ============ 初始化 ============
init() {
    mkdir -p "$BACKUP_DIR"/daily "$BACKUP_DIR"/hourly "$BACKUP_DIR"/archive
    
    # Git初始化
    if [[ -n "$REMOTE_GIT" && ! -d "$BACKUP_DIR/.git" ]]; then
        cd "$BACKUP_DIR"
        git init
        git remote add origin "$REMOTE_GIT" 2>/dev/null || true
    fi
}

# ============ 日志 ============
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ============ 创建备份 ============
create_backup() {
    local backup_type="$1"  # hourly/daily/manual
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="jingcai-${backup_type}-${timestamp}"
    local backup_path="$BACKUP_DIR/$backup_type/$backup_name.tar.gz"
    
    log "创建 $backup_type 备份: $backup_name"
    
    # 创建临时清单文件
    local file_list=$(mktemp)
    for item in "${BACKUP_ITEMS[@]}"; do
        if [[ -e "$item" ]]; then
            echo "$item" >> "$file_list"
        fi
    done
    
    # 创建tar包
    tar -czf "$backup_path" -T "$file_list" 2>/dev/null || {
        log "警告: 部分文件备份失败"
    }
    
    rm -f "$file_list"
    
    local size=$(du -h "$backup_path" | cut -f1)
    log "备份完成: $backup_path ($size)"
    
    echo "$backup_path"
}

# ============ 清理旧备份 ============
cleanup_old_backups() {
    log "清理旧备份..."
    
    # 清理小时备份（保留最近48个）
    ls -t "$BACKUP_DIR"/hourly/*.tar.gz 2>/dev/null | tail -n +49 | xargs rm -f 2>/dev/null || true
    
    # 清理日备份（保留最近30个）
    ls -t "$BACKUP_DIR"/daily/*.tar.gz 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
    
    # 清理归档（按时间）
    find "$BACKUP_DIR"/archive -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    
    log "清理完成"
}

# ============ Git同步 ============
sync_to_git() {
    if [[ -z "$REMOTE_GIT" ]]; then
        return
    fi
    
    log "同步到Git仓库..."
    
    cd "$BACKUP_DIR"
    
    # 复制关键文件到Git目录
    cp -r "$WORKSPACE/memory" ./ 2>/dev/null || true
    cp "$WORKSPACE"/*.md ./ 2>/dev/null || true
    
    # 提交
    git add -A
    git commit -m "backup: $(date '+%Y-%m-%d %H:%M:%S')" --quiet || true
    
    # 推送
    git push origin main --quiet 2>/dev/null || git push origin master --quiet 2>/dev/null || {
        log "Git推送失败，可能是网络问题"
    }
    
    log "Git同步完成"
}

# ============ 恢复备份 ============
restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log "错误: 备份文件不存在: $backup_file"
        exit 1
    fi
    
    log "恢复备份: $backup_file"
    log "警告: 这将覆盖当前工作区！"
    
    # 先创建当前状态的紧急备份
    create_backup "pre-restore-$(date +%Y%m%d-%H%M%S)"
    
    # 解压恢复
    tar -xzf "$backup_file" -C /
    
    log "恢复完成"
}

# ============ 列出备份 ============
list_backups() {
    echo "=== 竞猜世界备份列表 ==="
    echo ""
    
    echo "小时备份:"
    ls -lh "$BACKUP_DIR"/hourly/*.tar.gz 2>/dev/null | tail -10 || echo "  无"
    
    echo ""
    echo "日备份:"
    ls -lh "$BACKUP_DIR"/daily/*.tar.gz 2>/dev/null | tail -10 || echo "  无"
    
    echo ""
    echo "归档:"
    ls -lh "$BACKUP_DIR"/archive/*.tar.gz 2>/dev/null | tail -5 || echo "  无"
}

# ============ 主入口 ============
main() {
    init
    
    case "${1:-}" in
        hourly)
            create_backup "hourly"
            cleanup_old_backups
            ;;
        daily)
            local backup=$(create_backup "daily")
            cp "$backup" "$BACKUP_DIR"/archive/
            sync_to_git
            cleanup_old_backups
            ;;
        manual)
            create_backup "manual"
            ;;
        restore)
            restore_backup "$2"
            ;;
        list)
            list_backups
            ;;
        sync)
            sync_to_git
            ;;
        *)
            echo "竞猜世界 - 自动备份系统"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  hourly   - 创建小时备份"
            echo "  daily    - 创建日备份并同步Git"
            echo "  manual   - 手动创建备份"
            echo "  restore <file> - 恢复备份"
            echo "  list     - 列出所有备份"
            echo "  sync     - 同步到Git"
            echo ""
            echo "定时任务建议:"
            echo "  0 * * * * $0 hourly   # 每小时"
            echo "  0 2 * * * $0 daily    # 每天2点"
            ;;
    esac
}

main "$@"
