#!/bin/bash
# 竞猜世界 - OpenClaw版本升级脚本
# 每周检查npm和GitHub最新版本，自动升级

set -e

WORKSPACE="$HOME/.openclaw/workspace"
LOG_FILE="$WORKSPACE/logs/version-check.log"
CONFIG_FILE="$WORKSPACE/.version-config.json"

mkdir -p "$(dirname "$LOG_FILE")"

# ============ 初始化配置 ============
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "npm_package": "@openclaw/cli",
  "github_repo": "openclaw/openclaw",
  "auto_upgrade": false,
  "check_interval_days": 7,
  "last_check": "",
  "current_version": "",
  "latest_version": "",
  "notification_channel": "discord"
}
EOF
    fi
}

# ============ 日志 ============
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ============ 获取当前版本 ============
get_current_version() {
    if command -v openclaw &> /dev/null; then
        openclaw version 2>/dev/null | head -1 || echo "unknown"
    else
        echo "not_installed"
    fi
}

# ============ 获取npm最新版本 ============
get_npm_version() {
    local package=$(jq -r '.npm_package' "$CONFIG_FILE")
    
    # 使用npm view获取最新版本
    npm view "$package" version 2>/dev/null || echo "unknown"
}

# ============ 获取GitHub最新版本 ============
get_github_version() {
    local repo=$(jq -r '.github_repo' "$CONFIG_FILE")
    
    # 使用GitHub API获取最新release
    curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | \
        jq -r '.tag_name' 2>/dev/null || echo "unknown"
}

# ============ 比较版本 ============
version_compare() {
    local v1="$1"
    local v2="$2"
    
    # 移除v前缀
    v1=${v1#v}
    v2=${v2#v}
    
    if [[ "$v1" == "$v2" ]]; then
        echo "equal"
    else
        # 简单比较（假设版本号格式一致）
        if [[ "$v1" < "$v2" ]]; then
            echo "older"
        else
            echo "newer"
        fi
    fi
}

# ============ 执行升级 ============
do_upgrade() {
    log "开始升级OpenClaw..."
    
    # 备份当前配置
    local backup_dir="$HOME/.openclaw/backup/pre-upgrade-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$HOME/.openclaw/config" "$backup_dir/" 2>/dev/null || true
    
    log "配置已备份到: $backup_dir"
    
    # 执行升级
    if npm install -g @openclaw/cli@latest 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ 升级成功"
        
        # 重启gateway
        if systemctl --user restart openclaw-gateway.service 2>/dev/null; then
            log "✓ Gateway已重启"
        else
            log "⚠ Gateway重启失败，请手动重启"
        fi
        
        return 0
    else
        log "✗ 升级失败"
        return 1
    fi
}

# ============ 发送通知 ============
send_notification() {
    local message="$1"
    local channel=$(jq -r '.notification_channel' "$CONFIG_FILE")
    
    case "$channel" in
        discord)
            # 调用Discord通知脚本
            if [[ -f "$WORKSPACE/scripts/discord-notify.sh" ]]; then
                "$WORKSPACE/scripts/discord-notify.sh" send "$message" 2>/dev/null || true
            fi
            ;;
        *)
            log "通知: $message"
            ;;
    esac
}

# ============ 检查版本 ============
check_version() {
    init_config
    
    log "=== 开始版本检查 ==="
    
    local current=$(get_current_version)
    local npm_latest=$(get_npm_version)
    local github_latest=$(get_github_version)
    
    log "当前版本: $current"
    log "NPM最新: $npm_latest"
    log "GitHub最新: $github_latest"
    
    # 更新配置
    local tmp=$(mktemp)
    jq ".current_version = \"$current\" | .latest_version = \"$npm_latest\" | .last_check = \"$(date -Iseconds)\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    
    # 比较版本
    local compare=$(version_compare "$current" "$npm_latest")
    
    if [[ "$compare" == "older" ]]; then
        log "发现新版本: $current → $npm_latest"
        
        local message="📦 OpenClaw版本更新\n当前: $current\n最新: $npm_latest\n\n"
        
        local auto_upgrade=$(jq -r '.auto_upgrade' "$CONFIG_FILE")
        if [[ "$auto_upgrade" == "true" ]]; then
            log "自动升级已启用，开始升级..."
            if do_upgrade; then
                message+="✅ 自动升级成功"
            else
                message+="❌ 自动升级失败，请手动升级"
            fi
        else
            message+="请运行: npm install -g @openclaw/cli@latest"
        fi
        
        send_notification "$message"
        
    elif [[ "$compare" == "equal" ]]; then
        log "已是最新版本"
    else
        log "当前版本比最新版还新（可能是开发版）"
    fi
    
    log "=== 版本检查完成 ==="
}

# ============ 设置自动升级 ============
set_auto_upgrade() {
    local enabled="$1"
    local tmp=$(mktemp)
    jq ".auto_upgrade = $enabled" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    log "自动升级已设置为: $enabled"
}

# ============ 主入口 ============
main() {
    case "${1:-}" in
        check)
            check_version
            ;;
        upgrade)
            do_upgrade
            ;;
        auto-on)
            set_auto_upgrade "true"
            ;;
        auto-off)
            set_auto_upgrade "false"
            ;;
        status)
            init_config
            jq '.' "$CONFIG_FILE"
            echo ""
            echo "当前安装版本: $(get_current_version)"
            ;;
        *)
            echo "竞猜世界 - OpenClaw版本管理"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  check       - 检查最新版本"
            echo "  upgrade     - 立即升级"
            echo "  auto-on     - 启用自动升级"
            echo "  auto-off    - 禁用自动升级"
            echo "  status      - 查看状态"
            echo ""
            echo "定时任务建议:"
            echo "  0 9 * * 1 $0 check   # 每周一9点检查"
            ;;
    esac
}

main "$@"
