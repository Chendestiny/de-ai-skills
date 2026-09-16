# -*- coding: utf-8 -*-
"""de-ai-metrics: 中文文本 AI 痕迹确定性量化（DE-AI 流水线内置质检件）。纯 stdlib，零联网。

测量，不判断，不改写。同一段文本必出同一个分数；前后两版给同一张表上的数字变化。
门禁语义：本脚本 ≥55 为机械参考线，与 stop-slop 五维评分构成 de-ai 双道门禁；
检测器（朱雀等）永远不是判据。词源：humanizer-zh SKILL.md §7 AI 词汇 +
stop-slop phrases 折算 + RobinZorro86/humanizer-zh-plus Pattern34 四字格（致谢）。
"""
import argparse
import json
import re
import statistics
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent / "ai_words_zh.txt"

def load_words(path=None):
    """读通用词表：每行「词 空格 权重(默认1)」。# 注释，-- adlaw 段归 load_adlaw。"""
    path = Path(path) if path else DATA
    words, section = {}, ""
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("--"):
            section = line.split()[-1] if len(line.split()) > 1 else ""
            continue
        if section == "adlaw":
            continue
        parts = line.split()
        words[parts[0]] = int(parts[1]) if len(parts) > 1 else 1
    return words

def load_adlaw(path=None):
    """只取 -- adlaw 段：广告法极限词，ecommerce 场景重罚，多数场景仅提示。"""
    path = Path(path) if path else DATA
    words, section = {}, ""
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("--"):
            section = line.split()[-1] if len(line.split()) > 1 else ""
            continue
        if section == "adlaw":
            parts = line.split()
            words[parts[0]] = int(parts[1]) if len(parts) > 1 else 1
    return words

RE_CODE_BLOCK = re.compile(r"```.*?```", re.S)
RE_INLINE_CODE = re.compile(r"`[^`\n]+`")
RE_TABLE_SEP = re.compile(r"^\|[-: |\|]+\|$", re.M)
RE_MD_MARKS = re.compile(r"\*|_#>`")
RE_SENTENCE = re.compile(r"[^。！？!?；;…\n]{4,}[。！？!?；;…]?")

def strip_markup(text):
    t = RE_CODE_BLOCK.sub(" ", text)
    t = RE_INLINE_CODE.sub(" ", t)
    t = RE_TABLE_SEP.sub(" ", t)
    t = re.sub(r"\*\*([^*\n]+?)\*\*", r"\1", t)   # 剥粗体符号，留粗体文字
    t = re.sub(r"[*_`>#]", " ", t)
    return t

def split_sentences(text):
    out = []
    for s in RE_SENTENCE.findall(text):
        s = s.rstrip("。！？!?；;…").strip()
        if s:
            out.append(s)
    return out

def rhythm_metrics(sentences):
    lens = [len(s) for s in sentences]
    count = len(lens)
    mean = float(statistics.mean(lens)) if lens else 0.0
    stdev = float(statistics.pstdev(lens)) if count >= 2 else 0.0
    cv = round(stdev / mean, 3) if mean else 0.0
    best = run = 1
    for prev, cur in zip(lens, lens[1:]):
        run = run + 1 if abs(cur - prev) <= 1 else 1
        best = max(best, run)
    if count < 2:
        best = 1 if count else 0
    return {"count": count, "mean": round(mean, 2), "stdev": round(stdev, 2),
            "cv": cv, "max_equal_run": best}

RE_BOLD = re.compile(r"\*\*[^*\n]+\*\*")
RE_EMDASH = re.compile(r"——|--|—")
RE_EXCLAIM = re.compile(r"[！!]")
RE_CURLY = re.compile(r"[“”]")
RE_ELLIPSIS = re.compile(r"……")
RE_QUOTES = re.compile(r"[“”][^“”]*[“”]")

