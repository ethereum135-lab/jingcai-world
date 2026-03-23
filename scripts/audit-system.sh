#!/bin/bash
# 竞猜世界 - 基础能力排查脚本
# 运行环境检查，确保所有基础工具就绪
# 零Token成本，纯本地检查

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_FILE="/tmp/jingcai-audit-$(date +%Y%m%d-%H%M%S).md"

echo "# 竞猜世界 - 基础能力排查报告" > "$REPORT_FILE"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

log() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "- [x] $1" >> "$REPORT_FILE"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
    echo "- [!] $1" >> "$REPORT_FILE"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
    echo "- [✗] $1" >> "$REPORT_FILE"
}

info() {
    echo -e "${BLUE}[i]${NC} $1"
    echo "- $1" >> "$REPORT_FILE"
}

echo "========================================"
echo "   竞猜世界 - 基础能力排查"
echo "========================================"
echo ""

# ============ 1. 系统基础 ============
echo "## 1. 系统基础环境" >> "$REPORT_FILE"
echo ""

# Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    log "Node.js 已安装: $NODE_VERSION"
else
    error "Node.js 未安装 - 需要安装"
fi

# npm
if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm --version)
    log "npm 已安装: $NPM_VERSION"
else
    error "npm 未安装 - 需要安装"
fi

# jq (JSON处理)
if command -v jq &> /dev/null; then
    log "jq 已安装 (JSON处理工具)"
else
    warn "jq 未安装 - 建议安装: apt-get install jq"
fi

# curl
if command -v curl &> /dev/null; then
    log "curl 已安装"
else
    error "curl 未安装 - 必须安装"
fi

# git
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | awk '{print $3}')
    log "Git 已安装: $GIT_VERSION"
else
    warn "Git 未安装 - 建议安装用于版本控制"
fi

echo "" >> "$REPORT_FILE"

# ============ 2. OpenClaw 环境 ============
echo "## 2. OpenClaw 环境" >> "$REPORT_FILE"
echo ""

if command -v openclaw &> /dev/null; then
    OPENCLAW_VERSION=$(openclaw version 2>/dev/null || echo "unknown")
    log "OpenClaw 已安装: $OPENCLAW_VERSION"
else
    error "OpenClaw 未安装 - 核心环境缺失"
fi

# 检查 gateway
if systemctl --user is-active --quiet openclaw-gateway.service 2>/dev/null; then
    log "OpenClaw Gateway 运行中"
else
    warn "OpenClaw Gateway 未运行"
fi

# 检查配置目录
if [[ -d "$HOME/.openclaw" ]]; then
    log "OpenClaw 配置目录存在"
else
    warn "OpenClaw 配置目录不存在"
fi

echo "" >> "$REPORT_FILE"

# ============ 3. 已安装 Skills ============
echo "## 3. 已安装 Skills" >> "$REPORT_FILE"
echo ""

SKILLS_DIR="$HOME/.openclaw/skills"
if [[ -d "$SKILLS_DIR" ]]; then
    SKILL_COUNT=$(find "$SKILLS_DIR" -name "SKILL.md" 2>/dev/null | wc -l)
    log "已安装 $SKILL_COUNT 个 Skills"
    
    echo "" >> "$REPORT_FILE"
    echo "已安装 Skills 列表:" >> "$REPORT_FILE"
    find "$SKILLS_DIR" -name "SKILL.md" 2>/dev/null | while read -r skill; do
        skill_name=$(basename $(dirname "$skill"))
        echo "  - $skill_name" >> "$REPORT_FILE"
    done
else
    warn "Skills 目录不存在"
fi

echo "" >> "$REPORT_FILE"

# ============ 4. 工作空间 ============
echo "## 4. 工作空间检查" >> "$REPORT_FILE"
echo ""

