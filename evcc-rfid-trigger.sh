#!/bin/bash

set -euo pipefail

# 1. Check if jq is installed (Exit Early)
if ! command -v jq &> /dev/null; then
    echo "ERROR: 'jq' is not installed, but it is required for JSON parsing." >&2
    echo "Please install it using: sudo apt install jq" >&2
    exit 1
fi

# Configuration
EVCC_API="http://127.0.0.1:7070/api/state"
KEBA_IP="<your-keba-wallbox-ip>"
RFID_ID="<your-rfid-id>"
INTERVAL=10

# Status variable for the edge trigger (prevents repetitive firing)
rfid_sent=false

echo "[$(date +'%F %T')] EVCC RFID Trigger started successfully. Monitoring loadpoint reasons..."

while true; do
    # Query the API
    if evcc_response=$(curl -sS --connect-timeout 3 "$EVCC_API" 2>/dev/null); then

        # New robust JQ parsing:
        # Extracts whether a vehicle is physically connected and the exact status reason.
        # Output format example: "true waitingforauthorization" or "false none"
        parsed_state=$(echo "$evcc_response" | jq -r '
            .loadpoints[0] as $lp
            | "\($lp.connected) \($lp.chargerStatusReason)"
        ' 2>/dev/null)

        if [ -n "$parsed_state" ]; then
            read -r connected status_reason <<< "$parsed_state"

            # TRIGGER CONDITION: A car is plugged in AND the wallbox is hanging on authorization
            if [ "$connected" = "true" ] && [ "$status_reason" = "waitingforauthorization" ]; then
                if [ "$rfid_sent" = false ]; then
                    echo "[$(date +'%F %T')] Wallbox is waiting for authorization. Injecting RFID token via UDP..."

                    # Fire the UDP packet to the Keba wallbox
                    echo "start $RFID_ID" | nc -u -w 1 "$KEBA_IP" 7090
                    rfid_sent=true
                fi
            else
                # Reset the trigger once the car is unplugged or successfully authorized
                if [ "$rfid_sent" = true ] && [ "$status_reason" != "waitingforauthorization" ]; then
                    echo "[$(date +'%F %T')] State changed (Authorization complete or vehicle disconnected). Resetting trigger."
                    rfid_sent=false
                fi
            fi
        fi
    else
        echo "[$(date +'%F %T')] WARNING: evcc API at $EVCC_API is unreachable..." >&2
    fi

    sleep "$INTERVAL"
done