def punct_metrics(text, profile="generic"):
    flat = strip_markup(text)
    flat_no_dialog = RE_QUOTES.sub("", flat) if profile == "novel" else flat
    em_all = len(RE_EMDASH.findall(flat))
    em_sc = len(RE_EMDASH.findall(flat_no_dialog))
    chars = max(1, len(flat))
    return {
        "emdash": em_all,
        "em_per_1000": round(em_all / chars * 1000, 2),
        "em_scored": em_sc,
        "em_scored_per_1000": round(em_sc / chars * 1000, 2),
        "bold": len(RE_BOLD.findall(flat)),
        "exclaim": len(RE_EXCLAIM.findall(flat_no_dialog)),
        "curly": len(RE_CURLY.findall(flat)),
        "ellipsis": len(RE_ELLIPSIS.findall(flat)),
    }

TRIAD_PATTERNS = [
    re.compile(r"首先[^。]{1,40}[。；;]\s*其次[^。]{1,40}[。；;]\s*最后"),
    re.compile(r"一是[^。]{1,30}[。；;]二是[^。]{1,30}[。；;]三是"),
    re.compile(r"第一[，,][^。]{1,30}[。；;]第二[，,][^。]{1,30}[。；;]第三"),
]
# 机械三连（RobinZorro86 Pattern36 同源概念）：同一引导词三连判断句：在于…，在于…，在于…
RE_TRIAD_JUDGE = re.compile(r"(在于|堪称|是|有|能|为|会)[^，。；]{1,10}[，,]\1[^，。；]{1,10}[，,]\1[^。；]{1,30}")
RE_NEG_CONTRAST = re.compile(r"[不不仅][是仅]?[^。；;\n]{0,15}[，,]?[而更又还]是[^。]{1,18}")
RE_VAGUE = re.compile(r"(研究表明|有(研究|调查|报道)(显示|表明)|专家(们)?(指出|表示|认为)|业内(人士)?(表示|指出|认为)|有(观(察|点)|评论|人)(认为|指出|直言)|不少(网友|用户|读者)(认为|反驳))")
RE_FROM_TO = re.compile(r"从[^，。；;!?\n]{2,10}到[^，。；;!?\n]{2,14}[。；;,，!?\n]")
RE_STAMP_OPEN = re.compile(r"随着[^。]{2,12}的(发展|普及|兴起)[，,]|在这个[^，。]{2,10}的时代[，,]")
RE_LIFT_END = re.compile(r"(开启[^。]{0,12}新篇章|共同期待|值得深思|我们相信，在|展望未来|新篇章)")

def word_hits(text, words):
    hits, total = {}, 0
    for w in words:
        n = text.count(w)
        if n:
            hits[w] = n
            total += n
    per1k = round(total / max(1, len(text)) * 1000, 2)
    top = [[w, n] for w, n in sorted(hits.items(), key=lambda kv: -kv[1])[:8]]
    return {"hits": hits, "total": total, "per_1000": per1k, "top": top}

def structure_metrics(text, profile="generic"):
    flat = strip_markup(text)
    return {
        "triads": sum(len(p.findall(flat)) for p in TRIAD_PATTERNS),
        "judgment_triads": len(RE_TRIAD_JUDGE.findall(flat)),
        "negation_contrast": len(RE_NEG_CONTRAST.findall(flat)),
        "ordinal_chains": sum(1 for p in TRIAD_PATTERNS if p.search(flat)),
        "vague_attribution": len(RE_VAGUE.findall(flat)),
        "from_to_jumps": len(RE_FROM_TO.findall(flat + "。")),
        "stamp_open": len(RE_STAMP_OPEN.findall(flat)),
        "lift_end": len(RE_LIFT_END.findall(flat)),
    }

