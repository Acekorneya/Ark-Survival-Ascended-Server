#!/bin/bash

source /home/pok/scripts/common.sh

# Configure ulimit
ulimit -n 100000

# Create directories if not already present
mkdir -p ${ASA_DIR}/Engine/Binaries/ThirdParty/Steamworks/Steamv153/Win64/

if [ "${BACKUP_DIR}" != "false" ] ; then
  # Create backup directory if not already present
  mkdir -p ${BACKUP_DIR}
fi

# Mount backup directory
if [ -d "${BACKUP_DIR}" ] && [ "${BACKUP_DIR}" != "false" ]; then
  echo "----Backup directory exists, will mount from ${BACKUP_DIR}----"
  # Ensure the Save & Config directories exist
  mkdir -p ${ASA_DIR}/ShooterGame/Saved/SavedArks
  mkdir -p ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer

  # Create symlinks for the backup
  if [ ! -L "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ] && [ -d "${BACKUP_DIR}/SavedArks/${MAP_NAME}" ]; then
    echo "Creating symbolic link for the SavedArks/${MAP_NAME} from the backup..."
    rm -rf ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
    ln -sf ${BACKUP_DIR}/SavedArks/${MAP_NAME} ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
  elif [ ! -d "${BACKUP_DIR}/SavedArks/${MAP_NAME}" ]; then
    echo "Creating backup directory for SavedArks/${MAP_NAME}..."
    mkdir -p ${BACKUP_DIR}/SavedArks/${MAP_NAME}
    # If the local directory exists but is not a symlink, move its contents to the backup and create a symlink
    if [ -d "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ] && [ ! -L "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ]; then
      echo "Moving existing data to backup location..."
      cp -aR ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}/* ${BACKUP_DIR}/SavedArks/${MAP_NAME}/
      rm -rf ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
    fi
    ln -sf ${BACKUP_DIR}/SavedArks/${MAP_NAME} ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
  fi

  # Handle config files
  if [ ! -f "${BACKUP_DIR}/Config/Game.ini" ] && [ -f "${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini" ]; then
    echo "Moving current Game.ini to backup location..."
    cp -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini ${BACKUP_DIR}/Config/Game.ini
  fi

  if [ ! -f "${BACKUP_DIR}/Config/GameUserSettings.ini" ] && [ -f "${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" ]; then
    echo "Moving current GameUserSettings.ini to backup location..."
    cp -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini ${BACKUP_DIR}/Config/GameUserSettings.ini
  fi

  if [ -f "${BACKUP_DIR}/Config/Game.ini" ]; then
    echo "Linking Game.ini from backup..."
    rm -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini
    ln -sf ${BACKUP_DIR}/Config/Game.ini ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini
  fi

  if [ -f "${BACKUP_DIR}/Config/GameUserSettings.ini" ]; then
    echo "Linking GameUserSettings.ini from backup..."
    rm -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
    ln -sf ${BACKUP_DIR}/Config/GameUserSettings.ini ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
  fi
fi

# Enable container-aware Proton environment initialization
export CONTAINER_MODE="TRUE"

# Setup X virtual framebuffer for headless operation
setup_virtual_display() {
  echo "Setting up virtual display for headless operation..."
  export DISPLAY=:0.0
  
  # Check if Xvfb is installed
  if command -v Xvfb >/dev/null 2>&1; then
    # Kill any existing Xvfb processes
    pkill Xvfb >/dev/null 2>&1 || true
    
    # Start Xvfb
    Xvfb :0 -screen 0 1024x768x16 &
    XVFB_PID=$!
    echo "Started Xvfb with PID: $XVFB_PID"
    
    # Give Xvfb time to start
    sleep 2
    
    # Verify Xvfb is running
    if kill -0 $XVFB_PID 2>/dev/null; then
      echo "Xvfb is running successfully."
    else
      echo "WARNING: Xvfb failed to start. X applications might not work properly."
    fi
  else
    echo "WARNING: Xvfb not found. Installing minimal X server support..."
    apt-get update && apt-get install -y --no-install-recommends xvfb x11-xserver-utils xauth
    
    # Try again after installation
    Xvfb :0 -screen 0 1024x768x16 &
    XVFB_PID=$!
    echo "Started Xvfb with PID: $XVFB_PID"
    sleep 2
  fi
  
  # Export essential display environment variables
  export WINEDLLOVERRIDES="*version=n,b;vcrun2019=n,b"
  export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
  
  echo "Virtual display setup complete."
}

# Set up virtual display
setup_virtual_display

# Run comprehensive pre-launch environment check
echo "----Running pre-launch environment check----"
chmod +x /home/pok/scripts/prelaunch_check.sh
/home/pok/scripts/prelaunch_check.sh

# Robust AsaApi initialization for container environment
verify_proton_environment() {
  echo "----Robust Proton Environment Verification for AsaApi----"
  
  # Ensure we have the correct directory structure
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/users/steamuser"
  
  # Step 1: Check and find available Proton versions
  echo "Searching for available Proton GE versions..."
  PROTON_BASE_DIR="/home/pok/.steam/steam/compatibilitytools.d"
  mkdir -p "$PROTON_BASE_DIR"
  
  # Create an array to store found Proton directories
  FOUND_PROTON_DIRS=()
  
  # First search in the standard location
  if [ -d "$PROTON_BASE_DIR" ]; then
    while IFS= read -r dir; do
      if [ -d "$dir" ] && [ -f "$dir/proton" ]; then
        FOUND_PROTON_DIRS+=("$dir")
        echo "Found Proton at: $dir"
      fi
    done < <(find "$PROTON_BASE_DIR" -maxdepth 1 -name "GE-Proton*" -type d)
  fi
  
  # Then check in /usr/local/bin
  if [ -f "/usr/local/bin/proton" ]; then
    FOUND_PROTON_DIRS+=("/usr/local/bin")
    echo "Found Proton at: /usr/local/bin"
  fi
  
  # Step 2: If no Proton directories found, check if the tarball is available
  if [ ${#FOUND_PROTON_DIRS[@]} -eq 0 ]; then
    echo "No Proton installations found in standard locations."
    
    # Try to find the tarball
    PROTON_TARBALL=$(find /tmp -name "GE-Proton*.tar.gz" -type f 2>/dev/null | head -n 1)
    
    if [ -n "$PROTON_TARBALL" ]; then
      echo "Found Proton tarball: $PROTON_TARBALL. Extracting..."
      mkdir -p "$PROTON_BASE_DIR/GE-Proton-Current"
      tar -xzf "$PROTON_TARBALL" -C "$PROTON_BASE_DIR"
      EXTRACTED_DIR=$(find "$PROTON_BASE_DIR" -maxdepth 1 -name "GE-Proton*" -type d | head -n 1)
      
      if [ -n "$EXTRACTED_DIR" ]; then
        echo "Extracted Proton to: $EXTRACTED_DIR"
        FOUND_PROTON_DIRS+=("$EXTRACTED_DIR")
      fi
    else
      echo "WARNING: No Proton tarball found. Will try to use the system Proton."
    fi
  fi
  
  # Step 3: Create symlinks for expected Proton versions
  if [ ${#FOUND_PROTON_DIRS[@]} -gt 0 ]; then
    # Use the first found Proton directory as the source for symlinks
    PROTON_SOURCE="${FOUND_PROTON_DIRS[0]}"
    echo "Using $PROTON_SOURCE as the primary Proton installation"
    
    # Create symlinks for various expected version names
    ln -sf "$PROTON_SOURCE" "$PROTON_BASE_DIR/GE-Proton-Current"
    ln -sf "$PROTON_SOURCE" "$PROTON_BASE_DIR/GE-Proton8-21"
    ln -sf "$PROTON_SOURCE" "$PROTON_BASE_DIR/GE-Proton9-25"
    
    echo "Created symlinks for compatibility with scripts"
  else
    echo "WARNING: No Proton installations found. Container may not function correctly."
    
    # Try to create a minimal proton script as a last resort
    if [ ! -d "$PROTON_BASE_DIR/GE-Proton-Current" ]; then
      echo "Creating minimal Proton directory structure as fallback..."
      mkdir -p "$PROTON_BASE_DIR/GE-Proton-Current"
      mkdir -p "$PROTON_BASE_DIR/GE-Proton-Current/dist/bin"
      
      # Create a minimal proton script
      echo '#!/bin/bash' > "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      echo 'export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"' >> "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      echo 'wine "$@"' >> "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      chmod +x "$PROTON_BASE_DIR/GE-Proton-Current/proton"
      
      # Create symlinks
      ln -sf "$PROTON_BASE_DIR/GE-Proton-Current" "$PROTON_BASE_DIR/GE-Proton8-21"
      ln -sf "$PROTON_BASE_DIR/GE-Proton-Current" "$PROTON_BASE_DIR/GE-Proton9-25"
      
      echo "Created minimal Proton fallback"
    fi
  fi
  
  # Step 4: Force reset the Proton prefix to ensure clean environment
  echo "Force resetting Proton prefix for clean environment..."
  initialize_proton_prefix
  
  # Step 5: Set up directory permissions
  echo "Setting correct permissions for all directories..."
  chmod -R 755 "${STEAM_COMPAT_DATA_PATH}"
  chmod -R 755 "$PROTON_BASE_DIR"
  
  # Ensure synchronization
  sync
  # Add a delay to ensure all filesystem operations complete
  sleep 3
  
  # Step 6: Test Wine functionality
  echo "Testing Wine functionality..."
  if WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine --version >/dev/null 2>&1; then
    echo "Wine is functional in the environment."
  else
    echo "WARNING: Wine does not appear to be functioning correctly."
    # Try to set up Wine library paths
    export LD_LIBRARY_PATH="/usr/lib/wine:/usr/lib32/wine:$LD_LIBRARY_PATH"
  fi
  
  echo "Proton environment verification completed."
}

# Helper function to create minimal registry if other methods fail
create_minimal_registry() {
  echo "Creating minimal Wine registry structure..."
  
  echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  echo ";; All keys relative to \\\\Machine" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/system.reg"
  
  echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo ";; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "[Software\\\\Wine\\\\DllOverrides]" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "\"*version\"=\"native,builtin\"" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "\"vcrun2019\"=\"native,builtin\"" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/user.reg"
  
  echo "WINE REGISTRY Version 2" > "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  echo ";; All keys relative to \\\\User\\\\DefUser" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  echo "#arch=win64" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  echo "" >> "${STEAM_COMPAT_DATA_PATH}/pfx/userdef.reg"
  
  # Create Visual C++ directory structure to make AsaApiLoader believe it's installed
  local vc_dir="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Microsoft Visual Studio"
  mkdir -p "$vc_dir"
  
  echo "Minimal registry and directory structure created."
}

# Install/Update AsaApi if API=TRUE
if [ "${API}" = "TRUE" ]; then
  echo "----Initializing AsaApi in container mode----"
  
  # Set extra environment variables for Proton/Wine in container
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
  export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
  export WINEDLLOVERRIDES="version=n,b"
  
  # In container, do a full verification of the Proton environment
  verify_proton_environment
  
  # Install the API with extra verification for container mode
  install_ark_server_api
  
  # Verify the installation
  if [ -f "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
    echo "AsaApi installation confirmed in container environment."
    # Create logs directory if it doesn't exist
    mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Binaries/Win64"
    echo "AsaApi logs directory created and permissions set."
    
    # Pre-test AsaApiLoader.exe with Wine to ensure it can be found and executed
    echo "Testing AsaApiLoader.exe execution with Wine..."
    if WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" --help >/dev/null 2>&1; then
      echo "AsaApiLoader.exe seems executable in Wine environment."
    else
      echo "WARNING: AsaApiLoader.exe test execution failed. This may be normal if it requires additional arguments."
    fi
  else
    echo "WARNING: AsaApi loader not found after installation attempt."
  fi
fi

# Start the main application
echo "----Starting Ark Server----"
exec /home/pok/scripts/launch_ASA.sh

# Keep the script running to catch the signal
tail -f /dev/null