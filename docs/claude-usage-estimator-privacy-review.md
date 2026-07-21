# Claude usage estimator privacy review

Review date: 2026-07-21

Scope: the shipping `ClaudeLocalLogUsageReader` data path, every PromptJuice persistence site,
every production log call, the Phase 1 capture utilities, and the state passed to the app UI.

## G1 — narrow extraction boundary

Each bounded JSONL record is decoded into a private typed projection. Its coding keys retain
only:

- record type and timestamp;
- request and message identifiers used for deduplication;
- sidechain state;
- input, cache-creation, cache-read, and output token totals.

JSON fields outside that projection are discarded by `JSONDecoder`. Token arithmetic clamps
negative values to zero and saturates at `Int.max` for malformed or adversarial records.

## G2 — transient and retained data flow

The estimator reads at most 64 recent files, 512 KiB per file, and 8 MiB total. Source bytes
exist only in the bounded local parsing scope. Parsing returns typed usage entries or `nil`.
Errors use fixed enum descriptions, and unexpected errors are reduced to fixed fallback copy by
`ClaudeUsagePrivacyBoundary`.

Retained estimator state consists of timestamps, deduplication identifiers, sidechain state,
and token totals. The resulting `ProviderSnapshot` contains derived percentages, reset time,
confidence, source, and fixed status copy. App logs, cache records, notification state, UI state,
and fixtures receive derived metadata only. PromptJuice omits analytics transport.

The committed estimator fixtures contain usage metadata only. Privacy-boundary tests construct
conversation-bearing fields dynamically, then prove those fields disappear at the typed decode
boundary and remain absent from the resulting snapshot.

## G3 — persisted snapshot schema

`ClaudeSnapshotCache` eligibility is limited to `claudeUsageCLI` snapshots. Those snapshots persist
the following window keys through `ProviderWindowSnapshotCache`:

- `session` and optional `weekly`;
- `usedPercent`;
- `resetAt`;
- `durationMinutes`;
- `updatedAt`.

The persistence schema is limited to those derived window fields. `ClaudeUsagePersistence`
stores scheduling timestamps, refresh reasons, cooldown index, and an authentication-category
fingerprint.

## G4 — logging review

The review enumerated `PromptJuiceLog`, `Logger`, `os_log`, `NSLog`, and `print` usage across the
app and scripts.

Production app logs contain fixed lifecycle messages plus these allowlisted derived values:

- provider, source, confidence, and availability enum values;
- internal refresh reasons and outcomes;
- Claude probe milestones and typed outcome booleans.

The logging schema is limited to the allowlisted derived values above. The Claude provider maps
unknown error descriptions to fixed safe copy. PTY output and parsed terminal text stay outside logs.

The Phase 1 capture utilities write raw data directly to owner-only files and print structured
execution or sanitizer status. Raw capture payloads stay in those owner-only files. Sanitized
fixtures remain subject to the Phase 1 privacy scanner.

## Verification

`ClaudeEstimatorPrivacyTests` covers:

- typed allowlist extraction with conversation-bearing and additive input fields;
- malformed-record discard;
- derived-only snapshot state;
- fixed safe error descriptions;
- saturating token arithmetic;
- estimate-cache rejection;
- exact-cache field allowlisting and payload-canary absence.

These checks satisfy G1–G4 and unblock the target measurement-popover privacy copy.