# 权重集中一处；三档键名逐字一致；校准只改这里，不改断言
PROFILES = {
    "generic":   {"ai_words": 6.0, "em_over_1": 4.0, "bold_over": 2.0, "exclaim": 1.5,
                  "triad": 2.0, "neg": 2.5, "ordinal": 2.0, "vague": 2.0, "ft": 1.0,
                  "stamp_open": 2.5, "lift_end": 2.0, "adlaw": 4.0,
                  "cv_hard": 18, "cv_soft": 8, "cv_hard_at": 0.15, "cv_soft_at": 0.25, "eqrun": 10},
    "novel":     {"ai_words": 5.0, "em_over_1": 2.0, "bold_over": 2.0, "exclaim": 0.0,
                  "triad": 1.0, "neg": 2.0, "ordinal": 1.0, "vague": 2.0, "ft": 1.0,
                  "stamp_open": 2.5, "lift_end": 2.0, "adlaw": 4.0,
                  "cv_hard": 15, "cv_soft": 6, "cv_hard_at": 0.12, "cv_soft_at": 0.22, "eqrun": 10},
    "ecommerce": {"ai_words": 6.0, "em_over_1": 4.0, "bold_over": 2.0, "exclaim": 1.5,
                  "triad": 2.0, "neg": 2.5, "ordinal": 2.0, "vague": 2.0, "ft": 1.0,
                  "stamp_open": 2.0, "lift_end": 2.0, "adlaw": 10.0,
                  "cv_hard": 18, "cv_soft": 8, "cv_hard_at": 0.15, "cv_soft_at": 0.25, "eqrun": 10},
}

def calc_score(m, profile):
    w = PROFILES[profile]
    p = 0.0
    p += min(55.0, m["words"]["per_1000"] * w["ai_words"])
    p += max(0.0, m["punct"]["em_scored_per_1000"] - 1.0) * w["em_over_1"]
    p += max(0, m["punct"]["bold"] - 2) * w["bold_over"]
    p += m["punct"]["exclaim"] * w["exclaim"]
    p += m["structure"]["triads"] * w["triad"]
    p += m["structure"]["negation_contrast"] * w["neg"]
    p += m["structure"]["ordinal_chains"] * w["ordinal"]
    p += m["structure"]["vague_attribution"] * w["vague"]
    p += m["structure"]["from_to_jumps"] * w["ft"]
    p += m["structure"]["stamp_open"] * w["stamp_open"]
    p += m["structure"]["lift_end"] * w["lift_end"]
    p += m["adlaw"]["total"] * w["adlaw"]
    if m["rhythm"]["count"] >= 3:            # 句数不足时 CV 无信号，不判
        cv = m["rhythm"]["cv"]
        if cv < w["cv_hard_at"]:
            p += w["cv_hard"]
        elif cv < w["cv_soft_at"]:
            p += w["cv_soft"]
        if m["rhythm"]["max_equal_run"] >= 4:
            p += w["eqrun"]
    return max(0, round(100 - p))

def analyze(text, profile="generic"):
    flat = strip_markup(text)
    m = {
        "profile": profile,
        "chars": len(flat),
        "words": word_hits(flat, load_words()),
        "adlaw": word_hits(flat, load_adlaw()) if profile == "ecommerce" else {"total": 0},
        "punct": punct_metrics(text, profile),
        "rhythm": rhythm_metrics(split_sentences(flat)),
        "structure": structure_metrics(flat, profile),
    }
    m["score"] = calc_score(m, profile)
    return m

def fmt_report(m, title=""):
    w, p, r, s = m["words"], m["punct"], m["rhythm"], m["structure"]
    head = f"de-ai-metrics  profile={m['profile']}"
    rows = [
        f"字数 {m['chars']}  句数 {r['count']}  句长CV {r['cv']}（≥0.25 视为节奏良）  连续等长 {r['max_equal_run']}",
        f"AI高频词: {w['total']} 处 / 千字 {w['per_1000']}  高位: {w['top']}",
        f"标点: 破折号 {p['emdash']}（{p['em_per_1000']}/千字） 粗体 {p['bold']} 感叹号 {p['exclaim']} 弯引号 {p['curly']}",
        f"结构: 三段式 {s['triads']} 判断排比 {s['judgment_triads']} 否定排比 {s['negation_contrast']} 序数链 {s['ordinal_chains']} 模糊归因 {s['vague_attribution']} 从X到Y {s['from_to_jumps']} 套路开头 {s['stamp_open']} 升华结尾 {s['lift_end']}",
        f"得分 {m['score']}/100（≥55 机械参考线；门禁语义见 de-ai 路由 SKILL.md）",
    ]
    return head + "\n" + "\n".join(rows) + (f"\n{title}" if title else "")

