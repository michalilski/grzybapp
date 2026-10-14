# Grzyby – grzybowa mapa (iPhone)

Native SwiftUI app implementing `docs/Grzybowa mapa – plan aplikacji mobilnej`. Rule-based potential index 0–100 per 100 m cell, computed on the phone from BDL forest data, Open-Meteo weather and your own observations. No backend, no account, no LLM. UI styled after the Nike DESIGN.md (ink/white, pill CTAs, Bebas Neue display type).

## Run

```bash
brew install xcodegen          # once
xcodegen generate              # creates Grzyby.xcodeproj from project.yml
open Grzyby.xcodeproj          # pick your iPhone, Run (team N5H5R9A2K2, automatic signing)
```

Engine (pure Swift package, no UI):

```bash
cd Engine
swift test                                                    # 39 tests: units, golden ranking, determinism, performance, prior, calibration, store
swift run score-cli --region Tests/GrzybEngineTests/Fixtures --date 2026-10-09 --species boletus_edulis
UPDATE_GOLDEN=1 swift test --filter GoldenRankingTests        # deliberately rewrite expected_ranking.json after a heuristic change
```

## Layout

| Path | Contents |
| --- | --- |
| `Engine/Sources/GrzybEngine` | scorer, weather index, explainer, local prior, calibrator, flush detector, grid builder; `Resources/knowledge/*.json` holds every number |
| `Engine/Sources/GrzybData` | BDL ArcGIS client (5 km tiles, paging), Open-Meteo client, fixture loader |
| `Engine/Sources/GrzybStore` | SQLite (GRDB) schema from spec §9, repositories, JSON/GPX export & import |
| `Engine/Sources/score-cli` | CLI from phase 0 |
| `App/` | SwiftUI app: map (MapLibre + OpenFreeMap), cell sheet, observation form, journal, regions, species & rules, compass |

## What works

- Draw a region (≤ 30 × 30 km) → downloads BDL stands (layers 66 + 67) and sites (20), builds the 100 m grid, fetches weather, downloads offline map tiles (zoom 10–16).
- **Ogólnie** (default): smooth heatmap of today's overall potential = best species + `general_diversity_bonus` × (gap to “any of” 1 − Π(1 − sᵢ/100)); follows the day selector.
- Map overlay in 4 bands, species chips incl. "wszystkie jadalne" (max over species), day selector today … +7, stand outlines at zoom ≥ 14.5, field mode.
- Tap a cell → ranking with ✓ / ✗ / ★ reasons, source data with data year, 21-day rain chart, found / empty / 👍 👎 / terrain correction / in-app compass.
- Long-press or “+” → observation (≤ 3 taps), photo, note; `score_at_time`, factors and context are stored for calibration.
- Local prior (σ = 150 m), calibration every 10 observations (one logged parameter change, undo, restore atlas), flush banner + optional local notification (max 1/day).
- Journal with season summary, find calendar, JSON backup/import, GPX export.

## Decisions and deviations from the spec

- **Native Swift instead of Flutter**: iPhone-only target, Flutter not installed; architecture and module boundaries are unchanged (`engine` has no UI dependency, CLI + tests run on macOS).
- **BDL**: `https` is rejected (403) – app uses `http` with an ATS exception for `mapserver.bdl.lasy.gov.pl`. Layer 66/67 rows carry only the *dominant* species and its share (`part_cd` 1–10), not the full composition; the remainder share is filled from the site's `forest_type_cd` (e.g. `Db-So`).
- **Moisture**: derived from the TSL suffix (s/św/w/b/ł); `moisture_cd` codes are not documented and are stored but unused.
- **Water factor** = max(rain curve, soil-moisture curve × 0.8) − dry-day penalty; moist/wet/riparian sites keep part of the missing water (`drought_relief`). Without this a dry spell zeroed every cell.
- **Dry-day penalty**: −`dry_day_penalty` per day without ≥ 1 mm within the last `dry_window_days` (spec wording “w ostatnich N dniach”), so a long dry spell cannot zero the rain factor by itself.
- **Not in v1**: terrain/NMT (R_terrain uses forest-edge distance and stand structure only), 4-point weather interpolation for regions > 20 km (centroid only), distance to roads, adding custom species in the UI (add a record to `species.json`).
- Species parameters in `species.json` are approximate atlas knowledge (`source: atlas`); verify in the field.

## To verify in the field

`lag_days` per species, whether the arable-land penalty is too harsh for pine plantations, and band thresholds – the stored `score_at_time` + empty visits are what calibration will learn from.

Debug-only launch flags (simulator): `-demoRegion` seeds a 5 × 5 km region near Celestynów; env `DEMO_TAB=cell|journal|regions|species` opens a screen.
