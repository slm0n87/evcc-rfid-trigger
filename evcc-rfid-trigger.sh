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

# Status variable for the edge trigger (prevents repetitive firing)
authorization_done=false

echo "[$(date +'%F %T')] EVCC RFID Trigger started successfully. Monitoring loadpoint reasons..."

while true; do
    if evcc_response=$(curl -sS --connect-timeout 3 "$EVCC_API" 2>/dev/null); then

        # We extract 'enabled', 'connected', and 'chargerStatusReason'
        parsed_state=$(echo "$evcc_response" | jq -r '
            .loadpoints[0] as $lp
            | "\($lp.enabled) \($lp.connected) \($lp.chargerStatusReason)"
        ' 2>/dev/null)

        if [ -n "$parsed_state" ]; then
            read -r lp_enabled connected status_reason <<< "$parsed_state"

            # CONDITION: Car is plugged in, Keba wants auth, AND evcc wants to charge (enabled=true)
            if [ "$connected" = "true" ] && [ "$status_reason" = "waitingforauthorization" ] && [ "$lp_enabled" = "true" ]; then

                if [ "$authorization_done" = false ]; then
                    echo "[$(date +'%F %T')] Sun is ready (evcc enabled) & Wallbox needs auth. Injecting RFID token..."
                    echo "start $RFID_ID" | nc -u -w 1 "$KEBA_IP" 7090
                    authorization_done=true
                fi

            else
                # RESET LOGIC:
                # If evcc switches off/pauses (enabled=false) OR the car is unplugged,
                # we reset the lock so it can fire again on the next sunny window.
                if [ "$lp_enabled" = "false" ] || [ "$connected" = "false" ]; then
                    if [ "$authorization_done" = true ]; then
                        echo "[$(date +'%F %T')] evcc paused charging or car disconnected. Readying trigger for next sun window."
                        authorization_done=false
                    fi
                fi
            fi
        fi
    else
        echo "[$(date +'%F %T')] WARNING: evcc API unreachable..." >&2
    fi

    sleep "$INTERVAL"
done