def fmt_diff(ma, mb):
    pairs = [
        ("AI高频密度/千字", ma["words"]["per_1000"], mb["words"]["per_1000"]),
        ("破折号/千字", ma["punct"]["em_per_1000"], mb["punct"]["em_per_1000"]),
        ("粗体", ma["punct"]["bold"], mb["punct"]["bold"]),
        ("句长CV", ma["rhythm"]["cv"], mb["rhythm"]["cv"]),
        ("三段式", ma["structure"]["triads"], mb["structure"]["triads"]),
        ("判断排比", ma["structure"]["judgment_triads"], mb["structure"]["judgment_triads"]),
        ("否定排比", ma["structure"]["negation_contrast"], mb["structure"]["negation_contrast"]),
        ("模糊归因", ma["structure"]["vague_attribution"], mb["structure"]["vague_attribution"]),
        ("升华结尾", ma["structure"]["lift_end"], mb["structure"]["lift_end"]),
        ("总分", ma["score"], mb["score"]),
    ]
    lines = ["de-ai-metrics diff（原文 → 改后）"]
    for label, k1, k2 in pairs:
        arrow = "↓" if k2 < k1 else ("↑" if k2 > k1 else "→")
        lines.append(f"  {label}: {k1} → {k2}  {arrow}")
    verdict = "更像真人了 ✅" if mb["score"] > ma["score"] and mb["words"]["per_1000"] <= ma["words"]["per_1000"] else "数字没变好，回去重改"
    lines.append(f"  总评: 原文 {ma['score']} → 改后 {mb['score']}（{verdict}）")
    return "\n".join(lines)

def main(argv=None):
    ap = argparse.ArgumentParser(prog="de-ai-metrics", description="中文 AI 痕迹确定性量化（纯 stdlib）")
    ap.add_argument("file", nargs="?", help="文件路径，或 - 表示 stdin")
    ap.add_argument("--batch", help="目录，扫 *.md/*.txt")
    ap.add_argument("--diff", nargs=2, metavar=("A", "B"), help="改写前后对比")
    ap.add_argument("--profile", choices=list(PROFILES), default="generic")
    ap.add_argument("--json", action="store_true", help="输出 JSON（--batch 时包一层 files）")
    ns = ap.parse_args(argv)
    if ns.diff:
        ma = analyze(Path(ns.diff[0]).read_text(encoding="utf-8"), ns.profile)
        mb = analyze(Path(ns.diff[1]).read_text(encoding="utf-8"), ns.profile)
        print(json.dumps({"a": ma, "b": mb}, ensure_ascii=False) if ns.json else fmt_diff(ma, mb))
        return 0
    texts = []
    if ns.batch:
        for p in sorted(Path(ns.batch).glob("*.md")) + sorted(Path(ns.batch).glob("*.txt")):
            texts.append((p.name, p.read_text(encoding="utf-8")))
    elif ns.file in (None, "-"):
        texts.append(("<stdin>", sys.stdin.buffer.read().decode("utf-8", errors="replace")))
    else:
        texts.append((Path(ns.file).name, Path(ns.file).read_text(encoding="utf-8")))
    if ns.json:
        if texts and texts[0][0] == "<stdin>":
            print(json.dumps(analyze(texts[0][1], ns.profile), ensure_ascii=False))
        else:
            out = {name: analyze(t, ns.profile) for name, t in texts}
            print(json.dumps({"files": out} if ns.batch else out, ensure_ascii=False))
    else:
        for name, t in texts:
            print(fmt_report(analyze(t, ns.profile), name if name != "<stdin>" else ""))
    return 0

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8") if hasattr(sys.stdout, "reconfigure") else None
    sys.stderr.reconfigure(encoding="utf-8") if hasattr(sys.stderr, "reconfigure") else None
    sys.exit(main())
