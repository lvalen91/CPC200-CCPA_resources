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
├── check_claims.py        # stdlib checker: every claim's quote at its source_lines
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
- **Complete** — the goal is that all corpus docs are covered. Not met yet: see Known gaps.

## Maintaining the index

When documentation changes, keep the index 1:1: add claims for new facts (with the correct
`file`/`source_lines`/`quote`), update `source_lines` when content moves, and drop claims whose
content is removed. The index should never accumulate references to content that no longer exists.

## Checking the index

```
python3 -I documentation/_index/check_claims.py            # from the repository root
python3 -I documentation/_index/check_claims.py . kernel_  # also print the problems whose gid contains "kernel_"
```

For every claim it checks that the file exists and that the quote (whitespace-normalised) sits at
`source_lines`; it also checks `claim_count` and `gid` uniqueness. `quote moved` means the quote is
in the file but at other lines (update `source_lines`); `quote not found` means the text is gone
(update or drop the claim). It prints a per-file problem count and exits 1 if there is any problem.
Standard library only.

## Current state

| Cluster | Claims | Docs |
|---|---:|---:|
| 00_Root | 209 | 2 |
| 01_Firmware_Architecture | 1235 | 10 |
| 02_Protocol_Reference | 2398 | 12 |
| 03_Audio_Processing | 332 | 2 |
| 04_Implementation | 811 | 5 |
| 05_Security_Analysis | 497 | 3 |
| 06_Reference | 1259 | 6 |
| **Total** | **6741** | **40** |

The Docs column counts the docs that have claims, not the docs in the folder.

## Known gaps (2026-10-19)

- **Unindexed docs.** `01_Firmware_Architecture/`: `secure_boot_hab.md`, `kernel_compilation.md`,
  `device_variants_and_conversion.md`, `hardware_revisions.md`, `wifi_iw416_capabilities.md`,
  `c2air_v821_custom_build.md`, `c2air_v821_platform.md`, `c2air_v821_runtime_and_access.md`.
  `06_Reference/`: `external_landscape_survey.md`, `ncm_carplay_relay_feasibility.md`,
  `vehicle_platforms/gm_usb_host_admission.md`. Their facts are not in the ledgers.
- **Drift in untouched docs.** On 2026-10-19 the checker reports 475 problems, all in files the
  2026-10-19 edits did not touch: `02_Protocol_Reference/command_ids.md` (162),
  `04_Implementation/host_app_guide.md` (236), `06_Reference/binary_analysis/config_key_analysis.md`
  (22) and `CPC200-CCPA_SSH_over_USB_NCM.md` (55); 471 are `quote moved`, 4 `quote not found`.
  The claims for every other file pass.
