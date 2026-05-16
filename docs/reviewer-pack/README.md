# Reviewer pack — planning-optimizer

Source for the planning-optimizer review document. Produces a corporate-style
PDF for an external domain reviewer (planning / supply chain / manufacturing /
BC standard practice). The ADRs under `../adr/` and `../../CONTEXT.md` remain
the source of truth for architectural decisions; this pack is a composed
*snapshot* of those decisions tailored to a non-developer reviewer.

## Layout

```
docs/reviewer-pack/
├── README.md                 (this file)
├── source.md                 (the composed reviewer-pack markdown)
├── diagrams/
│   ├── 01-pipeline.mmd
│   ├── 02-ltd-bootstrap.mmd
│   ├── 03-confidence-cascade.mmd
│   ├── 04-recommendation-lifecycle.mmd
│   └── 05-reason-code-attribution.mmd
└── (generated artifacts, gitignored)
    ├── diagrams/*.png
    └── reviewer-pack.pdf
```

## Regenerate

One-time installs (Arch Linux):

```bash
# Pandoc + TeX Live (markdown → PDF via xelatex)
sudo pacman -S --needed pandoc-cli texlive-basic texlive-latexrecommended \
                        texlive-fontsrecommended texlive-fontsextra \
                        texlive-latexextra texlive-xetex

# Mermaid CLI (renders .mmd → .png) — needs nodejs + npm
sudo pacman -S --needed nodejs npm
npm install -g @mermaid-js/mermaid-cli

# Eisvogel pandoc template — distributed as a release tarball, not raw on master
mkdir -p ~/.local/share/pandoc/templates
EISVOGEL_VER="3.4.0"
curl -sLo /tmp/eisvogel.tar.gz \
  "https://github.com/Wandmalfarbe/pandoc-latex-template/releases/download/v${EISVOGEL_VER}/Eisvogel.tar.gz"
tar xzf /tmp/eisvogel.tar.gz -C /tmp/ "Eisvogel-${EISVOGEL_VER}/eisvogel.latex"
cp "/tmp/Eisvogel-${EISVOGEL_VER}/eisvogel.latex" ~/.local/share/pandoc/templates/
```

`texlive-meta` pulls everything in one hammer if you prefer.

Build the PDF:

```bash
cd docs/reviewer-pack

# 1. Render diagrams (PNG, not SVG — see note below)
for f in diagrams/*.mmd; do
  mmdc -i "$f" -o "${f%.mmd}.png" -t neutral -b transparent -w 2400
done

# 2. Compile PDF
pandoc source.md \
  --from markdown --to pdf --template eisvogel --pdf-engine xelatex \
  --variable mainfont="Noto Sans" \
  --variable sansfont="Noto Sans" \
  --variable monofont="Fira Code" \
  --variable colorlinks=true \
  --variable titlepage=true \
  --variable titlepage-rule-color="555555" \
  --variable toc=true --variable toc-own-page=true \
  --variable book=true \
  --variable disable-header-and-footer=false \
  --number-sections \
  --output reviewer-pack.pdf
```

### Font choices

Noto Sans / Fira Code are used because they're available on a stock Arch
install (`ttf-fira-code` plus the Noto Sans family that comes with most
desktop setups). Adobe's *Source Sans Pro* / *Source Code Pro* would
match the corporate register slightly better — install via
`sudo pacman -S adobe-source-sans-fonts adobe-source-code-pro-fonts`
then swap the `--variable` values in the invocation above.

### Glyph fallback

`source.md`'s YAML header includes a `newunicodechar` block that maps
mathematical symbols (→, ≥, ≤, ⌈, ⌉, α, β, μ, σ, √, Δ, Σ) to
*Noto Sans Math* or *Noto Sans Symbols*. Noto Sans Regular doesn't
carry these glyphs and would emit *missing-character* warnings; the
fallback definitions prevent that. If the font choice changes, audit
the fallback block — DejaVu Sans, for example, has these glyphs natively
and would let the block be deleted.

## Conventions used in `source.md`

- **Voice**: neutral declarative with selective first-person plural at
  rationale moments. *"The engine targets a per-class service level..."*
  (neutral) but *"We chose Stance A over total-cost minimization
  because..."* (first-person, for decision context).
- **Numbering**: chapters are numbered via pandoc's `--number-sections`.
  Decisions inside chapters carry the chapter-relative number (e.g.
  *Decision 4.1, 4.2*) so the reviewer's comments are addressable.
- **BC references**: `Item.Reorder Point`, `Stockkeeping Unit`,
  `Production Order Header.Finishing Date`, `Codeunit 99000854 Inventory
  Profile Offsetting`, `Codeunit 5790 Available to Promise` — used
  literally, not translated into generic language. The reviewer reads BC
  field names natively.
- **No code references**: AL object IDs, Python file paths, package
  layout from [ADR 0009](../adr/0009-python-package-with-api-and-file-seam.md)
  are out. The reviewer is non-developer.
- **Diagrams**: five PNG references embedded inline. Each renders from a
  single `.mmd` source in `diagrams/` via `mmdc`. PNG rather than SVG
  because Mermaid's SVG output uses `<foreignObject>` HTML elements for
  label rendering — those embed cleanly in browsers, but `librsvg` (the
  SVG renderer pandoc + xelatex falls back to) strips them, producing
  empty boxes. Rasterising to PNG sidesteps the issue; text is baked
  into pixels at render time. Width 2400 px keeps the embed crisp on
  print.

## Feedback workflow

The reviewer returns the PDF with inline annotations (Adobe Acrobat,
Foxit, or Apple Preview comments). Feedback flows back to the ADRs and
[CONTEXT.md](../../CONTEXT.md); a regenerated PDF goes out for round 2 if
substantive changes warrant.
