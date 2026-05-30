#!/usr/bin/env zsh
# =============================================================================
#  opus48_runner.sh — cross-language tokenization benchmark for Claude Opus 4.8
#
#  Runs 9 summarization calls (3 source langs x 3 target langs) against the
#  Anthropic API and logs token usage, response length, time, and cost per run.
#  Purpose: split "thinking tokens" from "response tokens" — /usage in Claude
#  Code reports them combined.
#
#  Requires: zsh, curl, jq, python3, and $ANTHROPIC_API_KEY.
#  Needs source_en.txt / source_zh.txt / source_ja.txt in this directory.
#  Usage:    ./opus48_runner.sh        (results written to results.csv)
#  Cost:     ~$0.13 total at effort=medium; higher effort costs more.
# =============================================================================

set -euo pipefail   # exit on error, unset var, or failed pipe


# --- Config ------------------------------------------------------------------
MODEL="claude-opus-4-8"
CSV="results.csv"
MAX_TOKENS=16000          # output ceiling; raise to 64K for xhigh/max effort
EFFORT="medium"           # low | medium | high | xhigh | max

LANGS=(EN ZH JA)          # outer loop = source, inner loop = target
typeset -A FILES=(EN source_en.txt ZH source_zh.txt JA source_ja.txt)
typeset -A NAMES=(EN English      ZH Chinese        JA Japanese)

# Per-TARGET length target, tuned so all three convey roughly the SAME amount
# of information as a ~260-300 word English summary. This is the fair tokenizer
# comparison: hold content constant, see which language encodes it cheapest.
#
# Calibration (from measured runs): 280 English words ~= 2,200 chars of English
# prose. CJK packs ~1.5-2 words of meaning per character, so the same content is:
#   - Chinese  ~= 750-850 characters (densest script)
#   - Japanese ~= 850-950 characters (kana/particles run longer than Chinese)
# Earlier 280-300 and 400-460 CJK targets UNDER-produced vs English -> unfair.
typeset -A LENREQ=(
  EN "at least 260 words and at most 300 words"
  ZH "at least 750 characters and at most 850 characters"
  JA "at least 850 characters and at most 950 characters"
)

PRICE_IN_PER_M=5          # USD per 1M tokens (Opus 4.8)
PRICE_OUT_PER_M=25


# --- Pre-flight checks -------------------------------------------------------
: "${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY first (export ANTHROPIC_API_KEY=sk-...)}"
command -v jq >/dev/null || { echo "Install jq first: brew install jq"; exit 1; }
for L in $LANGS; do
  [[ -f "${FILES[$L]}" ]] || { echo "Missing file: ${FILES[$L]}"; exit 1; }
done


# --- CSV header + running totals ---------------------------------------------
echo "pattern,source,target,input_tokens,output_tokens,thinking_chars,response_chars,response_runes,response_words,elapsed_sec,response_text" > "$CSV"
TOTAL_IN=0
TOTAL_OUT=0
i=0


# --- Main 3x3 loop -----------------------------------------------------------
for SRC in $LANGS; do
  for TGT in $LANGS; do
    i=$((i+1))
    SRCFILE="${FILES[$SRC]}"
    TGTNAME="${NAMES[$TGT]}"
    TGTLEN="${LENREQ[$TGT]}"   # words for EN, characters for ZH/JA
    PATTERN="${SRC}->${TGT}"
    echo "[${i}/9] ${PATTERN} ..."

    # Build prompt. Length unit depends on target language (see LENREQ).
    # The prompt instruction is in English regardless of target.
    SRCTEXT=$(<"$SRCFILE")
    PROMPT="Read the following text and summarize in ${TGTNAME} in ${TGTLEN}.

