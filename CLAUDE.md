# CLAUDE.md

## Project overview

Two standalone tools for analyzing Tecan i-control kinetic (absorbance) growth curve exports:

- **`tecan_growth_analyzer_live.html`** — single-file browser app; no install; supports live auto-refresh during a Tecan run via the File System Access API (Chrome/Edge only).
- **`tecan_streamlit.py`** — Python/Streamlit app with mechanistic growth-model fits (Gompertz, logistic), bootstrap CIs, AIC-based model comparison, and per-well fitting.

## Inputs

Both tools take the same two `.xlsx` files:

1. **Tecan i-control kinetic export** — the parser auto-detects the `Cycle Nr.` / `Time [s]` block, handles single- and multi-label exports, and supports plates up to 384 wells.
2. **Plate layout workbook** with three sheets: `Strains`, `Dilutions`, `Media` — each an 8×12 grid with `A`–`H` in column A and `1`–`12` in row 1.

## Running the Streamlit app

```bash
pip install streamlit pandas numpy scipy openpyxl plotly
streamlit run tecan_streamlit.py
```

## Architecture

### `tecan_streamlit.py`

| Section | Description |
|---|---|
| `parse_tecan()` / `_parse_block()` | Tecan xlsx parser — mirrors JS logic in the HTML version |
| `parse_layout()` | Layout workbook parser |
| `gompertz()`, `logistic()` | Growth models (Zwietering 1990 reparameterization) |
| `fit_model()` | `scipy.optimize.curve_fit` wrapper; works in ln(OD) space; returns AIC, R², SEs |
| `bootstrap_mu()` | Residual-resampling bootstrap for μ_max 95% CI (200 resamples) |
| `sliding_window_mu()` | Max-slope log-linear regression over a configurable window — the recommended default estimator |
| `blank_trace()` / `corrected_od()` | Per-medium blank subtraction |
| Streamlit UI | Sidebar inputs → plate grid → strain/dilution selection → fitting → plot → metrics table → per-strain expanders |

### `tecan_growth_analyzer_live.html`

Self-contained: all JS inline, no external dependencies except SheetJS (bundled) and Plotly (CDN). The File System Access API polling loop drives live-refresh mode.

## Key design decisions

- **Fitting is done in ln(OD) space** for numerical stability; OD floor (default 0.03) clips noise before log transform.
- **First timepoint is dropped by default** — Tecan's first read precedes shaking homogenization and is systematically high.
- **Baranyi model is present in code but disabled** — a log10-vs-ln parameterization issue inflates μ by ~2×; see inline comment in `baranyi()`.
- **Per-well mechanistic fitting is disabled** — individual noisy wells cause curve_fit to overestimate μ by 30–50%; per-well path uses sliding-window only.
- **Gompertz μ_max runs 10–30% higher than sliding-window** by construction (inflection-point tangent vs finite-window chord); this is documented as expected behavior, not a bug.

## Windows distribution

Non-technical users get a ZIP from GitHub Releases and double-click
`Start Tecan Analyzer.bat`. That calls `scripts/bootstrap.ps1`, which builds a
private conda environment under `%LOCALAPPDATA%\TecanGrowthCurves` from
`config/environment.yml` — no admin rights, no PATH changes, no interference
with any existing Python. The environment is rebuilt automatically when
`config/environment.yml` changes (tracked by a SHA256 marker), so that file is
the single source of truth for dependencies; do not add packages any other way.
`.github/workflows/release.yml` builds and attaches the ZIP on a `v*` tag push.
