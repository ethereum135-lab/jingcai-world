#!/bin/bash
# 竞猜世界 - 模型自动调配脚本
# 智能选择模型：根据任务类型+预算+可用性

set -e

CONFIG_FILE="$HOME/.openclaw/workspace/.model-router.json"
LOG_FILE="$HOME/.openclaw/workspace/logs/model-router.log"

mkdir -p "$(dirname "$LOG_FILE")"

# ============ 模型配置 ============
# 价格单位: USD per 1M tokens
declare -A MODELS
declare -A MODEL_PRICES_INPUT
declare -A MODEL_PRICES_OUTPUT
declare -A MODEL_CAPS

# Kimi (Moonshot)
MODELS["kimi-k2.5"]="moonshot/kimi-k2.5"
MODEL_PRICES_INPUT["kimi-k2.5"]="15"
MODEL_PRICES_OUTPUT["kimi-k2.5"]="60"
MODEL_CAPS["kimi-k2.5"]="chinese,long-context,general"

# DeepSeek
MODELS["deepseek-chat"]="deepseek/deepseek-chat"
MODEL_PRICES_INPUT["deepseek-chat"]="0.14"
MODEL_PRICES_OUTPUT["deepseek-chat"]="0.28"
MODEL_CAPS["deepseek-chat"]="math,coding,cheap,general"

MODELS["deepseek-reasoner"]="deepseek/deepseek-reasoner"
MODEL_PRICES_INPUT["deepseek-reasoner"]="0.55"
MODEL_PRICES_OUTPUT["deepseek-reasoner"]="2.19"
MODEL_CAPS["deepseek-reasoner"]="math,reasoning,advanced"

# Qwen (千问)
MODELS["qwen-max"]="qwen/qwen-max"
MODEL_PRICES_INPUT["qwen-max"]="3"
MODEL_PRICES_OUTPUT["qwen-max"]="9"
MODEL_CAPS["qwen-max"]="chinese,general"

# OpenAI (备用)
MODELS["gpt-4o"]="openai/gpt-4o"
MODEL_PRICES_INPUT["gpt-4o"]="5"
MODEL_PRICES_OUTPUT["gpt-4o"]="15"
MODEL_CAPS["gpt-4o"]="general,advanced"

MODELS["gpt-4o-mini"]="openai/gpt-4o-mini"
MODEL_PRICES_INPUT["gpt-4o-mini"]="0.15"
MODEL_PRICES_OUTPUT["gpt-4o-mini"]="0.6"
MODEL_CAPS["gpt-4o-mini"]="cheap,general"

# ============ 初始化配置 ============
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "api_keys": {
    "kimi": "",
    "deepseek": "",
    "qwen": "",
    "openai": ""
  },
  "preferences": {
    "chinese": "kimi-k2.5",
    "math": "deepseek-reasoner",
    "coding": "deepseek-chat",
    "cheap": "deepseek-chat",
    "general": "kimi-k2.5",
    "advanced": "deepseek-reasoner"
  },
  "budget": {
    "daily_usd": 10,
    "used_today": 0
  },
  "fallback_order": ["deepseek-chat", "kimi-k2.5", "qwen-max", "gpt-4o-mini"],
  "health_status": {}
}
EOF
    fi
}

# ============ 日志 ============
log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ============ 检查API Key有效性 ============
check_api_health() {
    local model="$1"
    local api_key="$2"
    
    # 简化检查：只检查key是否存在
    if [[ -z "$api_key" ]]; then
        echo "unavailable"
        return
    fi
    
    # TODO: 实际API调用检查（会消耗token，暂不实现）
    echo "available"
}

# ============ 更新健康状态 ============
update_health_status() {
    local tmp=$(mktemp)
    local status="{}"
    
    for model in "${!MODELS[@]}"; do
        local key_name=""
        case "$model" in
            kimi*) key_name="kimi" ;;
            deepseek*) key_name="deepseek" ;;
            qwen*) key_name="qwen" ;;
            gpt*) key_name="openai" ;;
        esac
        
        local api_key=$(jq -r ".api_keys.$key_name" "$CONFIG_FILE")
        local health=$(check_api_health "$model" "$api_key")
        
        status=$(echo "$status" | jq ". + {\"$model\": \"$health\"}")
    done
    
    jq ".health_status = $status" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

