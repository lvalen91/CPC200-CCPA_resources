/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Dropbear 2026.94 localoptions.h for the vanilla baselines (CCPA arm-imx6ul, C2Air riscv).
 * Copied into the source tree before ./configure. Dropbear silently ignores a macro it does not know,
 * so build.sh fails if any name defined here is absent from that version's default_options.h
 * (checked against 2026.94 by the 2026-10-20 builds).
 *
 * Server (recovery and rootfs, common/shared/ssh-up): public-key OR password login (owner decision
 * 2026-10-20; password from /etc/shadow via getspnam + crypt, sha512-crypt; no PAM), ed25519 host key,
 * no X11 or agent forwarding, no legacy algorithms; SFTP through a static OpenSSH sftp-server (modern
 * `scp` speaks SFTP). Host keys live under /run (the rootfs is a read-only squashfs); ssh-up passes -r.
 * With PASSWORD_AUTH 0, dropbear 2026.94 accepts -s/-g and ignores them (svr-runopts.c); with 1, -s or
 * -g would switch password logins off, so ssh-up passes neither.
 */

/* Authentication */
#define DROPBEAR_SVR_PASSWORD_AUTH 1
#define DROPBEAR_SVR_PAM_AUTH 0
#define DROPBEAR_SVR_PUBKEY_AUTH 1
#define DROPBEAR_SVR_PUBKEY_OPTIONS 1

/* Forwarding the box has no use for */
#define DROPBEAR_X11FWD 0
#define DROPBEAR_SVR_AGENTFWD 0
#define DROPBEAR_CLI_AGENTFWD 0

/* Host and user key types: ed25519 + ecdsa + rsa (sha2 only); no DSS, no ssh-rsa SHA-1 */
#define DROPBEAR_ED25519 1
#define DROPBEAR_ECDSA 1
#define DROPBEAR_RSA 1
#define DROPBEAR_RSA_SHA1 0
#define DROPBEAR_DSS 0

/* Key exchange and ciphers: drop the legacy ones, keep upstream defaults for the rest */
#define DROPBEAR_DH_GROUP1 0
#define DROPBEAR_DH_GROUP14_SHA1 0
#define DROPBEAR_3DES 0
#define DROPBEAR_ENABLE_CBC_MODE 0
#define DROPBEAR_SHA1_96_HMAC 0

/* SFTP subsystem: OpenSSH sftp-server built static (common/recipes/userspace.sh build_sftp_server) */
#define DROPBEAR_SFTPSERVER 1
#define SFTPSERVER_PATH "/usr/libexec/sftp-server"

/* Paths */
#define DEFAULT_PATH "/usr/sbin:/usr/bin:/sbin:/bin"
#define DEFAULT_ROOT_PATH "/usr/sbin:/usr/bin:/sbin:/bin"
#define DROPBEAR_PIDFILE "/run/dropbear.pid"
#define ED25519_PRIV_FILENAME "/run/dropbear/dropbear_ed25519_host_key"
#define ECDSA_PRIV_FILENAME "/run/dropbear/dropbear_ecdsa_host_key"
#define RSA_PRIV_FILENAME "/run/dropbear/dropbear_rsa_host_key"
#define DSS_PRIV_FILENAME "/run/dropbear/dropbear_dss_host_key"
