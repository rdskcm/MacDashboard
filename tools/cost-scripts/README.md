# cost-scripts

Scripts behind the "what would this project cost via the API" analysis in the
Habr article (https://habr.com/ru/articles/1063412/). They compute per-API-call
cost from Claude Code `.jsonl` transcripts instead of trusting the built-in
`/usage` summary, which sums the duplicated per-content-block `usage` objects
line by line (measured overcount on this project: 2.11×).

Core rule: group transcript records by `requestId` and keep the record with the
maximum `output_tokens` — one `requestId` = one billable API call. Streaming
writes several lines per call (one per content block, ~2.03 on average here),
each carrying the same `usage` object, and early lines hold partial output
counts.

| Script | Purpose |
|---|---|
| `FINAL.py` | Final per-call cost totals by model and by day |
| `sessions.py` | Per-session breakdown |
| `gapfill.py` | Extrapolation for days with an incomplete archive |
| `dupes.py` | Proof of per-block line duplication (lines per requestId) |
| `reconcile.py` | Day-by-day comparison against `~/.claude/stats-cache.json` |
| `validate.py`, `validate2.py` | Calibration of the price formula against official `/usage` → Session figures (0.1% error) |
| `agg.py`, `exact.py`, `tail.py` | Earlier/auxiliary aggregation passes |

To run these on your own history, edit the `ARCH`/`LIVE` path constants at the
top of each script: `LIVE` is your project's transcript directory under
`~/.claude/projects/…`, `ARCH` an optional archive of older transcripts (drop
it if you have none). Prices in the `PR` table are USD per 1M tokens
(input, output); cache write is 1.25× input for 5-minute TTL, 2× for 1-hour,
cache read 0.1× — taken from each record's `cache_creation` field, not assumed.
