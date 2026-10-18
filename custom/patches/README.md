# custom/patches/

Binary patches to the CPC200-CCPA stock firmware (board A15W, firmware `2025.10.15.1127CAY`).
Design, hook sites and device-verified results are documented in
[`documentation/04_Implementation/iap2_binary_patches.md`](../../documentation/04_Implementation/iap2_binary_patches.md);
this directory holds the artifacts.

## ARMiPhoneIAP2/

```
ARMiPhoneIAP2/
├── stock/                 factory baseline every builder starts from
│   ├── ARMiPhoneIAP2.unpacked   md5 f1e1a0aa4d7fa6e639048c93475af9df (UPX-unpacked, 494244 B)
│   └── ARMiPhoneIAP2.packed     md5 d933c9d5a0157e8694cda385e7efa3c2 (as shipped)
├── builders/              python generators (need `pip install capstone`)
│   ├── build_v5.py        NAV   emit-once design        -> ARMiPhoneIAP2.v5.patched
│   ├── build_persist.py   NAV   persistent /usr/sbin    -> ARMiPhoneIAP2.patched
│   ├── build_callraw.py   CALL  0x4155 -> _callraw      -> ARMiPhoneIAP2.callraw.patched
│   ├── build_commtest.py  CALL + COMM enable (0x4158 -> _commraw) -> ARMiPhoneIAP2.commenable.patched
│   ├── build_commraw.py   earlier call+comm-forward experiment (superseded by build_commtest.py)
│   └── analyze_packer.py, decode_burst.py   helpers
├── binaries/              file names say what each is; builder output names are mapped below
│   ├── production/    SHIPPED by carlink_native (app/src/main/assets/ARMiPhoneIAP2.patched)
│   │   ├── ARMiPhoneIAP2.nav_v5.packed     80f97b149762f69d1683b9a2db879aa7 (byte-identical to the asset)
│   │   └── ARMiPhoneIAP2.nav_v5.patched    e8c6c02e6b6c21c8dbd234370a02fdcc (its unpacked form)
│   └── macos_host/    carlink_macOS call + comm; NOT in carlink_native, has NO NAV hooks
│       └── ARMiPhoneIAP2.call_comm.patched dc87d77e30013f6afca3f304298d30e9
└── deploy/                dev_deploy.sh, dev_restore_stock.sh (set ADAPTER_HOST; sshpass required)
```

Builder output -> checked-in name: `build_v5.py` `ARMiPhoneIAP2.v5.patched` -> `production/ARMiPhoneIAP2.nav_v5.patched`;
`build_commtest.py` `ARMiPhoneIAP2.commenable.patched` -> `macos_host/ARMiPhoneIAP2.call_comm.patched`.
`build_persist.py` (`ARMiPhoneIAP2.patched`) and `build_callraw.py` (`ARMiPhoneIAP2.callraw.patched`) are
not in production and their outputs are not checked in; rebuild them if needed. Note the filename
`ARMiPhoneIAP2.patched` is what carlink_native calls its asset, but that asset is the v5 build, not
`build_persist.py`'s output.

**Identifying production (2026-10-18):** the asset is UPX-packed with a modified header, so it can't be
unpacked off-device. Its header's uncompressed-data checksum low 16 bits (`0x463d`) match only
`nav_v5` (adler32 `f327463d`); persist, callraw and commenable differ (`0x36d9`, `0xc53f`, `0x21ae`).
The high half of that field doesn't reproduce even for the stock binary, so treat this as strong
evidence, not proof. Confirm by unpacking on the adapter (`modified_upx_arm -d`) and comparing md5.

**The patches are not combined.** `commenable.patched` is call + comm only; its NAV hook sites
(`0x2d1c8`, `0x2d454`) hold stock bytes. Deploying it removes NAV forwarding. See §7 of the patch
doc for the cave/bss collision that a combined build has to resolve.

## Rebuilding

Builders read `ARMiPhoneIAP2.unpacked` from the current directory and write outputs there:

```
mkdir work && cp ARMiPhoneIAP2/stock/ARMiPhoneIAP2.unpacked work/ && cd work
python3 -I ../ARMiPhoneIAP2/builders/build_v5.py
```

All four builders verified to reproduce the checked-in md5s byte-for-byte (2026-10-18).

## Not included
Datastore edits (`CallStateItems_Usablity.expanded`, `CommunicationItems_Usablility`): editing
the datastores breaks the store signature and silences the iAP2 update channel (doc 09 in the
source project). Intermediate builds (v3/v4, commtest/commsub/commadv/callfwd) are history only.
