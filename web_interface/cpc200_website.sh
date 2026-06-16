#!/bin/bash
#
# CPC200-CCPA Website Manager
# Install replacement web interface or restore OEM
#
# Usage:
#   ./cpc200_website.sh install <adapter_ip>    - Install replacement website
#   ./cpc200_website.sh restore <adapter_ip>    - Restore OEM website
#   ./cpc200_website.sh status <adapter_ip>     - Check current website status
#
# Requirements:
#   - ssh and scp available
#   - SSH key authentication or password for root@<adapter_ip>
#   - Archive files in same directory as script:
#     - new_website.tar.gz (for install)
#     - website_backup.tar.gz (for restore)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEW_WEBSITE_ARCHIVE="$SCRIPT_DIR/new_website.tar.gz"
BACKUP_ARCHIVE="$SCRIPT_DIR/website_backup.tar.gz"
SSH_USER="root"

# SSH connection multiplexing: the first connection authenticates (at most one
# prompt), and every subsequent ssh/scp reuses that socket without re-asking.
# %C is a short hash of the connection params (keeps the socket path well under
# the OS unix-socket length limit).
SSH_CTRL_DIR="/tmp/cpc200_ssh"
mkdir -p "$SSH_CTRL_DIR" 2>/dev/null || true
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ControlMaster=auto -o ControlPath=$SSH_CTRL_DIR/%C -o ControlPersist=300"

# Optional sshpass prefix (set by init_auth). Empty = use ssh's own prompt.
SSH_AUTH=""

# Wrappers so all ssh/scp calls share the same auth + multiplexed connection.
do_ssh() { $SSH_AUTH ssh $SSH_OPTS "$@"; }
do_scp() { $SSH_AUTH scp $SSH_OPTS "$@"; }

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "CPC200-CCPA Website Manager"
    echo ""
    echo "Usage:"
    echo "  $0 install <adapter_ip>    Install replacement website"
    echo "  $0 restore <adapter_ip>    Restore OEM website"
    echo "  $0 status <adapter_ip>     Check current website status"
    echo ""
    echo "Examples:"
    echo "  $0 install 192.168.43.1"
    echo "  $0 restore 192.168.43.1"
    echo ""
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Ask for the password once and cache it for the whole run. Blank is allowed
# (the adapter's root account commonly has no password). Requires sshpass; if
# it isn't installed we fall back to connection multiplexing, where ssh prompts
# at most once and reuses that connection for every later step.
init_auth() {
    # Already initialized for this run
    [ -n "$AUTH_DONE" ] && return 0
    AUTH_DONE=1

    if command -v sshpass > /dev/null 2>&1; then
        printf "Password for %s@%s (leave blank if none): " "$SSH_USER" "$1" >&2
        read -rs PASS
        echo "" >&2
        export SSHPASS="$PASS"
        SSH_AUTH="sshpass -e"
        print_info "Password cached for this run (sshpass)."
    else
        print_info "sshpass not installed — using SSH connection multiplexing."
        print_info "ssh will prompt at most once, then reuse the connection for all steps."
        print_info "Blank password: just press Enter at the prompt."
        print_info "(For fully unattended runs incl. blank passwords: brew install sshpass)"
    fi
}

# Close the multiplexed master connection and clean up its socket on exit.
close_master() {
    local ip="${IP:-}"
    [ -n "$ip" ] && ssh $SSH_OPTS -O exit ${SSH_USER}@${ip} 2>/dev/null || true
    rm -rf "$SSH_CTRL_DIR" 2>/dev/null || true
}

check_connection() {
    local ip="$1"
    init_auth "$ip"
    print_info "Checking connection to $ip..."
    if ! do_ssh ${SSH_USER}@${ip} "echo 'Connected'" > /dev/null 2>&1; then
        print_error "Cannot connect to ${SSH_USER}@${ip}"
        print_error "Make sure the adapter is powered on and connected to WiFi"
        exit 1
    fi
    print_info "Connection successful"
}

check_archive() {
    local archive="$1"
    local name="$2"
    if [ ! -f "$archive" ]; then
        print_error "$name not found: $archive"
        print_error "Please ensure the archive is in the same directory as this script"
        exit 1
    fi
    print_info "Found $name: $(basename $archive)"
}

