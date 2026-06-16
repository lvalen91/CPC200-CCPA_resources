#!/bin/sh
# Log download CGI - Serves various log files

# CORS headers
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"

# Parse query string for type parameter
TYPE=$(echo "$QUERY_STRING" | sed -n 's/.*type=\([^&]*\).*/\1/p')

case "$TYPE" in
    dmesg)
        echo "Content-Type: text/plain"
        echo "Content-Disposition: attachment; filename=dmesg.txt"
        echo ""
        dmesg 2>/dev/null || echo "Unable to read kernel log"
        ;;
    userspace)
        echo "Content-Type: text/plain"
        echo "Content-Disposition: attachment; filename=userspace.log"
        echo ""
        if [ -f /tmp/userspace.log ]; then
            cat /tmp/userspace.log
        elif [ -f /tmp/box.log ]; then
            cat /tmp/box.log
        else
            echo "No userspace log found"
        fi
        ;;
    config)
        echo "Content-Type: application/json"
        echo "Content-Disposition: attachment; filename=riddle.conf"
        echo ""
        if [ -f /etc/riddle.conf ]; then
            cat /etc/riddle.conf
        else
            echo "{}"
        fi
        ;;
    *)
        echo "Content-Type: application/json"
        echo ""
        echo "{\"error\":\"Invalid log type. Use: dmesg, userspace, config\"}"
        ;;
esac
