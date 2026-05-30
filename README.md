# Cross-Language Token Efficiency on Claude Opus 4.8

Does an LLM really use fewer tokens in English? This repo measures how many **output tokens** Claude Opus 4.8 spends to produce the **same summary content** in English, Japanese, and Chinese — and contains the raw data, the script, and the source texts so you can reproduce it.

**Short answer:** For an equal amount of information, **English is the most token-efficient.** Japanese costs ~1.23× and Chinese ~1.29× the output tokens of English for the same content.

> ⚠️ **A note on honesty:** the first version of this experiment produced the *opposite* result — "Chinese costs 3× more." That was a measurement bug: targeting an equal **character count** across languages is unfair, because 280 characters of Chinese carries ~5× the information of 280 characters of English. After equalizing the *information content* instead, the result flipped. Both the bug and the fix are documented below — that story is half the point.

## Results

Average output tokens per **target** language, with every summary carrying roughly the same information (~280 English words' worth):

| Output language | Avg output tokens | vs English | Content produced |
|-----------------|-------------------|------------|------------------|
| 🇺🇸 English  | **690** | **1.00× (cheapest)** | 272–277 words |
| 🇯🇵 Japanese | 851 | 1.23× | ~890–955 characters |
| 🇨🇳 Chinese  | 888 | 1.29× | ~865–936 characters |

The cost is driven by the **output** language, not the input language — generating English was cheapest regardless of what language was read.

Full per-run data is in [`results.csv`](results.csv).

## The method, and the bug

The experiment runs a 3×3 matrix: read a source text in {EN, ZH, JA}, summarize it into {EN, ZH, JA} = 9 runs.

**The trap:** the first version asked every language for "280–300 characters." But:
- English 280 chars ≈ **~50 words** (a couple of sentences)
- CJK 280 chars ≈ **~250+ words of meaning** (a full paragraph — one CJK char ≈ one word)

So it compared a short English note against a full Chinese paragraph and concluded Chinese was "3× more expensive." It was measuring unequal content, not the tokenizer.

**The fix:** target each language for equal *information* (~280 English words):
- English: 260–300 **words**
- Chinese: 750–850 **characters**
- Japanese: 850–950 **characters**

With content held constant, the real result emerges: English encodes a given amount of meaning in the fewest tokens.

## What's in this repo

| File | Description |
|------|-------------|
| [`opus48_runner.sh`](opus48_runner.sh) | The experiment driver — zsh + `curl` + `jq`. Loops the 9 patterns, calls the Anthropic API, logs tokens/cost to CSV. |
| [`results.csv`](results.csv) | Raw data, one row per pattern: input/output tokens, thinking chars, response chars/runes/words, elapsed time, full response text. |
| `source_en.txt` / `source_ja.txt` / `source_zh.txt` | The input corpus — the same content (AWS "Claude on Amazon Bedrock" product copy) in three languages, trimmed to the sections common to all three. |

## Reproduce it

Requirements: `zsh`, `curl`, `jq`, `python3`, and an Anthropic API key.

```sh
# 1. Install jq if needed
brew install jq

# 2. Set your API key (the script reads it from the environment — never hardcode it)
export ANTHROPIC_API_KEY=sk-ant-...

# 3. Run
./opus48_runner.sh
```

Output is written to `results.csv`, and per-run token counts + a running cost total print to the terminal as it goes. All 9 runs cost ~$0.25 at `effort=medium`.

## Caveats

- **n=1 per cell** — each pattern ran once. The English-is-cheapest result was consistent across all three input languages (690 ± 30 tokens), but it's a single run per cell.
- **Equal-content is approximate** — "750 Chinese chars ≈ 280 English words" is a calibrated estimate, not an exact information measure. The ~20–30% gap is large enough to survive reasonable calibration error.
- **One text type** — AWS product copy. Code or prose may behave differently.
- **`effort=medium`, Opus 4.8 only** — no non-thinking / Sonnet / Haiku baseline.
- **CSV column notes:** `response_runes` is the true character count; `response_chars` is byte-length (~3 bytes per CJK char, so it reads large for CJK). `response_words` is only meaningful for English (CJK has no spaces between words).

## License

[MIT](LICENSE) — do whatever you like with the data and script.
