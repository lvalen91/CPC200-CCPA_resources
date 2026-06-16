#!/bin/sh
# CPU Governor CGI - Get/Set CPU scaling governor

echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Content-Type: application/json"
echo ""

GOV_PATH="/sys/devices/system/cpu/cpu0/cpufreq"

# Handle POST request to set governor
if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r new_gov
    # Sanitize input - only allow alphanumeric
    new_gov=$(echo "$new_gov" | tr -cd 'a-z')
    if [ -n "$new_gov" ] && [ -f "$GOV_PATH/scaling_governor" ]; then
        echo "$new_gov" > "$GOV_PATH/scaling_governor" 2>/dev/null
    fi
fi

# Get current governor
if [ -f "$GOV_PATH/scaling_governor" ]; then
    current=$(cat "$GOV_PATH/scaling_governor")
else
    current="unknown"
fi

# Get available governors
if [ -f "$GOV_PATH/scaling_available_governors" ]; then
    available=$(cat "$GOV_PATH/scaling_available_governors")
else
    available=""
fi

echo "{\"current\":\"$current\",\"available\":\"$available\"}"
