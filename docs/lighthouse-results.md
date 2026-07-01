# Lighthouse results — landing SEO/a11y/CWV pass

Measured locally with Lighthouse (Chromium headless) against `npx serve .` on port 3456.

## Before / after scores

| Page | Metric | Before | After | Δ |
| --- | --- | ---: | ---: | ---: |
| `/` (index.html) | Performance | 85 | 83–96* | within variance |
| `/` (index.html) | Accessibility | 91 | 94 | +3 |
| `/` (index.html) | SEO | 90 | 100 | +10 |
| `/privacy` | Performance | 91 | 99 | +8 |
| `/privacy` | Accessibility | 93 | 95 | +2 |
| `/privacy` | SEO | 90 | 100 | +10 |

\*Index Performance varies ±10 points run-to-run on this VM (sample: 83, 86, 87, 96); no sustained regression observed.

## Remaining items below 95 A11y

- **`index.html` (94):** `color-contrast` on muted footer/trust copy and accent links — documented in `docs/a11y-color-contrast-report.md`; fix deferred to a design pass (work-order guardrail).
- **`privacy.html` (95):** at threshold; `color-contrast` on section numbers and table headers remains (same report).

## Screenshots

Before/after pairs: `docs/lighthouse-screenshots/before/` and `docs/lighthouse-screenshots/after/`.

## Production domain

Canonical URLs, `sitemap.xml`, and `robots.txt` use **`https://www.withsavvy.ai`** (Cloudflare Pages custom domain per deploy config).
