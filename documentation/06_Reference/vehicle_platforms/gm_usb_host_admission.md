# GM AAOS USB Host Admission: "USB Device not supported" and how a 3rd-party app still gets the adapter

Applies to: GM head units running AAOS, specifically gminfo 3.7 (AAOS 12) and VCU / "Premium Infotainment
System" (AAOS 14; CT5 and other 2025+ GM vehicles). Covers the stock Carlinkit firmware (riddleBox, 0x1314:0x1520 /
0x1521) and the OCBM firmware (0x1314:0x2d00).

Status legend: **field** = reported by users on real vehicles; **code** = read from GM's decompiled `services.jar`;
**emulator** = observed on GM's unmodified CT5 AAOS 14 images booted on GM's real kernel under QEMU;
**on-box UART** = read from the CCPA's own root serial console.

## What users see

| Platform | On adapter attach | Can the host app claim the adapter? |
|---|---|---|
| gminfo 3.7 (AAOS 12) | Nothing user-facing. The deny shows only in logcat. The normal Android USB permission prompt appears for the app ("Allow Carlink to access Auto Box", or the reverse wording). | Yes, after the permission prompt. **field** |
| VCU / CT5 (AAOS 14) | A GM popup: "USB Device not supported." | Not on first attach. Users report that toggling the **stock firmware's UDisk mode** on and then off gets the app to see the adapter and ask for permission. After that it works. **field** |

## Why (AAOS 14 VCU, firmware 86384258): **code**

GM modified `com.android.server.usb.UsbHostManager` so that it admits only known device types:

- `usbDeviceAdded()` runs `isDenyListed()` **before** the device is added to `mDevices`.
- A denied device is never added. `UsbManager.getDeviceList()` / `openDevice()` serve only `mDevices`,
  so no app can see, request permission for, or open a denied device. The rejection is also handed to GM's
  remote-device service, which shows the "not supported" popup.
- Admitted device types:
  - Apple iPhone
  - `18d1:2d0x` (Android Auto)
  - Google Pixel `18d1`
  - class 0/0/0 devices with an MTP (6/1/1) or ADB (ff/42/01) interface (the MTP path is
    emulator-confirmed; the ADB `ff/42/01` path is **code-plausible only** — jadx decompiled
    `isAdbDevice` with mangled loop control, and it was never exercised on the emulator)
  - specific BCS/Aptiv hubs
  - mass storage
  - hubs
  - **a class 0/0/0 device whose serial number equals the serial of the last admitted device that was removed**
    (`isReconnectedPhoneOrTabletDevice`, compared against `mLastRemovedDeviceSerial`)
- The only other bypass is a debuggable build (`sys.usb.exit` && `Build.IS_DEBUGGABLE`). Production vehicles are
  `user` builds.

