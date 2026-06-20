#!/bin/bash

set -euo pipefail

if ! command -v jq &> /dev/null; then
    echo "ERROR: 'jq' is not installed, but it is required for JSON parsing." >&2
    echo "Please install it using: sudo apt install jq" >&2
    exit 1
fi

EVCC_API="http://127.0.0.1:7070/api/state"
KEBA_IP="<your-keba-wallbox-ip>"
RFID_ID="<your-rfid-id>"
INTERVAL=10

# Tracking variable to ensure we only send ONE authorization per evcc charge request
authorization_done=false

echo "[$(date +'%F %T')] EVCC RFID Trigger started successfully. Monitoring deterministic state..."

while true; do
    if evcc_response=$(curl -sS --connect-timeout 3 "$EVCC_API" 2>/dev/null); then

        # We extract 'enabled', 'connected', and 'charging' booleans
        parsed_state=$(echo "$evcc_response" | jq -r '
            .loadpoints[0] as $lp
            | "\($lp.enabled) \($lp.connected) \($lp.charging)"
        ' 2>/dev/null)

        if [ -n "$parsed_state" ]; then
            read -r lp_enabled connected charging <<< "$parsed_state"

            # Condition: Car connected, evcc wants to charge, but power flow has NOT started yet
            if [ "$connected" = "true" ] && [ "$lp_enabled" = "true" ] && [ "$charging" = "false" ]; then

                if [ "$authorization_done" = false ]; then
                    echo "[$(date +'%F %T')] evcc enabled charging but wallbox is blocked. Injecting RFID token..."
                    echo "start $RFID_ID" | nc -u -w 1 "$KEBA_IP" 7090
                    authorization_done=true
                fi

            else
                # Reset if charging pauses or vehicle disconnects
                if [ "$lp_enabled" = "false" ] || [ "$connected" = "false" ]; then
                    if [ "$authorization_done" = true ]; then
                        echo "[$(date +'%F %T')] evcc paused charging or car disconnected. Readying trigger for next cycle."
                        authorization_done=false
                    fi
                fi
                # Reset tracking once charging is actively running
                if [ "$charging" = "true" ] && [ "$authorization_done" = true ]; then
                    authorization_done=false
                fi
            fi
        fi
    else
        echo "[$(date +'%F %T')] WARNING: evcc API unreachable..." >&2
    fi

    sleep "$INTERVAL"
done
