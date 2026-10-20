/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * hciup [-d|-i] [hciN|N]: bring a Bluetooth HCI device up (HCIDEVUP), down (-d) or only print it
 * (-i), for the baseline's radio-up. BusyBox has no HCI tool and the baseline carries no BlueZ.
 * HCIDEVUP makes the kernel run the controller's HCI init sequence (reset, read version, read BD
 * address, ...); it fails if the controller does not answer, so "UP" with a BD address here means
 * real HCI round trips happened, not just that hci0 is registered.
 *
 * The constants and struct layouts are the kernel's (include/net/bluetooth/{bluetooth.h,hci_sock.h},
 * linux 7.2.10); the UAPI headers in the musl sysroot do not carry them.
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#define AF_BLUETOOTH_ 31
#define BTPROTO_HCI_ 1
/* musl declares ioctl(int, int, ...): the request numbers are passed as int (0x800448d3 does not fit) */
#define HCIDEVUP_ ((int)_IOW('H', 201, int))
#define HCIDEVDOWN_ ((int)_IOW('H', 202, int))
#define HCIGETDEVINFO_ ((int)_IOR('H', 211, int))
#define HCI_UP_FLAG 0 /* enum: HCI_UP is bit 0 of hci_dev_info.flags */

typedef struct { uint8_t b[6]; } __attribute__((packed)) bdaddr_t_;

struct hci_dev_stats_ {
	uint32_t err_rx, err_tx, cmd_tx, evt_rx, acl_tx, acl_rx, sco_tx, sco_rx, byte_rx, byte_tx;
};

struct hci_dev_info_ {
	uint16_t dev_id;
	char name[8];
	bdaddr_t_ bdaddr;
	uint32_t flags;
	uint8_t type;
	uint8_t features[8];
	uint32_t pkt_type, link_policy, link_mode;
	uint16_t acl_mtu, acl_pkts, sco_mtu, sco_pkts;
	struct hci_dev_stats_ stat;
};

static int info(int s, int id)
{
	struct hci_dev_info_ di;
	memset(&di, 0, sizeof(di));
	di.dev_id = (uint16_t)id;
	if (ioctl(s, HCIGETDEVINFO_, (void *)&di) < 0) {
		fprintf(stderr, "hciup: hci%d: %s\n", id, strerror(errno));
		return 1;
	}
	printf("%.8s: %s, bdaddr %02x:%02x:%02x:%02x:%02x:%02x, acl_mtu %u:%u, cmd_tx %u evt_rx %u\n",
	       di.name, (di.flags & (1u << HCI_UP_FLAG)) ? "UP" : "DOWN",
	       di.bdaddr.b[5], di.bdaddr.b[4], di.bdaddr.b[3], di.bdaddr.b[2], di.bdaddr.b[1], di.bdaddr.b[0],
	       di.acl_mtu, di.acl_pkts, di.stat.cmd_tx, di.stat.evt_rx);
	return 0;
}

int main(int argc, char **argv)
{
	int mode = 'u', id = 0, i, s, rc = 0;
	for (i = 1; i < argc; i++) {
		const char *a = argv[i];
		if (!strcmp(a, "-d"))
			mode = 'd';
		else if (!strcmp(a, "-i"))
			mode = 'i';
		else if (!strncmp(a, "hci", 3) && a[3])
			id = atoi(a + 3);
		else if (a[0] >= '0' && a[0] <= '9')
			id = atoi(a);
		else {
			fprintf(stderr, "usage: hciup [-d|-i] [hciN|N]\n");
			return 2;
		}
	}
	s = socket(AF_BLUETOOTH_, SOCK_RAW | SOCK_CLOEXEC, BTPROTO_HCI_);
	if (s < 0) {
		fprintf(stderr, "hciup: no Bluetooth socket (%s): bluetooth.ko not loaded?\n", strerror(errno));
		return 1;
	}
	if (mode == 'u' && ioctl(s, HCIDEVUP_, id) < 0 && errno != EALREADY) {
		fprintf(stderr, "hciup: hci%d up failed: %s\n", id, strerror(errno));
		rc = 1;
	} else if (mode == 'd' && ioctl(s, HCIDEVDOWN_, id) < 0) {
		fprintf(stderr, "hciup: hci%d down failed: %s\n", id, strerror(errno));
		rc = 1;
	}
	if (info(s, id))
		rc = 1;
	close(s);
	return rc;
}
