# de-ai-skills: the de-AI router

One line: **say "de-AI this article" and one router runs you through marking → rewrite → style injection → QA scoring.**

## Install

```powershell
# Windows
irm https://raw.githubusercontent.com/Chendestiny/de-ai-skills/main/install.ps1 | iex

# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/Chendestiny/de-ai-skills/main/install.sh | bash

# Dry run (no writes)
.\install.ps1 -CheckOnly      # or: bash install.sh --check
```

## What it is

`de-ai` is a router/combinator. It never rewrites a word itself; it routes by language and task, then orchestrates:

0. **Prevent (optional)**: optimize the draft prompt first (de-ai-prompt-enhancer), feed real material
1. **Mark**: flag AI patterns per the main skill's checklist
2. **One rewrite**: main skill rewrites in full, with a nuwa-distilled style profile injected as the "author sample" (one pass, both parameters — never two sequential rewriters fighting each other)
3. **QA gate (two arms)**: slop-gauge deterministic diff (AI-loanword density, punctuation, sentence-length CV; below 55 goes back) plus stop-slop quick checks and 5-dimension score (below 35/50 goes back)
4. **Deliver**: full text + change summary + scorecard + residual risks

## Sub-skills (registry.json is the source of truth)

Two of them are ours: humanizer-zh-plus and slop-gauge (`origin: self` in registry.json, MIT, same account, same cadence as this router).

| Skill | Role | Upstream | Status |
|---|---|---|---|
| humanizer-zh-plus | Chinese rewrite, the 24 base patterns plus Chinese-native tells, writing profiles and ad-law substitution | Chendestiny/humanizer-zh-plus | required (self) |
| humanizer-zh | Chinese rewrite base (fallback when plus is absent) | op7418/Humanizer-zh | required |
| humanizer | English rewrite (35 patterns) | blader/humanizer | required |
| stop-slop | QA scoring gate (LLM read) | hardikpandya/stop-slop | required |
| slop-gauge | QA scoring gate (deterministic meter, diff mode) | Chendestiny/slop-gauge | required (self) |
| nuwa-skill | style distillation | alchaincyf/nuwa-skill | optional |
| taste-skill | anti-slop frontend/UI | Leonxlnx/taste-skill | optional (alias design-taste-frontend counts as installed) |
| de-ai-prompt-enhancer | input-side prevention | gitliuyun/De-AI-Prompt-Enhancer-Writer-Booster-SKILL | optional |
| chatgpt-comparison-detection | pre-scan reference | Hello-SimpleAI/chatgpt-comparison-detection | deferred (upstream is an academic code repo, no SKILL.md) |

The installer skips what you already have (canonical or alias), fetches what is missing straight from upstream, and only reports deferred entries. Every copy it lands is then checked the way an agent loader checks it: the frontmatter must parse as YAML, carry a `description`, and name the skill in lowercase kebab-case matching its directory. Copies we just placed get repaired (`[fix]`); your own pre-existing files are only reported (`[warn]`, summarized as `LOAD-RISK`) — a skill that fails this is on disk but invisible to the agent, which is exactly what `install.ps1 -CheckOnly` is for.

## License

- This repo (router SKILL.md / registry.json / installers / docs): MIT — see [LICENSE](LICENSE)
- Sub-skills belong to their upstream authors and are fetched at install time; the three MIT cores (humanizer / humanizer-zh / stop-slop) are bundled as zips under `vendor/` with their LICENSEs kept (zip form keeps the repo two-level, which strict skill-market packagers require) as upstream-failure fallback. The two upstreams without a LICENSE file are fetch-at-install only — never copy them into a redistributing repo.
