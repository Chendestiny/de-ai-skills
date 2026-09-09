---
name: deai
version: 1.0.0
display_name: 去AI味总入口（deai）
display_name_en: De-AI Router
description_zh: 对任意 Agent 说一句"去AI味"，自动跑完标记、一次重写（文风注入）、stop-slop 质检评分的完整流水线，35/50 分以下自动打回重改。一行命令安装，内置 MIT 核心包兜底，子技能按 registry.json 自动补齐。
description_en: The de-AI router for any agent — one trigger phrase runs the full pipeline (mark, rewrite with personal style slot, independent QA score gate below 35/50), one-line install with bundled MIT core fallback, sub-skills fetched per registry.
description: 去AI味总入口（路由与组合器）。当用户说"给XX文章去AI味 / 去AI痕迹 / 人性化改写 / 这文章太AI了 / 没人味 / 不像人写的 / humanize / de-AI / remove AI flavor"时必须先加载本技能。它判定语言与任务并路由子技能（中文→humanizer-zh，英文→humanizer，UI→taste-skill），文风插槽（DEAI_STYLE_SKILL 环境变量 / 提示词点名 / nuwa-skill 现蒸）注入作者样本，stop-slop 做质检评分门禁，子技能缺失按 registry.json 引导安装。 The de-AI router for any agent — one trigger phrase runs the full pipeline (mark, rewrite with personal style slot, QA score), one-line install with bundled core fallback.
---

# deai: 去AI味总入口

本技能不直接改写文字。它负责子技能自检、路由判定、冲突裁决、流水线编排和输出格式。实际改写规则全部在子技能里。

## 第零步：子技能自检（Bootstrap）

路由前先确认子技能在位。判断"已安装"看技能目录名，**同时检查 canonical 和 aliases**（同一天会上游改名、装机改名都会发生）：

| canonical | 别名也算已装 | 缺失时的降级 |
|---|---|---|
| humanizer-zh | — | 中文走 humanizer 会产翻译腔，宁可提示安装 |
| humanizer | — | 英文无主改写，提示安装 |
| stop-slop | — | 无质检门禁，提示安装（写读分离是底线） |
| nuwa-skill | — | 可缺：跳过文风注入，用默认规则 |
| taste-skill | design-taste-frontend | 可缺：UI 任务提示安装或用户自选 |
| de-ai-prompt-enhancer | — | 可缺：跳过源头预防 |
| chatgpt-comparison-detection | — | deferred，暂不安装不路由 |

缺失时引导执行本项目安装器（或直接代跑）：

```
Windows 在线:  irm https://raw.githubusercontent.com/Chendestiny/deai-skills/main/install.ps1 | iex
Windows 本地:  powershell -ExecutionPolicy Bypass -File .\install.ps1
只看缺什么:    .\install.ps1 -CheckOnly
Unix:          curl -fsSL https://raw.githubusercontent.com/Chendestiny/deai-skills/main/install.sh | bash
```

规则：
- `registry.json` 是唯一清单（repo / skill_path / aliases / license），不凭记忆安装
- license 为 none 的两个子技能（de-ai-prompt-enhancer、chatgpt-comparison-detection）只允许装时从上游拉取，禁止复制进任何再分发仓库
- status 为 deferred 的条目不安装、不路由，只留占位

## 第一步：拿到文章

- 用户粘贴了文本 → 直接用
- 用户给了文件路径 → 用 read 读取；二进制/文档用 read_document
- 用户只说"给XXX文章去AI味"但没给内容 → 只问一个问题把文章要来（路径或粘贴），不要自作主张编内容

## 第二步：路由判定

| 任务 | 加载的子技能（用 skill 工具，按顺序） |
|---|---|
| 中文文章/文案/博客/公众号 | 1) `humanizer-zh`（主改写） 2) `stop-slop`（质检）＋ 文风插槽（见下） |
| 英文文章/prose/docs | 1) `humanizer`（主改写） 2) `stop-slop`（质检）；文风同理 |
| 中英混合文章 | 两边主技能都加载，按段落语言分段套用 |
| 网页/落地页/UI"去AI味" | `taste-skill`（本地可能叫 design-taste-frontend，同一个） |
| 还没动笔，要生成初稿 | `de-ai-prompt-enhancer` 先过提示词（源头预防） |
| 代码注释/commit message | `humanizer`（其 Embedded mode：只返回最终文本） |

判定依据是文章主要语言，不是用户提问用的语言。

**文风插槽（作者样本的通用约定，不绑定任何具体技能名）**——按优先级取第一个命中的：

1. 环境变量 `DEAI_STYLE_SKILL` 点名的技能：用户自己蒸馏或自写的个人文风技能，装在任意技能目录
2. 提示词点名"用我的文风 / 按我的风格写"：从已装技能的 description 匹配个人文风类技能
3. 用户给了旧文样本：`nuwa-skill` 现场蒸馏成文风档案
4. 都没有：无样本，走默认规则

统一入口永远是【去AI味】触发词，文风插槽只是可选修饰。

## 第三步：组合流水线

0. **源头（可选，动笔前）**：提示词先过 de-ai-prompt-enhancer；同时要求用户喂真实素材（数字、案例、出处）。空心稿靠后端工序救不回来
1. **标记**：通读原文，按主技能的模式清单逐项标出 AI 痕迹（不急着逐句改）。检测类子技能（如未来就位的 chatgpt-comparison-detection）只做定位参考，不当判据
2. **一次重写**：主技能按处理流程整段重写，围绕段落主旨重述，而不是对标记过的短语逐个打补丁。文风插槽若命中（见第二步），作为"作者样本"注入本次重写——规则与文风同一刀，避免两个改写器串行互相拆台
3. **质检门禁**：stop-slop 的 Quick Checks 过一遍，再打五维评分（直接性/节奏/信任度/真实性/精炼度，各 10 分）。总分 < 35/50 → 打回第 2 步重改；35-44 → 可交付但指出残余问题
4. **交付**：按下面格式输出

## 冲突裁决（子技能规则打架时按此顺序）

1. **事实红线最高**：不得新增或丢失任何事实、数字、日期、引文、出处。缺细节就问用户或用更简单的句子，不许编
2. **作者样本优先**：文风插槽命中的个人风格技能（环境变量点名 / 提示词点名 / nuwa 现蒸）、或用户直接提供的过往文章样本，其习惯（句长、用词、连词、破折号频率、口语动词、感叹号取舍）覆盖 stop-slop 的绝对禁令
3. **无样本时**：英文默认清除 em/en dash；中文清除破折号滥用
4. **stop-slop 只做质检**：其 Core Rules 与主技能冲突时，以主技能为准；Quick Checks 和评分表永远执行
5. **个性注入看场合**：博客/随笔/观点文注入个性；技术文档/法律/参考类保持中性

## 输出格式

1. **重写后全文**（改文件时为改动清单 + 落盘路径）
2. **修改点摘要**：按模式归类，一行一条（如：删"此外"×3（AI高频词）；三段式改两项×2）
3. **评分表**：五维各 /10 + 总分 /50
4. **残余风险（可选）**：无法核实的事实、需要用户补充的信息

## 不该触发本技能的情况

- 用户让你"写一篇文章"（全新创作）且没提"去AI味"也没提"用我的文风"：可借鉴子技能原则，但那是写作任务，不走本流水线；带了任一关键词，就走第 0 步源头流水线（提示词预防 + 文风插槽 + 素材前置）
- 输入是代码/配置：只有注释和 commit message 适用，且只用 `humanizer`
