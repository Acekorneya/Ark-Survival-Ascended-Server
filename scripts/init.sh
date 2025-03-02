#!/bin/bash

source /home/pok/scripts/common.sh

# Configure ulimit
ulimit -n 100000

echo ""
echo "🎮 ==== ARK SURVIVAL ASCENDED SERVER STARTING ==== 🎮"
echo ""

# Create directories if not already present
mkdir -p ${ASA_DIR}/Engine/Binaries/ThirdParty/Steamworks/Steamv153/Win64/

if [ "${BACKUP_DIR}" != "false" ] && [ -n "${BACKUP_DIR}" ]; then
  # Create backup directory if not already present
  mkdir -p ${BACKUP_DIR}
  # Also create Config subdirectory to prevent errors later
  mkdir -p ${BACKUP_DIR}/Config
  mkdir -p ${BACKUP_DIR}/SavedArks
fi

# Mount backup directory
if [ -d "${BACKUP_DIR}" ] && [ "${BACKUP_DIR}" != "false" ]; then
  echo "📂 Mounting backup directory from ${BACKUP_DIR}"
  # Ensure the Save & Config directories exist
  mkdir -p ${ASA_DIR}/ShooterGame/Saved/SavedArks
  mkdir -p ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer

  # Create symlinks for the backup
  if [ ! -L "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ] && [ -d "${BACKUP_DIR}/SavedArks/${MAP_NAME}" ]; then
    echo "↔️ Creating symbolic link for SavedArks/${MAP_NAME} from backup"
    rm -rf ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
    ln -sf ${BACKUP_DIR}/SavedArks/${MAP_NAME} ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
  elif [ ! -d "${BACKUP_DIR}/SavedArks/${MAP_NAME}" ] && [ -n "${MAP_NAME}" ]; then
    echo "📁 Creating backup directory for SavedArks/${MAP_NAME}"
    mkdir -p ${BACKUP_DIR}/SavedArks/${MAP_NAME}
    # If the local directory exists but is not a symlink, move its contents to the backup and create a symlink
    if [ -d "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ] && [ ! -L "${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}" ]; then
      echo "↔️ Moving existing data to backup location"
      cp -aR ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}/* ${BACKUP_DIR}/SavedArks/${MAP_NAME}/ 2>/dev/null || true
      rm -rf ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
    fi
    ln -sf ${BACKUP_DIR}/SavedArks/${MAP_NAME} ${ASA_DIR}/ShooterGame/Saved/SavedArks/${MAP_NAME}
  fi

  # Handle config files
  if [ ! -f "${BACKUP_DIR}/Config/Game.ini" ] && [ -f "${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini" ]; then
    echo "📄 Moving current Game.ini to backup location"
    cp -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini ${BACKUP_DIR}/Config/Game.ini
  fi

  if [ ! -f "${BACKUP_DIR}/Config/GameUserSettings.ini" ] && [ -f "${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" ]; then
    echo "📄 Moving current GameUserSettings.ini to backup location"
    cp -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini ${BACKUP_DIR}/Config/GameUserSettings.ini
  fi

  if [ -f "${BACKUP_DIR}/Config/Game.ini" ]; then
    echo "📄 Linking Game.ini from backup"
    rm -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini
    ln -sf ${BACKUP_DIR}/Config/Game.ini ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/Game.ini
  fi

  if [ -f "${BACKUP_DIR}/Config/GameUserSettings.ini" ]; then
    echo "📄 Linking GameUserSettings.ini from backup"
    rm -f ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
    ln -sf ${BACKUP_DIR}/Config/GameUserSettings.ini ${ASA_DIR}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
  fi
fi

# Enable container-aware Proton environment initialization
export CONTAINER_MODE="TRUE"

# Setup X virtual framebuffer for headless operation
setup_virtual_display() {
  echo "🖥️ Setting up virtual display for headless operation..."
  export DISPLAY=:0.0
  
  # Check if Xvfb is installed
  if command -v Xvfb >/dev/null 2>&1; then
    # Kill any existing Xvfb processes
    pkill Xvfb >/dev/null 2>&1 || true
    
    # Create .X11-unix directory first to avoid errors
    if [ ! -d "/tmp/.X11-unix" ]; then
      mkdir -p /tmp/.X11-unix 2>/dev/null || true
      chmod 1777 /tmp/.X11-unix 2>/dev/null || true
    fi
    
    # Start Xvfb with error output suppressed
    Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
    XVFB_PID=$!
    echo "  → Started Xvfb (virtual display)"
    
    # Give Xvfb time to start
    sleep 2
    
    # Verify Xvfb is running
    if kill -0 $XVFB_PID 2>/dev/null; then
      echo "  ✅ Virtual display is running"
    else
      echo "  ⚠️ Virtual display failed to start (non-critical)"
    fi
  else
    echo "  ⚠️ Xvfb not found. Will attempt to install..."
    apt-get update -qq && apt-get install -y --no-install-recommends xvfb x11-xserver-utils xauth >/dev/null 2>&1
    
    # Create .X11-unix directory
    mkdir -p /tmp/.X11-unix 2>/dev/null || true
    chmod 1777 /tmp/.X11-unix 2>/dev/null || true
    
    # Try again after installation, with error output suppressed
    Xvfb :0 -screen 0 1024x768x16 2>/dev/null &
    XVFB_PID=$!
    echo "  → Started Xvfb after installation"
    sleep 2
  fi
  
  # Export essential display environment variables
  export WINEDLLOVERRIDES="*version=n,b;vcrun2019=n,b"
  export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
}

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

# Set up virtual display
setup_virtual_display

echo ""
echo "🔍 Running environment checks..."
# Run comprehensive pre-launch environment check
chmod +x /home/pok/scripts/prelaunch_check.sh
/home/pok/scripts/prelaunch_check.sh

# Set essential Proton/Wine environment variables regardless of API setting
# These need to be set for both API=TRUE and API=FALSE cases
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/pok/.steam/steam"
export STEAM_COMPAT_DATA_PATH="/home/pok/.steam/steam/steamapps/compatdata/2430930"
export WINEDLLOVERRIDES="version=n,b"

# Initialize Proton environment regardless of API setting
verify_proton_environment

# Install/Update AsaApi if API=TRUE
if [ "${API}" = "TRUE" ]; then
  echo ""
  echo "🔌 Initializing AsaApi plugin system..."
  
  # Install the API with extra verification for container mode
  install_ark_server_api
  
  # Verify the installation
  if [ -f "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" ]; then
    echo "  ✅ AsaApi installation confirmed"
    # Create logs directory if it doesn't exist
    mkdir -p "${ASA_DIR}/ShooterGame/Binaries/Win64/logs"
    chmod -R 755 "${ASA_DIR}/ShooterGame/Binaries/Win64"
    
    # Pre-test AsaApiLoader.exe with Wine to ensure it can be found and executed
    if WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" wine "${ASA_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe" --help >/dev/null 2>&1; then
      echo "  ✅ AsaApiLoader.exe is executable"
    else
      echo "  ℹ️ AsaApiLoader.exe test execution returned expected result"
    fi
  else
    echo "  ⚠️ AsaApi loader not found after installation attempt"
  fi
fi

echo ""
echo "🚀 LAUNCHING ARK SERVER..."
echo ""
# Start the main application
exec /home/pok/scripts/launch_ASA.sh

# Keep the script running to catch the signal
tail -f /dev/null