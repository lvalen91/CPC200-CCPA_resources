#!/bin/sh
# Config CGI - Read/write settings via /usr/sbin/riddleBoxCfg
# Used for keys NOT in server.cgi's 48-field API (AdvancedFeatures, CustomCarLogo)
# and for reading runtime values that server.cgi 'infos' doesn't return
# mode=full returns ALL 106 config keys for the full dump view

get_val() {
    val=$(/usr/sbin/riddleBoxCfg -g "$1" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo "null"
    else
        echo "$val"
    fi
}

# For string keys — wrap in quotes, escape special chars
get_str() {
    val=$(/usr/sbin/riddleBoxCfg -g "$1" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo "null"
    else
        # Escape backslashes and quotes for JSON
        val=$(printf '%s' "$val" | sed 's/\\/\\\\/g;s/"/\\"/g')
        printf '"%s"' "$val"
    fi
}

# For array keys — only pass through if valid JSON array, else null
get_arr() {
    val=$(/usr/sbin/riddleBoxCfg -g "$1" 2>/dev/null)
    case "$val" in
        \[*) echo "$val" ;;
        *)   echo "null" ;;
    esac
}

# Allowlist of keys that can be set via this endpoint
# Only keys NOT in server.cgi's API belong here
is_allowed_key() {
    case "$1" in
        AdvancedFeatures|CustomCarLogo|UdiskMode) return 0 ;;
        *) return 1 ;;
    esac
}

# Common CORS headers (no blank line yet — caller ends headers)
send_cors() {
    echo "Access-Control-Allow-Origin: *"
    echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
    echo "Content-Type: application/json"
}

# POST: set a config key via /usr/sbin/riddleBoxCfg
if [ "$REQUEST_METHOD" = "POST" ]; then
    send_cors
    echo ""

    # Read POST body
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
        POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    else
        POST_DATA=""
    fi

    # Parse key=...&val=... from URL-encoded body
    POST_KEY=$(echo "$POST_DATA" | tr '&' '\n' | grep '^key=' | head -1 | sed 's/^key=//' | tr -cd 'A-Za-z0-9_')
    POST_VAL=$(echo "$POST_DATA" | tr '&' '\n' | grep '^val=' | head -1 | sed 's/^val=//' | tr -cd '0-9')

    if [ -z "$POST_KEY" ] || [ -z "$POST_VAL" ]; then
        echo '{"error":"missing key or val"}'
        exit 0
    fi

    if ! is_allowed_key "$POST_KEY"; then
        echo '{"error":"key not allowed"}'
        exit 0
    fi

    /usr/sbin/riddleBoxCfg -s "$POST_KEY" "$POST_VAL" 2>/dev/null
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        echo "{\"ok\":true,\"key\":\"$POST_KEY\",\"val\":$POST_VAL}"
    else
        echo "{\"error\":\"/usr/sbin/riddleBoxCfg failed\",\"code\":$RESULT}"
    fi
    exit 0
fi

# GET mode=full: return ALL 106 config keys (79 int + 24 string + 3 array)
# Integer keys ordered by table index; string keys by string table index
case "$QUERY_STRING" in
    *mode=full*)
        send_cors
        echo ""
        printf '{'

        # ---- 79 Integer Keys (table index order) ----
        INT_KEYS="iAP2TransMode MediaQuality MediaLatency UdiskMode LogMode BoxConfig_UI_Lang BoxConfig_DelayStart BoxConfig_preferSPSPPSType NotCarPlayH264DecreaseMode NeedKeyFrame EchoLatency DisplaySize UseBTPhone MicGainSwitch CustomFrameRate NeedAutoConnect BackgroundMode HudGPSSwitch CarDate WiFiChannel AutoPlauMusic MouseMode CustomCarLogo VideoBitRate VideoResolutionHeight VideoResolutionWidth UDiskPassThrough AndroidWorkMode CarDrivePosition AndroidAutoWidth AndroidAutoHeight ScreenDPI KnobMode NaviAudio ScreenPhysicalW ScreenPhysicalH CallQuality VoiceQuality AutoUpdate LastBoxUIType BoxSupportArea HNPInterval lightType MicType RepeatKeyframe BtAudio MicMode SpsPpsMode MediaPacketLen TtsPacketLen VrPacketLen TtsVolumGain VrVolumGain CarLinkType SendHeartBeat SendEmptyFrame autoDisplay USBConnectedMode USBTransMode ReturnMode LogoType BackRecording FastConnect WiredConnect ImprovedFluency NaviVolume OriginalResolution AutoConnectInterval AutoResetUSB HiCarConnectMode GNSSCapability DashboardInfo AudioMultiBusMode DayNightMode InternetHotspots UseUartBLE WiFiP2PMode DuckPosition AdvancedFeatures"

        first=1
        for key in $INT_KEYS; do
            [ $first -eq 0 ] && printf ','
            first=0
            printf '"%s":%s' "$key" "$(get_val "$key")"
        done

        # ---- 24 String Keys (string table index order) ----
        STR_KEYS="CarBrand CarModel BluetoothName WifiName CustomBluetoothName CustomWifiName LastPhoneSpsPps CustomId LastConnectedDevice IgnoreUpdateVersion CustomBoxName WifiPassword BrandName BrandBluetoothName BrandWifiName BrandServiceURL BoxIp USBProduct USBManufacturer USBPID USBVID USBSerial oemName BrandWifiChannel"

        for key in $STR_KEYS; do
            printf ',"%s":%s' "$key" "$(get_str "$key")"
        done

        # ---- 3 Array Keys ----
        for key in DevList DeletedDevList LangList; do
            printf ',"%s":%s' "$key" "$(get_arr "$key")"
        done

        printf '}'
        exit 0
        ;;
esac

# GET (default): return settings for interactive UI controls
send_cors
echo ""
echo "{"
echo "\"MicType\":$(get_val MicType),"
echo "\"BtAudio\":$(get_val BtAudio),"
echo "\"BackgroundMode\":$(get_val BackgroundMode),"
echo "\"HudGPSSwitch\":$(get_val HudGPSSwitch),"
echo "\"FastConnect\":$(get_val FastConnect),"
echo "\"UdiskMode\":$(get_val UdiskMode),"
echo "\"AdvancedFeatures\":$(get_val AdvancedFeatures),"
echo "\"CustomCarLogo\":$(get_val CustomCarLogo)"
echo "}"