---
${SRCTEXT}
---"

    # Build JSON payload. thinking=adaptive is the only mode Opus 4.8 allows;
    # display=summarized surfaces a reasoning summary (does NOT change billing).
    PAYLOAD=$(jq -n \
      --arg model "$MODEL" \
      --arg prompt "$PROMPT" \
      --arg effort "$EFFORT" \
      --argjson maxtok "$MAX_TOKENS" \
      '{
        model: $model,
        max_tokens: $maxtok,
        thinking: {type: "adaptive", display: "summarized"},
        output_config: {effort: $effort},
        messages: [{role: "user", content: $prompt}]
      }')

    # Send request, time it (whole-second resolution)
    START=$(date +%s)
    RESP=$(curl -sS https://api.anthropic.com/v1/messages \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      --data-binary "$PAYLOAD")
    END=$(date +%s)
    ELAPSED=$((END - START))

    # On API error: log, write partial CSV row, skip to next run
    if print -r -- "$RESP" | jq -e '.error' >/dev/null 2>&1; then
      ERR=$(print -r -- "$RESP" | jq -r '.error.message')
      echo "  ERROR: $ERR"
      print -r -- "${PATTERN},${SRC},${TGT},,,,,,,${ELAPSED},\"ERROR: ${ERR//\"/\"\"}\"" >> "$CSV"
      continue
    fi

    # Token counts. NOTE: output_tokens = thinking + response text, combined.
    IN_TOK=$(print -r -- "$RESP" | jq -r '.usage.input_tokens')
    OUT_TOK=$(print -r -- "$RESP" | jq -r '.usage.output_tokens')

    # Split response content blocks by type
    THINK_TEXT=$(print -r -- "$RESP" | jq -r '[.content[]? | select(.type=="thinking") | .thinking] | join("")')
    RESP_TEXT=$(print -r -- "$RESP" | jq -r '[.content[]? | select(.type=="text")     | .text]     | join("")')

    # Lengths. ${#var} = bytes (wrong for CJK); RESP_RUNES = real char count.
    THINK_CHARS=${#THINK_TEXT}
    RESP_CHARS=${#RESP_TEXT}
    RESP_RUNES=$(python3 -c "import sys; print(len(sys.stdin.read()))" <<< "$RESP_TEXT")
    # Word count (whitespace-split). Meaningful for EN target (verify >=260);
    # near-zero for CJK since those scripts don't space-separate words.
    RESP_WORDS=$(python3 -c "import sys; print(len(sys.stdin.read().split()))" <<< "$RESP_TEXT")

    # Accumulate totals + cost (Python: zsh can't do decimal math)
    TOTAL_IN=$((TOTAL_IN + IN_TOK))
    TOTAL_OUT=$((TOTAL_OUT + OUT_TOK))
    RUN_COST=$(python3 -c "print(f'{($IN_TOK * $PRICE_IN_PER_M + $OUT_TOK * $PRICE_OUT_PER_M) / 1000000:.4f}')")
    CUM_COST=$(python3 -c "print(f'{($TOTAL_IN * $PRICE_IN_PER_M + $TOTAL_OUT * $PRICE_OUT_PER_M) / 1000000:.4f}')")

    # Live status: this run + running total
    echo "  [${PATTERN}] this run -> input=${IN_TOK} tok | output=${OUT_TOK} tok | think_chars=${THINK_CHARS} | resp_chars=${RESP_CHARS} | runes=${RESP_RUNES} | words=${RESP_WORDS} | elapsed=${ELAPSED}s | cost=\$${RUN_COST}"
    echo "  [${PATTERN}] cumulative -> input=${TOTAL_IN} tok | output=${TOTAL_OUT} tok | total=$((TOTAL_IN + TOTAL_OUT)) tok | cost=\$${CUM_COST}"

    # Append CSV row (newlines -> spaces, " -> "" per RFC 4180)
    SAFE_RESP=${RESP_TEXT//$'\n'/ }
    SAFE_RESP=${SAFE_RESP//\"/\"\"}
    print -r -- "${PATTERN},${SRC},${TGT},${IN_TOK},${OUT_TOK},${THINK_CHARS},${RESP_CHARS},${RESP_RUNES},${RESP_WORDS},${ELAPSED},\"${SAFE_RESP}\"" >> "$CSV"
  done
done


# --- Final summary -----------------------------------------------------------
echo ""
echo "=========================================="
echo "Done. Results: ${CSV}"
echo "Grand total tokens: input=${TOTAL_IN} | output=${TOTAL_OUT} | total=$((TOTAL_IN + TOTAL_OUT))"
FINAL_COST=$(python3 -c "print(f'{($TOTAL_IN * $PRICE_IN_PER_M + $TOTAL_OUT * $PRICE_OUT_PER_M) / 1000000:.4f}')")
echo "Grand total cost: \$${FINAL_COST}"
echo "=========================================="
