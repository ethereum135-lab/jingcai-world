#!/bin/bash
# 竞猜世界 - 省钱机制脚本
# 核心：强制记忆读取 + Token压缩 + 成本控制
# 所有AI Agent调用前必须先执行此脚本

set -e

WORKSPACE="$HOME/.openclaw/workspace"
MEMORY_DIR="$WORKSPACE/memory"
CONFIG_FILE="$WORKSPACE/.cost-control.json"
LOG_FILE="$WORKSPACE/logs/cost-control.log"

mkdir -p "$WORKSPACE/logs" "$MEMORY_DIR"

# ============ Token 价格配置 (每1K tokens) ============
declare -A MODEL_PRICES_INPUT
declare -A MODEL_PRICES_OUTPUT

# 输入价格 (USD per 1K tokens)
MODEL_PRICES_INPUT=(
    ["moonshot/kimi-k2.5"]=0.015
    ["deepseek/deepseek-chat"]=0.00014
    ["deepseek/deepseek-reasoner"]=0.00055
    ["qwen/qwen-max"]=0.003
    ["openai/gpt-4o"]=0.005
    ["openai/gpt-4o-mini"]=0.00015
)

# 输出价格
MODEL_PRICES_OUTPUT=(
    ["moonshot/kimi-k2.5"]=0.06
    ["deepseek/deepseek-chat"]=0.00028
    ["deepseek/deepseek-reasoner"]=0.00219
    ["qwen/qwen-max"]=0.009
    ["openai/gpt-4o"]=0.015
    ["openai/gpt-4o-mini"]=0.0006
)

# ============ 初始化配置 ============
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "daily_budget_usd": 10.0,
  "daily_budget_cny": 70.0,
  "alert_threshold": 0.8,
  "emergency_threshold": 0.95,
  "preferred_models": {
    "chinese": "moonshot/kimi-k2.5",
    "math": "deepseek/deepseek-reasoner",
    "coding": "deepseek/deepseek-chat",
    "cheap": "deepseek/deepseek-chat"
  },
  "compression_enabled": true,
  "force_memory_read": true,
  "stats": {}
}
EOF
    fi
}

# ============ 日志 ============
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ============ 强制记忆读取 ============
force_memory_read() {
    log "=== 强制记忆读取 ==="
    
    local today=$(date +%Y-%m-%d)
    local yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
    local memory_loaded=false
    
    # 1. 读取长期记忆
    if [[ -f "$WORKSPACE/MEMORY.md" ]]; then
        log "✓ 长期记忆已加载 ($(wc -c < "$WORKSPACE/MEMORY.md") bytes)"
        memory_loaded=true
    else
        log "✗ 长期记忆缺失 - 创建空白文件"
        touch "$WORKSPACE/MEMORY.md"
    fi
    
    # 2. 读取昨日记忆
    if [[ -f "$MEMORY_DIR/$yesterday.md" ]]; then
        log "✓ 昨日记忆已加载: $yesterday ($(wc -c < "$MEMORY_DIR/$yesterday.md") bytes)"
        memory_loaded=true
    fi
    
    # 3. 读取今日记忆
    if [[ -f "$MEMORY_DIR/$today.md" ]]; then
        log "✓ 今日记忆已加载: $today ($(wc -c < "$MEMORY_DIR/$today.md") bytes)"
        memory_loaded=true
    fi
    
    # 4. 如果没有记忆，警告
    if [[ "$memory_loaded" == "false" ]]; then
        log "⚠ 警告：没有任何记忆文件，可能导致失忆"
    fi
    
    # 5. 记录读取时间
    local state_file="$WORKSPACE/.memory_state.json"
    echo "{\"last_read\":\"$(date -Iseconds)\",\"today\":\"$today\"}" > "$state_file"
    
    log "=== 记忆读取完成 ==="
}

