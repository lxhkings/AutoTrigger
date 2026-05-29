# TODOS — AutoTrigger

Deferred from /plan-ceo-review 2026-05-28 (SELECTIVE EXPANSION). Decided during cherry-pick ceremony.

## P2 — 跨机器 fleet view
- **What:** 每台 Mac 跑轻量 agent，把任务状态上报到一个面板，一处看多机器谁跑了/谁挂了。
- **Why:** 这是 office-hours Q2 里说的原始痛点（多机器散乱），也是区别于免费 launchd GUI 的核心护城河 — "Healthchecks for your Macs" 的本体。
- **Pros:** 真正的差异化、可收费品类（对标 Cronitor/Healthchecks/Dead Man's Snitch，Mac 上空白）。
- **Cons:** 工量大（agent + 上报协议 + 跨机配对/认证）；需求未验证前投入风险高。
- **Context:** 单机 MVP 先验证"有人要看板+告警"。验证信号出现后再做。架构上 baseline 的 wrapper + 本地 store 已是上报协议的雏形。
- **Depends on:** 单机 MVP 上线并拿到留存/付费意愿信号。

## P3 — Delight 包
- **What:** 菜单栏红点健康总览、一键 run-now、popover 日志 tail、snooze-alert、免 plist 图形化改调度。
- **Why:** 把"能用"变成"想用"，提升留存与口碑。
- **Cons:** 验证前做 = 给可能没人要的产品抛光。
- **Context:** 单机核心（看板+心跳告警+机外渠道）验证后逐个加。每项 ~S 工量。
- **Depends on:** 核心功能验证通过。
