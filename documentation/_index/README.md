# `_index/` — Documentation Claims Index

A machine- and LLM-readable map of the documentation corpus: every atomic factual claim in the
docs is recorded with its source file, line, and a verbatim quote anchor. It exists so the
documentation can be queried, cross-checked, and re-organized **without losing information** —
each fact is accounted for with exact provenance.

This index is a **1:1 reflection of the current documentation** and is the baseline going forward.
It carries no historical reconciliation records — the docs themselves are the source of truth, and
git history + backups hold the past.

## Layout

```
_index/
├── README.md              # this file
└── claims/
    └── <cluster>.json     # the claims ledger, one file per top-level doc folder
```

Each `claims/<cluster>.json` contains **only** the claims for that cluster's documents; every
claim's `file`/`source_lines` resolves to current content.

## Claims ledger schema (`claims/*.json`)

```jsonc
{
  "cluster": "02_Protocol_Reference",
  "method": "re-synced 1:1 to current documentation",
  "generated_from": ["02_Protocol_Reference/usb_protocol.md", "..."],  // the cluster's docs
  "claim_count": 2364,
  "claims": [
    {
      "gid": "02_Protocol_Reference/usb_protocol.md#42",  // <file>#<per-file local id>
      "file": "02_Protocol_Reference/usb_protocol.md",     // cluster-relative path from the corpus root
      "local_id": 42,
      "statement": "Self-contained atomic fact.",
      "topic": "usb-zlp",                                  // short tag for cross-file clustering
      "source_lines": "120",                               // current line in the file
      "confidence": "high | medium | low",
      "signals": null,                                     // in-text status markers, if any
      "quote": "exact phrase from the source"              // anchor to relocate the claim
    }
  ]
}
```

## Invariants

- **1:1 with the docs** — every claim resolves to current content at its `source_lines`; no claim
  references removed, superseded, or relocated-away content.
- **In-cluster only** — each ledger lists only its own cluster's files; a fact that lives in
  another cluster's doc is recorded in *that* cluster's ledger.
- **Unique** — `gid` is unique within a cluster (`<file>#<local_id>`, `local_id` sequential per file).
- **Complete** — all corpus docs are covered.

## Maintaining the index

When documentation changes, keep the index 1:1: add claims for new facts (with the correct
`file`/`source_lines`/`quote`), update `source_lines` when content moves, and drop claims whose
content is removed. The index should never accumulate references to content that no longer exists.

## Current state

| Cluster | Claims | Docs |
|---|---:|---:|
| 00_Root | 221 | 2 |
| 01_Firmware_Architecture | 1164 | 10 |
| 02_Protocol_Reference | 2364 | 12 |
| 03_Audio_Processing | 332 | 2 |
| 04_Implementation | 694 | 5 |
| 05_Security_Analysis | 442 | 3 |
| 06_Reference | 1268 | 6 |
| **Total** | **6485** | **40** |
