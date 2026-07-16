#!/bin/bash
#
# Pre-launch environment checks for Proton, Wine, and required server paths.
# prelaunch_check.sh - Comprehensive environment check before starting the ARK server

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"

# Function to check and create directory if it doesn't exist
check_create_directory() {
  local dir_path="$1"
  if [ ! -d "$dir_path" ]; then
    echo "Creating directory: $dir_path"
    mkdir -p "$dir_path"
    # Set proper permissions
    chmod 755 "$dir_path"
    return 1
  fi
  return 0
}

# Repair only prefix entries that lack the minimum access Proton/Wine needs.
# Avoid recursively rewriting already-correct metadata on large persisted prefixes.
repair_proton_prefix_permissions() {
  local prefix_path="$1"

  if [[ ! -d "$prefix_path" ]]; then
    echo "ERROR: Proton prefix directory not found: $prefix_path"
    return 1
  fi

  find "$prefix_path" -type d ! -perm -755 -exec chmod u+rwx,go+rx -- {} +
  find "$prefix_path" -type f ! -perm -644 -exec chmod u+rw,go+r -- {} +
}

# Function to check for critical files
check_critical_file() {
  local file_path="$1"
  local optional="${2:-false}"
  
  if [ ! -f "$file_path" ]; then
    if [ "$optional" = "true" ]; then
      echo "NOTICE: Optional file not found: $file_path"
      return 1
    elif [[ "$file_path" == *"ArkAscendedServer.exe"* ]]; then
      # Special case for server executable - don't show as error
      # We'll handle this message in check_server_files instead
      return 1
    else
      echo "ERROR: Critical file not found: $file_path"
      return 1
    fi
  fi
  echo "File check passed: $file_path"
  return 0
}

# Function to check Proton installations
check_proton_installations() {
  echo "Checking for Proton installations..."

  if ! resolve_pinned_proton; then
    echo "Proton installation check: FAILED"
    return 1
  fi

  echo "Pinned Proton installation found: $POK_PROTON_VERSION"
  echo "Proton executable: $POK_PROTON_EXECUTABLE"
  echo "Proton installation check: PASSED"
  return 0
}

# Function to check and initialize Wine/Proton environment
check_wine_environment() {
  echo "Checking Wine/Proton environment..."
  
  local WINE_CHECK_PASSED=false
  
  # Set up virtual display for headless operation
  export DISPLAY=:0.0
  echo "Setting up virtual display at :0.0"
  if command -v Xvfb >/dev/null 2>&1; then
    # Kill any existing Xvfb processes
    pkill Xvfb >/dev/null 2>&1 || true
    
    # Create .X11-unix directory first to avoid errors
    mkdir -p /tmp/.X11-unix 2>/dev/null || true
    chmod 1777 /tmp/.X11-unix 2>/dev/null || true
    
    # Start Xvfb with error output suppressed
    Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
    echo "Started Xvfb with PID: $!"
    # Give Xvfb time to start
    sleep 2
  else
    echo "WARNING: Xvfb not found. X applications might not work properly."
  fi
  
  # Check if Wine is available in PATH
  if command -v wine >/dev/null 2>&1; then
    echo "Wine binary found in PATH"
    
    # Set essential Wine environment variables
    export WINEDLLOVERRIDES="*version=n,b;vcrun2022=n,b"
    export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
    
    # Test if Wine works
    if DISPLAY=:0.0 WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine --version >/dev/null 2>&1; then
      echo "Wine basic functionality check: PASSED"
      WINE_CHECK_PASSED=true
    else
      echo "Wine found but failed basic test. Trying to fix..."
      # Try to set up Wine library paths
      export LD_LIBRARY_PATH="/usr/lib/wine:/usr/lib32/wine:$LD_LIBRARY_PATH"
      
      # Test again
      if DISPLAY=:0.0 WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine --version >/dev/null 2>&1; then
        echo "Wine basic functionality check after library path fix: PASSED"
        WINE_CHECK_PASSED=true
      else
        echo "Wine basic functionality check: FAILED"
      fi
    fi
  else
    echo "Wine binary not found in PATH"
  fi
  
  # Check/create Proton prefix
  echo "Checking Proton prefix..."
  local PREFIX_PATH="${STEAM_COMPAT_DATA_PATH}/pfx"
  
  check_create_directory "$PREFIX_PATH"
  check_create_directory "$PREFIX_PATH/drive_c"
  check_create_directory "$PREFIX_PATH/drive_c/windows/system32"
  check_create_directory "$PREFIX_PATH/drive_c/Program Files"
  check_create_directory "$PREFIX_PATH/drive_c/Program Files (x86)"
  check_create_directory "$PREFIX_PATH/drive_c/users/steamuser"
  
  # Create required Wine registry files if they don't exist
  for reg_file in "system.reg" "user.reg" "userdef.reg"; do
    if [ ! -f "$PREFIX_PATH/$reg_file" ]; then
      echo "Creating $reg_file..."
      case "$reg_file" in
        "system.reg")
          echo "WINE REGISTRY Version 2" > "$PREFIX_PATH/$reg_file"
          echo ";; All keys relative to \\\\Machine" >> "$PREFIX_PATH/$reg_file"
          echo "#arch=win64" >> "$PREFIX_PATH/$reg_file"
          echo "" >> "$PREFIX_PATH/$reg_file"
          ;;
        "user.reg")
          echo "WINE REGISTRY Version 2" > "$PREFIX_PATH/$reg_file"
          echo ";; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000" >> "$PREFIX_PATH/$reg_file"
          echo "#arch=win64" >> "$PREFIX_PATH/$reg_file"
          echo "[Software\\\\Wine\\\\DllOverrides]" >> "$PREFIX_PATH/$reg_file"
          echo "\"*version\"=\"native,builtin\"" >> "$PREFIX_PATH/$reg_file"
        echo "\"vcrun2022\"=\"native,builtin\"" >> "$PREFIX_PATH/$reg_file"
          echo "" >> "$PREFIX_PATH/$reg_file"
          ;;
        "userdef.reg")
          echo "WINE REGISTRY Version 2" > "$PREFIX_PATH/$reg_file"
          echo ";; All keys relative to \\\\User\\\\DefUser" >> "$PREFIX_PATH/$reg_file"
          echo "#arch=win64" >> "$PREFIX_PATH/$reg_file"
          echo "" >> "$PREFIX_PATH/$reg_file"
          ;;
      esac
    else
      # If user.reg exists but doesn't have DllOverrides, add them
      if [ "$reg_file" = "user.reg" ] && ! grep -q "DllOverrides" "$PREFIX_PATH/$reg_file"; then
        echo "Adding DLL overrides to user.reg..."
        echo "[Software\\\\Wine\\\\DllOverrides]" >> "$PREFIX_PATH/$reg_file"
        echo "\"*version\"=\"native,builtin\"" >> "$PREFIX_PATH/$reg_file"
        echo "\"vcrun2022\"=\"native,builtin\"" >> "$PREFIX_PATH/$reg_file"
      fi
    fi
  done
  
  # Make sure tracked_files exists
  touch "${STEAM_COMPAT_DATA_PATH}/tracked_files" 2>/dev/null || true
  
  # Repair only entries that are missing required access bits. This avoids
  # expensive metadata rewrites across an already-correct persisted prefix.
  repair_proton_prefix_permissions "$PREFIX_PATH"
  
  # Create Visual C++ Redistributable directory structure for AsaApi
  if [ "${API}" = "TRUE" ]; then
    echo "Setting up Visual C++ directory structure for AsaApi..."
    local vc_dir="$PREFIX_PATH/drive_c/Program Files (x86)/Microsoft Visual Studio"
    check_create_directory "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT"
    check_create_directory "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT"

    # Create dummy DLL files to make AsaApiLoader believe VC++ is installed (both architectures)
    touch "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/msvcp140.dll"
    touch "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/vcruntime140.dll"
    touch "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT/msvcp140.dll"
    touch "$vc_dir/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT/vcruntime140.dll"

    # Trigger winetricks install if runtime DLLs are missing
    if [ ! -f "$PREFIX_PATH/drive_c/windows/SysWOW64/msvcp140.dll" ] || \
       [ ! -f "$PREFIX_PATH/drive_c/windows/SysWOW64/vcruntime140.dll" ] || \
       [ ! -f "$PREFIX_PATH/drive_c/windows/system32/msvcp140.dll" ] || \
       [ ! -f "$PREFIX_PATH/drive_c/windows/system32/vcruntime140.dll" ]; then
      echo "Visual C++ runtime DLLs missing; attempting winetricks vcrun2022 install..."
      WINEPREFIX="$PREFIX_PATH" winetricks -q vcrun2022 >/dev/null 2>&1 || true
    fi
  fi
  
  echo "Wine/Proton environment check: PASSED"
  return 0
}

