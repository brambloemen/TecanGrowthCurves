# Tecan growth curve analyzer — README

Two tools, same inputs, different strengths.

---

## Install on Windows (no coding required)

For colleagues who just want to use the tool:

1. Go to the [Releases page](../../releases) and download
   `TecanGrowthCurves-Windows-*.zip`.
2. **Right-click the ZIP → Properties → tick "Unblock" → OK.** Windows blocks
   files downloaded from the internet; skipping this makes the launcher refuse
   to start.
3. Extract it somewhere you can write to — Desktop or Documents.
4. Double-click **`Start Tecan Analyzer.bat`**.

The first launch sets itself up: it downloads about 100 MB and takes 3–10
minutes. **No administrator rights are needed** — it installs a private Python
environment into your own `%LOCALAPPDATA%\TecanGrowthCurves` folder, does not
change `PATH`, and does not disturb any Python or conda already on the machine.
Every launch after that takes a few seconds. Your browser opens automatically.

`Uninstall.bat` removes that private environment again; it never touches your
data files.

If PowerShell is blocked by IT policy, or there is no internet, double-click
**`Open Offline HTML Tool.bat`** instead — the browser-only version needs no
setup at all (see Tool 1 below).

### Cutting a release (maintainer)

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/release.yml` builds the ZIP and attaches it to a GitHub
Release. Run it from the Actions tab (`workflow_dispatch`) to inspect the
bundle without publishing.

---

## Inputs (shared between both tools)

Both versions take:

1. **A Tecan i-control kinetic export** (`.xlsx`) — absorbance readouts over
   time. The parser auto-detects the `Cycle Nr.` / `Time [s]` block, handles
   single- or multi-label exports, and supports plates up to 384 wells.

2. **A plate layout workbook** (`.xlsx`) with three sheets:
   - **Strains** — any string label per well. Leave empty for unused wells.
     Wells with a strain name starting with `blank` (case-insensitive) are
     treated as blanks.
   - **Dilutions** — a number per well. Choose in the UI whether to interpret
     as a *linear factor* (`10` = 10× diluted) or *log10* (`1` = 10× diluted).
   - **Media** — any string (`LB`, `LB+Kan5`, `BHI`, …). Blanks are matched
     to strain wells by medium.

   Each sheet is an 8×12 grid with `A`–`H` in column A and `1`–`12` in row 1.
   An example (`example_layout_30C.xlsx`) and a blank template (downloadable
   from the HTML app) are included.

---

## Tool 1 — Live HTML analyzer (`tecan_growth_analyzer_live.html`)

**When to use:** quick visual check during or right after a run. Single file,
no install, works offline. Includes live auto-refresh mode for monitoring
growth during a Tecan run.

### Usage

1. Double-click the HTML file. Opens in your default browser.
2. Drop your Tecan `.xlsx` on the left pane, layout `.xlsx` on the right.
3. For post-run quick look — that's it, curves render immediately.
4. For live monitoring during a run:
   - Click **Monitor live** under the Tecan drop zone.
   - Browser asks for read permission on the file (once per session).
   - Pick refresh interval (15 s – 10 min) from the dropdown.
   - Page auto-refreshes as Tecan writes new cycles. Green ● LIVE indicator
     shows last-read time and current cycle count.
   - Click Monitor again to stop.

### Browser support for live mode

- **Chrome, Edge** — full live-refresh support (File System Access API).
- **Firefox, Safari** — button greyed out; drag-drop still works, just
  re-drop the file manually to refresh.

### Analysis method

Sliding-window μ_max on the mean trajectory across dilution replicates.
Configurable window (default 3 h) and fit floor (default 0.03). Blank-
subtracted using the per-medium mean of all wells flagged as blank.

---

## Tool 2 — Streamlit analyzer (`tecan_streamlit.py`)

**When to use:** post-run analysis where you want mechanistic growth models,
per-well vs mean-fit comparison, bootstrap CIs, or AIC-based model
selection. You can edit the Python to add your own analyses.

### Install

Non-developers should use the Windows launcher at the top of this README
instead. To set it up by hand:

```bash
conda env create -f config/environment.yml
conda activate tecan-growth-curves
```

`config/environment.yml` is the single source of truth for dependencies — the
Windows launcher builds from the same file. Or with pip:

```bash
pip install "streamlit>=1.40" "pandas>=2.0" "numpy>=1.24" "scipy>=1.10" "openpyxl>=3.1" "plotly>=5.18"
```

Python 3.10 or newer is required.

### Run

```bash
streamlit run tecan_streamlit.py
```

Opens in your browser at `http://localhost:8501`. Everything runs locally;
no internet needed after install.

### What it adds over the HTML version

- **Gompertz / logistic sigmoid fits** (Zwietering et al. 1990
  reparameterization) — gives you lag time, asymptotic amplitude (A), and
  μ_max from the same fit.
- **AIC-based model comparison** — fits both Gompertz and logistic, picks
  the lower-AIC winner per strain.
- **Bootstrap 95% CI on μ_max** — 200 residual-resampled refits for
  non-asymptotic uncertainty.
- **Per-well vs mean fitting** — for cases where dilutions are in different
  growth phases and the mean isn't a clean sigmoid.
- **Skip-first-timepoint default** — Tecan's first read happens before
  shaking homogenizes the inoculum and is systematically off.
- **Minimum-growth guard** — strains with less than 0.5 ln units of OD
  increase skip mechanistic fits (parameters become unidentifiable).

### Which method to use

In order of recommendation:

1. **Sliding-window on mean** (default). Direct log-linear regression on the
   steepest chunk of ln(OD). Most interpretable, visually verifiable.
   Matches `growthrates::fit_easylinear` in R.

2. **Gompertz on mean**. Use when you specifically need lag time or the
   full sigmoid. Note that Gompertz μ_max runs 10–30% higher than sliding-
   window on the same data — the inflection-point slope of a fitted sigmoid
   is steeper than the mean slope over any finite window, and the model
   sharpens its inflection to accommodate imperfect real-world curves
   (post-stationary settling, evaporation). This is a known, systematic
   effect, not a bug.

3. **Per-well sliding-window**. When your dilutions are in different growth
   phases at the same time, the mean isn't a proper sigmoid — fit each well
   separately and report the median μ with IQR across wells. Wide IQR is a
   signal to look at the curves individually and pick one dilution.

### Why Baranyi isn't included

The Baranyi model has a log10-vs-ln parameterization subtlety that I didn't
fully reconcile — my implementation gave μ estimates inflated by ~2× relative
to Gompertz and to manual log-linear regression. Rather than ship a bug, I
removed it. If you want Baranyi specifically, the R `biogrowth` or
`nlsMicrobio` packages have well-tested implementations.

---

## Troubleshooting

**"None of the layout wells match the Tecan wells"** — usually means the
layout sheet row labels aren't `A`–`H` in column 1 and column labels aren't
`1`–`12` in row 1. Use the template generator in the HTML app to get a
correctly-formatted starting file.

**A strain gets dropped with no fit** — check the curves view: if the strain
hasn't grown 0.5 ln units (~1.6× OD increase) above the fit floor, mechanistic
fits are skipped. Lower the fit floor or use sliding-window.

**μ values seem too high with Gompertz** — expected, see "Which method" above.
For comparison with published rates or with other labs' measurements, use
sliding-window. The Gompertz μ is correct *as defined by Zwietering* (tangent
at inflection) but that definition is biased upward relative to the chord
slope over an exponential-phase window.

**Live-monitor button is greyed out** — you're on Firefox or Safari. Switch
to Chrome or Edge, or use drag-drop and manually re-drop to refresh.
