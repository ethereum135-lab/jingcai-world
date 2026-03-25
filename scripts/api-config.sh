#!/bin/bash
# 竞猜世界 - API配置脚本
# 配置各种数据源API Key

set -e

CONFIG_FILE="$HOME/.openclaw/workspace/.api-config.json"

init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "polymarket": {
    "enabled": true,
    "api_endpoint": "https://gamma-api.polymarket.com",
    "note": "免费，无需API Key"
  },
  "sportsradar": {
    "enabled": false,
    "api_key": "",
    "endpoint": "https://api.sportradar.com",
    "pricing": "付费，体育数据"
  },
  "pandascore": {
    "enabled": false,
    "api_key": "",
    "endpoint": "https://api.pandascore.co",
    "pricing": "付费，电竞数据"
  },
  "dune": {
    "enabled": false,
    "api_key": "",
    "endpoint": "https://api.dune.com",
    "pricing": "付费，链上数据"
  },
  "football_data": {
    "enabled": false,
    "api_key": "",
    "endpoint": "https://api.football-data.org",
    "pricing": "免费/付费，足球数据"
  },
  "api_football": {
    "enabled": false,
    "api_key": "",
    "endpoint": "https://v3.football.api-sports.io",
    "pricing": "免费/付费，足球数据"
  }
}
EOF
    fi
}

set_key() {
    local service="$1"
    local key="$2"
    
    local tmp=$(mktemp)
    jq ".$service.api_key = \"$key\" | .$service.enabled = true" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "✅ $service API Key 已配置"
}

show_config() {
    cat "$CONFIG_FILE" | jq .
}

main() {
    init_config
    
    case "${1:-}" in
        set)
            set_key "$2" "$3"
            ;;
        show)
            show_config
            ;;
        *)
            echo "竞猜世界 - API配置管理"
            echo ""
            echo "用法:"
            echo "  $0 set <service> <key>  - 配置API Key"
            echo "  $0 show                  - 查看配置"
            echo ""
            echo "支持的服务:"
            echo "  sportsradar   - 体育数据（付费）"
            echo "  pandascore    - 电竞数据（付费）"
            echo "  dune          - 链上数据（付费）"
            echo "  football_data - 足球数据（免费/付费）"
            echo "  api_football  - 足球数据（免费/付费）"
            echo ""
            echo "免费服务:"
            echo "  polymarket    - 已启用，无需配置"
            ;;
    esac
}

main "$@"
