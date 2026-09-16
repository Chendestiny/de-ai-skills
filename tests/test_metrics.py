# -*- coding: utf-8 -*-
"""deai-metrics 单测。stdlib unittest；断言不迁就实现，修阈值只去 PROFILES。"""
import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from deai_metrics import load_words, load_adlaw, strip_markup, split_sentences, \
    rhythm_metrics, word_hits, structure_metrics, punct_metrics, analyze  # noqa: E402

class TestLoad(unittest.TestCase):
    def test_loads_default_weight(self):
        w = load_words()
        self.assertIn("此外", w)
        self.assertGreaterEqual(w["此外"], 1)
    def test_adlaw_section_separate(self):
        a = load_adlaw()
        self.assertIn("国家级", a)
        self.assertNotIn("国家级", load_words())
    def test_no_junk_rows(self):
        w = load_words()
        self.assertNotIn("Seamless", w)
        self.assertFalse(any(k for k in w if not k.strip()))

class TestStrip(unittest.TestCase):
    def test_code_and_bold(self):
        t = "前文 `code x` 后文 ```py\nblock\n``` **粗**收"
        s = strip_markup(t)
        self.assertNotIn("code x", s)
        self.assertNotIn("block", s)
        self.assertNotIn("**", s)
        self.assertIn("粗", s)

class TestRhythm(unittest.TestCase):
    def test_split_and_cv(self):
        text = "甲甲甲甲甲。乙乙乙乙乙乙乙乙乙乙。丙丙丙丙丙丙丙丙丙丙丙丙丙丙丙。"
        ss = split_sentences(text)
        self.assertEqual(len(ss), 3)
        m = rhythm_metrics(ss)
        self.assertEqual(m["count"], 3)
        self.assertAlmostEqual(m["mean"], 10.0, places=1)
        self.assertGreater(m["cv"], 0.3)
    def test_equal_run(self):
        ss = ["甲" * 10, "乙" * 10, "丙" * 10, "丁" * 10]
        self.assertGreaterEqual(rhythm_metrics(ss)["max_equal_run"], 4)

class TestWordsStructure(unittest.TestCase):
    def test_word_hits_counts(self):
        w = {"此外": 2, "赋能": 1}
        r = word_hits("此外，此外，我们继续。赋能大局。此外。", w)
        self.assertEqual(r["top"][0], ["此外", 3])
        self.assertEqual(r["total"], 4)
    def test_triad_ordinal(self):
        t = "首先，看成本。其次，看稳定。最后，看交付。"
        m = structure_metrics(t, "generic")
        self.assertGreaterEqual(m["ordinal_chains"], 1)
        self.assertGreaterEqual(m["triads"], 1)
    def test_judgment_triads(self):
        m = structure_metrics("AI 的价值在于省钱，在于省时，在于省事。", "generic")
        self.assertGreaterEqual(m["judgment_triads"], 1)
    def test_negation_contrast(self):
        m = structure_metrics("这不仅是一次更新，更是一场革命。", "generic")
        self.assertGreaterEqual(m["negation_contrast"], 1)
    def test_vague_attribution(self):
        m = structure_metrics("研究表明，这样做更好。专家表示同意。", "generic")
        self.assertGreaterEqual(m["vague_attribution"], 2)
    def test_from_to(self):
        m = structure_metrics("从入门到精通，从想法到落地。", "generic")
        self.assertGreaterEqual(m["from_to_jumps"], 2)
    def test_stamp_open(self):
        m = structure_metrics("随着人工智能技术的发展，我们进入了新时代。", "generic")
        self.assertGreaterEqual(m["stamp_open"], 1)

class TestPunctScore(unittest.TestCase):
    def test_emdash_density_penalized(self):
        t = "甲——乙——丙——丁。戊——己。"
        p = punct_metrics(t, "generic")
        self.assertEqual(p["emdash"], 4)
        a = analyze(t, "generic")
        self.assertLess(a["score"], 90)
    def test_novel_exempts_quoted(self):
        t = "他说：“干得好！”——然后走了。"
        self.assertEqual(punct_metrics(t, "novel")["exclaim"], 0)
        self.assertEqual(punct_metrics(t, "generic")["exclaim"], 1)
    def test_ecommerce_adlaw_heavy(self):
        t = "国家级品质，全网最低价。"
        a_ec = analyze(t, "ecommerce")
        a_ge = analyze(t, "generic")
        self.assertIn("国家级", a_ec["adlaw"]["hits"])
        self.assertLess(a_ec["score"], a_ge["score"])
    def test_clean_scores_high(self):
        clean = ("用过三台后我留了这台。前两台一台慢、一台贵。"
                 "这块屏幕不发光，看久了眼睛不累。充一次电能用几个星期。")
        self.assertGreaterEqual(analyze(clean, "generic")["score"], 70)
    def test_slop_scores_low(self):
        slop = ("在当今数字化浪潮席卷全球的时代，我们见证了深刻变革。"
                "与此同时，随着人工智能技术的持续深化，各行各业正在重塑格局。"
                "毋庸置疑，其核心在于赋能与闭环的深度融合。"
                "研究表明，这至关重要。总而言之，未来会更加美好。"
                "展望未来，让我们携手拥抱美好明天。这标志着新篇章的全面开启。")
        self.assertLess(analyze(slop, "generic")["score"], 50)

class TestCLI(unittest.TestCase):
    def _run(self, *args, **kw):
        return subprocess.run(
            [sys.executable, str(REPO / "scripts" / "deai_metrics.py"), *args],
            capture_output=True, text=True, encoding="utf-8", **kw)
    def test_json_stdin(self):
        r = self._run("-", "--json", input="此外，值得注意的是，这一格局值得深入探讨。综上所述，节奏平稳。")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = json.loads(r.stdout.splitlines()[-1])
        self.assertLess(d["score"], 100)
        self.assertIn("此外", d["words"]["hits"])
    def test_diff_mode(self):
        a = REPO / "tests" / "_s_ai.txt"; a.write_text("此外，值得注意的是，赋能了闭环。综上所述。", encoding="utf-8")
        b = REPO / "tests" / "_s_ok.txt"; b.write_text("我试过。慢，但是稳。充一次电能用几周。", encoding="utf-8")
        r = self._run("--diff", str(a), str(b))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("→", r.stdout)
        a.unlink(); b.unlink()
    def test_batch_dir(self):
        d = REPO / "tests" / "_batch"; d.mkdir(exist_ok=True)
        p = d / "x.md"; p.write_text("此外，赋能。综上所述。", encoding="utf-8")
        r = self._run("--batch", str(d), "--json")
        self.assertEqual(r.returncode, 0, r.stderr)
        d2 = json.loads(r.stdout.splitlines()[-1])
        self.assertIn("files", d2)
        self.assertIn("x.md", d2["files"])
        p.unlink()

if __name__ == "__main__":
    unittest.main()
