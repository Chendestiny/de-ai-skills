# deai-skills: the de-AI router

One line: **say "de-AI this article" and one router runs you through marking → rewrite → style injection → QA scoring.**

## Install

```powershell
# Windows
irm https://raw.githubusercontent.com/Chendestiny/deai-skills/main/install.ps1 | iex

# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/Chendestiny/deai-skills/main/install.sh | bash

# Dry run (no writes)
.\install.ps1 -CheckOnly      # or: bash install.sh --check
```

## What it is

`de-ai` is a router/combinator. It never rewrites a word itself; it routes by language and task, then orchestrates:

0. **Prevent (optional)**: optimize the draft prompt first (de-ai-prompt-enhancer), feed real material
1. **Mark**: flag AI patterns per the main skill's checklist
2. **One rewrite**: main skill rewrites in full, with a nuwa-distilled style profile injected as the "author sample" (one pass, both parameters — never two sequential rewriters fighting each other)
3. **QA gate**: stop-slop quick checks + 5-dimension score; below 35/50 goes back to step 2
4. **Deliver**: full text + change summary + scorecard + residual risks

## Sub-skills (registry.json is the source of truth)

| Skill | Role | Upstream | Status |
|---|---|---|---|
| humanizer-zh | Chinese rewrite (24 patterns) | op7418/Humanizer-zh | required |
| humanizer | English rewrite (35 patterns) | blader/humanizer | required |
| stop-slop | QA scoring gate | hardikpandya/stop-slop | required |
| nuwa-skill | style distillation | alchaincyf/nuwa-skill | optional |
| taste-skill | anti-slop frontend/UI | Leonxlnx/taste-skill | optional (alias design-taste-frontend counts as installed) |
| de-ai-prompt-enhancer | input-side prevention | gitliuyun/De-AI-Prompt-Enhancer-Writer-Booster-SKILL | optional |
| chatgpt-comparison-detection | pre-scan reference | Hello-SimpleAI/chatgpt-comparison-detection | deferred (upstream is an academic code repo, no SKILL.md) |

The installer skips what you already have (canonical or alias), fetches what is missing straight from upstream, and only reports deferred entries.

## License

- This repo (router SKILL.md / registry.json / installers / docs): MIT — see [LICENSE](LICENSE)
- Sub-skills belong to their upstream authors and are fetched at install time; the three MIT cores (humanizer / humanizer-zh / stop-slop) are bundled as zips under `vendor/` with their LICENSEs kept (zip form keeps the repo two-level, which strict skill-market packagers require) as upstream-failure fallback. The two upstreams without a LICENSE file are fetch-at-install only — never copy them into a redistributing repo.
