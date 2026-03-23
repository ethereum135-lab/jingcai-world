# HEARTBEAT.md - 定期检查任务

## 频道健康检查（每 5 分钟）

已配置 cron job 自动检查：
- Job ID: c5b4c0a7-a1c6-4344-8590-c0b5054e4cd9
- 检查间隔: 每 5 分钟
- 检查内容:
  - Gateway 是否运行
  - Telegram 是否有 404 错误
  - 企业微信是否断线
  - 自动重启如有问题

## 手动检查命令

```bash
# 查看 gateway 状态
openclaw gateway status

# 查看频道日志
tail -50 /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | grep -E '(telegram|wecom|channel exited|404)'

# 手动重启 gateway
systemctl --user restart openclaw-gateway.service
```

## 问题分析

### Telegram 404 错误
- **原因**: Bot Token 无效或网络不通
- **频率**: 国内访问 Telegram 不稳定
- **解决**: 自动重启 gateway，或禁用 Telegram

### 企业微信断线
- **原因**: WebSocket 超时或网络波动
- **解决**: 插件已内置自动重连（最多 100 次）

## Skill 文档

详细说明见: `~/.openclaw/skills/channel-health-monitor/SKILL.md`