# ============ 选择模型 ============
select_model() {
    local task_type="${1:-general}"
    local budget_constrained="${2:-false}"
    
    init_config
    
    # 更新健康状态
    update_health_status
    
    # 1. 根据任务类型获取首选模型
    local preferred=$(jq -r ".preferences.$task_type" "$CONFIG_FILE")
    if [[ -z "$preferred" || "$preferred" == "null" ]]; then
        preferred="deepseek-chat"
    fi
    
    # 2. 检查首选模型是否可用
    local health=$(jq -r ".health_status.$preferred" "$CONFIG_FILE")
    if [[ "$health" == "available" ]]; then
        # 检查预算
        if [[ "$budget_constrained" == "true" ]]; then
            local price=${MODEL_PRICES_INPUT[$preferred]:-100}
            if [[ $price -lt 1 ]]; then  # 便宜模型
                log "选择模型: $preferred (预算受限+任务:$task_type)"
                echo "${MODELS[$preferred]}"
                return
            fi
        else
            log "选择模型: $preferred (任务:$task_type)"
            echo "${MODELS[$preferred]}"
            return
        fi
    fi
    
    # 3. 按fallback顺序查找可用模型
    local fallback=$(jq -r '.fallback_order[]' "$CONFIG_FILE")
    for model in $fallback; do
        health=$(jq -r ".health_status.$model" "$CONFIG_FILE")
        if [[ "$health" == "available" ]]; then
            log "选择模型: $model (fallback, 任务:$task_type)"
            echo "${MODELS[$model]}"
            return
        fi
    done
    
    # 4. 如果都不可用，返回最便宜的
    log "警告: 所有首选模型不可用，使用最便宜模型"
    echo "${MODELS["deepseek-chat"]}"
}

# ============ 记录使用 ============
record_usage() {
    local model="$1"
    local input_tokens="${2:-0}"
    local output_tokens="${3:-0}"
    
    local input_price=${MODEL_PRICES_INPUT[$model]:-0}
    local output_price=${MODEL_PRICES_OUTPUT[$model]:-0}
    
    # 计算成本 (USD)
    local input_cost=$(echo "scale=6; $input_tokens * $input_price / 1000000" | bc)
    local output_cost=$(echo "scale=6; $output_tokens * $output_price / 1000000" | bc)
    local total_cost=$(echo "scale=6; $input_cost + $output_cost" | bc)
    
    # 更新今日使用
    local tmp=$(mktemp)
    jq ".budget.used_today = ((.budget.used_today // 0) + $total_cost)" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    
    log "记录使用: $model | 输入:${input_tokens} | 输出:${output_tokens} | 成本:$${total_cost}"
}

# ============ 检查预算 ============
check_budget() {
    local daily_budget=$(jq -r '.budget.daily_usd' "$CONFIG_FILE")
    local used_today=$(jq -r '.budget.used_today' "$CONFIG_FILE")
    local remaining=$(echo "scale=2; $daily_budget - $used_today" | bc)
    
    local usage_rate=$(echo "scale=2; $used_today / $daily_budget * 100" | bc)
    
    log "预算状态: $${used_today} / $${daily_budget} (${usage_rate}%)"
    
    if (( $(echo "$usage_rate > 90" | bc -l) )); then
        echo "critical"
    elif (( $(echo "$usage_rate > 70" | bc -l) )); then
        echo "warning"
    else
        echo "ok"
    fi
}

# ============ 设置API Key ============
set_api_key() {
    local provider="$1"
    local key="$2"
    
    local tmp=$(mktemp)
    jq ".api_keys.$provider = \"$key\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    log "已设置 $provider API Key"
}

# ============ 主入口 ============
main() {
    case "${1:-}" in
        select)
            select_model "${2:-general}" "${3:-false}"
            ;;
        record)
            record_usage "$2" "$3" "$4"
            ;;
        budget)
            check_budget
            ;;
        health)
            update_health_status
            jq '.health_status' "$CONFIG_FILE"
            ;;
        set-key)
            set_api_key "$2" "$3"
            ;;
        status)
            jq '.' "$CONFIG_FILE"
            ;;
        init)
            init_config
            log "配置已初始化"
            ;;
        *)
            echo "竞猜世界 - 模型自动调配"
            echo ""
            echo "用法: $0 [命令] [参数]"
            echo ""
            echo "命令:"
            echo "  select [task] [budget]  - 选择模型 (task: chinese/math/coding/general)"
            echo "  record <model> <in> <out> - 记录使用"
            echo "  budget                  - 检查预算"
            echo "  health                  - 检查模型健康状态"
            echo "  set-key <provider> <key> - 设置API Key"
            echo "  status                  - 查看完整配置"
            echo "  init                    - 初始化配置"
            echo ""
            echo "示例:"
            echo "  $0 select chinese       # 选择中文优化模型"
            echo "  $0 select math true     # 预算受限时选择数学模型"
            ;;
    esac
}

main "$@"
