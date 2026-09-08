# AGENTS.md — deai-skills 操作手册（agent 视角）

本手册供 agent 读。人类视角的介绍在 README.md。技能路由规则在 SKILL.md（权威）。

## 触发词

用户说以下任何一种，先加载 `deai` 技能再干活：

- 去AI味 / 去AI痕迹 / 人性化改写 / 这文章太AI了 / 没人味 / 不像人写的
- humanize / de-AI / remove AI flavor

## 标准动作序列

1. **自检**：按 SKILL.md 第零步的表核对子技能是否在位（同时查 canonical 和 aliases 目录）。缺失且必装 → 跑安装器；可选缺失 → 降级并告知用户
2. **拿文章**：文本直接用；路径用 read / read_document；只有意图没内容 → 只问一个问题要文章，不编
3. **路由**：按语言/任务选主技能（中文 humanizer-zh，英文 humanizer，UI 走 taste-skill，动笔前走 de-ai-prompt-enhancer）
4. **跑流水线**：标记 → 一次重写（文风档案作作者样本）→ stop-slop 质检 → 交付
5. **输出**：全文（或改动清单）+ 修改点摘要 + 五维评分表 + 残余风险

## 硬规则（违反任何一条算事故）

- **事实红线**：不新增、不丢失事实/数字/日期/引文/出处。宁可问用户，不许编
- **一次重写**：不把两个改写器串行跑（会互相拆台）；文风用样本注入
- **写读分离**：改写技能不得自评，评分必须由 stop-slop 独立出
- **检测器不是判据**：任何 AI 浓度检测只做定位参考，不决定交付
- **license=none 的子技能**（de-ai-prompt-enhancer、chatgpt-comparison-detection）：只允许装时从上游拉取，禁止复制进任何再分发仓库

## 安装器速查

```
.\install.ps1                # 安装/升级路由 + 补缺失子技能
.\install.ps1 -CheckOnly     # 干跑，只报告
.\install.ps1 -Source <zip|dir>  # 离线安装
bash install.sh [--check]
$env:DEAI_GH_PREFIX='<mirror>/'   # GitHub 镜像前缀
```

判断"已安装"：在 `~/.agents/skills/<name>` 或 `~/.dsh/skills/<name>` 下存在 `SKILL.md`，name 匹配 canonical 或任一 alias。

## 文风插槽

作者样本不绑定任何技能名（个人风格技能各用户名字不同，不能当统一格式）。按优先级解析：① 环境变量 `DEAI_STYLE_SKILL` 点名的技能（用户级配置，如自己用 nuwa-skill 蒸馏的风格技能）② 提示词"用我的文风"按 description 匹配已装技能 ③ `nuwa-skill` 现场蒸馏旧文样本 ④ 无样本走默认规则。统一入口永远是【去AI味】触发词，文风插槽只是可选修饰。

## 维护规则

- **registry.json 是唯一清单**：加/换子技能只改它，不改安装器逻辑
- 上游 URL 变更 / 分支从 main 变 master：改 repo 字段即可，安装器两个分支都会试
- 新增 deferred 条目：`skill_path` 留 null + `status: "deferred"`
- 别名产生（用户机器上被改名安装）：追加到该条目的 aliases 数组
- 本项目自己的改动永远发生在源码仓（本仓库的本地 clone → push GitHub），不要直接改运行态目录（重装会被备份覆盖）
- **离线三层兜底**：① 上游拉取（最新）→ ② 仓库内置包 `vendor/<canonical>/`（三个必装核心 humanizer-zh / humanizer / stop-slop，均 MIT，原 LICENSE 随包保留，上游挂掉/改名/删库时自动 fallback）→ ③ 环境变量 `DEAI_OFFLINE_DIR` 个人缓存（按 `<canonical>` 或 `<canonical>-main` 忽略大小写匹配，需含 SKILL.md）。铁律：vendor/ 只收 MIT 等可再分发许可证的核心包且必须保留原 LICENSE；无 LICENSE 上游（de-ai-prompt-enhancer、chatgpt-comparison-detection）永不入 vendor。注意 vendor 是快照，上游更新要手动刷新
