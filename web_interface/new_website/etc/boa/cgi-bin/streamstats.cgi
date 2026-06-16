#!/bin/sh
# Stream stats CGI - Parses ttyLog for video/audio frame rates

echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Content-Type: application/json"
echo ""

# Get the most recent frame rate line from ttyLog
LOGFILE="/tmp/ttyLog"

if [ -f "$LOGFILE" ]; then
    # Parse the last frame rate entry
    LINE=$(grep "box video frame rate" "$LOGFILE" | tail -1)

    if [ -n "$LINE" ]; then
        # Extract: box video frame rate: 30, 109.78 KB/s, audio frame rate: 17, 191.45 KB/s
        VIDEO_FPS=$(echo "$LINE" | sed -n 's/.*video frame rate: \([0-9]*\),.*/\1/p')
        VIDEO_RATE=$(echo "$LINE" | sed -n 's/.*video frame rate: [0-9]*, \([0-9.]*\) KB.*/\1/p')
        AUDIO_FPS=$(echo "$LINE" | sed -n 's/.*audio frame rate: \([0-9]*\),.*/\1/p')
        AUDIO_RATE=$(echo "$LINE" | sed -n 's/.*audio frame rate: [0-9]*, \([0-9.]*\) KB.*/\1/p')

        # Default to 0 if parsing failed
        VIDEO_FPS=${VIDEO_FPS:-0}
        VIDEO_RATE=${VIDEO_RATE:-0}
        AUDIO_FPS=${AUDIO_FPS:-0}
        AUDIO_RATE=${AUDIO_RATE:-0}

        echo "{\"videoFps\":$VIDEO_FPS,\"videoRate\":$VIDEO_RATE,\"audioFps\":$AUDIO_FPS,\"audioRate\":$AUDIO_RATE}"
    else
        echo "{\"videoFps\":0,\"videoRate\":0,\"audioFps\":0,\"audioRate\":0}"
    fi
else
    echo "{\"videoFps\":0,\"videoRate\":0,\"audioFps\":0,\"audioRate\":0,\"error\":\"log not found\"}"
fi