# ============ Token 压缩 ============
compress_context() {
    local input_file="$1"
    local max_tokens="${2:-4000}"
    
    if [[ ! -f "$input_file" ]]; then
        echo ""
        return
    fi
    
    # 估算token数 (粗略: 1 token ≈ 4 chars for English, 1 token ≈ 1 char for Chinese)
    local content=$(cat "$input_file")
    local char_count=${#content}
    local estimated_tokens=$((char_count / 2))
    
    log "原始内容: $char_count 字符, 估算 $estimated_tokens tokens"
    
    if [[ $estimated_tokens -le $max_tokens ]]; then
        echo "$content"
        return
    fi
    
    # 压缩策略
    log "需要压缩: $estimated_tokens → $max_tokens tokens"
    
    # 1. 移除多余空行
    content=$(echo "$content" | sed '/^[[:space:]]*$/d')
    
    # 2. 移除注释行 (以#开头但不包含重要标记的行)
    content=$(echo "$content" | grep -v "^# [A-Z]" | grep -v "^##")
    
    # 3. 如果还超长，保留关键部分
    local new_char_count=${#content}
    if [[ $new_char_count -gt $((max_tokens * 2)) ]]; then
        # 保留前30%和后70%（通常开头是背景，结尾是任务）
        local head_chars=$((max_tokens * 2 * 3 / 10))
        local tail_chars=$((max_tokens * 2 * 7 / 10))
        local total_chars=$((head_chars + tail_chars))
        
        local head_content="${content:0:$head_chars}"
        local tail_content="${content: -$tail_chars}"
        
        content="$head_content\n\n...[中间内容省略]...\n\n$tail_content"
        log "应用头部+尾部压缩策略"
    fi
    
    log "压缩后: ${#content} 字符"
    echo -e "$content"
}

# ============ 成本控制 ============
check_budget() {
    local today=$(date +%Y-%m-%d)
    local daily_budget=$(jq -r '.daily_budget_usd' "$CONFIG_FILE")
    local alert_threshold=$(jq -r '.alert_threshold' "$CONFIG_FILE")
    local emergency_threshold=$(jq -r '.emergency_threshold' "$CONFIG_FILE")
    
    # 获取今日已用
    local used_today=$(jq -r ".stats.\"$today\" // 0" "$CONFIG_FILE")
    local usage_rate=$(echo "scale=2; $used_today / $daily_budget" | bc)
    
    log "今日预算: $${daily_budget}, 已用: $${used_today}, 使用率: ${usage_rate}%"
    
    if (( $(echo "$usage_rate > $emergency_threshold" | bc -l) )); then
        log "🚨 紧急：预算使用率超过 ${emergency_threshold*100}%！暂停非关键调用"
        return 1
    elif (( $(echo "$usage_rate > $alert_threshold" | bc -l) )); then
        log "⚠️ 警告：预算使用率超过 ${alert_threshold*100}%"
    fi
    
    return 0
}

record_cost() {
    local model="$1"
    local input_tokens="$2"
    local output_tokens="$3"
    local today=$(date +%Y-%m-%d)
    
    # 计算成本
    local input_price=${MODEL_PRICES_INPUT[$model]:-0.01}
    local output_price=${MODEL_PRICES_OUTPUT[$model]:-0.03}
    
    local input_cost=$(echo "scale=6; $input_tokens * $input_price / 1000" | bc)
    local output_cost=$(echo "scale=6; $output_tokens * $output_price / 1000" | bc)
    local total_cost=$(echo "scale=6; $input_cost + $output_cost" | bc)
    
    # 更新统计
    local tmp=$(mktemp)
    jq ".stats.\"$today\" = ((.stats.\"$today\" // 0) + $total_cost)" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    
    log "记录成本: $model | 输入:${input_tokens} | 输出:${output_tokens} | 费用:$${total_cost}"
}

# ============ 模型选择 ============
select_model() {
    local task_type="$1"  # chinese/math/coding/cheap
    
    init_config
    
    # 检查预算
    if ! check_budget; then
        log "预算紧张，切换到最便宜模型"
        task_type="cheap"
    fi
    
    local model=$(jq -r ".preferred_models.\"$task_type\" // .preferred_models.cheap" "$CONFIG_FILE")
    log "选择模型 [$task_type]: $model"
    echo "$model"
}

# ============ 主入口 ============
main() {
    case "${1:-}" in
        memory)
            force_memory_read
            ;;
        compress)
            compress_context "${2:-}" "${3:-4000}"
            ;;
        budget)
            check_budget
            ;;
        record)
            record_cost "$2" "$3" "$4"
            ;;
        select)
            select_model "${2:-cheap}"
            ;;
        stats)
            cat "$CONFIG_FILE" | jq '.stats'
            ;;
        init)
            init_config
            log "配置已初始化"
            ;;
        *)
            echo "竞猜世界 - 省钱机制"
            echo ""
            echo "用法: $0 [命令] [参数]"
            echo ""
            echo "命令:"
            echo "  memory          - 强制读取记忆"
            echo "  compress <file> [max_tokens] - 压缩内容"
            echo "  budget          - 检查预算"
            echo "  record <model> <input_tokens> <output_tokens> - 记录成本"
            echo "  select [type]   - 选择模型 (chinese/math/coding/cheap)"
            echo "  stats           - 查看统计"
            echo "  init            - 初始化配置"
            echo ""
            echo "使用示例:"
            echo "  $0 memory                    # 读取记忆"
            echo "  $0 select chinese            # 选择中文优化模型"
            echo "  $0 record deepseek/chat 1000 500  # 记录调用成本"
            ;;
    esac
}

main "$@"
