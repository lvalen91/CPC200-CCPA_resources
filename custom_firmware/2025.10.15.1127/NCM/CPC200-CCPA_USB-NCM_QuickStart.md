# Without NCM CFW, use this for a temp NCM interface

# CPC200-CCPA — Root SSH over USB (CDC-NCM): Quick Start

Get a root shell on the adapter over the **USB cable**, set up from the adapter's **WiFi**.
Works on **macOS and Linux** (both ship a built-in CDC-NCM driver — no install).
Validated: 4/4 reboot cycles, 0.0% packet loss over a 4-minute ping, ~1.7 ms RTT, SSH stable.

---

## Prerequisites

- Adapter powered on.
- Adapter's **USB cable plugged into the host computer** (the plug that normally goes to the car).
- Host joined to the adapter's **WiFi AP** (used only to issue the one-time setup).
- macOS or Linux host. (Windows: see Troubleshooting — use RNDIS.)

---

## Step 1 — SSH in over WiFi and arm NCM

SSH to the adapter over WiFi (password is **blank** — press Enter):

```sh
ssh root@192.168.43.1
```

On the adapter, paste this block (switches the USB port to a network device and serves DHCP):

```sh
A=/sys/class/android_usb_accessory/android0
killall ARMadb-driver ARMiPhoneIAP2 fakeiOSDevice 2>/dev/null
pkill -f phone_link_deamon 2>/dev/null
sleep 1
echo 0   > /sys/class/android_usb/android0/enable 2>/dev/null
echo 0   > $A/enable
echo 239 > $A/bDeviceClass; echo 2 > $A/bDeviceSubClass; echo 1 > $A/bDeviceProtocol
echo ncm > $A/functions
echo 1   > $A/enable
sleep 2
echo 0   > $A/enable; sleep 2; echo ncm > $A/functions; echo 1 > $A/enable   # bounce: forces host to re-enumerate
sleep 2
busybox ifconfig ncm0 192.168.50.2 netmask 255.255.255.0 mtu 1500 up        # assign IP AFTER the bounce
cat > /tmp/udhcpd_ncm.conf <<'CFG'
start 192.168.50.100
end 192.168.50.150
interface ncm0
opt subnet 255.255.255.0
opt lease 86400
lease_file /tmp/udhcpd_ncm.leases
pidfile /tmp/udhcpd_ncm.pid
max_leases 20
CFG
touch /tmp/udhcpd_ncm.leases
pkill -f udhcpd_ncm.conf 2>/dev/null; sleep 1
busybox udhcpd -f /tmp/udhcpd_ncm.conf >/tmp/udhcpd_ncm.log 2>&1 &
sleep 1
echo "ARMED: functions=$(cat $A/functions) state=$(cat $A/state)"
```

Expected last line: `ARMED: functions=ncm state=CONFIGURED`.

---

## Step 2 — Connect from the host (over USB)

Open a **second** terminal on the host (leave the WiFi session open). The host's built-in CDC-NCM
driver creates a new Ethernet interface and **auto-gets `192.168.50.100` via DHCP** — no manual IP.
Wait ~5 s, then:

```sh
ssh root@192.168.50.2
```

Password is blank. You are now on the adapter over USB.

**Confirm it is really USB, not WiFi:**

```sh
echo $SSH_CONNECTION                            # must show: 192.168.50.100 <port> 192.168.50.2 22
```

```sh
route -n get 192.168.50.2 | grep interface     # macOS — shows the USB enX
ip route get 192.168.50.2                       # Linux — shows the USB dev
```

To find the new interface name: `ifconfig` (macOS) or `ip -br addr` (Linux) — it's the one on `192.168.50.x`.

---

## Step 3 — Restore normal operation

The setup is in RAM only. To return the adapter to a normal CarPlay/Android-Auto dongle:

```sh
busybox reboot      # run on the adapter
```

After ~25 s it boots back to normal. Nothing was written to flash.

---

## Warnings

- **This disables projection while armed.** The USB port can be CarPlay/Android Auto **or** NCM,
  not both — arming kills the projection daemon. A reboot restores projection.
**Everything here is volatile** (RAM/sysfs/tmp). It does **not** survive a reboot — re-run Step 1
  after each boot. Do not attempt to make it boot-persistent without a tested, self-reverting setup
  and WiFi left enabled.
- Run the block **in this order** — assign the IP and start DHCP **after** the bounce. The bounce
  recreates `ncm0` and drops its IP; assigning earlier makes DHCP fail with `bind: No such device`.

---

## Suggestions

- Keep the WiFi SSH session (`192.168.43.1`) open while you work — it is your recovery channel.
- If the host interface doesn't appear, unplug/replug the USB cable once (re-triggers enumeration).
- The adapter's WiFi DHCP is untouched; the NCM DHCP server is a separate instance on `ncm0`.
- The NCM DHCP intentionally serves **no `router`/`dns`** option — so `192.168.50.x` stays a host route and never hijacks your default route (e.g. an iPhone-USB or other WAN). Add them back only if you want the adapter to be your gateway.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No new interface on the host | Replug the USB cable. Confirm on adapter: `cat $A/state` = `CONFIGURED` and `cat /sys/class/udc/ci_hdrc.1/state` = `configured`. |
| Interface appears but stays on `169.254.x` (no IP) | DHCP didn't land. Check `cat /tmp/udhcpd_ncm.log`; re-run the bounce + `ifconfig` + `udhcpd` lines from Step 1. |
| Want a static IP instead of DHCP | macOS: `sudo ifconfig <enX> 192.168.50.1 netmask 255.255.255.0 up`. Linux: `sudo ip addr add 192.168.50.1/24 dev <dev> && sudo ip link set <dev> up`. Then `ssh root@192.168.50.2`. |
| `udhcpd: bind(PACKET): No such device` | You assigned the IP/started DHCP before the bounce. Re-run in order (IP + DHCP last). |
| NCM reverts to "Auto Box" | The projection daemon was still running. Re-run the `killall ARMadb-driver` line, then the switch. |
| Windows host | macOS won't bind RNDIS and `ncm` is awkward on Windows — on the adapter use `echo rndis > $A/functions` instead of `ncm`, then DHCP/static as above. (RNDIS also works on Linux; macOS requires `ncm`.) |
