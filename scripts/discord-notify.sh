#!/bin/bash
# 竞猜世界 - 晨报发送脚本
# 每天早上8点发送晨报到Discord频道

set -e

WORKSPACE="$HOME/.openclaw/workspace"
LOGS_DIR="$WORKSPACE/logs"
CONFIG_FILE="$WORKSPACE/.discord-config.json"

# Discord配置
DISCORD_SERVER_ID="${JINGCAI_DISCORD_SERVER:-}"  # 从环境变量读取
DISCORD_CHANNEL_ID="${JINGCAI_DISCORD_CHANNEL:-}"  # 晨报频道ID
DISCORD_BOT_TOKEN="${JINGCAI_DISCORD_TOKEN:-}"  # Bot Token

# ============ 初始化配置 ============
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << EOF
{
  "server_id": "$DISCORD_SERVER_ID",
  "channel_id": "$DISCORD_CHANNEL_ID",
  "bot_token": "$DISCORD_BOT_TOKEN",
  "enabled": false
}
EOF
    fi
}

# ============ 发送晨报 ============
send_morning_report() {
    local report_file="$LOGS_DIR/morning-report-$(date +%Y%m%d).md"
    
    if [[ ! -f "$report_file" ]]; then
        echo "错误: 晨报文件不存在: $report_file"
        return 1
    fi
    
    local enabled=$(jq -r '.enabled' "$CONFIG_FILE")
    if [[ "$enabled" != "true" ]]; then
        echo "Discord发送未启用，仅显示晨报内容:"
        cat "$report_file"
        return 0
    fi
    
    local channel_id=$(jq -r '.channel_id' "$CONFIG_FILE")
    local bot_token=$(jq -r '.bot_token' "$CONFIG_FILE")
    
    if [[ -z "$channel_id" || -z "$bot_token" ]]; then
        echo "错误: Discord配置不完整"
        return 1
    fi
    
    # 读取晨报内容
    local content=$(cat "$report_file")
    
    # 如果内容太长，分段发送
    local max_length=1900
    if [[ ${#content} -gt $max_length ]]; then
        # 发送摘要
        local summary="📊 **竞猜世界 - 每日晨报**\n\n"
        summary+="日期: $(date '+%Y年%m月%d日')\n"
        summary+="状态: 详细报告已生成\n"
        summary+="查看完整报告请访问工作区\n\n"
        summary+="@老师 请查收"
        
        curl -s -X POST \
            -H "Authorization: Bot $bot_token" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"$summary\"}" \
            "https://discord.com/api/v10/channels/$channel_id/messages" > /dev/null
        
        echo "晨报摘要已发送到Discord"
    else
        # 发送完整内容
        local json_content=$(echo "$content" | jq -Rs '.')
        
        curl -s -X POST \
            -H "Authorization: Bot $bot_token" \
            -H "Content-Type: application/json" \
            -d "{\"content\":$json_content}" \
            "https://discord.com/api/v10/channels/$channel_id/messages" > /dev/null
        
        echo "晨报已发送到Discord"
    fi
}

# ============ 发送消息 ============
send_message() {
    local message="$1"
    local enabled=$(jq -r '.enabled' "$CONFIG_FILE")
    
    if [[ "$enabled" != "true" ]]; then
        echo "[Discord未启用] $message"
        return 0
    fi
    
    local channel_id=$(jq -r '.channel_id' "$CONFIG_FILE")
    local bot_token=$(jq -r '.bot_token' "$CONFIG_FILE")
    
    curl -s -X POST \
        -H "Authorization: Bot $bot_token" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$message\"}" \
        "https://discord.com/api/v10/channels/$channel_id/messages" > /dev/null
}

# ============ 配置设置 ============
set_config() {
    local key="$1"
    local value="$2"
    
    local tmp=$(mktemp)
    jq ".$key = \"$value\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "已设置: $key = $value"
}

enable() {
    local tmp=$(mktemp)
    jq '.enabled = true' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "Discord发送已启用"
}

disable() {
    local tmp=$(mktemp)
    jq '.enabled = false' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "Discord发送已禁用"
}

# ============ 主入口 ============
main() {
    init_config
    
    case "${1:-}" in
        report)
            send_morning_report
            ;;
        send)
            send_message "$2"
            ;;
        set-server)
            set_config "server_id" "$2"
            ;;
        set-channel)
            set_config "channel_id" "$2"
            ;;
        set-token)
            set_config "bot_token" "$2"
            ;;
        enable)
            enable
            ;;
        disable)
            disable
            ;;
        status)
            cat "$CONFIG_FILE" | jq .
            ;;
        *)
            echo "竞猜世界 - Discord通知脚本"
            echo ""
            echo "用法: $0 [命令] [参数]"
            echo ""
            echo "命令:"
            echo "  report                    - 发送晨报"
            echo "  send <message>            - 发送自定义消息"
            echo "  set-server <id>           - 设置服务器ID"
            echo "  set-channel <id>          - 设置频道ID"
            echo "  set-token <token>         - 设置Bot Token"
            echo "  enable                    - 启用发送"
            echo "  disable                   - 禁用发送"
            echo "  status                    - 查看配置"
            echo ""
            echo "环境变量:"
            echo "  JINGCAI_DISCORD_SERVER    - 服务器ID"
            echo "  JINGCAI_DISCORD_CHANNEL   - 频道ID"
            echo "  JINGCAI_DISCORD_TOKEN     - Bot Token"
            ;;
    esac
}

main "$@"
