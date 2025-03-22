#!/bin/bash
source /home/pok/scripts/common.sh

# Check for updates using SteamCMD only
echo "[INFO] Checking for updates using SteamCMD..."
saved_build_id=$(get_build_id_from_acf)
current_build_id=$(get_current_build_id)

# Exit with error if we couldn't get the build ID from SteamCMD
if [ -z "$current_build_id" ] || [[ "$current_build_id" == error* ]]; then
    echo "[ERROR] Failed to get build ID from SteamCMD."
    exit 2
fi

# Validate build IDs are numeric only
if ! [[ "$current_build_id" =~ ^[0-9]+$ ]]; then
    echo "[WARNING] SteamCMD returned invalid build ID format: '$current_build_id'"
    exit 2
fi

if ! [[ "$saved_build_id" =~ ^[0-9]+$ ]]; then
    echo "[WARNING] Saved build ID has invalid format: '$saved_build_id'. Will attempt update."
    saved_build_id=""  # Force update by invalidating the saved ID
fi

# Ensure both IDs are stripped of any whitespace
current_build_id=$(echo "$current_build_id" | tr -d '[:space:]')
saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')

if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
    echo "===================== BUILD ID COMPARISON ====================="
    echo "🔵 SteamCMD Current Build ID: $current_build_id"
    echo "🟢 Server Installed Build ID: $saved_build_id"
    echo "=============================================================="
    
    # Diagnostic comparison for debugging
    if [ "${VERBOSE_DEBUG}" = "TRUE" ]; then
        echo "Detailed comparison:"
        echo "   - Current: '${current_build_id}' (length: ${#current_build_id})"
        echo "   - Saved: '${saved_build_id}' (length: ${#saved_build_id})"
        if [ "$current_build_id" = "$saved_build_id" ]; then
          echo "   - String comparison result: MATCH"
        else
          echo "   - String comparison result: DIFFERENT"
        fi
    fi
fi

if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "[INFO] ✅ UPDATE AVAILABLE: SteamCMD has newer build ($current_build_id) than installed ($saved_build_id)"
    fi
    exit 0
else
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
        echo "[INFO] ✅ No updates available. Server is running latest SteamCMD build ID: $current_build_id"
    fi
    exit 1
fi