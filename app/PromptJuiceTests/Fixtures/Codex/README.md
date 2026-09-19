# Codex rate limit fixtures

- `pro-weekly-only.json` follows the captured Pro payload structure: the weekly limit is in `primary`, `secondary` is null, and `codex` is the only bucket. Percentages and reset times are synthetic.
- `lower-tier-inferred.json` models the expected 5-hour plus weekly shape. It has not been captured from a non-Pro account. Live validation is planned after merge.

The files contain no account identifiers or credentials.
