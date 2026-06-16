#!/bin/sh
# Restart CGI - Trigger device restart

echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Content-Type: application/json"
echo ""

# Only allow POST requests for restart
if [ "$REQUEST_METHOD" != "POST" ] && [ "$REQUEST_METHOD" != "GET" ]; then
    echo "{\"error\":\"Method not allowed\"}"
    exit 1
fi

echo "{\"status\":\"restarting\"}"

# Schedule reboot in background after response is sent
# Note: Use busybox reboot - plain 'reboot' may not work on this busybox configuration
(sleep 2 && busybox reboot) &