WORKSPACE="$HOME/.openclaw/workspace"
if [[ -d "$WORKSPACE" ]]; then
    log "工作空间存在: $WORKSPACE"
    
    # 检查核心文件
    [[ -f "$WORKSPACE/SOUL.md" ]] && log "SOUL.md 存在" || warn "SOUL.md 缺失"
    [[ -f "$WORKSPACE/IDENTITY.md" ]] && log "IDENTITY.md 存在" || warn "IDENTITY.md 缺失"
    [[ -f "$WORKSPACE/USER.md" ]] && log "USER.md 存在" || warn "USER.md 缺失"
    [[ -f "$WORKSPACE/AGENTS.md" ]] && log "AGENTS.md 存在" || warn "AGENTS.md 缺失"
else
    error "工作空间不存在"
fi

echo "" >> "$REPORT_FILE"

# ============ 5. 网络连通性 ============
echo "## 5. 网络连通性" >> "$REPORT_FILE"
echo ""

# 测试关键网站
SITES=(
    "github.com:GitHub"
    "npmjs.com:NPM Registry"
    "api.telegram.org:Telegram API"
    "openai.com:OpenAI"
    "www.google.com:Google"
)

for site in "${SITES[@]}"; do
    IFS=':' read -r url name <<< "$site"
    if curl -s --max-time 5 -o /dev/null "https://$url" 2>/dev/null; then
        log "$name 可访问"
    else
        warn "$name 访问受限 (可能需要代理)"
    fi
done

echo "" >> "$REPORT_FILE"

# ============ 6. 竞猜领域相关工具 ============
echo "## 6. 竞猜领域工具" >> "$REPORT_FILE"
echo ""

# Python (数据分析)
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    log "Python3 已安装: $PYTHON_VERSION"
    
    # 检查关键库
    python3 -c "import requests" 2>/dev/null && log "requests 库已安装" || warn "requests 库未安装"
    python3 -c "import pandas" 2>/dev/null && log "pandas 库已安装" || warn "pandas 库未安装"
else
    warn "Python3 未安装 - 数据分析需要"
fi

# Web3工具
if command -v cast &> /dev/null; then
    log "Foundry (cast) 已安装 - 链上交互"
else
    info "Foundry 未安装 - 可选，用于链上交互"
fi

echo "" >> "$REPORT_FILE"

# ============ 7. 安全与备份 ============
echo "## 7. 安全与备份" >> "$REPORT_FILE"
echo ""

# SSH密钥
if [[ -f "$HOME/.ssh/id_rsa" ]] || [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    log "SSH 密钥存在"
else
    warn "SSH 密钥不存在 - 建议配置用于Git操作"
fi

# Git配置
if git config --global user.name &> /dev/null; then
    log "Git 用户已配置"
else
    warn "Git 用户未配置"
fi

echo "" >> "$REPORT_FILE"

# ============ 8. 资源使用情况 ============
echo "## 8. 系统资源" >> "$REPORT_FILE"
echo ""

# 磁盘
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ "$DISK_USAGE" -lt 80 ]]; then
    log "磁盘空间充足 (${DISK_USAGE}% 已用)"
else
    warn "磁盘空间紧张 (${DISK_USAGE}% 已用)"
fi

# 内存
if command -v free &> /dev/null; then
    MEM_INFO=$(free -h | awk 'NR==2{printf "%.1fG/%.1fG", $3,$2}')
    info "内存使用: $MEM_INFO"
fi

echo "" >> "$REPORT_FILE"

# ============ 总结 ============
echo "" >> "$REPORT_FILE"
echo "## 总结与建议" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "### 竞猜世界启动清单:" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "- [ ] 安装缺失的基础工具 (jq, git)" >> "$REPORT_FILE"
echo "- [ ] 配置网络代理 (如需要访问海外API)" >> "$REPORT_FILE"
echo "- [ ] 安装竞猜领域专用 Skills" >> "$REPORT_FILE"
echo "- [ ] 配置 API Keys (Kimi, DeepSeek, etc.)" >> "$REPORT_FILE"
echo "- [ ] 设置自动备份" >> "$REPORT_FILE"
echo "- [ ] 配置告警通知" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo ""
echo "========================================"
echo "   排查完成"
echo "========================================"
echo ""
echo "详细报告: $REPORT_FILE"
echo ""

# 显示报告内容
cat "$REPORT_FILE"
