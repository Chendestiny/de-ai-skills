# de-ai-skills: 去AI味技能合集

一句话：**说"去AI味"，一个路由带你跑完 检测标记 → 主技能重写 → 文风注入 → 质检评分 的完整流水线。**

## 安装

**方式一 · 安装器**（推荐，自动补齐子技能 + 内置兜底）：

```powershell
# Windows（任意 agent 或终端）
irm https://raw.githubusercontent.com/Chendestiny/de-ai-skills/main/install.ps1 | iex

# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/Chendestiny/de-ai-skills/main/install.sh | bash

# 只看会装什么，不实际写入
.\install.ps1 -CheckOnly      # 或: bash install.sh --check
```

**方式二 · 通过 skills 生态安装**（[skills.sh](https://skills.sh) / Clawhub 等市场用户）：

```bash
npx skills add Chendestiny/de-ai-skills
```

> 整个仓库就是一个 skill bundle（根目录 SKILL.md + registry + 安装器），安装时整目录拷入 skills 目录。
> 此方式只装路由本体，子技能（humanizer-zh 等）不会自动补齐——对 agent 说"去AI味"时按 SKILL.md 第零步引导跑安装器补上即可。

装完对任意 agent 说 **"给这篇文章去AI味"** 即可触发。

> 装完如果 agent 说"找不到 humanizer-zh-plus / slop-gauge"：跑 `.\install.ps1 -CheckOnly`（或 `bash install.sh --check`）。安装器会逐个校验落地副本的 frontmatter，`LOAD-RISK` 行点名的技能就是"文件在、agent 看不见"——通常是 SKILL.md 的 YAML 解析失败（值里有裸 `": "`）或 `name` 不是小写 kebab-case。新装/升级的副本安装器会就地 `[fix]`，用户自己的旧副本只报不改。

## 它是什么

`de-ai` 是路由与组合器（总入口），自己不改一个字。它按语言和任务路由到子技能，并编排流水线：

```
0 源头预防（可选，动笔前）   提示词先过 de-ai-prompt-enhancer，喂真实素材
1 标记                      按主技能模式清单逐项标出 AI 痕迹
2 一次重写                  主技能整段重写 + 文风插槽作"作者样本"注入（DEAI_STYLE_SKILL / 提示词点名 / nuwa 现蒸）
3 质检门禁                  slop-gauge 机械量化（≥55）与 stop-slop 五维（≥35/50）双道门禁，单项不过打回
4 交付                      全文 + 修改点摘要 + 评分表 + 残余风险
```

## 子技能清单（registry.json 为准）

子技能分两类：**拉取类**从第三方上游安装；**自研扩展**（humanizer-zh-plus、slop-gauge，registry 里 origin=self）由本账号出品、与主仓同节奏维护。

| 技能 | 职责 | 上游 | 状态 |
|---|---|---|---|
| humanizer-zh-plus | 中文主改写·plus（24 类基座 + 中文原生套路 + 场景档 + 广告法）｜**自研扩展** | [Chendestiny/humanizer-zh-plus](https://github.com/Chendestiny/humanizer-zh-plus) | 必装 |
| humanizer-zh | 中文改写基座（plus 缺失时的降级位） | [op7418/Humanizer-zh](https://github.com/op7418/Humanizer-zh) | 必装 |
| humanizer | 英文主改写（35 模式） | [blader/humanizer](https://github.com/blader/humanizer) | 必装 |
| stop-slop | 质检评分门禁 | [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop) | 必装 |
| slop-gauge | 双道门禁机械量表（确定性量化 + diff）｜**自研扩展** | [Chendestiny/slop-gauge](https://github.com/Chendestiny/slop-gauge) | 必装 |
| nuwa-skill | 文风蒸馏（作者样本） | [alchaincyf/nuwa-skill](https://github.com/alchaincyf/nuwa-skill) | 可选 |
| taste-skill | UI/前端反 slop | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | 可选（别名 design-taste-frontend 视为已装） |
| de-ai-prompt-enhancer | 源头预防（提示词端） | [gitliuyun/De-AI-Prompt-Enhancer-Writer-Booster-SKILL](https://github.com/gitliuyun/De-AI-Prompt-Enhancer-Writer-Booster-SKILL) | 可选 |
| chatgpt-comparison-detection | 改前定位参考 | [Hello-SimpleAI/chatgpt-comparison-detection](https://github.com/Hello-SimpleAI/chatgpt-comparison-detection) | 占位延后（上游为学术代码仓，无 SKILL.md） |

安装器行为：**已有的跳过（canonical 和别名都认），缺的从上游现场拉取，延后项只报告不安装。**

## 设计原则

1. **总入口保持薄**：路由、流水线、冲突裁决、安装自检，四件事，不吸改写逻辑
2. **上游优先 + 内置兜底**：子技能装时优先从各自上游拉取；五个必装核心（humanizer-zh / humanizer-zh-plus / humanizer / stop-slop / slop-gauge，均 MIT）以 zip 内置包随仓库分发（`vendor/*.zip`，整仓保持两级目录以通过 WorkBuddy 等平台的打包校验），上游失败时自动解压兜底。其余子技能不打包：nuwa 34MB 太重，无 LICENSE 的永不入仓。vendor 是快照，上游或自研技能更新后用 `.\pack-vendor.ps1` 重打（`-Check` 只报哪些过期，`-Only <name>` 单打）
3. **事实红线**：流水线全程不得新增或丢失事实、数字、日期、出处
4. **写读分离**：改写技能不给自己打分，质检永远由 stop-slop 独立执行
5. **作者样本优先**：nuwa 蒸馏的用户文风覆盖默认禁令（防止两个改写器互相拆台——一次重写带双参数，不串行两刀）
6. **装上没有不算数**：agent 只认 SKILL.md 的 frontmatter，不认磁盘。安装器对每个落地副本校验（name 合法、description 在位、YAML 能解析），新拷入的能修就 `[fix]`，用户已有文件只报 `[warn]` 并列进 `LOAD-RISK`

## 许可证

- 本仓库（路由 SKILL.md / registry.json / 安装器 / 文档）：MIT，见 [LICENSE](LICENSE)。两个自研扩展 humanizer-zh-plus、slop-gauge 同为本账号出品，均 MIT
- 五个核心子技能（humanizer-zh / humanizer-zh-plus / humanizer / stop-slop / slop-gauge，MIT）以内置包形式随仓库分发（`vendor/`，原 LICENSE 保留）；其余子技能装时从上游拉取；**无 LICENSE 的两个（de-ai-prompt-enhancer、chatgpt-comparison-detection）只装时拉取，禁止复制进任何再分发仓库**

## 开发模型

```
本地源码仓（clone 本仓库，git 管理）
        ↓ push
GitHub Chendestiny/de-ai-skills（分发入口）
        ↓ install.ps1 / install.sh
~/.agents/skills/de-ai + 子技能（运行态，agent 加载）
```

改完本地验证：`powershell -ExecutionPolicy Bypass -File .\install.ps1`（就地升级，旧版自动备份）；只看会装什么用 `-CheckOnly`。动过 humanizer-zh-plus / slop-gauge 的 SKILL.md 就要 push 后 `.\pack-vendor.ps1` 重打内置包，再连 vendor 一起提交。收尾跑一次 `.\install.ps1 -CheckOnly`，`LOAD-RISK` 为空才算装到位。
