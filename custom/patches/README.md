# custom/patches/

Reserved for **binary patches** to the CPC200-CCPA firmware, imported from a separate
patching project (the `ARMiPhoneIAP2` call-enrichment / navigation patches).

Expected contents when populated:
- patch sets / code-cave trampolines (per target message, e.g. CallState `0x4155`, RouteGuidance `0x5201`)
- builder scripts (unpack → patch → repack → deploy)
- per-patch docs (what, why, hook sites, deploy strategy, verification)

These are *custom modifications* of the stock firmware binaries, hence their home under `custom/`.
