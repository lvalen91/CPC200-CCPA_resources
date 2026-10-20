#!/bin/sh
# ccpa_custom: owned -- the one mdev USB-storage hook (2026-10-19; replaces stock udisk_insert.sh
# and udisk_hotplug.sh). mdev.conf points both rules at it, add and remove (`*`):
#   sd[a-z]       0:0 666 */etc/mdev/usb_mount.sh    whole disk
#   sd[a-z][0-9]  0:0 666 */etc/mdev/usb_mount.sh    partition
# add:    mount vfat at /mnt/UPAN (-o utf8=1). A whole disk is mounted only when it has no
#         partitions; otherwise the first partition that mounts wins and later ones are skipped.
#         Skipped when /mnt/UPAN is already a mountpoint (/proc/mounts), so repeats are harmless.
# remove: unmount only when the device on /mnt/UPAN is $MDEV (or, for a whole-disk event, one of
#         its partitions), so pulling a second stick leaves the first mounted. umount -l fallback.
# One console line per decision. Exit 0 on every skip, 1 only when a mount or umount failed.
# USB_MOUNT_ROOT prefixes /dev /sys /proc /mnt for tests; unset in production.
R=${USB_MOUNT_ROOT:-}
MP=$R/mnt/UPAN
ACTION=${ACTION:-add}
log() { echo "[usb_mount] $ACTION $MDEV: $*" >> "$R/dev/console" 2>/dev/null; }
on_mp() { d=; while read -r s m rest; do [ "$m" = "$MP" ] && d=$s; done < "$R/proc/mounts"; echo "$d"; }

case $MDEV in sd[a-z]|sd[a-z][0-9]|sd[a-z][0-9][0-9]) ;; *) log "ignored"; exit 0 ;; esac
disk=${MDEV%%[0-9]*}
# mdev runs one process per uevent (no /dev/mdev.seq here), so two partitions could both see an
# empty /mnt/UPAN and stack mounts. flock on this file serialises them with no lock file to go
# stale. busybox flock has no -w, so poll -n, bounded at ~5 s: past that, go on unlocked rather
# than drop the event (the /proc/mounts check still applies). Units without flock run unlocked.
if [ -f "$0" ] && command -v flock >/dev/null 2>&1; then
  exec 9<"$0"; i=0
  until flock -n 9; do
    i=$((i+1)); [ $i -gt 5 ] && { log "lock busy 5s - going on unlocked"; break; }
    sleep 1
  done
fi

case $ACTION in
add)
  if [ "$MDEV" = "$disk" ]; then
    set -- "$R/sys/block/$disk/$disk"[0-9]*
    [ -e "$1" ] && { log "has partitions - left to the partition events"; exit 0; }
  fi
  cur=$(on_mp)
  [ -n "$cur" ] && { log "skipped - $MP already holds $cur"; exit 0; }
  mkdir -p "$MP"
  if err=$(mount -t vfat -o utf8=1 "$R/dev/$MDEV" "$MP" 2>&1); then log "mounted on $MP"; exit 0; fi
  log "mount failed: $err"; exit 1 ;;
remove)
  # Loop: without flock, two partitions of one stick can end up stacked on /mnt/UPAN (measured);
  # peel off every top mount that belongs to the removed device, stop at the first that does not.
  n=0; hit=
  while cur=$(on_mp); [ -n "$cur" ] && [ $n -lt 4 ]; do
    case $cur in
      "$R/dev/$MDEV") ;;
      "$R/dev/$MDEV"[0-9]*) [ "$MDEV" = "$disk" ] || break ;;
      *) break ;;
    esac
    umount "$MP" 2>/dev/null || umount -l "$MP" 2>/dev/null || { log "umount failed - $cur still on $MP"; exit 1; }
    log "unmounted $cur"; hit=1; n=$((n+1))
  done
  [ -n "$hit" ] || log "skipped - $MP holds ${cur:-nothing}"
  exit 0 ;;
*) log "ignored" ;;
esac
exit 0
