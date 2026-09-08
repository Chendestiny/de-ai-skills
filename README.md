# deai-skills: 去AI味技能总舵手

一句话：**说"去AI味"，一个路由带你跑完 检测标记 → 主技能重写 → 文风注入 → 质检评分 的完整流水线。**

## 安装

```powershell
# Windows（任意 agent 或终端）
irm https://raw.githubusercontent.com/Chendestiny/deai-skills/main/install.ps1 | iex

# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/Chendestiny/deai-skills/main/install.sh | bash

# 只看会装什么，不实际写入
.\install.ps1 -CheckOnly      # 或: bash install.sh --check
```

装完对任意 agent 说 **"给这篇文章去AI味"** 即可触发。

## 它是什么

`deai` 是路由与组合器（总舵手），自己不改一个字。它按语言和任务路由到子技能，并编排流水线：

```
0 源头预防（可选，动笔前）   提示词先过 de-ai-prompt-enhancer，喂真实素材
1 标记                      按主技能模式清单逐项标出 AI 痕迹
2 一次重写                  主技能整段重写 + nuwa 文风档案作"作者样本"注入
3 质检门禁                  stop-slop Quick Checks + 五维评分，<35/50 打回
4 交付                      全文 + 修改点摘要 + 评分表 + 残余风险
```

## 子技能清单（registry.json 为准）

| 技能 | 职责 | 上游 | 状态 |
|---|---|---|---|
| humanizer-zh | 中文主改写（24 类模式） | [op7418/Humanizer-zh](https://github.com/op7418/Humanizer-zh) | 必装 |
| humanizer | 英文主改写（35 模式） | [blader/humanizer](https://github.com/blader/humanizer) | 必装 |
| stop-slop | 质检评分门禁 | [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop) | 必装 |
| nuwa-skill | 文风蒸馏（作者样本） | [alchaincyf/nuwa-skill](https://github.com/alchaincyf/nuwa-skill) | 可选 |
| taste-skill | UI/前端反 slop | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | 可选（别名 design-taste-frontend 视为已装） |
| de-ai-prompt-enhancer | 源头预防（提示词端） | [gitliuyun/De-AI-Prompt-Enhancer-Writer-Booster-SKILL](https://github.com/gitliuyun/De-AI-Prompt-Enhancer-Writer-Booster-SKILL) | 可选 |
| chatgpt-comparison-detection | 改前定位参考 | [Hello-SimpleAI/chatgpt-comparison-detection](https://github.com/Hello-SimpleAI/chatgpt-comparison-detection) | 占位延后（上游为学术代码仓，无 SKILL.md） |

安装器行为：**已有的跳过（canonical 和别名都认），缺的从上游现场拉取，延后项只报告不安装。**

## 设计原则

1. **总舵手保持薄**：路由、流水线、冲突裁决、安装自检，四件事，不吸改写逻辑
2. **fetch-at-install**：子技能装时从各自上游拉取，本仓库不 vendor 任何第三方代码
3. **事实红线**：流水线全程不得新增或丢失事实、数字、日期、出处
4. **写读分离**：改写技能不给自己打分，质检永远由 stop-slop 独立执行
5. **作者样本优先**：nuwa 蒸馏的用户文风覆盖默认禁令（防止两个改写器互相拆台——一次重写带双参数，不串行两刀）

## 许可证

- 本仓库（路由 SKILL.md / registry.json / 安装器 / 文档）：MIT，见 [LICENSE](LICENSE)
- 子技能版权归各自上游作者，通过安装器从源头获取；**两个上游无 LICENSE 的（de-ai-prompt-enhancer、chatgpt-comparison-detection）只装时拉取，禁止复制进任何再分发仓库**

## 开发模型

```
本地源码仓（clone 本仓库，git 管理）
        ↓ push
GitHub Chendestiny/deai-skills（分发入口）
        ↓ install.ps1 / install.sh
~/.agents/skills/deai + 子技能（运行态，agent 加载）
```

改完本地验证：`powershell -ExecutionPolicy Bypass -File .\install.ps1`（就地升级，旧版自动备份）。