get_status() {
    local ip="$1"
    check_connection "$ip"

    echo ""
    echo "=== CPC200-CCPA Website Status ==="
    echo ""

    # Check what's currently installed
    do_ssh ${SSH_USER}@${ip} '
        echo "Persistent storage (/etc/boa/www):"
        if [ -f /etc/boa/www/js/app.js ]; then
            echo "  -> Replacement website (Vanilla JS)"
        elif [ -f /etc/boa/www/js/PublicV2.*.js.gz ]; then
            echo "  -> OEM website (Vue.js)"
        else
            echo "  -> Unknown/Missing"
        fi

        echo ""
        echo "Runtime storage (/tmp/boa/www):"
        if [ -L /tmp/boa/www ]; then
            target=$(readlink /tmp/boa/www)
            echo "  -> Symlinked to: $target"
        elif [ -f /tmp/boa/www/js/app.js ]; then
            echo "  -> Replacement website (Vanilla JS)"
        elif ls /tmp/boa/www/js/PublicV2.*.js.gz >/dev/null 2>&1; then
            echo "  -> OEM website (Vue.js)"
        else
            echo "  -> Unknown/Missing"
        fi

        echo ""
        echo "Disk usage:"
        echo "  /etc/boa: $(du -sh /etc/boa 2>/dev/null | cut -f1)"
        echo "  /tmp/boa: $(du -sh /tmp/boa 2>/dev/null | cut -f1)"
    '
}

