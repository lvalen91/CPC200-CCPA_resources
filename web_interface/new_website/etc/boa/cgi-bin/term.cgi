#!/bin/sh
# Terminal CGI - passthrough shell command runner for the CPC200-CCPA
#
# Runs an arbitrary command supplied by the client and returns its combined
# stdout/stderr, exit code, and resulting working directory. There is NO input
# sanitization by design: this IS a shell. boa.conf sets `User root`, so every
# command runs as root, exactly like the other CGIs in this interface.
#
# SECURITY NOTE: this is unauthenticated root command execution for anyone who
# can reach the boa server (i.e. anyone on the adapter's WiFi AP). That is the
# same exposure the adapter already ships via root-no-password dropbear SSH and
# (optionally) telnetd, so it adds no new attack surface on a research adapter.
# Do not deploy this on a unit exposed to an untrusted network.
#
# Request:  POST body
#             line 1            = working directory to start in
#             remaining lines   = command to run (full shell syntax)
# Response: text/plain
#             <combined command output>
#             ###CPCTERM_META###<exit_code>|<new_working_directory>   (final line)

echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: POST, OPTIONS"
echo "Content-Type: text/plain"
echo "Cache-Control: no-store"
echo ""

# Only POST carries a command; preflight/GET just returns headers.
[ "$REQUEST_METHOD" = "POST" ] || exit 0

# Read the POST body into a temp file (avoids command-substitution mangling).
TMP="/tmp/term.$$"
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    dd bs=1 count="$CONTENT_LENGTH" of="$TMP" 2>/dev/null
else
    : > "$TMP"
fi

START_CWD=$(head -n 1 "$TMP")
CMD=$(sed '1d' "$TMP")
rm -f "$TMP"

# Fall back to / if the client-supplied directory no longer exists.
[ -d "$START_CWD" ] || START_CWD="/"

# Run the command inside a subshell rooted at START_CWD. Using `eval` (not a
# child `sh -c`) means a `cd` in the command persists to the `pwd` we capture
# below, so the new directory can be returned to the client and echoed back on
# the next request -> a persistent working directory across stateless calls.
# stdin is /dev/null so commands that try to read input get EOF instead of
# hanging the request.
RESULT=$(
    cd "$START_CWD" 2>/dev/null || cd /
    eval "$CMD" </dev/null 2>&1
    RC=$?
    printf '\n###CPCTERM_META###%s|%s' "$RC" "$(pwd)"
)

printf '%s' "$RESULT"