# Function to check server files
check_server_files() {
  echo "Checking ARK server files..."
  
  # Check server binaries
  local server_binary="${ASA_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
  if ! check_critical_file "$server_binary"; then
    echo "ℹ️ Server binary not found - this is normal on first run."
    echo "ℹ️ The server files will be downloaded automatically in the next step."
    echo "Server files check: PENDING DOWNLOAD"
    return 1
  fi
  
  # Check AsaApi files if enabled
  if [ "${API}" = "TRUE" ]; then
    echo "Checking AsaApi files..."
    local api_binary="${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe"
    local api_logs_dir="${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    
    check_create_directory "$api_logs_dir"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Binaries/Win64"
    
    if ! check_critical_file "$api_binary" "true"; then
      echo "NOTICE: AsaApi binary not found. Attempting installation..."
      install_ark_server_api
      if ! check_critical_file "$api_binary" "true"; then
        echo "NOTICE: Failed to install AsaApi. Will retry later."
        echo "AsaApi check: PENDING"
      else
        echo "AsaApi installation successful."
        echo "AsaApi check: PASSED"
      fi
    else
      echo "AsaApi check: PASSED"
    fi
  fi
  
  # Check configuration directories
  check_create_directory "${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer"
  check_create_directory "${ASA_DIR}/ShooterGame/Saved/SavedArks"
  check_create_directory "${ASA_DIR}/ShooterGame/Saved/Logs"
  
  echo "Server files check: PASSED"
  return 0
}

# Main function to run all checks
run_all_checks() {
  echo "Running all pre-launch checks..."
  local all_passed=true
  
  # Check for Proton installations
  if ! check_proton_installations; then
    all_passed=false
  fi
  
  # Check/initialize Wine environment
  if ! check_wine_environment; then
    all_passed=false
  fi
  
  # Check server files
  if ! check_server_files; then
    all_passed=false
  fi
  
  # Force file system sync
  sync
  sleep 2
  
  if [ "$all_passed" = "true" ]; then
    echo "====== All pre-launch checks PASSED ======"
    return 0
  else
    echo "====== Some pre-launch checks FAILED ======"
    echo "Attempting to fix issues and continue..."
    
    # Force initialize Proton prefix as a final attempt to fix issues
    initialize_proton_prefix
    
    # Force sync again
    sync
    sleep 3
    
    return 1
  fi
}

main() {
  prepare_runtime_env
  echo "====== ARK Survival Ascended Pre-Launch Environment Check ======"
  run_all_checks
  echo "====== Pre-Launch Environment Check Complete ======"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