do_install() {
    local ip="$1"

    check_archive "$NEW_WEBSITE_ARCHIVE" "new_website.tar.gz"
    check_connection "$ip"

    echo ""
    print_warn "This will REPLACE the OEM website with the replacement interface."
    print_warn "Make sure you have a backup (website_backup.tar.gz) before proceeding."
    echo ""
    read -p "Continue with installation? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi

    print_info "Uploading new_website.tar.gz to adapter..."
    do_scp "$NEW_WEBSITE_ARCHIVE" ${SSH_USER}@${ip}:/tmp/

    print_info "Installing replacement website..."
    do_ssh ${SSH_USER}@${ip} '
        set -e

        echo "Extracting archive..."
        cd /tmp
        rm -rf /tmp/new_website
        mkdir -p /tmp/new_website
        tar -xzf new_website.tar.gz -C /tmp/new_website

        echo "Removing OEM website files..."
        rm -rf /etc/boa/www/js/*.js.gz /etc/boa/www/js/*.js 2>/dev/null || true
        rm -rf /etc/boa/www/lang /etc/boa/www/static 2>/dev/null || true
        rm -f /etc/boa/www/advanced.html 2>/dev/null || true

        echo "Installing replacement files..."
        # Copy www files
        cp -f /tmp/new_website/etc/boa/www/index.html /etc/boa/www/
        mkdir -p /etc/boa/www/css /etc/boa/www/js
        cp -f /tmp/new_website/etc/boa/www/css/style.css /etc/boa/www/css/
        cp -f /tmp/new_website/etc/boa/www/js/*.js /etc/boa/www/js/

        # Copy CGI scripts (keep OEM server.cgi and upload.cgi, add new ones)
        cp -f /tmp/new_website/etc/boa/cgi-bin/config.cgi /etc/boa/cgi-bin/
        cp -f /tmp/new_website/etc/boa/cgi-bin/sysinfo.cgi /etc/boa/cgi-bin/
        cp -f /tmp/new_website/etc/boa/cgi-bin/governor.cgi /etc/boa/cgi-bin/
        cp -f /tmp/new_website/etc/boa/cgi-bin/logs.cgi /etc/boa/cgi-bin/
        cp -f /tmp/new_website/etc/boa/cgi-bin/wifi_clients.cgi /etc/boa/cgi-bin/
        cp -f /tmp/new_website/etc/boa/cgi-bin/restart.cgi /etc/boa/cgi-bin/
        cp -f /tmp/new_website/etc/boa/cgi-bin/streamstats.cgi /etc/boa/cgi-bin/
        cp -f /tmp/new_website/etc/boa/cgi-bin/term.cgi /etc/boa/cgi-bin/

        # Set permissions
        chmod 644 /etc/boa/www/index.html
        chmod 644 /etc/boa/www/css/style.css
        chmod 644 /etc/boa/www/js/*.js
        chmod 755 /etc/boa/cgi-bin/*.cgi

        # Disable USB override by removing custom_init.sh
        if [ -f /script/custom_init.sh ]; then
            mv /script/custom_init.sh /script/custom_init.sh.disabled
            echo "Disabled USB override script"
        fi

        # Remove USB www folder to prevent override
        if [ -d /mnt/UPAN/www ]; then
            mv /mnt/UPAN/www /mnt/UPAN/www.disabled
            echo "Disabled USB www folder"
        fi

        # Cleanup
        rm -rf /tmp/new_website /tmp/new_website.tar.gz

        echo "Installation complete!"
    '

    print_info "Installation successful!"
    print_info "Rebooting adapter..."

    do_ssh ${SSH_USER}@${ip} "sync; busybox reboot" || true

    echo ""
    print_info "Adapter is rebooting. Wait ~30 seconds then access http://${ip}"
    print_info "You may need to reconnect to the adapter's WiFi network."
}

do_restore() {
    local ip="$1"

    check_archive "$BACKUP_ARCHIVE" "website_backup.tar.gz"
    check_connection "$ip"

    echo ""
    print_warn "This will RESTORE the OEM website, removing the replacement interface."
    echo ""
    read -p "Continue with restore? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Restore cancelled"
        exit 0
    fi

    print_info "Uploading website_backup.tar.gz to adapter..."
    do_scp "$BACKUP_ARCHIVE" ${SSH_USER}@${ip}:/tmp/

    print_info "Restoring OEM website..."
    do_ssh ${SSH_USER}@${ip} '
        set -e

        echo "Extracting archive..."
        cd /tmp
        tar -xzf website_backup.tar.gz

        echo "Removing replacement website files..."
        rm -rf /etc/boa/www/* 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/config.cgi 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/sysinfo.cgi 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/governor.cgi 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/logs.cgi 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/wifi_clients.cgi 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/restart.cgi 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/streamstats.cgi 2>/dev/null || true
        rm -f /etc/boa/cgi-bin/term.cgi 2>/dev/null || true

        echo "Restoring OEM files..."
        cp -a /tmp/website_backup/etc/boa/www/* /etc/boa/www/
        cp -a /tmp/website_backup/etc/boa/cgi-bin/* /etc/boa/cgi-bin/
        cp -a /tmp/website_backup/etc/boa/images/* /etc/boa/images/ 2>/dev/null || true

        # Cleanup any leftover USB override files
        rm -f /script/custom_init.sh /script/custom_init.sh.disabled 2>/dev/null || true
        rm -rf /mnt/UPAN/www /mnt/UPAN/www.disabled 2>/dev/null || true

        # Cleanup
        rm -rf /tmp/website_backup /tmp/website_backup.tar.gz

        echo "Restore complete!"
    '

    print_info "Restore successful!"
    print_info "Rebooting adapter..."

    do_ssh ${SSH_USER}@${ip} "sync; busybox reboot" || true

    echo ""
    print_info "Adapter is rebooting. Wait ~30 seconds then access http://${ip}"
    print_info "You may need to reconnect to the adapter's WiFi network."
}

# Main
if [ $# -lt 1 ]; then
    print_usage
    exit 1
fi

COMMAND="$1"
IP="${2:-192.168.43.1}"

# Tear down the multiplexed SSH connection when the script exits.
trap close_master EXIT

case "$COMMAND" in
    install)
        if [ $# -lt 2 ]; then
            print_error "Missing IP address"
            print_usage
            exit 1
        fi
        do_install "$IP"
        ;;
    restore)
        if [ $# -lt 2 ]; then
            print_error "Missing IP address"
            print_usage
            exit 1
        fi
        do_restore "$IP"
        ;;
    status)
        if [ $# -lt 2 ]; then
            print_error "Missing IP address"
            print_usage
            exit 1
        fi
        get_status "$IP"
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        print_usage
        exit 1
        ;;
esac
