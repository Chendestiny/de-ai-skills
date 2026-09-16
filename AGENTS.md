# AGENTS.md — deai-skills 操作手册（agent 视角）

本手册供 agent 读。人类视角的介绍在 README.md。技能路由规则在 SKILL.md（权威）。

## 触发词

用户说以下任何一种，先加载 `de-ai` 技能再干活：

- 去AI味 / 去AI痕迹 / 人性化改写 / 这文章太AI了 / 没人味 / 不像人写的
- humanize / de-AI / remove AI flavor

## 标准动作序列

1. **自检**：按 SKILL.md 第零步的表核对子技能是否在位（同时查 canonical 和 aliases 目录）。**"在位"看 agent 技能清单，不是看目录**——目录在但清单没有 = frontmatter 不合法（YAML 解析失败或 name 非法），按缺失处理。缺失且必装 → 跑安装器；可选缺失 → 降级并告知用户
2. **拿文章**：文本直接用；路径用 read / read_document；只有意图没内容 → 只问一个问题要文章，不编
3. **路由**：按语言/任务选主技能（中文 humanizer-zh 基座 + humanizer-zh-plus 增量，英文 humanizer，UI 走 taste-skill，动笔前走 de-ai-prompt-enhancer）
4. **跑流水线**：标记 → 一次重写（文风档案作作者样本）→ slop-gauge `--diff` 出数据变化行 → stop-slop 质检 → 交付（双道门禁：机械 <55 或 stop-slop <35 → 打回）
5. **输出**：全文（或改动清单）+ 修改点摘要 + 五维评分表 + metrics 数据变化行 + 残余风险

## 硬规则（违反任何一条算事故）

- **事实红线**：不新增、不丢失事实/数字/日期/引文/出处。宁可问用户，不许编
- **一次重写**：不把两个改写器串行跑（会互相拆台）；文风用样本注入
- **写读分离**：改写技能不得自评，评分必须由 stop-slop 独立出
- **检测器不是判据**：任何 AI 浓度检测只做定位参考，不决定交付
- **license=none 的子技能**（de-ai-prompt-enhancer、chatgpt-comparison-detection）：只允许装时从上游拉取，禁止复制进任何再分发仓库
- **frontmatter 必须机器可载**：SKILL.md 的 `name` 用小写 kebab-case 且与安装目录名一致（nuwa / taste 这类刻意不同的要在 registry 的 aliases 里登记）；`description` 必填；**任何 frontmatter 值里不得出现裸的 ASCII `": "`**（YAML 会把整块解析失败，技能直接隐身），要断句就用破折号、分号或全角冒号。vendor zip 重打后跑一次 `install.ps1 -CheckOnly`，看到 LOAD-RISK 为空才算过

## 安装器速查

```
.\install.ps1                # 安装/升级路由 + 补缺失子技能
.\install.ps1 -CheckOnly     # 干跑，只报告（顺带体检已装技能的 frontmatter）
.\install.ps1 -Source <zip|dir>  # 离线安装
bash install.sh [--check]
$env:DEAI_GH_PREFIX='<mirror>/'   # GitHub 镜像前缀
```

判断"已安装"：在 `~/.agents/skills/<name>` 或 `~/.dsh/skills/<name>` 下存在 `SKILL.md`，name 匹配 canonical 或任一 alias。

落地校验（两个安装器同一套语义）：拷进 skills 目录后逐个查 frontmatter——name 非法就在**我们刚放的副本**上重写为目录名、值里裸冒号自动加引号（输出 `[fix]`）；已存在的用户副本只报不改（`[warn]`）；报告里出现 `LOAD-RISK` 就等于该技能在 agent 清单里看不见，得修上游。`registry parser` 那行是 install.sh 的自检输出：Windows git-bash 的 `python3` 是商店占位程序，会退回 `python`。

## 文风插槽

作者样本不绑定任何技能名（个人风格技能各用户名字不同，不能当统一格式）。按优先级解析：① 环境变量 `DEAI_STYLE_SKILL` 点名的技能（用户级配置，如自己用 nuwa-skill 蒸馏的风格技能）② 提示词"用我的文风"按 description 匹配已装技能 ③ `nuwa-skill` 现场蒸馏旧文样本 ④ 无样本走默认规则。统一入口永远是【去AI味】触发词，文风插槽只是可选修饰。

## 维护规则

- **registry.json 是唯一清单**（repo / skill_path / aliases / license / origin）：加/换子技能只改它，不改安装器逻辑。`origin=self` 的两条（humanizer-zh-plus、slop-gauge）为本账号自研扩展：仓库与主仓同账号维护，版本同节奏更新，vendor zip 也要主仓重打时一并对齐
- 上游 URL 变更 / 分支从 main 变 master：改 repo 字段即可，安装器两个分支都会试
- 新增 deferred 条目：`skill_path` 留 null + `status: "deferred"`
- 别名产生（用户机器上被改名安装）：追加到该条目的 aliases 数组
- 本项目自己的改动永远发生在源码仓（本仓库的本地 clone → push GitHub），不要直接改运行态目录（重装会被备份覆盖）
- **安装来源三级优先**（与安装器实际行为一致）：① 环境变量 `DEAI_OFFLINE_DIR` 个人缓存（按 `<canonical>` 或 `<canonical>-main` 忽略大小写匹配，需含 SKILL.md，命中即用不再碰网络）→ ② 上游拉取（最新）→ ③ 仓库内置 zip `vendor/<canonical>.zip` 兜底（五个必装核心 humanizer-zh / humanizer-zh-plus / humanizer / stop-slop / slop-gauge，均 MIT，原 LICENSE 随 zip 保留，上游挂掉/改名/删库时解压安装）。zip 形式是有意的：整仓保持两级目录（根目录/二级目录/文件），过 WorkBuddy 等平台的目录层级硬校验。铁律：vendor/ 只收 MIT 等可再分发许可证的核心包且 zip 内必须保留原 LICENSE；无 LICENSE 上游（de-ai-prompt-enhancer、chatgpt-comparison-detection）永不入 vendor
- **vendor 是快照，重打用 `.\pack-vendor.ps1`**（从 registry 里 `bundled: true` 条目的 repo 现拉 main/master 重打包，`-Check` 只报告哪些过期，`-Only <name>` 单打）；自研两条改了 SKILL.md 就必须 push → 重打 → 一起提交，否则兜底路径装出旧版
- 改完三个仓都要 `.\install.ps1 -CheckOnly` 收尾：LOAD-RISK 行不为空就说明某个技能装上了但 agent 看不见
