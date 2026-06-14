# evcc-keba-rfid-trigger

A lightweight, automated background service that bridges the gap between evcc and a Keba wallbox requiring external RFID authorization before charging can begin.

## The Problem

When a vehicle is plugged into a Keba wallbox operating with an active backend authorization scheme, evcc cannot start the charging cycle because the wallbox expects a valid RFID transmission within a 60-second window. 

This script decouples the authorization logic from your core evcc configuration file, monitoring the evcc REST API and automatically injecting a specific UDP RFID token only when a vehicle is connected and explicitly waiting for validation.

## Prerequisites

* Linux-based host (systemd supported)
* jq installed (sudo apt install jq)
* Netcat (nc) installed

## Installation

1. Clone this repository and move the script to your binaries folder:
   ```bash
   sudo cp evcc-rfid-trigger.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/evcc-rfid-trigger.sh
   ```

3. Open /usr/local/bin/evcc-rfid-trigger.sh and configure your settings:
   ```bash
   EVCC_API="http://127.0.0.1:7070/api/state"
   KEBA_IP="<your-keba-wallbox-ip>"
   RFID_ID="<your-rfid-id>"
   ```

4. Copy the systemd service file into place, reload, and enable it:
   ```bash
   sudo cp evcc-rfid-trigger.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now evcc-rfid-trigger.service
   ```

## Monitoring

You can check the operational status and view the live logs using standard journal tracking:

# Check service status
sudo systemctl status evcc-rfid-trigger.service

# Follow real-time logs
sudo journalctl -u evcc-rfid-trigger.service -f

## License

MIT