The Carlinkit adapter matches none of the fixed types: class 0/0/0 with a single vendor interface (ff/f0/00 on
OCBM). **Likely explanation of the UDisk toggle** (hypothesis: user field reports combined with static analysis of
the firmware and of GM's code; not yet observed on a vehicle):
1. UDisk on (`UdiskMode`, see [config_key_analysis.md](../binary_analysis/config_key_analysis.md) key 3): the
   adapter re-enumerates as a device class GM already knows. The adapter's gadget kernel has `f_mass_storage` and
   `f_mtp` compiled in ([hardware_platform.md](../../01_Firmware_Architecture/hardware_platform.md), Host-Facing
   Gadget), so this is most likely mass storage (a vfat-style drive) or MTP. Both types are on GM's allow-list. The
   device is admitted into `mDevices`.
2. UDisk off: that device is removed, and `mLastRemovedDeviceSerial` records its serial.
3. The adapter comes back as the Carlinkit device. **If it carries the same serial**, it passes
   `isReconnectedPhoneOrTabletDevice` and is admitted. The normal Android flow then follows: the app's
   `USB_DEVICE_ATTACHED` filter matches, the permission prompt appears, and `openDevice` / `claimInterface` succeed.

**emulator-verified (2026-09-27)** on GM's unmodified CT5 images (build type `user`, ro.debuggable=0):
- **Mass storage.** Hot-add an emulated USB mass-storage device with serial `0123456789FEDCBA`, remove it, then attach
  the OCBM adapter (1314:2d00). The logs are:
  ```
  D/UsbHostManager: isReconnectedPhoneOrTabletDevice: 0123456789FEDCBA : 0123456789FEDCBA
  D/UsbHostManager: isReconnectedPhoneOrTabletDevice: true
  D/UsbHostManager: Added device UsbDevice[...mVendorId=4884,mProductId=11520,...Auto Box...]
  ```
  Then the prompt **"Allow Carlink to access Auto Box?"** appears (it also draws an "Always open Carlink when Auto
  Box is connected" checkbox), and after the grant the app claims interface 0 and completes the OCBM `CT_HELLO` /
  `CT_HELLO_ACK` handshake.

  **The "Always open" checkbox is NOT honored on GM automotive.** GM sets `config_UsbDeviceConnectionHandling_component`
  to `android.car.usb.handler`, so `usbDeviceAdded` takes the connection-handler branch and never calls
  `getCurrentUserSettings().deviceAttached()` — the AOSP path that would persist the grant in the "always" map. The
  grant would also key on a device instance whose `/dev/bus/usb/...` node changes on every enumeration. So **every
  fresh admission produces one permission prompt; it is never remembered across enumerations or sessions.** The
  practical floor is one prompt per physical connect / ignition cycle. Within a single connection the OCBM device
  stays enumerated, so the claim holds and the prompt does not recur — but any re-enumeration (re-prime) is another
  prompt. This makes "prime exactly once per link event, never re-enumerate mid-session" a hard requirement, not an
  optimization.
- **MTP.** The same works with an emulated MTP/PTP device (`isMtpDevice.deviceMatch: true`) in place of mass storage.
- **Control run.** A device with a different serial is admitted and removed first. The adapter is then denied
  (`... : AAAABBBBCCCCDDDD` → `false` → `isDenyListed`). This isolates the serial as the cause.
- **Self-chaining.** Once the adapter itself has been admitted, removing it records its own serial, so a
  re-enumerating adapter is admitted again without another toggle.
- **Reset.** A reboot clears the recorded serial (a fresh process). The field is service-global, with no per-user reset and no timeout.
- **Logging.** GM's DEBUG lines are hidden by a global INFO log threshold. Run `setprop log.tag.UsbHostManager V` to see
  them; otherwise only the WARN-level `isDenyListed.vid/pid` shows.
- **Timing (measured on the emulator).** Phase-1 has **no wall-clock minimum** — even a 20 ms hold admits and arms, because
  the primer only has to complete one enumeration + `usbDeviceAdded → mDevices.put`. A safe firmware target is **≥ ~300–500 ms**
  present. The gap between dropping phase-1 and presenting OCBM has **no lower bound** (0 ms works; remove-before-add is ordered)
  and **no upper bound** (30 s works; nothing clears the serial on a timer). So re-enumerate OCBM any time after the drop.
- **NCM cannot prime.** A CDC/NCM device is device-class 2 → deny-listed → never enters `mDevices` → its removal arms nothing.
  Only a **mass-storage (class 8)** or **MTP (6/1/1)** primer works. MTP is the cleaner primer on the bench (mass storage makes
  vold attempt a mount; the removal still arms, but MTP isn't block-mounted and detaches instantly).

On-box confirmation (UART root console): the CCPA's car-facing gadget presents OCBM as **1314:2d00, serial 0123456789FEDCBA,
class 0/0/0, single vendor interface (ff/f0/00)**, and the same gadget has `f_mass_storage` and `f_mtp` available at that serial —
so the primer and OCBM can both come from the one car-facing controller. (Do not confuse this with the box's *phone-facing* EHCI
host controller, or with the stock `android0` gadget personality at 18d1/serial …ABCDEF used for NCM.)

A plain unplug/replug of the adapter does **not** help. A denied device was never in `mDevices`, so its removal
records no serial. **emulator**: the OCBM app (`zeno.carlink.ocbm`) installed and ran, the adapter at 1314:2d00
was enumerated by the kernel and denied by GM, and `getDeviceList()` returned only the root hubs. The app logged
`Failed to find the OCBM adapter`. Replugging repeated the deny and the popup.

## Implications for firmware and host app

- **The OS is not meant to claim the adapter.** The GM popup is expected and harmless. The goal is only that the
  device reaches `mDevices`, so that a 3rd-party app can request it.
- The mechanism depends on **the serial string being identical** across the admitted mode and the Carlinkit mode, and
  on the device class being 0/0/0 in the Carlinkit mode.
  - The OCBM firmware reports serial `0123456789FEDCBA`.
  - A firmware-side equivalent of the UDisk toggle would be: enumerate briefly as mass storage with that serial, drop,
    then enumerate as OCBM. It needs no OS change or user action. (The serial rule is emulator-verified; see above.)
- `mLastRemovedDeviceSerial` holds only the **last** removed admitted device. Any other admitted device removed in
  between (a phone, a USB stick) overwrites it; a *denied* device does not.

### Firmware sequence (auto, no user toggle) — verified end-to-end on the emulator
On the car-facing gadget, keyed off the gadget's own USB `state` (never a wall clock):

1. On a fresh link-up / bus reset (cable in, ignition power, or a head-unit reboot — all seen as a reset by the gadget),
   bring the gadget up as **mass_storage or MTP at serial 0123456789FEDCBA**, on a PID your host app does *not* filter
   (so the app ignores the transient primer). Wait for `state = CONFIGURED` (≥ ~300–500 ms budget).
2. Tear it down → GM records the serial.
3. Bring the gadget up as **OCBM (1314:2d00, ff/f0/00, same serial)**. GM's reconnect rule admits it; the host app gets
   `USB_DEVICE_ATTACHED`, the permission prompt, and claims it.
4. **Re-run step 1 on every fresh link/reset** — a head-unit reboot clears the recorded serial, and the gadget sees the
   reboot as a bus reset, so lead with the primer whenever no OCBM session is live.
5. Do **not** re-enumerate while a session is live, and do not loop on "no handshake yet": every OCBM re-enumeration is
   another (non-persisted) permission prompt and drops the current claim. One prime per physical connect / ignition cycle.

The box can self-time this from signals it already has: `state = CONFIGURED` (host enumerated the primer) and, for
mass_storage, the first SCSI READ (the OS storage stack engaged). It cannot observe GM's framework-level admission, so it
triggers on the USB-level signal plus a small margin.

### Interim manual method: prime via the box's UART gadget toggle
Until the box firmware auto-primes on link-up (the sequence above), the reconnect serial can be armed by hand from
the box's **debug UART root console (115200 8N1)**. This is the manual equivalent of the auto-UDisk firmware
sequence: the same mass_storage → OCBM prime, done by toggling the gadget's functions one at a time instead of
having the firmware self-time it.

The box's car-facing accessory gadget — the one that presents OCBM as **1314:2d00, iSerial `0123456789FEDCBA`,
class 0/0/0, single vendor interface**, via `g_android_accessory` — also has `f_mass_storage` and `f_mtp`
available at that same serial. So over UART:

1. Switch the gadget to a **mass_storage** (or **MTP**) function. The GM head unit enumerates it, admits it into
   `mDevices` (both types are on the allow-list), and — because the serial is `0123456789FEDCBA` — records that
   serial on removal.
2. Switch the gadget back to the **accessory/OCBM** function. GM admits the returning class-0/0/0 device via
   `isReconnectedPhoneOrTabletDevice` (its serial matches `mLastRemovedDeviceSerial`), and the host app can then
   claim it.

The gadget lives at the box's Android-gadget sysfs (the OCBM boot path sets `functions=accessory` there —
reference it generically, e.g. `.../android_usb_accessory/android0`). Each switch is the usual gadget dance:

```
echo 0 > enable
echo <function> > functions      # mass_storage (or mtp), then accessory
echo 1 > enable
```

**Status.** The constituent facts are verified: UART root console is confirmed; the accessory gadget exposes
`f_mass_storage` and `f_mtp` at iSerial `0123456789FEDCBA` (on-box UART); and on the emulator a `0123456789FEDCBA`
mass_storage primer arms GM's reconnect rule and the OCBM app then claims the box (see the emulator-verified
section above). The **end-to-end box-side function toggle itself has not yet been exercised** — it is planned for
the on-vehicle / on-emulator CarPlay bring-up test. Do not treat it as run.

## History

- 2026-09-27: first written. It combines user field reports and static firmware analysis (UDisk toggle on CT5 / AAOS 14; gminfo shows only the
  permission prompt) with a code read of the CT5 firmware `services.jar` and emulator observation. The same day,
  the reconnect-by-serial path was emulator-verified with both mass-storage and MTP devices, plus a different-serial control run.
