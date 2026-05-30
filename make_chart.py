#!/usr/bin/env python3
"""Generate a bar chart (SVG) of average output tokens per target language.

Dependency-free — writes hand-built SVG so it renders crisply on GitHub and
stays diff-able as text. Data is the equal-content Opus 4.8 run.
Usage: python3 make_chart.py  ->  writes output_tokens_by_language.svg
"""

# Average output tokens per TARGET language (equal-information run).
DATA = [
    ("English",  690, "1.00x (cheapest)"),
    ("Japanese", 851, "1.23x"),
    ("Chinese",  888, "1.29x"),
]
BAR_COLOR = ["#2e7d32", "#ef6c00", "#c62828"]  # green / orange / red

# Layout
W, H = 720, 440
PAD_L, PAD_R, PAD_T, PAD_B = 70, 30, 70, 80
plot_w = W - PAD_L - PAD_R
plot_h = H - PAD_T - PAD_B
y_max = 1000          # round ceiling above 888
bar_w = 110
gap = (plot_w - bar_w * len(DATA)) / (len(DATA) + 1)


def y(val):
    return PAD_T + plot_h * (1 - val / y_max)


parts = []
parts.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
    f'viewBox="0 0 {W} {H}" font-family="-apple-system,Segoe UI,Helvetica,Arial,sans-serif">'
)
parts.append(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

# Title
parts.append(
    f'<text x="{W/2}" y="34" text-anchor="middle" font-size="20" '
    f'font-weight="700" fill="#1a1a1a">Avg output tokens for equal content '
    f'(Claude Opus 4.8)</text>'
)

# Y gridlines + labels
for t in range(0, y_max + 1, 200):
    yy = y(t)
    parts.append(
        f'<line x1="{PAD_L}" y1="{yy:.1f}" x2="{W-PAD_R}" y2="{yy:.1f}" '
        f'stroke="#e0e0e0" stroke-width="1"/>'
    )
    parts.append(
        f'<text x="{PAD_L-10}" y="{yy+4:.1f}" text-anchor="end" font-size="12" '
        f'fill="#666">{t}</text>'
    )

# Y axis title
parts.append(
    f'<text x="18" y="{PAD_T+plot_h/2:.1f}" text-anchor="middle" font-size="12" '
    f'fill="#666" transform="rotate(-90 18 {PAD_T+plot_h/2:.1f})">output tokens</text>'
)

# Bars
x = PAD_L + gap
for (label, val, rel), color in zip(DATA, BAR_COLOR):
    by = y(val)
    bh = (PAD_T + plot_h) - by
    parts.append(
        f'<rect x="{x:.1f}" y="{by:.1f}" width="{bar_w}" height="{bh:.1f}" '
        f'rx="4" fill="{color}"/>'
    )
    # value on top of bar
    parts.append(
        f'<text x="{x+bar_w/2:.1f}" y="{by-22:.1f}" text-anchor="middle" '
        f'font-size="18" font-weight="700" fill="#1a1a1a">{val}</text>'
    )
    # relative multiplier
    parts.append(
        f'<text x="{x+bar_w/2:.1f}" y="{by-6:.1f}" text-anchor="middle" '
        f'font-size="12" fill="#666">{rel}</text>'
    )
    # language label under axis
    parts.append(
        f'<text x="{x+bar_w/2:.1f}" y="{PAD_T+plot_h+26:.1f}" text-anchor="middle" '
        f'font-size="15" font-weight="600" fill="#1a1a1a">{label}</text>'
    )
    x += bar_w + gap

# X axis line
parts.append(
    f'<line x1="{PAD_L}" y1="{PAD_T+plot_h:.1f}" x2="{W-PAD_R}" '
    f'y2="{PAD_T+plot_h:.1f}" stroke="#999" stroke-width="1.5"/>'
)

# Caption
parts.append(
    f'<text x="{W/2}" y="{H-18}" text-anchor="middle" font-size="12" fill="#888">'
    f'Same information content per summary (~280 English words). Lower = more efficient.</text>'
)

parts.append('</svg>')

with open("output_tokens_by_language.svg", "w") as f:
    f.write("\n".join(parts))

print("Wrote output_tokens_by_language.svg")
