#!/bin/bash
# Version information
POK_MANAGER_VERSION="2.1.75"
POK_MANAGER_BRANCH="stable" # Can be "stable" or "beta"

# Get the base directory for the script
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BASE_DIR="$SCRIPT_DIR"

# Create a path preference file 
PATH_CONFIG_FILE="${BASE_DIR}/config/POK-manager/path_preferences.txt"

# Store the last displayed version for patch notes
LAST_VERSION_FILE="${BASE_DIR}/config/POK-manager/last_displayed_version.txt"

# Create config directory if it doesn't exist
mkdir -p "${BASE_DIR}/config/POK-manager"

# Function to determine the expected ownership (UID:GID) based on installation mode
get_expected_ownership() {
  local expected_uid="1000"
  local expected_gid="1000"
  
  # Check for 2.1+ mode with 7777 UID
  if [ -f "${BASE_DIR}/config/POK-manager/migration_complete" ]; then
    expected_uid="7777"
    expected_gid="7777"
  else
    # Check existing config directory ownership to determine mode
    if [ -d "${BASE_DIR}/config/POK-manager" ]; then
      local config_dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/config/POK-manager)"
      local config_dir_uid=$(echo "$config_dir_ownership" | cut -d: -f1)
      local config_dir_gid=$(echo "$config_dir_ownership" | cut -d: -f2)
      
      # If directory is owned by 7777, use that
      if [ "$config_dir_uid" = "7777" ]; then
        expected_uid="7777"
        expected_gid="7777"
      fi
    fi
  fi
  
  echo "${expected_uid}:${expected_gid}"
}

# Function to initialize the last displayed version if not exists
initialize_last_version() {
  if [ ! -f "$LAST_VERSION_FILE" ]; then
    echo "$POK_MANAGER_VERSION" > "$LAST_VERSION_FILE"
    
    # Apply permissions when running as root
    if [ "$(id -u)" -eq 0 ]; then
      # Get expected ownership
      local ownership=$(get_expected_ownership)
      local expected_uid=$(echo "$ownership" | cut -d: -f1)
      local expected_gid=$(echo "$ownership" | cut -d: -f2)
      
      # Apply ownership to the file
      chown ${expected_uid}:${expected_gid} "$LAST_VERSION_FILE"
      
      # Also update the parent directory if needed
      if [ -d "${BASE_DIR}/config/POK-manager" ]; then
        local dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/config/POK-manager)"
        if [ "$dir_ownership" != "${expected_uid}:${expected_gid}" ]; then
          chown ${expected_uid}:${expected_gid} "${BASE_DIR}/config/POK-manager"
        fi
      fi
    fi
  fi
}

# Call initialize at startup
initialize_last_version

# Function to create and display the POK-Manager logo
display_logo() {
  local logo_file="${BASE_DIR}/config/POK-manager/logo.txt"
  local config_dir=$(dirname "$logo_file")
  
  # Create config directory if it doesn't exist
  mkdir -p "$config_dir"
  
  # Check if the logo file exists, create it if it doesn't
  if [ ! -f "$logo_file" ]; then
    # Create ASCII art logo and save it to the file
    cat > "$logo_file" << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
                                                                    
   ██████╗  ██████╗ ██╗  ██╗      █████╗ ██████╗ ██╗  ██╗          
   ██╔══██╗██╔═══██╗██║ ██╔╝     ██╔══██╗██╔══██╗██║ ██╔╝          
   ██████╔╝██║   ██║█████╔╝█████╗███████║██████╔╝█████╔╝           
   ██╔═══╝ ██║   ██║██╔═██╗╚════╝██╔══██║██╔══██╗██╔═██╗           
   ██║     ╚██████╔╝██║  ██╗     ██║  ██║██║  ██║██║  ██╗          
   ╚═╝      ╚═════╝ ╚═╝  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝          
                                                                    
             ARK Survival Ascended Server Manager                   
╚═══════════════════════════════════════════════════════════════════╝
EOF
  fi

  # Check if version is 2.1 or higher (to determine whether to show the logo)
  local major_version=$(echo "$POK_MANAGER_VERSION" | cut -d'.' -f1)
  local minor_version=$(echo "$POK_MANAGER_VERSION" | cut -d'.' -f2)
  
  if [ "$major_version" -gt 2 ] || ([ "$major_version" -eq 2 ] && [ "$minor_version" -ge 1 ]); then
    # Check if we're in a terminal that supports color
    if [ -t 1 ]; then
      # Define colors for the logo
      local CYAN='\033[0;36m'
      local GREEN='\033[0;32m'
      local YELLOW='\033[1;33m'
      local RESET='\033[0m'
      
      # Display the logo with colors
      echo -e "${CYAN}"
      cat "$logo_file"
      echo -e "${RESET}"
      
      # Display version information
      echo -e "${GREEN}Version:${RESET} ${YELLOW}$POK_MANAGER_VERSION${RESET} (${YELLOW}$POK_MANAGER_BRANCH${RESET})"
      echo ""
    else
      # In non-interactive mode, don't display the logo
      :
    fi
  fi
}

# Check for beta mode early
if [ -f "${BASE_DIR}/config/POK-manager/beta_mode" ]; then
  POK_MANAGER_BRANCH="beta"
fi

# Function to check if volume paths in docker-compose files match the current BASE_DIR
check_volume_paths() {
  local auto_update=${1:-false}
  local mismatched_files=()
  local config_dir="${BASE_DIR}/config/POK-manager"
  
  # Ensure config directory exists
  mkdir -p "$config_dir"
  
  # If user has already chosen to auto-update paths, just do it
  if [ -f "$PATH_CONFIG_FILE" ] && [ "$auto_update" != "force_check" ]; then
    if grep -q "AUTO_UPDATE_PATHS=true" "$PATH_CONFIG_FILE"; then
      update_volume_paths
      return 0
    elif grep -q "AUTO_UPDATE_PATHS=false" "$PATH_CONFIG_FILE"; then
      # User previously chose not to update paths
      return 0
    fi
  fi
  
  # Find all docker-compose files
  local compose_files=($(find "${BASE_DIR}/Instance_"* -name 'docker-compose-*.yaml' 2>/dev/null || true))
  
  for file in "${compose_files[@]}"; do
    # Extract the base directory path from the file
    local file_base_dir=$(grep -o '"[^"]*:/home/pok/arkserver"' "$file" | head -1 | sed 's/"//g' | cut -d':' -f1 | sed 's|/ServerFiles/arkserver$||')
    
    # If file_base_dir is empty, try a different pattern
    if [ -z "$file_base_dir" ]; then
      file_base_dir=$(grep -o '"[^"]*/ServerFiles/arkserver:/home/pok/arkserver"' "$file" | head -1 | sed 's/"//g' | cut -d':' -f1 | sed 's|/ServerFiles/arkserver$||')
    fi
    
    # If we found a path and it doesn't match current BASE_DIR
    if [ -n "$file_base_dir" ] && [ "$file_base_dir" != "$BASE_DIR" ]; then
      mismatched_files+=("$file")
    fi
  done
  
  # If we found mismatched files, ask the user what to do
  if [ ${#mismatched_files[@]} -gt 0 ]; then
    echo "⚠️ NOTICE: POK-Manager directory has changed"
    echo "The volume paths in your docker-compose files don't match the current directory."
    echo "This can happen if you've moved the POK-Manager to a new location."
    echo "Found ${#mismatched_files[@]} files with mismatched paths:"
    
    # Show the first 3 mismatched files as examples
    local max_display=3
    local count=0
    for file in "${mismatched_files[@]}"; do
      if [ $count -lt $max_display ]; then
        echo "  - $file"
      else
        break
      fi
      ((count++))
    done
    
    if [ ${#mismatched_files[@]} -gt $max_display ]; then
      echo "  - ... and $((${#mismatched_files[@]} - $max_display)) more"
    fi
    
    echo ""
    echo "Would you like to update all volume paths to the current directory? (y/n)"
    echo "This ensures your containers will use the correct paths when started."
    
    # Only ask if we're not running in auto mode
    if [ "$auto_update" != "true" ]; then
      local response
      read -p "Update paths? (y/n): " response
      
      if [[ "$response" =~ ^[Yy] ]]; then
        update_volume_paths
        echo "AUTO_UPDATE_PATHS=true" > "$PATH_CONFIG_FILE"
        echo "✅ All paths updated successfully. Future path changes will be updated automatically."
      else
        echo "AUTO_UPDATE_PATHS=false" > "$PATH_CONFIG_FILE"
        echo "⚠️ Paths not updated. Docker containers may fail to start if they can't access the old paths."
      fi
    else
      update_volume_paths
      echo "AUTO_UPDATE_PATHS=true" > "$PATH_CONFIG_FILE"
    fi
  fi
}

# Function to update volume paths in docker-compose files
update_volume_paths() {
  local compose_files=($(find "${BASE_DIR}/Instance_"* -name 'docker-compose-*.yaml' 2>/dev/null || true))
  local updated_count=0
  
  for file in "${compose_files[@]}"; do
    # Find the old base dir by extracting from the ServerFiles volume
    local old_base_dir=$(grep -o '"[^"]*:/home/pok/arkserver"' "$file" | head -1 | sed 's/"//g' | cut -d':' -f1 | sed 's|/ServerFiles/arkserver$||')
    
    # If old_base_dir is empty, try a different pattern
    if [ -z "$old_base_dir" ]; then
      old_base_dir=$(grep -o '"[^"]*/ServerFiles/arkserver:/home/pok/arkserver"' "$file" | head -1 | sed 's/"//g' | cut -d':' -f1 | sed 's|/ServerFiles/arkserver$||')
    fi
    
    # If we found a path and it doesn't match current BASE_DIR
    if [ -n "$old_base_dir" ] && [ "$old_base_dir" != "$BASE_DIR" ]; then
      # Make a backup of the file
      cp "$file" "${file}.bak"
      
      # Replace all instances of the old base dir with the new one
      sed -i "s|\"${old_base_dir}/|\"${BASE_DIR}/|g" "$file"
      
      ((updated_count++))
    fi
  done
  
  if [ $updated_count -gt 0 ]; then
    echo "✅ Updated volume paths in $updated_count docker-compose files."
  fi
}

# Function to get container ID by instance name (more reliable than just using folder names)
get_instance_container_id() {
  local instance_name="$1"
  local container_name="asa_${instance_name}"
  
  # First try to get the container ID by container name
  local container_id=$(docker ps -qf "name=$container_name" 2>/dev/null)
  
  # If that fails, try to identify by compose project
  if [ -z "$container_id" ]; then
    container_id=$(docker ps -qf "label=com.docker.compose.project=$instance_name" 2>/dev/null)
  fi
  
  echo "$container_id"
}

# Define colors for pretty output
RED='\033[0;31m'

# Set PUID and PGID to match the container's expected values
# Legacy default was 1000:1000, new default is 7777:7777
if [ "$POK_MANAGER_BRANCH" = "beta" ]; then
  # Beta branch uses 7777:7777
  PUID=${CONTAINER_PUID:-7777}
  PGID=${CONTAINER_PGID:-7777}
else
  # For stable branch, determine the appropriate PUID:PGID based on file ownership
  # For new installations, default to 7777:7777 (new recommended default)
  # Only use 1000:1000 if server files exist and are owned by 1000:1000
  server_files_dir="${BASE_DIR}/ServerFiles/arkserver"
  
  # First, check if server files directory exists
  if [ -d "$server_files_dir" ]; then
    file_ownership=$(stat -c '%u:%g' "$server_files_dir")
    
    # If files are owned by 1000:1000, use legacy values for compatibility
    if [ "$file_ownership" = "1000:1000" ]; then
      PUID=${CONTAINER_PUID:-1000}
      PGID=${CONTAINER_PGID:-1000}
    else
      # For all other cases, use the new default or match existing ownership
      PUID=${CONTAINER_PUID:-$(echo "$file_ownership" | cut -d: -f1)}
      PGID=${CONTAINER_PGID:-$(echo "$file_ownership" | cut -d: -f2)}
    fi
  else
    # No server files yet - check script ownership as fallback
    script_ownership=$(stat -c '%u:%g' "$0")
    
    # If script is owned by 1000:1000, use legacy values
    if [ "$script_ownership" = "1000:1000" ]; then
      PUID=${CONTAINER_PUID:-1000}
      PGID=${CONTAINER_PGID:-1000}
    # If script is owned by 7777:7777, use those values
    elif [ "$script_ownership" = "7777:7777" ]; then
      PUID=${CONTAINER_PUID:-7777}
      PGID=${CONTAINER_PGID:-7777}
    # For new installations with any other ownership, use current user's UID/GID if it's 7777 or 1000
    elif [ "$(id -u)" -eq 7777 ] || [ "$(id -u)" -eq 1000 ]; then
      PUID=${CONTAINER_PUID:-$(id -u)}
      PGID=${CONTAINER_PGID:-$(id -g)}
    else
      # Use the new recommended default
      PUID=${CONTAINER_PUID:-7777}
      PGID=${CONTAINER_PGID:-7777}
    fi
  fi
fi

# Define the order in which the settings should be displayed
declare -a config_order=(
    "Memory Limit" 
    "BattleEye"
    "API"
    "RCON Enabled"
    "POK Monitor Message"
    "Random Startup Delay"
    "CPU Optimization"
    "Update Server"
    "Update Interval"
    "Update Window Start"
    "Update Window End"
    "Restart Notice"
    "MOTD Enabled"
    "MOTD"
    "MOTD Duration"
    "Map Name"
    "Session Name"
    "Admin Password"
    "Server Password"
    "ASA Port"
    "RCON Port"
    "Max Players"
    "Show Admin Commands In Chat"
    "Cluster ID"
    "Mod IDs"
    "Passive Mods"
    "Custom Server Args"
)
# Global associative array for default configuration values
declare -A default_config_values=(
    ["TZ"]="America/New_York, America/Los_Angeles"
    ["Memory Limit"]="16G" 
    ["BattleEye"]="FALSE"
    ["API"]="FALSE"
    ["RCON Enabled"]="TRUE"
    ["POK Monitor Message"]="FALSE"
    ["Random Startup Delay"]="TRUE"
    ["CPU Optimization"]="FALSE"
    ["Update Server"]="TRUE"
    ["Update Interval"]="24"
    ["Update Window Start"]="12:00 AM"
    ["Update Window End"]="11:59 PM" 
    ["Restart Notice"]="30"
    ["MOTD Enabled"]="FALSE"
    ["MOTD"]="Welcome To my Server"
    ["MOTD Duration"]="30"
    ["Map Name"]="TheIsland"
    ["Session Name"]="MyServer"
    ["Admin Password"]="myadminpassword"
    ["Server Password"]=
    ["ASA Port"]=""7777""
    ["RCON Port"]="27020"
    ["Max Players"]="70"
    ["Show Admin Commands In Chat"]="FALSE"
    ["Cluster ID"]="cluster"
    ["Mod IDs"]=
    ["Passive Mods"]=
    ["Custom Server Args"]=
    # Add other default values here
)

# Validation functions
validate_boolean() {
  local input=$1
  local key=$2 # Added key parameter for custom message
  # Convert input to uppercase for case-insensitive comparison
  input="${input^^}"
  while ! [[ "$input" =~ ^(TRUE|FALSE)$ ]]; do
    read -rp "Invalid input for $key. Please enter TRUE or FALSE: " input
    input="${input^^}" # Convert again after re-prompting
  done
  echo "$input" # Already uppercase
}

validate_time() {
  local input=$1
  while ! [[ "$input" =~ ^(1[0-2]|0?[1-9]):[0-5][0-9]\ (AM|PM)$ ]]; do
    read -rp "Invalid input. Please enter a time in the format HH:MM AM/PM: " input
  done
  echo "$input"
}

validate_number() {
  local input=$1
  while ! [[ "$input" =~ ^[0-9]+$ ]]; do
    read -rp "Invalid input. Please enter a number: " input
  done
  echo "$input"
}

validate_memory_limit() {
  local input=$1
  # Check if the input already ends with 'G' or is a numeric value without 'G'
  while ! [[ "$input" =~ ^[0-9]+G$ ]] && ! [[ "$input" =~ ^[0-9]+$ ]]; do
    read -rp "Invalid input. Please enter memory limit in the format [number]G or [number] for GB: " input
  done

  # If the input is numeric without 'G', append 'G' to it
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    input="${input}G"
  fi

  echo "$input"
}

validate_mod_ids() {
  local input="$1"
  # Check if input is 'None' or 'NONE', and return an empty string if so
  if [[ "$input" =~ ^(none|NONE|None)$ ]]; then
    echo ""
    return
  fi
  # Continue with the regular validation if input is not 'None' or 'NONE'
  while ! [[ "$input" =~ ^([0-9]+,)*[0-9]+$ ]]; do
    read -rp "Invalid input. Please enter mod IDs in the format 12345,67890, or 'NONE' for blank: " input
    # Allow immediate exit from the loop if 'None' or 'NONE' is entered
    if [[ "$input" =~ ^(none|NONE|None)$ ]]; then
      echo ""
      return
    fi
  done
  echo "$input"
}


validate_simple_password() {
  local input="$1"
  # Loop until the input is alphanumeric (letters and numbers only)
  while ! [[ "$input" =~ ^[a-zA-Z0-9]+$ ]]; do
    read -rp "Invalid input. Please enter a password with numbers or letters only, no special characters: " input
  done
  echo "$input"
}

validate_admin_password() {
  local input="$1"
  while [[ "$input" =~ [\"\'] ]]; do
    read -rp "Invalid input. The password cannot contain double quotes (\") or single quotes ('). Please enter a valid password: " input
  done
  echo "$input"
}

validate_session_name() {
  local input="$1"
  # Allow any characters except double quotes and single quotes
  while [[ "$input" =~ [\"\'] ]]; do
    read -rp "Invalid input. The session name cannot contain double quotes (\") or single quotes ('). Please enter a valid session name: " input
  done
  echo "$input"
}

prompt_for_input() {
  local config_key="$1"
  local user_input
  local prompt_message="Enter new value for $config_key [Current: ${config_values[$config_key]}]:"
  local prompt_suffix=" (Enter to keep current/Type to change):"

  # Adjust the prompt suffix for fields that can be set to blank with 'NONE'
  if [[ "$config_key" =~ ^(Cluster ID|Mod IDs|Passive Mods|Custom Server Args|Server Password|MOTD)$ ]]; then
    prompt_suffix=" (Enter to keep current/'NONE' for blank/Type to change):"
  fi

  echo -n "$prompt_message$prompt_suffix"
  read user_input

  # Handle 'NONE' for special fields, and empty input to use current values
  if [[ -z "$user_input" ]]; then
    return # Keep the current value
  elif [[ "$user_input" =~ ^(none|NONE|None)$ ]] && [[ "$config_key" =~ ^(Cluster ID|Mod IDs|Passive Mods|Custom Server Args|Server Password|MOTD)$ ]]; then
    config_values[$config_key]=""
    return
  fi

  # Proceed with specific validation based on the config key
  case $config_key in
    "BattleEye"|"RCON Enabled"|"POK Monitor Message"|"Update Server"|"MOTD Enabled"|"Show Admin Commands In Chat"|"Random Startup Delay")
      config_values[$config_key]=$(validate_boolean "$user_input" "$config_key")
      ;;
    "Update Window Start"|"Update Window End")
      config_values[$config_key]=$(validate_time "$user_input")
      ;;
    "Update Interval"|"Max Players"|"Restart Notice"|"MOTD Duration"|"ASA Port"|"RCON Port")
      config_values[$config_key]=$(validate_number "$user_input")
      ;;
    "Memory Limit")
      config_values[$config_key]=$(validate_memory_limit "$user_input")
      ;;
    "Mod IDs"|"Passive Mods")
      config_values[$config_key]=$(validate_mod_ids "$user_input")
      ;;
    "Session Name")
      config_values[$config_key]=$(validate_session_name "$user_input")
      ;;
    "Server Password")
      config_values[$config_key]=$(validate_simple_password "$user_input")
      ;;
    "Admin Password")
      config_values[$config_key]=$(validate_admin_password "$user_input")
      ;;
    "MOTD")
      config_values[$config_key]="$user_input"
      ;;
    "Custom Server Args")
      config_values[$config_key]="$user_input"
      ;;
    *)
      config_values[$config_key]="$user_input"
      ;;
  esac
}

install_jq() {
  if ! command -v jq &>/dev/null; then
    echo "jq is not installed. Attempting to install jq..."
    if [ -f /etc/debian_version ]; then
      # Debian or Ubuntu
      sudo apt-get update
      sudo apt-get install -y jq
    elif [ -f /etc/redhat-release ]; then
      # Red Hat, CentOS, or Fedora
      if command -v dnf &>/dev/null; then
        sudo dnf install -y jq
      else
        sudo yum install -y jq
      fi
    elif [ -f /etc/arch-release ]; then
      # Arch Linux
      sudo pacman -Sy --noconfirm jq
    elif [ -f /etc/alpine-release ]; then
      # Alpine Linux
      sudo apk add --no-cache jq
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
      # openSUSE
      sudo zypper install -y jq
    elif [ -f /etc/gentoo-release ]; then
      # Gentoo
      sudo emerge -av app-misc/jq
    else
      echo "Unsupported Linux distribution. Please install jq manually and run the setup again."
      return 1
    fi
    
    if command -v jq &>/dev/null; then
      echo "jq has been successfully installed."
    else
      echo "Failed to install jq. Please install it manually and run the setup again."
      return 1
    fi
  else
    echo "jq is already installed."
  fi
}

check_dependencies() {
  # Check if Docker is installed
  if ! command -v docker &>/dev/null; then
    echo "Docker is not installed on your system."
    read -p "Do you want to install Docker? [y/N]: " install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
      # Detect the OS and install Docker accordingly
      if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y docker.io
      elif command -v dnf &>/dev/null; then
        # Fedora
        sudo dnf install -y docker
      elif command -v yum &>/dev/null; then
        # CentOS/RHEL
        sudo yum install -y docker
      elif [ -f /etc/arch-release ]; then
        # Arch Linux
        sudo pacman -Sy --noconfirm docker
      elif [ -f /etc/alpine-release ]; then
        # Alpine Linux
        sudo apk add --no-cache docker
      elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        # openSUSE
        sudo zypper install -y docker
      elif [ -f /etc/gentoo-release ]; then
        # Gentoo
        sudo emerge -av app-containers/docker
      else
        echo "Unsupported Linux distribution. Please install Docker manually and run the script again."
        exit 1
      fi
      sudo systemctl enable docker
      sudo systemctl start docker
      sudo usermod -aG docker $USER
      echo "Docker has been installed. Please log out and log back in for the changes to take effect."
    else
      echo "Docker installation declined. Please install Docker manually to proceed."
      exit 1
    fi
  fi

  # Initialize Docker Compose command variable
  local docker_compose_version_command

  # Check for the Docker Compose V2 command availability ('docker compose')
  if docker compose version &>/dev/null; then
    docker_compose_version_command="docker compose version"
    DOCKER_COMPOSE_CMD="docker compose"
  elif docker-compose --version &>/dev/null; then
    # Fallback to Docker Compose V1 command if V2 is not available
    docker_compose_version_command="docker-compose --version"
    DOCKER_COMPOSE_CMD="docker-compose"
  else
    echo "Neither 'docker compose' (V2) nor 'docker-compose' (V1) command is available."
    # Automatically install Docker Compose without prompting
    echo "Docker Compose is required and will be installed automatically..."
    
    # Detect the OS and install Docker Compose accordingly
    if command -v apt-get &>/dev/null; then
      # Debian/Ubuntu
      echo "Detected Debian/Ubuntu system, installing Docker Compose..."
      sudo apt-get update
      # Try to install docker compose plugin first (for V2)
      if sudo apt-get install -y docker-compose-plugin 2>/dev/null; then
        echo "Docker Compose V2 plugin installed successfully."
        DOCKER_COMPOSE_CMD="docker compose"
        docker_compose_version_command="docker compose version"
      else
        # Fallback to standalone docker-compose
        echo "Installing standalone Docker Compose V1..."
        sudo apt-get install -y docker-compose
        DOCKER_COMPOSE_CMD="docker-compose"
        docker_compose_version_command="docker-compose --version"
      fi
    elif command -v dnf &>/dev/null; then
      # Fedora
      echo "Detected Fedora system, installing Docker Compose..."
      # Try to install docker compose plugin first (for V2)
      if sudo dnf install -y docker-compose-plugin 2>/dev/null; then
        echo "Docker Compose V2 plugin installed successfully."
        DOCKER_COMPOSE_CMD="docker compose"
        docker_compose_version_command="docker compose version"
      else
        # Fallback to standalone docker-compose
        echo "Installing standalone Docker Compose V1..."
        sudo dnf install -y docker-compose
        DOCKER_COMPOSE_CMD="docker-compose"
        docker_compose_version_command="docker-compose --version"
      fi
    elif command -v yum &>/dev/null; then
      # CentOS/RHEL
      echo "Detected CentOS/RHEL system, installing Docker Compose..."
      # Try to install docker compose plugin first (for V2)
      if sudo yum install -y docker-compose-plugin 2>/dev/null; then
        echo "Docker Compose V2 plugin installed successfully."
        DOCKER_COMPOSE_CMD="docker compose"
        docker_compose_version_command="docker compose version"
      else
        # Fallback to standalone docker-compose
        echo "Installing standalone Docker Compose V1..."
        sudo yum install -y docker-compose
        DOCKER_COMPOSE_CMD="docker-compose"
        docker_compose_version_command="docker-compose --version"
      fi
    elif [ -f /etc/arch-release ]; then
      # Arch Linux
      echo "Detected Arch Linux system, installing Docker Compose..."
      sudo pacman -Sy --noconfirm docker-compose
      DOCKER_COMPOSE_CMD="docker-compose"
      docker_compose_version_command="docker-compose --version"
    elif [ -f /etc/alpine-release ]; then
      # Alpine Linux
      echo "Detected Alpine Linux system, installing Docker Compose..."
      sudo apk add --no-cache docker-compose
      DOCKER_COMPOSE_CMD="docker-compose"
      docker_compose_version_command="docker-compose --version"
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
      # openSUSE
      echo "Detected openSUSE system, installing Docker Compose..."
      sudo zypper install -y docker-compose
      DOCKER_COMPOSE_CMD="docker-compose"
      docker_compose_version_command="docker-compose --version"
    elif [ -f /etc/gentoo-release ]; then
      # Gentoo
      echo "Detected Gentoo system, installing Docker Compose..."
      sudo emerge -av app-containers/docker-compose
      DOCKER_COMPOSE_CMD="docker-compose"
      docker_compose_version_command="docker-compose --version"
    else
      # For unsupported distributions, use the latest Docker Compose binary
      echo "Unsupported Linux distribution. Attempting to install Docker Compose binary..."
      
      # Install docker compose v2 as a plugin
      DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
      echo "Installing Docker Compose ${DOCKER_COMPOSE_VERSION}..."
      DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
      mkdir -p $DOCKER_CONFIG/cli-plugins
      
      # Download the binary to the plugins directory
      sudo curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      
      # Make it executable
      sudo chmod +x /usr/local/bin/docker-compose
      
      # Create a symbolic link for the plugin
      sudo ln -sf /usr/local/bin/docker-compose $DOCKER_CONFIG/cli-plugins/docker-compose
      
      # Check which command works now
      if docker compose version &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        docker_compose_version_command="docker compose version"
        echo "Docker Compose V2 installed successfully."
      elif docker-compose --version &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        docker_compose_version_command="docker-compose --version"
        echo "Docker Compose V1 installed successfully."
      else
        echo "Error: Docker Compose installation failed."
        echo "Please install Docker Compose manually and run the script again."
        exit 1
      fi
    fi
  fi

  # Extract the version number using the appropriate command
  local compose_version=$($docker_compose_version_command | grep -oE '([0-9]+\.[0-9]+\.[0-9]+)')
  local major_version=$(echo $compose_version | cut -d. -f1)

  # Ensure we use 'docker compose' for version 2 and above
  if [[ $major_version -ge 2 ]]; then
    DOCKER_COMPOSE_CMD="docker compose"
  else
    DOCKER_COMPOSE_CMD="docker-compose"
  fi
  echo "$DOCKER_COMPOSE_CMD" > ./config/POK-manager/docker_compose_cmd
  echo "Using Docker Compose command: '$DOCKER_COMPOSE_CMD'."
}

# Function to update Docker Compose image tag
update_docker_compose_image_tag() {
  local compose_file="$1"
  local new_tag="$2"
  
  if [ ! -f "$compose_file" ]; then
    echo "❌ ERROR: Docker compose file not found: $compose_file"
    return 1
  fi
  
  # Update the image tag in the docker-compose file
  sed -i "s|image: acekorneya/asa_server:.*|image: acekorneya/asa_server:${new_tag}|g" "$compose_file"
  
  if [ $? -eq 0 ]; then
    echo "✅ Updated image tag to '${new_tag}' in: $(basename "$compose_file")"
  else
    echo "❌ ERROR: Failed to update image tag in: $compose_file"
    return 1
  fi
}

get_docker_compose_cmd() {
  local cmd_file="./config/POK-manager/docker_compose_cmd"
  local config_dir="./config/POK-manager"
  mkdir -p "$config_dir"
  if [ ! -f "$cmd_file" ]; then
    touch "$cmd_file"
  fi
  
  # Changed condition from -f to -s to check for non-empty file
  if [ -s "$cmd_file" ]; then
    DOCKER_COMPOSE_CMD=$(cat "$cmd_file")
    echo "Using Docker Compose command: '$DOCKER_COMPOSE_CMD' (read from file)."
  else
    if docker compose version &>/dev/null; then
      DOCKER_COMPOSE_CMD="docker compose"
    elif docker-compose --version &>/dev/null; then
      DOCKER_COMPOSE_CMD="docker-compose"
    else
      echo "Neither 'docker compose' (V2) nor 'docker-compose' (V1) command is available."
      # Automatically install Docker Compose without prompting
      echo "Docker Compose is required and will be installed automatically..."
      
      # Detect the OS and install Docker Compose accordingly
      if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu
        echo "Detected Debian/Ubuntu system, installing Docker Compose..."
        sudo apt-get update
        # Try to install docker compose plugin first (for V2)
        if sudo apt-get install -y docker-compose-plugin 2>/dev/null; then
          echo "Docker Compose V2 plugin installed successfully."
          DOCKER_COMPOSE_CMD="docker compose"
        else
          # Fallback to standalone docker-compose
          echo "Installing standalone Docker Compose V1..."
          sudo apt-get install -y docker-compose
          DOCKER_COMPOSE_CMD="docker-compose"
        fi
      elif command -v dnf &>/dev/null; then
        # Fedora
        echo "Detected Fedora system, installing Docker Compose..."
        # Try to install docker compose plugin first (for V2)
        if sudo dnf install -y docker-compose-plugin 2>/dev/null; then
          echo "Docker Compose V2 plugin installed successfully."
          DOCKER_COMPOSE_CMD="docker compose"
        else
          # Fallback to standalone docker-compose
          echo "Installing standalone Docker Compose V1..."
          sudo dnf install -y docker-compose
          DOCKER_COMPOSE_CMD="docker-compose"
        fi
      elif command -v yum &>/dev/null; then
        # CentOS/RHEL
        echo "Detected CentOS/RHEL system, installing Docker Compose..."
        # Try to install docker compose plugin first (for V2)
        if sudo yum install -y docker-compose-plugin 2>/dev/null; then
          echo "Docker Compose V2 plugin installed successfully."
          DOCKER_COMPOSE_CMD="docker compose"
        else
          # Fallback to standalone docker-compose
          echo "Installing standalone Docker Compose V1..."
          sudo yum install -y docker-compose
          DOCKER_COMPOSE_CMD="docker-compose"
        fi
      elif [ -f /etc/arch-release ]; then
        # Arch Linux
        echo "Detected Arch Linux system, installing Docker Compose..."
        # Try to install docker compose plugin first (for V2)
        if sudo pacman -Sy --noconfirm docker-compose 2>/dev/null; then
          echo "Docker Compose installed successfully."
          DOCKER_COMPOSE_CMD="docker-compose"
        fi
      else
        # For unsupported distributions, use the latest Docker Compose binary
        echo "Unsupported Linux distribution. Attempting to install Docker Compose binary..."
        
        # Install docker compose v2 as a plugin
        DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
        echo "Installing Docker Compose ${DOCKER_COMPOSE_VERSION}..."
        DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
        mkdir -p $DOCKER_CONFIG/cli-plugins
        
        # Download the binary to the plugins directory
        sudo curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        
        # Make it executable
        sudo chmod +x /usr/local/bin/docker-compose
        
        # Create a symbolic link for the plugin
        sudo ln -sf /usr/local/bin/docker-compose $DOCKER_CONFIG/cli-plugins/docker-compose
        
        # Check which command works now
        if docker compose version &>/dev/null; then
          DOCKER_COMPOSE_CMD="docker compose"
          echo "Docker Compose V2 installed successfully."
        elif docker-compose --version &>/dev/null; then
          DOCKER_COMPOSE_CMD="docker-compose"
          echo "Docker Compose V1 installed successfully."
        else
          echo "Error: Docker Compose installation failed."
          echo "Please install Docker Compose manually and run the script again."
          exit 1
        fi
      fi
    fi
    echo "$DOCKER_COMPOSE_CMD" > "$cmd_file"
    echo "Using Docker Compose command: '$DOCKER_COMPOSE_CMD'."
  fi
}


get_config_file_path() {
  local config_dir="./config/POK-manager"
  
  # Check if we're in post-migration state with wrong user ID
  if [ "$(id -u)" -ne 0 ] && [ -f "${BASE_DIR}/config/POK-manager/migration_complete" ]; then
    # Check if config directory is owned by 7777 but we're not running as 7777
    if [ -d "$config_dir" ]; then
      local config_dir_ownership="$(stat -c '%u:%g' $config_dir)"
      local config_dir_uid=$(echo "$config_dir_ownership" | cut -d: -f1)
      
      if [ "$config_dir_uid" = "7777" ] && [ "$(id -u)" -ne 7777 ]; then
        # Return path but don't try to create the directory - will be handled by permission check
        echo "$config_dir/config.txt"
        return
      fi
    fi
  fi
  
  # Normal behavior - create directory if it doesn't exist
  mkdir -p "$config_dir"
  echo "$config_dir/config.txt"
}
prompt_change_host_timezone() {
  # Get the current host timezone
  local current_tz=$(timedatectl show -p Timezone --value)

  read -p "Do you want to change the host's timezone? Current timezone: $current_tz (y/N): " change_tz
  if [[ "$change_tz" =~ ^[Yy]$ ]]; then
    read -p "Enter the desired timezone (e.g., America/New_York): " new_tz
    if timedatectl set-timezone "$new_tz"; then
      echo "Host timezone set to $new_tz"
    else
      echo "Failed to set the host timezone to $new_tz"
      read -p "Do you want to use the default UTC timezone instead? (Y/n): " use_default
      if [[ ! "$use_default" =~ ^[Nn]$ ]]; then
        if timedatectl set-timezone "UTC"; then
          echo "Host timezone set to the default UTC"
        else
          echo "Failed to set the host timezone to the default UTC"
        fi
      fi
    fi
  else
    echo "Host timezone change skipped."
  fi

  echo "You can always run './POK-manager.sh -setup' again to change the host's timezone later."
}
# Set timezone
set_timezone() {
  # Try to read the current timezone from /etc/timezone or equivalent
  local current_tz
  if [ -f "/etc/timezone" ]; then
    current_tz=$(cat /etc/timezone)
  elif [ -h "/etc/localtime" ]; then
    # For systems where /etc/localtime is a symlink to the timezone in /usr/share/zoneinfo
    current_tz=$(readlink /etc/localtime | sed "s#/usr/share/zoneinfo/##")
  else
    current_tz="UTC" # Default to UTC if unable to determine the timezone
  fi

  echo "Detected Host Timezone: $current_tz"
  read -rp "Press Enter to accept the host default for the container timezone ($current_tz) or type to change: " user_tz
  TZ="${user_tz:-$current_tz}" # Use user input or fall back to detected timezone
  
  # Export the TZ variable for use in other functions
  export TZ
  export USER_TIMEZONE="$TZ"
  # Add TZ environment variable to the Docker Compose file for the instance
  echo "Configured Timezone: $TZ"
  echo "TZ=$TZ" >> "${instance_dir}/docker-compose-${instance_name}.yaml"
}
# Adjust file ownership and permissions on the host
adjust_ownership_and_permissions() {
  local dir="$1"
  if [ -z "$dir" ]; then
    echo "Error: No directory provided."
    return 1
  fi

  # Create the directory if it doesn't exist
  if [ ! -d "$dir" ]; then
    echo "Creating directory: $dir"
    mkdir -p "$dir"
    chown $PUID:$PGID "$dir"
    chmod 755 "$dir"
  fi

  echo "Checking and adjusting ownership and permissions for $dir..."
  find "$dir" -type d -exec chown $PUID:$PGID {} \;
  find "$dir" -type d -exec chmod 755 {} \;
  find "$dir" -type f -exec chown $PUID:$PGID {} \;
  find "$dir" -type f -exec chmod 644 {} \;

  # Always check and fix the main script permissions
  local script_path="$(realpath "$0")"
  
  # If the script is run as root, we need to ensure proper ownership
  if [ "$(id -u)" -eq 0 ]; then
    local target_owner=""
    
    # First try to determine ownership from parent directory
    local parent_dir="$(dirname "$BASE_DIR")"
    if [ -d "$parent_dir" ]; then
      local parent_ownership="$(stat -c '%u:%g' "$parent_dir")"
      
      # Check if parent directory is owned by either 7777:7777 or 1000:1000
      if [ "$parent_ownership" = "7777:7777" ]; then
        target_owner="7777:7777"
        echo "Setting ownership based on parent directory ownership: 7777:7777"
      elif [ "$parent_ownership" = "1000:1000" ]; then
        target_owner="1000:1000"
        echo "Setting ownership based on parent directory ownership: 1000:1000"
      else
        # If parent directory has other ownership, check base dir
        local base_ownership="$(stat -c '%u:%g' "$BASE_DIR")"
        if [ "$base_ownership" = "7777:7777" ]; then
          target_owner="7777:7777"
          echo "Setting ownership based on base directory ownership: 7777:7777"
        elif [ "$base_ownership" = "1000:1000" ]; then
          target_owner="1000:1000"
          echo "Setting ownership based on base directory ownership: 1000:1000"
        fi
      fi
    fi
    
    # If we still don't have a target_owner, determine based on migration status as fallback
    if [ -z "$target_owner" ]; then
      if [ -f "${BASE_DIR}/config/POK-manager/migration_complete" ]; then
        target_owner="7777:7777"
        echo "Setting ownership based on migration status: 7777:7777"
      else
        target_owner="1000:1000"
        echo "Setting ownership based on migration status: 1000:1000"
      fi
    fi
    
    echo "Setting POK-manager.sh ownership to $target_owner"
    chown $target_owner "$script_path"
  fi
  
  # Set executable bit for POK-manager.sh
  chmod +x "$script_path"
  echo "Ensuring POK-manager.sh is executable"

  echo "Ownership and permissions adjustment on $dir completed."
}

# Check vm.max_map_count
check_vm_max_map_count() {
  local required_map_count=262144
  local current_map_count=$(cat /proc/sys/vm/max_map_count)
  
  # Check if sudo is available
  local has_sudo=true
  sudo -n true 2>/dev/null || has_sudo=false
  
  if [ "$current_map_count" -lt "$required_map_count" ]; then
    echo "WARNING: vm.max_map_count is too low ($current_map_count). Needs to be at least $required_map_count."
    
    if [ "$has_sudo" = true ]; then
      echo "Would you like to set vm.max_map_count to $required_map_count now? [y/N]: "
      read -r response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo sysctl -w vm.max_map_count=262144
        echo "Value set temporarily. To set permanently, add the following line to /etc/sysctl.conf:"
        echo "  vm.max_map_count=262144"
      else
        echo "Please run the following command to temporarily set the value:"
        echo "  sudo sysctl -w vm.max_map_count=262144"
        echo "To set the value permanently, add the following line to /etc/sysctl.conf and run 'sudo sysctl -p':"
        echo "  vm.max_map_count=262144"
        echo "The ARK server may not run correctly without this setting."
      fi
    else
      echo "You do not have sudo privileges to set this value."
      echo "Please ask your system administrator to run the following command:"
      echo "  sudo sysctl -w vm.max_map_count=262144"
      echo "To set the value permanently, add the following line to /etc/sysctl.conf and run 'sudo sysctl -p':"
      echo "  vm.max_map_count=262144"
      echo "The ARK server may not run correctly without this setting."
      echo "Continuing setup, but be aware that the server may not start properly."
    fi
  fi
}

check_puid_pgid_user() {
  local puid="$1"
  local pgid="$2"
  local original_command="$3"  # This contains the original command (e.g., "-stop -all")
  local legacy_puid=1000
  local legacy_pgid=1000
  local user_info_flag_file="${BASE_DIR}/config/POK-manager/user_info_shown"
  local migration_complete_file="${BASE_DIR}/config/POK-manager/migration_complete"

  # Check if the script is run with sudo (EUID is 0)
  if is_sudo; then
    echo "Running with sudo privileges. Skipping PUID and PGID check."
    return
  fi

  local current_uid=$(id -u)
  local current_gid=$(id -g)
  local current_user=$(id -un)
  
  # If the -setup command is being run, check if user is either 7777:7777 (new default) or 1000:1000 (legacy)
  if [[ "$original_command" == *"-setup"* ]]; then
    # If user is running as either the new default (7777) or legacy (1000) UID, allow setup to proceed
    if [ "$current_uid" -eq 7777 ] || [ "$current_uid" -eq 1000 ]; then
      # Update PUID/PGID to match current user for this execution
      PUID=$current_uid
      PGID=$current_gid
      echo "Using UID:GID ${PUID}:${PGID} for server setup."
      
      # Create a flag file to prevent showing migration messages during setup
      mkdir -p "${BASE_DIR}/config/POK-manager"
      touch "$user_info_flag_file"
      return
    elif [ "$current_uid" -ne "$puid" ] && [ "$current_uid" -ne 0 ]; then
      echo "⚠️ You are setting up a new server but not running as user with UID $puid."
      echo "Creating a user with the correct UID/GID is recommended for proper permissions."
      echo ""
      read -r -p "Would you like to create a user with UID/GID $puid:$pgid for managing your server? [y/N] " create_user
      if [[ "$create_user" =~ ^[Yy]$ ]]; then
        echo "Creating user 'pokuser' with UID/GID $puid:$pgid..."
        echo "This command requires sudo permissions."
        echo ""
        local command_sudo="sudo groupadd -g $pgid pokuser && sudo useradd -u $puid -g $pgid -m -s /bin/bash pokuser"
        echo "Running: $command_sudo"
        eval "$command_sudo"
        
        if [ $? -eq 0 ]; then
          echo "✅ User created successfully!"
          echo "To use this user, run:"
          echo "sudo su - pokuser"
          echo "cd $(pwd) && ./POK-manager.sh $original_command"
          exit 0
        else
          echo "❌ Failed to create user. You may need to run the commands manually:"
          echo "sudo groupadd -g $pgid pokuser"
          echo "sudo useradd -u $puid -g $pgid -m -s /bin/bash pokuser"
          echo ""
          echo "You can continue with the current user, but you might encounter permission issues."
          echo "To bypass permission checks, run with sudo: sudo ./POK-manager.sh $original_command"
        fi
      fi
    fi
  fi
  
  # Skip showing migration info if migration is complete
  if [ -f "$migration_complete_file" ]; then
    # Still use the correct PUID/PGID values, but don't show the info message
    if [ -d "${BASE_DIR}/ServerFiles/arkserver" ]; then
      local dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/ServerFiles/arkserver)"
      local dir_uid=$(echo "$dir_ownership" | cut -d: -f1)
      local dir_gid=$(echo "$dir_ownership" | cut -d: -f2)
      
      # If directory ownership doesn't match current PUID/PGID, adjust for this execution
      if [ "${puid}" != "${dir_uid}" ] || [ "${pgid}" != "${dir_gid}" ]; then
        PUID=${dir_uid}
        PGID=${dir_gid}
      fi
    fi
    
    # ENHANCEMENT: Check if user has correct permissions after migration
    if [ -f "$migration_complete_file" ] && [ "${current_uid}" -ne 7777 ] && [ "${current_uid}" -ne 0 ]; then
      echo ""
      echo "⚠️ POST-MIGRATION PERMISSION ISSUE DETECTED ⚠️"
      echo "Your server files are owned by UID:GID 7777:7777 after migration, but you're running"
      echo "this script as user '${current_user}' with UID:GID ${current_uid}:${current_gid}."
      echo ""
      echo "You have two options to fix this:"
      echo ""
      echo "1. Run commands with sudo (easiest temporary solution):"
      echo "   sudo ./POK-manager.sh $original_command"
      echo ""
      
      # Check if pokuser or any user with UID 7777 exists
      local pokuser=$(grep ":7777:" /etc/passwd | cut -d: -f1)
      if [ -n "$pokuser" ]; then
        echo "2. Switch to the correct user account with UID 7777 (recommended):"
        echo "   sudo su - $pokuser"
        echo "   cd $(pwd) && ./POK-manager.sh $original_command"
      else
        echo "2. The migration should have created a user with UID 7777."
        echo "   If this user doesn't exist, please run the migration again:"
        echo "   sudo ./POK-manager.sh -migrate"
      fi
      exit 1
    fi
    
    return
  fi

  # Check if user is already using 7777:7777 and has seen the info message
  local show_info=true
  if [ -f "$user_info_flag_file" ] && [ "$puid" = "7777" ] && [ "$current_uid" = "7777" ]; then
    show_info=false
  fi
  
  # Display important information about container permissions only if needed
  if [ "$show_info" = "true" ]; then
    echo "ℹ️ INFORMATION: The default container user changed from 1000:1000 to 7777:7777 in version 2.1+"
    echo "This change improves compatibility with most Linux distributions that use 1000:1000 for the first user."
    echo "For best results, server files should be owned by user with UID:GID matching the container settings."
    echo ""
    
    # If user is running with correct 7777:7777 UID/GID, create the flag file
    if [ "$puid" = "7777" ] && [ "$current_uid" = "7777" ]; then
      mkdir -p "${BASE_DIR}/config/POK-manager"
      touch "$user_info_flag_file"
    fi
  fi
  
  # Check for existing directories that might be owned by legacy PUID:PGID
  if [ -d "${BASE_DIR}/ServerFiles/arkserver" ]; then
    # Get the actual ownership of the directory
    local dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/ServerFiles/arkserver)"
    local dir_uid=$(echo "$dir_ownership" | cut -d: -f1)
    local dir_gid=$(echo "$dir_ownership" | cut -d: -f2)
    
    # Inform about detected file ownership
    if [ "$dir_ownership" = "${legacy_puid}:${legacy_pgid}" ]; then
      echo "⚠️ DETECTED LEGACY CONFIGURATION: Your server files are owned by the old default UID:GID (1000:1000)"
      
      # Check if current UID/GID matches neither current nor legacy settings
      if [ "${current_uid}" -ne "${puid}" ] && [ "${current_uid}" -ne "${legacy_puid}" ]; then
        echo "⚠️ PERMISSION MISMATCH: Your files are owned by ${dir_uid}:${dir_gid} but you're running as ${current_uid}:${current_gid}"
        echo "This will likely cause permission issues between the host and container for save data and server files."
        echo ""
        echo "You have these options:"
        echo ""
        echo "1. Run the script with the correct user:"
        local possible_users=$(getent passwd "$dir_uid" | cut -d: -f1)
        if [ -n "$possible_users" ]; then
          echo "   Switch to user '$possible_users' with: su - $possible_users"
          echo "   Then run: ./POK-manager.sh $original_command"
        else
          echo "   (No user with UID $dir_uid was found on this system)"
          
          # Special case for 7777 UID after migration but no matching user
          if [ "$dir_uid" = "7777" ]; then
            echo ""
            echo "   It appears you've migrated to the new 7777:7777 ownership but don't have a matching user."
            echo "   You can create a user with this UID/GID to manage your server more easily:"
            echo "   sudo groupadd -g 7777 pokuser"
            echo "   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser"
            echo "   sudo su - pokuser"
            echo ""
            echo "   You can also create this user automatically by running: sudo ./POK-manager.sh -migrate"
            echo "   and answering 'y' when prompted to create a user."
          fi
        fi
        echo ""
        echo "2. Run with sudo to bypass permission checks:"
        echo "   sudo ./POK-manager.sh $original_command"
        echo "   (This lets you run the script with any user, but note that server files"
        echo "    still need to be owned by either 1000:1000 or 7777:7777 for the container to work properly)"
        echo ""
        echo "3. Update file ownership to the new default (7777:7777):"
        echo "   sudo chown -R 7777:7777 ${BASE_DIR}"
        echo "   (Recommended for new setups to match container defaults)"
        echo ""
        echo "4. Change file ownership to legacy configuration (1000:1000):"
        echo "   sudo chown -R 1000:1000 ${BASE_DIR}"
        echo "   (Only for POK-manager 2.0 users. If using 2.0, you can either:"
        echo "    - Continue using 2.0 with 1000:1000 permissions, or"
        echo "    - Upgrade to 2.1 by running: ./POK-manager.sh -migrate)"
        echo ""
        exit 1
      fi
    elif [ "${current_uid}" -ne "${puid}" ] && [ "${current_uid}" -ne "${dir_uid}" ]; then
      # File ownership doesn't match legacy, but also doesn't match current user
      echo "⚠️ PERMISSION MISMATCH: Your files are owned by ${dir_uid}:${dir_gid} but you're running as ${current_uid}:${current_gid}"
      echo "This will likely cause permission issues between the host and container for save data and server files."
      echo ""
      echo "You have these options:"
      echo ""
      echo "1. Run the script with the correct user:"
      local possible_users=$(getent passwd "$dir_uid" | cut -d: -f1)
      if [ -n "$possible_users" ]; then
        echo "   Switch to user '$possible_users' with: su - $possible_users"
        echo "   Then run: ./POK-manager.sh $original_command"
      else
        echo "   (No user with UID $dir_uid was found on this system)"
        
        # Special case for 7777 UID after migration but no matching user
        if [ "$dir_uid" = "7777" ]; then
          echo ""
          echo "   It appears you've migrated to the new 7777:7777 ownership but don't have a matching user."
          echo "   You can create a user with this UID/GID to manage your server more easily:"
          echo "   sudo groupadd -g 7777 pokuser"
          echo "   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser"
          echo "   sudo su - pokuser"
          echo ""
          echo "   You can also create this user automatically by running: sudo ./POK-manager.sh -migrate"
          echo "   and answering 'y' when prompted to create a user."
        fi
      fi
      echo ""
      echo "2. Run with sudo to bypass permission checks:"
      echo "   sudo ./POK-manager.sh $original_command"
      echo "   (This lets you run the script with any user, but note that server files"
      echo "    still need to be owned by either 1000:1000 or 7777:7777 for the container to work properly)"
      echo ""
      echo "3. Update file ownership to the new default (7777:7777):"
      echo "   sudo chown -R 7777:7777 ${BASE_DIR}"
      echo "   (Recommended for new setups to match container defaults)"
      echo ""
      echo "4. Change file ownership to legacy configuration (1000:1000):"
      echo "   sudo chown -R 1000:1000 ${BASE_DIR}"
      echo "   (Only for POK-manager 2.0 users. If using 2.0, you can either:"
      echo "    - Continue using 2.0 with 1000:1000 permissions, or"
      echo "    - Upgrade to 2.1 by running: ./POK-manager.sh -migrate)"
      echo ""
      exit 1
    fi
    
    # Set PUID/PGID to match existing directories for this execution
    if [ "${puid}" != "${dir_uid}" ] || [ "${pgid}" != "${dir_gid}" ]; then
      echo "For this execution, we'll use values (${dir_uid}:${dir_gid}) to match your existing files."
      PUID=${dir_uid}
      PGID=${dir_gid}
      return
    fi
  fi

  if [ "${current_uid}" -ne "${puid}" ] || [ "${current_gid}" -ne "${pgid}" ]; then
    echo "⚠️ PERMISSION MISMATCH: You are not running the script as the user with the correct PUID (${puid}) and PGID (${pgid})."
    echo "Your current user '${current_user}' has UID ${current_uid} and GID ${current_gid}."
    echo "This can cause permission issues between the host and container for save data and server files."
    echo ""
    echo "The script supports both legacy (1000:1000) and new (7777:7777) user configurations:"
    echo "- If your files are owned by 1000:1000, the script will use those values"
    echo "- If your files are owned by 7777:7777, the script will use those values"
    echo "- For new installations, 7777:7777 is recommended to avoid conflicts with system users"
    echo ""
    echo "You have these options:"
    echo ""
    echo "1. Run with sudo to bypass permission checks:"
    echo "   sudo ./POK-manager.sh $original_command"
    echo "   (This lets you run the script with any user, but note that server files"
    echo "    still need to be owned by either 1000:1000 or 7777:7777 for the container to work properly)"
    echo ""
    echo "2. Update file ownership to the new default (7777:7777):"
    echo "   sudo chown -R 7777:7777 ${BASE_DIR}"
    echo "   (Recommended for new setups to match container defaults)"
    echo ""
    echo "3. Change file ownership to legacy configuration (1000:1000):"
    echo "   sudo chown -R 1000:1000 ${BASE_DIR}"
    echo "   (Only for POK-manager 2.0 users. If using 2.0, you can either:"
    echo "    - Continue using 2.0 with 1000:1000 permissions, or"
    echo "    - Upgrade to 2.1 by running: ./POK-manager.sh -migrate)"
    echo ""
    echo "4. Switch to a user with the correct UID/GID:"
    local possible_users=$(getent passwd "$puid" | cut -d: -f1)
    if [ -n "$possible_users" ]; then
      echo "   Switch to user '$possible_users' with: su - $possible_users"
      echo "   Then run: ./POK-manager.sh $original_command"
    else
      echo "   Or create a user with the correct UID/GID:"
      echo "   sudo groupadd -g ${puid} pokuser"
      echo "   sudo useradd -u ${puid} -g ${pgid} -m -s /bin/bash pokuser"
      echo "   sudo su - pokuser"
      echo "   cd $(pwd) && ./POK-manager.sh $original_command"
      
      # Special case for 7777 UID after migration but no matching user
      if [ "$puid" = "7777" ]; then
        echo ""
        echo "   NOTE: You can also create this user automatically by running: sudo ./POK-manager.sh -migrate"
        echo "   and answering 'y' when prompted to create a user."
      fi
    fi
    echo ""
    exit 1
  fi
}


copy_default_configs() {
  # Define the directory where the configuration files will be stored
  local config_dir="${base_dir}/Instance_${instance_name}/Saved/Config/WindowsServer"
  local base_dir="${BASE_DIR}"

  # Ensure the configuration directory exists
  mkdir -p "$config_dir"

  # Copy GameUserSettings.ini if it does not exist
  if [ ! -f "${config_dir}/GameUserSettings.ini" ]; then
    echo "Copying default GameUserSettings.ini"
    cp ./defaults/GameUserSettings.ini "$config_dir"
    chown $PUID:$PGID "${config_dir}/GameUserSettings.ini"
  fi

  # Copy Game.ini if it does not exist
  if [ ! -f "${config_dir}/Game.ini" ]; then
    echo "Copying default Game.ini"
    cp ./defaults/Game.ini "$config_dir"
    chown $PUID:$PGID "${config_dir}/Game.ini"
  fi
}

install_yq() {
  echo "Checking for yq..."
  if ! command -v yq &>/dev/null; then
    echo "yq not found. Attempting to install Mike Farah's yq..."

    # Define the version of yq to install
    YQ_VERSION="v4.9.8" # Check https://github.com/mikefarah/yq for the latest version

    # Determine OS and architecture
    os=""
    case "$(uname -s)" in
      Linux) os="linux" ;;
      Darwin) os="darwin" ;;
      *) echo "Unsupported OS."; exit 1 ;;  
    esac

    arch=""
    case "$(uname -m)" in
      x86_64) arch="amd64" ;;
      arm64) arch="arm64" ;;
      aarch64) arch="arm64" ;;
      *) echo "Unsupported architecture."; exit 1 ;;
    esac

    YQ_BINARY="yq_${os}_${arch}"

    # Check for wget or curl and install if not present
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
      echo "Neither wget nor curl found. Attempting to install wget..."
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y wget
      elif command -v yum &>/dev/null; then
        sudo yum install -y wget
      elif command -v pacman &>/dev/null; then
        sudo pacman -Sy wget
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y wget
      else
        echo "Package manager not detected. Please manually install wget or curl."
        exit 1
      fi
    fi

    # Download and install yq
    if command -v wget &>/dev/null; then
      wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq
    elif command -v curl &>/dev/null; then
      curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
    fi

    # Verify installation
    if ! command -v yq &>/dev/null; then
      echo "Failed to install Mike Farah's yq."
      exit 1
    else
      echo "Mike Farah's yq installed successfully."
    fi
  else
    echo "yq is already installed."
  fi
}

# Root tasks
root_tasks() {
  local base_dir="${BASE_DIR}"
  check_vm_max_map_count
  check_puid_pgid_user "$PUID" "$PGID"
  check_dependencies
  install_jq
  install_yq
  adjust_ownership_and_permissions "${base_dir}/ServerFiles/arkserver"
  adjust_ownership_and_permissions "${base_dir}/ServerFiles/arkserver/ShooterGame"
  adjust_ownership_and_permissions "${base_dir}/Cluster"
  prompt_change_host_timezone  
  echo "Root tasks completed. You're now ready to create an instance."
}

pull_docker_image() {
  local instance_name="$1"
  local image_tag=$(get_docker_image_tag "$instance_name")
  local image_name="acekorneya/asa_server:${image_tag}"
  echo "Pulling Docker image: $image_name"
  
  # Check if user is in docker group
  if groups | grep -q '\bdocker\b'; then
    # User is in docker group, no need for sudo
    docker pull "$image_name"
  else
    # Check if we're already running as root
    if [ "$(id -u)" -eq 0 ]; then
      docker pull "$image_name"
    else
      # Check if we're in a non-interactive environment (like cron)
      if [ ! -t 0 ]; then
        echo "Warning: Not in docker group and running in non-interactive mode. Attempting docker pull without sudo."
        docker pull "$image_name" || echo "Failed to pull docker image. Consider adding user to docker group for cronjob compatibility."
      else
        # Interactive session, can use sudo and offer to add user to docker group
        echo "You are not in the docker group. Adding you to the docker group will allow running docker commands without sudo."
        echo "Would you like to add your user to the docker group? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
          sudo usermod -aG docker "$(whoami)"
          echo "User added to docker group. You need to log out and log back in for this to take effect."
          echo "For now, using sudo to pull the image."
        fi
        sudo docker pull "$image_name"
      fi
    fi
  fi
}

read_docker_compose_config() {
  local instance_name="$1"
  local base_dir="${BASE_DIR}"
  local docker_compose_file="${base_dir}/Instance_${instance_name}/docker-compose-${instance_name}.yaml"
  if [ ! -f "$docker_compose_file" ]; then
    echo "Docker compose file for ${instance_name} does not exist."
    exit 1
  fi

  # Parse the environment section
  local env_vars
  mapfile -t env_vars < <(yq e '.services.asaserver.environment[]' "$docker_compose_file")

  for env_var in "${env_vars[@]}"; do
    # Splitting each line into key and value
    IFS='=' read -r key value <<< "${env_var}"
    key="${key//-/_}" # Replace hyphens with underscores to match your script's keys
    key="${key^^}" # Convert to uppercase to match your associative array keys

    # Map environment variable keys to your script's config keys if needed
    case "$key" in
    "TZ") config_key="TZ" ;;
    "BATTLEEYE") config_key="BattleEye" ;;  
    "API") config_key="API" ;;
    "RCON_ENABLED") config_key="RCON Enabled" ;;
    "DISPLAY_POK_MONITOR_MESSAGE") config_key="POK Monitor Message" ;;
    "RANDOM_STARTUP_DELAY") config_key="Random Startup Delay" ;;
    "UPDATE_SERVER") config_key="Update Server" ;;
    "CHECK_FOR_UPDATE_INTERVAL") config_key="Update Interval" ;;
    "UPDATE_WINDOW_MINIMUM_TIME") config_key="Update Window Start" ;;
    "UPDATE_WINDOW_MAXIMUM_TIME") config_key="Update Window End" ;;
    "RESTART_NOTICE_MINUTES") config_key="Restart Notice" ;;
    "ENABLE_MOTD") config_key="MOTD Enabled" ;;
    "MOTD") config_key="MOTD" ;; 
    "MOTD_DURATION") config_key="MOTD Duration" ;; 
    "MAP_NAME") config_key="Map Name" ;;
    "SESSION_NAME") config_key="Session Name" ;;
    "SERVER_ADMIN_PASSWORD") config_key="Admin Password" ;;
    "SERVER_PASSWORD") config_key="Server Password" ;;
    "ASA_PORT") config_key="ASA Port" ;;
    "RCON_PORT") config_key="RCON Port" ;;
    "MAX_PLAYERS") config_key="Max Players" ;;
    "SHOW_ADMIN_COMMANDS_IN_CHAT") config_key="Show Admin Commands In Chat" ;;      
    "CLUSTER_ID") config_key="Cluster ID" ;;
    "MOD_IDS") config_key="Mod IDs" ;;
    "PASSIVE_MODS") config_key="Passive Mods" ;;
    "CUSTOM_SERVER_ARGS") config_key="Custom Server Args" ;;
    *) config_key="$key" ;; # For any not explicitly mapped
    esac
    
    # Populate config_values
    config_values[$config_key]="$value"
  done

  # Separately parse the mem_limit
  local mem_limit
  mem_limit=$(yq e '.services.asaserver.mem_limit' "$docker_compose_file")
  if [ ! -z "$mem_limit" ]; then
    # Assuming you want to strip the last character (G) and store just the numeric part
    # If you want to keep the 'G', remove the `${mem_limit%?}` manipulation
    config_values["Memory Limit"]="${mem_limit}" 
  fi
}

# Function to write Docker Compose file
write_docker_compose_file() {
  local instance_name="$1"
  local base_dir="${BASE_DIR}"
  local instance_dir="${base_dir}/Instance_${instance_name}"
  local docker_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
  local image_tag=$(get_docker_image_tag "$instance_name")

  # Ensure the instance directory exists
  mkdir -p "${instance_dir}"
  
  # Create API_Logs directory for this instance
  mkdir -p "${instance_dir}/API_Logs"
  
  # Set appropriate permissions based on the image tag
  if [[ "$image_tag" == 2_0* ]]; then
    # For 2_0 image, use 1000:1000
    chmod 755 "${instance_dir}/API_Logs"
    chown 1000:1000 "${instance_dir}/API_Logs"
    echo "Setting 1000:1000 ownership on API_Logs directory for 2_0_latest image compatibility"
  else
    # For 2_1 image, use 7777:7777
    chmod 755 "${instance_dir}/API_Logs"
    chown 7777:7777 "${instance_dir}/API_Logs"
    echo "Setting 7777:7777 ownership on API_Logs directory for 2_1_latest image compatibility"
  fi

  # Start writing the Docker Compose configuration
  cat > "$docker_compose_file" <<-EOF
version: '2.4'

services:
  asaserver:
    build: .
    image: acekorneya/asa_server:${image_tag}
    container_name: asa_${instance_name} 
    restart: unless-stopped
    environment:
      - INSTANCE_NAME=${instance_name}
      - TZ=$TZ
EOF

  # Iterate over the config_order to maintain the order in Docker Compose
  for key in "${config_order[@]}"; do
    # Convert the friendly name to the actual environment variable key.
    case "$key" in
      "BattleEye") env_key="BATTLEEYE" ;;
      "API") env_key="API" ;;
      "RCON Enabled") env_key="RCON_ENABLED" ;;
      "POK Monitor Message") env_key="DISPLAY_POK_MONITOR_MESSAGE" ;;
      "Random Startup Delay") env_key="RANDOM_STARTUP_DELAY" ;;
      "CPU Optimization") env_key="CPU_OPTIMIZATION" ;;
      "Update Server") env_key="UPDATE_SERVER" ;;
      "Update Interval") env_key="CHECK_FOR_UPDATE_INTERVAL" ;;
      "Update Window Start") env_key="UPDATE_WINDOW_MINIMUM_TIME" ;;
      "Update Window End") env_key="UPDATE_WINDOW_MAXIMUM_TIME" ;;
      "Restart Notice") env_key="RESTART_NOTICE_MINUTES" ;;
      "MOTD Enabled") env_key="ENABLE_MOTD" ;;
      "MOTD") env_key="MOTD" ;;
      "MOTD Duration") env_key="MOTD_DURATION" ;;
      "Map Name") env_key="MAP_NAME" ;;
      "Session Name") env_key="SESSION_NAME" ;;
      "Admin Password") env_key="SERVER_ADMIN_PASSWORD" ;;
      "Server Password") env_key="SERVER_PASSWORD" ;;
      "ASA Port") env_key="ASA_PORT" ;;
      "RCON Port") env_key="RCON_PORT" ;;
      "Show Admin Commands In Chat") env_key="SHOW_ADMIN_COMMANDS_IN_CHAT" ;;      
      "Max Players") env_key="MAX_PLAYERS" ;;
      "Cluster ID") env_key="CLUSTER_ID" ;;
      "Mod IDs") env_key="MOD_IDS" ;;
      "Passive Mods") env_key="PASSIVE_MODS" ;;
      "Custom Server Args") env_key="CUSTOM_SERVER_ARGS" ;;
      *) env_key="$key" ;; # Default case if the mapping is direct
    esac
    
    # Write the environment variable to the Docker Compose file, skipping Memory Limit
    if [[ "$key" != "Memory Limit" ]]; then
      echo "      - $env_key=${config_values[$key]}" >> "$docker_compose_file"
    fi
  done

  # Continue writing the rest of the Docker Compose configuration
cat >> "$docker_compose_file" <<-EOF
    ports:
      - "${config_values[ASA Port]}:${config_values[ASA Port]}/tcp"
      - "${config_values[ASA Port]}:${config_values[ASA Port]}/udp"
      - "${config_values[RCON Port]}:${config_values[RCON Port]}/tcp"
    volumes:
      - "${base_dir}/ServerFiles/arkserver:/home/pok/arkserver"
      - "${instance_dir}/Saved:/home/pok/arkserver/ShooterGame/Saved"
EOF

  # Check if API is enabled and only add API_Logs volume if it is
  if grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"; then
    # Get absolute path for the instance directory to ensure we use absolute paths
    local abs_instance_dir=$(realpath "$instance_dir")
    echo "      - \"${abs_instance_dir}/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs\"" >> "$docker_compose_file"
  fi

  # Add the Cluster volume
  cat >> "$docker_compose_file" <<-EOF
      - "${base_dir}/Cluster:/home/pok/arkserver/ShooterGame/Saved/clusters"
    mem_limit: ${config_values[Memory Limit]}
EOF

  # If running with sudo, set the file ownership to the correct user
  if is_sudo; then
    # Get the ownership of the parent directory
    local dir_owner=$(stat -c '%u' "$instance_dir")
    local dir_group=$(stat -c '%g' "$instance_dir")
    
    # If the directory has non-root ownership, use that; otherwise default to PUID:PGID
    if [ "$dir_owner" -ne 0 ] && [ "$dir_group" -ne 0 ]; then
      chown "${dir_owner}:${dir_group}" "$docker_compose_file"
      echo "Set docker-compose file ownership to match parent directory: ${dir_owner}:${dir_group}"
    else
      # If the directory is owned by root, use PUID:PGID from the script
      chown "${PUID}:${PGID}" "$docker_compose_file"
      echo "Set docker-compose file ownership to PUID:PGID: ${PUID}:${PGID}"
    fi
  fi

  echo "Created Docker Compose file: $docker_compose_file"
  echo "Using Docker image with tag: ${image_tag}"
  
  # Display information about file ownership and container permissions
  if [[ "$image_tag" == 2_0* ]]; then
    echo -e "\n⚠️ IMPORTANT: This instance will use the 2_0 image with fixed UID:GID 1000:1000."
    echo "Make sure your files are owned by a user with UID:GID 1000:1000 on the host system."
    echo "To set file ownership: sudo chown -R 1000:1000 ${BASE_DIR}"
  else
    echo -e "\n⚠️ IMPORTANT: This instance will use the 2_1 image with fixed UID:GID 7777:7777."
    echo "Make sure your files are owned by a user with UID:GID 7777:7777 on the host system."
    echo "To set file ownership: sudo chown -R 7777:7777 ${BASE_DIR}"
  fi
}

# Function to check and optionally adjust Docker command permissions
adjust_docker_permissions() {
  local config_file=$(get_config_file_path)
  local config_dir=$(dirname "$config_file")

  # Ensure the directory exists
  mkdir -p "$config_dir"

  # If we can access the file, read its content
  if [ -f "$config_file" ] && [ -r "$config_file" ]; then
    local use_sudo
    use_sudo=$(cat "$config_file" 2>/dev/null || echo "true")
    if [ "$use_sudo" = "false" ]; then
      echo "User has chosen to run Docker commands without 'sudo'."
      return
    fi
  else
    # If we can't read the file due to permissions
    if [ "$(id -u)" -eq 0 ]; then
      # If running as root/sudo, fix permissions and try again
      if [ -d "${BASE_DIR}/ServerFiles/arkserver" ]; then
        local dir_owner=$(stat -c '%u' "${BASE_DIR}/ServerFiles/arkserver")
        local dir_group=$(stat -c '%g' "${BASE_DIR}/ServerFiles/arkserver")
        chown -R "${dir_owner}:${dir_group}" "$config_dir"
      fi
    fi
    
    # After fixing permissions, check if user is in docker group
    if groups $USER | grep -q '\bdocker\b'; then
      echo "User $USER is already in the docker group."
      read -r -p "Would you like to run Docker commands without 'sudo'? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Changing ownership of /var/run/docker.sock to $USER..."
        sudo chown $USER /var/run/docker.sock
        echo "false" > "$config_file" 2>/dev/null || true
        if [ -f "$config_file" ] && [ "$(cat "$config_file" 2>/dev/null)" = "false" ]; then
          echo "User preference saved. You can now run Docker commands without 'sudo'."
          return
        else
          echo "Failed to save user preference. You may need to run with sudo."
        fi
      fi
    else
      read -r -p "Config file not found or inaccessible. Do you want to add user $USER to the 'docker' group? [y/N] " add_to_group
      if [[ "$add_to_group" =~ ^[Yy]$ ]]; then
        echo "Adding user $USER to the 'docker' group..."
        sudo usermod -aG docker $USER
        echo "User $USER has been added to the 'docker' group."
        
        echo "Changing ownership of /var/run/docker.sock to $USER..."
        sudo chown $USER /var/run/docker.sock
        
        echo "You can now run Docker commands without 'sudo'."
        echo "false" > "$config_file" 2>/dev/null || true
        
        return
      fi
    fi
  fi

  # If we got here, use sudo for docker commands
  echo "true" > "$config_file" 2>/dev/null || true
  echo "Please ensure to use 'sudo' for Docker commands or run this script with 'sudo'."
}

prompt_for_instance_name() {
  local provided_name="$1"
  if [ -z "$provided_name" ]; then
    read -rp "Please enter an instance name: " instance_name
    if [ -z "$instance_name" ]; then
      echo "Instance name is required to proceed."
      exit 1 # Now exits if no instance name is provided
    fi
  else
    instance_name="$provided_name"
  fi
  echo "$instance_name" # Return the determined instance name
}

# Function to perform an action on all instances
perform_action_on_all_instances() {
  local action=$1
  local base_dir="${BASE_DIR}"
  echo "Performing '${action}' on all instances..."

  # Special case for stop action - use the optimized function
  if [[ "$action" == "-stop" ]]; then
    stop_all_instances
    return
  fi

  # Find all instance directories
  local instance_dirs=($(find "${base_dir}/Instance_"* -maxdepth 0 -type d 2>/dev/null || true))

  for instance_dir in "${instance_dirs[@]}"; do
    # Extract instance name from directory
    local instance_name=$(basename "$instance_dir" | sed -E 's/Instance_(.*)/\1/')
    echo "Performing '${action}' on instance: $instance_name"

    case $action in
    -start)
      start_instance "$instance_name"
      ;;
    -stop)
      stop_instance "$instance_name"
      ;;
    *)
      echo "Unsupported action '${action}' for all instances."
      ;;
    esac
  done
}

# Function to stop all instances
stop_all_instances() {
  local base_dir="${BASE_DIR}"
  
  echo "Stopping all running instances..."
  
  # Get all running instances
  local running_instances=($(list_running_instances))
  
  if [ ${#running_instances[@]} -eq 0 ]; then
    echo "No running instances found. Nothing to stop."
    return 0
  fi
  
  echo "Found ${#running_instances[@]} running instances to stop."
  
  # First, attempt quick saves on all running instances in parallel
  echo "Attempting quick saves on all running instances..."
  for instance in "${running_instances[@]}"; do
    local container_name="asa_${instance}"
    echo "  Sending quick save command to $instance..."
    
    # Run saveworld command with a 3-second timeout in background
    (
      timeout 3s docker exec "$container_name" /bin/bash -c "/home/pok/scripts/rcon_interface.sh -saveworld" >/dev/null 2>&1
      save_exit_code=$?
      if [ $save_exit_code -eq 0 ]; then
        echo "  Save command sent successfully to $instance"
      else
        echo "  Save command failed or timed out for $instance, proceeding with stop"
      fi
    ) &
  done
  
  # Give all instances a short time to process their saves
  echo "Waiting 5 seconds for save operations to complete..."
  sleep 5
  
  # Now stop all instances
  echo "Now stopping all containers..."
  for instance in "${running_instances[@]}"; do
    echo "Stopping instance: $instance"
    stop_instance "$instance" &
  done
  
  # Wait for all stop operations to complete
  wait
  
  echo "All instances have been stopped."
  return 0
}

# Function to inject shutdown flag and perform shutdown
inject_shutdown_flag_and_shutdown() {
  local instance="$1"
  local message="$2"
  local wait_time="$3"
  local container_name="asa_${instance}" # Assuming container naming convention
  local base_dir="${BASE_DIR}"
  local instance_dir="${base_dir}/Instance_${instance}"
  local docker_compose_file="${instance_dir}/docker-compose-${instance}.yaml"

  # Check if the container exists and is running
  if docker ps -q -f name=^/${container_name}$ > /dev/null; then
    echo "Preparing container for shutdown..."
    
    # Create a check file to verify if the server was already saved
    docker exec "$container_name" touch /home/pok/shutdown_prepared.flag
    
    # First inject shutdown.flag into the container
    # This signals to the container's monitoring scripts that shutdown is intended
    echo "Injecting shutdown flag..."
    docker exec "$container_name" touch /home/pok/shutdown.flag
    
    # Check if any wait time is left - rarely needed but good for safety
    local current_time=$(date +%s)
    local eta_time=$(date -d "@$((current_time + wait_time * 60))" "+%s")
    local remaining_seconds=$((eta_time - current_time))
    
    if [ $remaining_seconds -gt 10 ]; then  # If more than 10 seconds left
      echo "Waiting for server's internal countdown to complete..."
      sleep $remaining_seconds
    fi
    
    # Verify the game process is still running before trying to save again
    if docker exec "$container_name" pgrep -f "ArkAscendedServer.exe" > /dev/null; then
      # Send a final saveworld command to ensure latest data is saved
      echo "Sending final save command to server..."
      docker exec "$container_name" /bin/bash -c "/home/pok/scripts/rcon_interface.sh -saveworld" >/dev/null 2>&1 || true
      
      # Create a short wait to allow save to complete
      sleep 5
    else
      echo "Game process has already stopped."
    fi
    
    # Create a shutdown_complete flag for the wait function to check
    docker exec "$container_name" touch /home/pok/shutdown_complete.flag 2>/dev/null || true
    
    # Wait for shutdown completion with timeout
    echo "Waiting for server process to exit completely..."
    if ! wait_for_shutdown "$instance" "$wait_time"; then
      echo "Warning: Shutdown wait timed out. Forcing container shutdown."
    fi
    
    # Get docker compose command
    get_docker_compose_cmd
    
    # Shutdown the container using docker-compose
    echo "Stopping container for $instance..."
    if [ -f "$docker_compose_file" ]; then
      $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down
    else
      # Fallback to docker stop if compose file not found
      docker stop "$container_name"
    fi
    
    echo "Instance ${instance} shutdown completed successfully."
  else
    echo "Instance ${instance} is not running or does not exist."
  fi
}

# Helper function to prompt for instance copy
prompt_for_instance_copy() {
  local instance_name="$1"
  local instances=($(list_instances))
  if [ ${#instances[@]} -gt 0 ]; then
    echo "Existing instances found. Would you like to copy settings from another instance? (y/N)"
    read answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      echo "Select the instance you want to copy settings from:"
      select instance in "${instances[@]}"; do
        if [ -n "$instance" ] && [ "$instance" != "$instance_name" ]; then
          echo "Copying settings from $instance..."
          read_docker_compose_config "$instance"
          break
        else
          echo "Invalid selection."
        fi
      done
    else
      echo "Proceeding with default settings."
      # Initially populate config_values with defaults if not copying
      for key in "${!default_config_values[@]}"; do
        config_values[$key]=${default_config_values[$key]}
      done
    fi
  else
    echo "No existing instances found. Proceeding with default settings."
    # Initially populate config_values with defaults if no existing instances
    for key in "${!default_config_values[@]}"; do
      config_values[$key]=${default_config_values[$key]}
    done
  fi
}

# Function to review and modify configuration before finalizing
review_and_modify_configuration() {
  local repeat=true
  while $repeat; do
    echo "Current Configuration:"
    for key in "${config_order[@]}"; do
      echo "$key: ${config_values[$key]}"
    done

    echo "If you need to modify any setting, enter the setting name. Type 'confirm' to proceed with the current configuration."
    local modify
    read -rp "Modify setting (or 'confirm'): " modify

    if [[ $modify == "confirm" ]]; then
      repeat=false
    elif [[ ${config_values[$modify]+_} ]]; then
      prompt_for_input "$modify" 
    else
      echo "Invalid setting name. Please try again."
    fi
  done
}

edit_instance() {
  local instances=($(list_instances))
  echo "Select the instance you wish to edit:"
  select instance in "${instances[@]}"; do
    if [ -n "$instance" ]; then
      local editor=$(find_editor)
      local docker_compose_file="./Instance_$instance/docker-compose-$instance.yaml"
      echo "Opening $docker_compose_file for editing with $editor..."
      $editor "$docker_compose_file"
      break
    else
      echo "Invalid selection."
    fi
  done
}

# Function to generate or update Docker Compose file for an instance
generate_docker_compose() {
  check_puid_pgid_user "$PUID" "$PGID"
  local instance_name="$1"
  # Assuming TZ is set or defaults to UTC
  local tz="${TZ:-UTC}"
  declare -A config_values

  # Prompt for copying settings from an existing instance
  prompt_for_instance_copy "$instance_name"

  # Configuration review and modification loop
  review_and_modify_configuration

  # Path where Docker Compose files are located
  local base_dir="${BASE_DIR}"
  local instance_dir="${base_dir}/Instance_${instance_name}"
  local docker_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"

  # Check if the Docker Compose file already exists
  if [ -f "$docker_compose_file" ]; then
    echo "Docker Compose file for ${instance_name} already exists. Extracting and updating configuration..."
    read_docker_compose_config "$instance_name"
  else
    echo "Creating new Docker Compose configuration for ${instance_name}."
    mkdir -p "${instance_dir}"
    mkdir -p "${instance_dir}/Saved" # Ensure Saved directory is created
    copy_default_configs
    adjust_ownership_and_permissions "${instance_dir}" # Adjust permissions right after creation
  fi
  # Set the timezone for the container
  set_timezone
  
  # Ensure ServerFiles directory has correct permissions to prevent SteamCMD error 0x602
  echo "Ensuring ServerFiles directory has correct ownership..."
  mkdir -p "${BASE_DIR}/ServerFiles/arkserver"
  adjust_ownership_and_permissions "${BASE_DIR}/ServerFiles/arkserver"
  
  # Generate or update Docker Compose file with the confirmed settings
  write_docker_compose_file "$instance_name"

  # Prompt user for any final edits before saving
  prompt_for_final_edit "$docker_compose_file"

  echo "Docker Compose configuration for ${instance_name} has been finalized."
}

# Function to prompt user for final edits before saving the Docker Compose file
prompt_for_final_edit() {
  local docker_compose_file="$1"
  echo "Would you like to review and edit the Docker Compose configuration before finalizing? [y/N]"
  read -r response
   
  if [[ "$response" =~ ^[Yy]$ ]]; then
    local editor=$(find_editor) # Ensure find_editor function returns a valid editor command
    "$editor" "$docker_compose_file"
  fi
}


list_instances() {
  local base_dir="${BASE_DIR}"
  local compose_files=($(find "${base_dir}/Instance_"* -name 'docker-compose-*.yaml' 2>/dev/null || true))
  local instances=()
  for file in "${compose_files[@]}"; do
    local instance_name=$(echo "$file" | sed -E 's|.*/Instance_([^/]+)/docker-compose-.*\.yaml|\1|')
    instances+=("$instance_name")
  done
  echo "${instances[@]}"
}

find_editor() {
  # List of common text editors, ordered by preference
  local editors=("nano" "vim" "vi" "emacs")

  for editor in "${editors[@]}"; do
    if command -v "$editor" &> /dev/null; then
      echo "$editor"
      return
    fi
  done

  # No editor found, ask the user to specify one
  echo "No text editor found in your system. Please install 'nano', 'vim', or similar."
  echo "Alternatively, you can specify the path to your preferred text editor."
  read -rp "Enter the command or path for your text editor: " user_editor
  if [ -n "$user_editor" ]; then
    if command -v "$user_editor" &> /dev/null; then
      echo "$user_editor"
      return
    else
      echo "The specified editor could not be found. Please ensure the command or path is correct."
      exit 1
    fi
  else
    echo "No editor specified. Exiting..."
    exit 1
  fi
}

# Function to start an instance
start_instance() {
  local instance_name="$1"
  local instance_dir="${BASE_DIR}/Instance_${instance_name}"
  local docker_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
  local image_tag=$(get_docker_image_tag "$instance_name")
  
  echo "-----Starting ${instance_name} Server with image tag ${image_tag}-----"

  # Check if volume paths need to be updated
  check_volume_paths
  
  # First check if the docker-compose file exists
  if [ ! -f "$docker_compose_file" ]; then
    # Try to find any docker-compose file in the instance directory
    local found_compose_files=($(find "${instance_dir}" -maxdepth 1 -name 'docker-compose-*.yaml' 2>/dev/null || true))
    
    if [ ${#found_compose_files[@]} -gt 0 ]; then
      # Take the first one found
      local found_compose_file="${found_compose_files[0]}"
      local found_instance_name=$(basename "$found_compose_file" | sed 's/docker-compose-//g' | sed 's/\.yaml//g')
      
      echo "⚠️ Found a docker-compose file for instance '$found_instance_name' in folder for '$instance_name'"
      echo "This may happen if you renamed the folder manually instead of using the script's rename feature."
      
      # Ask user which name they want to use
      echo "Would you like to:"
      echo "1) Change the docker-compose file to match the folder name: '$instance_name'"
      echo "2) Use the instance name from the docker-compose file: '$found_instance_name'"
      read -p "Enter your choice (1 or 2): " name_choice
      
      if [[ "$name_choice" == "2" ]]; then
        echo "Using instance name from docker-compose file: '$found_instance_name'"
        instance_name="$found_instance_name"
        docker_compose_file="$found_compose_file"
      else
        echo "Automatically fixing the docker-compose file to match the instance name: '$instance_name'"
        
        # Create a backup of the original file
        local backup_file="${found_compose_file}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$found_compose_file" "$backup_file"
        # Set the correct ownership for the backup file to match parent folder
        local parent_ownership=$(stat -c "%u:%g" "${instance_dir}")
        chown "$parent_ownership" "$backup_file"
        echo "Created backup of original docker-compose file at: $backup_file"
        
        # Update the compose file - container name, instance name and volumes
        echo "Updating docker-compose file to match new instance name: $instance_name"
        
        # Update container name - handle both quoted and unquoted formats
        sed -i "s/container_name: \"asa_${found_instance_name}\"/container_name: \"asa_${instance_name}\"/g" "$found_compose_file"
        sed -i "s/container_name: asa_${found_instance_name}/container_name: asa_${instance_name}/g" "$found_compose_file"
        
        # Update environment variables for instance name
        sed -i "s/INSTANCE_NAME=${found_instance_name}/INSTANCE_NAME=${instance_name}/g" "$found_compose_file"
        sed -i "s/- INSTANCE_NAME=${found_instance_name}/- INSTANCE_NAME=${instance_name}/g" "$found_compose_file"
        
        # Update volume paths
        sed -i "s|Instance_${found_instance_name}/Saved|Instance_${instance_name}/Saved|g" "$found_compose_file"
        sed -i "s|Instance_${found_instance_name}/API_Logs|Instance_${instance_name}/API_Logs|g" "$found_compose_file"
        
        # Rename the file itself to match the new instance name
        mv "$found_compose_file" "$docker_compose_file"
        echo "Renamed docker-compose file to match new instance name"
        
        echo "Using updated docker-compose file: $docker_compose_file"
      fi
    else
      echo "❌ ERROR: Docker Compose file not found at $docker_compose_file"
      echo "Make sure the instance ${instance_name} exists and is properly configured."
      exit 1
    fi
  else
    # Docker compose file exists, but let's verify its contents match the instance name
    local file_instance_name=$(grep -E "container_name:.*asa_" "$docker_compose_file" | sed -E 's/.*container_name:.*asa_([^"]*).*/\1/' | tr -d ' ')
    local env_instance_name=$(grep -E "INSTANCE_NAME=" "$docker_compose_file" | sed -E 's/.*INSTANCE_NAME=([^"]*).*/\1/' | tr -d ' ')
    
    if [[ "$file_instance_name" != "$instance_name" || "$env_instance_name" != "$instance_name" ]]; then
      echo "⚠️ Docker compose file exists but contains mismatched instance names."
      echo "Found container name in docker-compose file: 'asa_$file_instance_name'"
      echo "Found INSTANCE_NAME in docker-compose file: '$env_instance_name'"
      
      # Ask user which name they want to use
      echo "Would you like to:"
      echo "1) Change the docker-compose file to match the folder name: '$instance_name'"
      echo "2) Use the instance name from the docker-compose file: '$file_instance_name'"
      read -p "Enter your choice (1 or 2): " name_choice
      
      if [[ "$name_choice" == "2" ]]; then
        echo "Using instance name from docker-compose file: '$file_instance_name'"
        instance_name="$file_instance_name"
      else
        echo "Automatically fixing the docker-compose file to match the instance name: '$instance_name'"
        
        # Create a backup of the original file
        local backup_file="${docker_compose_file}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$docker_compose_file" "$backup_file"
        # Set the correct ownership for the backup file to match parent folder
        local parent_ownership=$(stat -c "%u:%g" "${instance_dir}")
        chown "$parent_ownership" "$backup_file"
        echo "Created backup of original docker-compose file at: $backup_file"
        
        # Update container name - handle both quoted and unquoted formats
        sed -i "s/container_name: \"asa_${file_instance_name}\"/container_name: \"asa_${instance_name}\"/g" "$docker_compose_file"
        sed -i "s/container_name: asa_${file_instance_name}/container_name: asa_${instance_name}/g" "$docker_compose_file"
        
        # Update environment variables for instance name - handle both formats with and without leading hyphen
        sed -i "s/INSTANCE_NAME=${env_instance_name}/INSTANCE_NAME=${instance_name}/g" "$docker_compose_file"
        sed -i "s/- INSTANCE_NAME=${env_instance_name}/- INSTANCE_NAME=${instance_name}/g" "$docker_compose_file"
        
        # Update volume paths if they contain the old instance name
        sed -i "s|Instance_${file_instance_name}/Saved|Instance_${instance_name}/Saved|g" "$docker_compose_file"
        sed -i "s|Instance_${file_instance_name}/API_Logs|Instance_${instance_name}/API_Logs|g" "$docker_compose_file"
        
        echo "Updated docker-compose file to match instance name: $instance_name"
      fi
    fi
  fi
  
  # Validate docker-compose file to ensure all instance names match
  echo "Validating docker-compose file for consistency..."
  local compose_file_name=$(basename "$docker_compose_file" | sed 's/docker-compose-//g' | sed 's/\.yaml//g')
  local container_name=$(grep -E "container_name:.*asa_" "$docker_compose_file" | sed -E 's/.*container_name:.*asa_([^"]*).*/\1/' | tr -d ' ')
  local env_instance_name=$(grep -E "INSTANCE_NAME=" "$docker_compose_file" | sed -E 's/.*INSTANCE_NAME=([^"]*).*/\1/' | tr -d ' ')
  
  if [[ "$compose_file_name" != "$instance_name" || "$container_name" != "$instance_name" || "$env_instance_name" != "$instance_name" ]]; then
    echo "⚠️ WARNING: Inconsistencies found in docker-compose file:"
    echo "  - Folder instance name: $instance_name"
    echo "  - Docker compose filename instance: $compose_file_name"
    echo "  - Container name instance: $container_name"
    echo "  - Environment INSTANCE_NAME: $env_instance_name"
    echo "These inconsistencies may cause issues with server operation."
    
    # Only prompt for fixing if running interactively
    if [ -t 0 ]; then
      echo "Would you like to fix these inconsistencies automatically? (y/N)"
      read -p "> " fix_inconsistencies
      
      if [[ "$fix_inconsistencies" =~ ^[Yy]$ ]]; then
        echo "Creating backup of current docker-compose file..."
        local backup_file="${docker_compose_file}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$docker_compose_file" "$backup_file"
        # Set the correct ownership for the backup file to match parent folder
        local parent_ownership=$(stat -c "%u:%g" "${instance_dir}")
        chown "$parent_ownership" "$backup_file"
        
        echo "Fixing inconsistencies to use instance name: $instance_name"
        # Update container name - handle both quoted and unquoted formats
        sed -i "s/container_name: \"asa_${container_name}\"/container_name: \"asa_${instance_name}\"/g" "$docker_compose_file"
        sed -i "s/container_name: asa_${container_name}/container_name: asa_${instance_name}/g" "$docker_compose_file"
        
        # Update environment variables - handle both formats with and without leading hyphen
        sed -i "s/INSTANCE_NAME=${env_instance_name}/INSTANCE_NAME=${instance_name}/g" "$docker_compose_file"
        sed -i "s/- INSTANCE_NAME=${env_instance_name}/- INSTANCE_NAME=${instance_name}/g" "$docker_compose_file"
        
        # Update volume paths
        sed -i "s|Instance_${container_name}/Saved|Instance_${instance_name}/Saved|g" "$docker_compose_file"
        sed -i "s|Instance_${container_name}/API_Logs|Instance_${instance_name}/API_Logs|g" "$docker_compose_file"
        
        # If the filename doesn't match, rename it
        if [[ "$compose_file_name" != "$instance_name" ]]; then
          local new_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
          mv "$docker_compose_file" "$new_compose_file"
          docker_compose_file="$new_compose_file"
          echo "Renamed docker-compose file to: $(basename "$docker_compose_file")"
        fi
        
        echo "✅ All inconsistencies fixed. Using instance name: $instance_name"
      else
        echo "Continuing with existing configuration. Some features may not work correctly."
      fi
    else
      # In non-interactive mode, automatically fix inconsistencies
      echo "Running in non-interactive mode. Automatically fixing inconsistencies..."
      local backup_file="${docker_compose_file}.backup_$(date +%Y%m%d_%H%M%S)"
      cp "$docker_compose_file" "$backup_file"
      local parent_ownership=$(stat -c "%u:%g" "${instance_dir}")
      chown "$parent_ownership" "$backup_file"
      
      # Fix inconsistencies
      sed -i "s/container_name: \"asa_${container_name}\"/container_name: \"asa_${instance_name}\"/g" "$docker_compose_file"
      sed -i "s/container_name: asa_${container_name}/container_name: asa_${instance_name}/g" "$docker_compose_file"
      sed -i "s/INSTANCE_NAME=${env_instance_name}/INSTANCE_NAME=${instance_name}/g" "$docker_compose_file"
      sed -i "s/- INSTANCE_NAME=${env_instance_name}/- INSTANCE_NAME=${instance_name}/g" "$docker_compose_file"
      sed -i "s|Instance_${container_name}/Saved|Instance_${instance_name}/Saved|g" "$docker_compose_file"
      sed -i "s|Instance_${container_name}/API_Logs|Instance_${instance_name}/API_Logs|g" "$docker_compose_file"
      
      if [[ "$compose_file_name" != "$instance_name" ]]; then
        local new_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
        mv "$docker_compose_file" "$new_compose_file"
        docker_compose_file="$new_compose_file"
        echo "Renamed docker-compose file to: $(basename "$docker_compose_file")"
      fi
      
      echo "✅ All inconsistencies fixed automatically. Using instance name: $instance_name"
    fi
  else
    echo "✅ Docker-compose file validation passed. All instance names match: $instance_name"
  fi

  # Check for root-owned files that might cause permission issues
  if detect_root_owned_files; then
    echo ""
    echo "⚠️ Found root-owned files that will cause permission issues with the container."
    
    # Check if we're already running with sudo
    if is_sudo; then
      echo "Since we're already running with sudo, we'll fix these permissions automatically."
      fix_root_owned_files
    else
      echo "Attempting to fix permission issues automatically using sudo..."
      echo "You may be prompted for your password."
      echo ""
      
      # Try to run the fix command with sudo
      if sudo "$0" -fix; then
        echo "✅ Permission issues fixed successfully."
      else
        echo "❌ Failed to automatically fix permissions."
        echo ""
        echo "This is likely because sudo requires a password, or you're not authorized to use sudo."
        echo "Please run the fix command manually: sudo ./POK-manager.sh -fix"
        echo ""
        # In non-interactive mode or for restart operations, continue without prompting
        if [ ! -t 0 ] || [[ "$RESTART_IN_PROGRESS" == "true" ]]; then
          echo "Continuing with server start despite permission issues (non-interactive mode or restart in progress)..."
        else
          echo "Would you like to continue starting the server anyway? (This might cause container errors)"
          read -p "Continue despite permission issues? (y/N): " continue_start
          if [[ ! "$continue_start" =~ ^[Yy]$ ]]; then
            echo "Server start cancelled. Please run 'sudo ./POK-manager.sh -fix' to fix permissions."
            exit 1
          fi
          echo "Continuing with server start despite permission issues..."
        fi
      fi
    fi
  fi
  
  # Ensure the API_Logs directory exists for this instance
  local base_dir="${BASE_DIR}"
  local instance_dir="${base_dir}/Instance_${instance_name}"
  local api_logs_dir="${instance_dir}/API_Logs"
  local api_logs_created=false
  
  # Create API_Logs directory if it doesn't exist
  if [ ! -d "$api_logs_dir" ]; then
    echo "Creating API_Logs directory for instance: $instance_name"
    mkdir -p "$api_logs_dir"
    api_logs_created=true
  else
    # Check if permissions need to be updated on existing directory
    local current_owner=$(stat -c "%u:%g" "$api_logs_dir")
    local target_owner=""
    
    if [[ "$image_tag" == 2_0* ]]; then
      target_owner="1000:1000"
    else
      target_owner="7777:7777"
    fi
    
    if [ "$current_owner" != "$target_owner" ]; then
      echo "Updating API_Logs directory ownership to match container ($target_owner)"
      api_logs_created=true
    fi
  fi
  
  # Set proper permissions on the directory based on image tag
  if [ "$api_logs_created" = true ]; then
    if [[ "$image_tag" == 2_0* ]]; then
      echo "Setting 1000:1000 ownership on API_Logs directory for 2_0_latest image compatibility"
      if is_sudo; then
        chown 1000:1000 "$api_logs_dir"
      else
        sudo chown 1000:1000 "$api_logs_dir"
      fi
    else
      echo "Setting 7777:7777 ownership on API_Logs directory for 2_1_latest image compatibility"
      if is_sudo; then
        chown 7777:7777 "$api_logs_dir"
      else
        sudo chown 7777:7777 "$api_logs_dir"
      fi
    fi
    chmod 755 "$api_logs_dir"
  fi
  
  # Check if the docker-compose file needs to be updated to include the API_Logs volume
  if ! grep -q "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file"; then
    # Only add API_Logs volume if API=TRUE
    if grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"; then
      echo "Adding API_Logs volume mapping to docker-compose file"
      
      # Create a temporary file
      local tmp_file="${docker_compose_file}.tmp"
      
      # Get absolute path for consistency with other volume paths
      local abs_instance_dir=$(realpath "$instance_dir")
      
      # Use sed to add the API_Logs volume after the Saved volume with absolute path
      sed -e "/Saved:.*ShooterGame\/Saved/ a\\      - \"$abs_instance_dir/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs\"" "$docker_compose_file" > "$tmp_file"
      
      # Replace the original file with the updated one
      mv -f "$tmp_file" "$docker_compose_file"
      
      # Set proper permissions on the file
      if is_sudo; then
        # Match file ownership with the API_Logs directory
        if [[ "$image_tag" == 2_0* ]]; then
          chown 1000:1000 "$docker_compose_file"
        else
          chown 7777:7777 "$docker_compose_file"
        fi
      else
        # Use sudo as needed
        if [[ "$image_tag" == 2_0* ]]; then
          sudo chown 1000:1000 "$docker_compose_file"
        else
          sudo chown 7777:7777 "$docker_compose_file"
        fi
      fi
    fi
  elif ! (grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file") && grep -q "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file"; then
    # If API=FALSE, blank, or not present but API_Logs volume exists, remove it
    echo "Removing API_Logs volume mapping from docker-compose file since API is disabled or not set"
    
    # Create a temporary file
    local tmp_file="${docker_compose_file}.tmp"
    
    # Remove the API_Logs line
    grep -v "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file" > "$tmp_file"
    
    # Replace the original file with the updated one
    mv -f "$tmp_file" "$docker_compose_file"
    
    # Set proper permissions on the file
    if is_sudo; then
      # Match file ownership with the instance directory
      if [[ "$image_tag" == 2_0* ]]; then
        chown 1000:1000 "$docker_compose_file"
      else
        chown 7777:7777 "$docker_compose_file"
      fi
    else
      # Use sudo as needed
      if [[ "$image_tag" == 2_0* ]]; then
        sudo chown 1000:1000 "$docker_compose_file"
      else
        sudo chown 7777:7777 "$docker_compose_file"
      fi
    fi
  fi
  
  # Fix any relative paths in the API_Logs volume mapping
  if grep -q "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file"; then
    # Check if the path is relative (starts with ./)
    if grep -q "^ *- \"\./Instance_" "$docker_compose_file"; then
      echo "Converting relative API_Logs path to absolute path"
      
      # Create a temporary file
      local tmp_file="${docker_compose_file}.tmp"
      
      # Get absolute path for consistency with other volume paths
      local abs_instance_dir=$(realpath "$instance_dir")
      
      # Use sed to replace the relative path with absolute path
      sed -e "s|^ *- \"\./Instance_${instance_name}/API_Logs|      - \"$abs_instance_dir/API_Logs|g" "$docker_compose_file" > "$tmp_file"
      
      # Replace the original file with the updated one
      mv -f "$tmp_file" "$docker_compose_file"
      
      # Set proper permissions on the file
      if is_sudo; then
        # Match file ownership with the API_Logs directory
        if [[ "$image_tag" == 2_0* ]]; then
          chown 1000:1000 "$docker_compose_file"
        else
          chown 7777:7777 "$docker_compose_file"
        fi
      else
        # Use sudo as needed
        if [[ "$image_tag" == 2_0* ]]; then
          sudo chown 1000:1000 "$docker_compose_file"
        else
          sudo chown 7777:7777 "$docker_compose_file"
        fi
      fi
    fi
  fi
  
  # Check if API is enabled but file ownership is 1000:1000
  local api_enabled=false
  local file_ownership_legacy=false
  
  # Check if API is enabled in the docker-compose file
  if grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"; then
    api_enabled=true
  else
    # API is either FALSE, blank, or not present - treat as disabled
    api_enabled=false
    
    # If API is not explicitly defined, add it as FALSE for clarity
    if ! grep -q "^ *- API=" "$docker_compose_file" && ! grep -q "^ *- API:" "$docker_compose_file"; then
      echo "API setting not found, adding API=FALSE to docker-compose file for clarity"
      sed -i "/- INSTANCE_NAME/a \ \ \ \ \ \ - API=FALSE" "$docker_compose_file"
    # Check for blank API setting (e.g., "- API=" or "- API:")
    elif grep -q "^ *- API=$" "$docker_compose_file" || grep -q "^ *- API:$" "$docker_compose_file"; then
      echo "Blank API setting found, setting to FALSE for clarity"
      local tmp_file="${docker_compose_file}.tmp"
      grep -v "^ *- API=$\|^ *- API:$" "$docker_compose_file" > "$tmp_file"
      mv "$tmp_file" "$docker_compose_file"
      sed -i "/- INSTANCE_NAME/a \ \ \ \ \ \ - API=FALSE" "$docker_compose_file"
    fi
  fi
  
  # Check server files ownership
  local server_files_dir="${BASE_DIR}/ServerFiles/arkserver"
  if [ -d "$server_files_dir" ]; then
    local file_ownership=$(stat -c '%u:%g' "$server_files_dir")
    if [ "$file_ownership" = "1000:1000" ]; then
      file_ownership_legacy=true
    fi
  fi
  
  # If API is enabled but using legacy ownership, recommend migration
  if [ "$api_enabled" = "true" ] && [ "$file_ownership_legacy" = "true" ]; then
    echo ""
    echo "⚠️ IMPORTANT API COMPATIBILITY WARNING ⚠️"
    echo "You're trying to start instance '$instance_name' with AsaApi enabled, but using legacy"
    echo "1000:1000 file ownership (image tag: $image_tag)."
    echo ""
    echo "For optimal API compatibility, it's strongly recommended to migrate to the newer"
    echo "7777:7777 ownership structure which works better with AsaApi."
    echo ""
    
    # Only prompt for migration if running interactively and not during a restart
    if [ -t 0 ] && [[ "$RESTART_IN_PROGRESS" != "true" ]]; then
      echo "Would you like to migrate to the recommended 7777:7777 ownership now?"
      echo "This process will:"
      echo "  1. Stop all running server instances"
      echo "  2. Change file ownership from 1000:1000 to 7777:7777"
      echo "  3. Update to use the 2_1_latest image which is optimized for AsaApi"
      echo "  4. Restart your servers with API enabled"
      echo ""
      read -p "Perform migration now? (Strongly Recommended) [Y/n]: " perform_migration
      
      # Default to yes if nothing entered
      if [[ -z "$perform_migration" || "$perform_migration" =~ ^[Yy]$ ]]; then
        echo ""
        echo "🔄 Starting migration to 7777:7777 ownership..."
        
        # We need to run migration with sudo
        if ! is_sudo; then
          echo "Migration requires sudo privileges. Please enter your password when prompted."
          
          # Store all arguments to pass to sudo
          local all_args="-migrate"
          
          # Execute the same script with sudo and the migrate option
          if sudo "$0" $all_args; then
            echo "✅ Migration completed successfully."
            
            # After migration completed, start the server fresh
            echo ""
            echo "Starting server with new 7777:7777 ownership..."
            sudo "$0" -start "$instance_name"
            
            # Exit because the above command will handle the start
            exit 0
          else
            echo "❌ Migration failed. The server will still be started but AsaApi may not work correctly."
          fi
        else
          # Already running with sudo, so directly call migrate_file_ownership
          if migrate_file_ownership; then
            echo "✅ Migration completed successfully."
            echo ""
            echo "Continuing with server start using new ownership..."
            
            # Server will be started below with the normal flow
            # The image tag should automatically update to 2_1_latest
            image_tag="2_1_latest"
          else
            echo "❌ Migration failed. The server will still be started but AsaApi may not work correctly."
          fi
        fi
      else
        echo ""
        echo "⚠️ Migration skipped. The server will be started but AsaApi may not work correctly."
        echo "Consider running the migration later with sudo ./POK-manager.sh -migrate"
        echo ""
      fi
    else
      # Non-interactive mode or restart in progress, just warn and continue
      echo "When running in non-interactive mode or during restart, migration is not performed automatically."
      echo "Consider running './POK-manager.sh -migrate' manually for proper API compatibility."
      echo "Proceeding with server start as requested..."
      echo ""
    fi
  fi
  
  # Check for permission mismatches between files and container before starting
  local server_files_dir="${BASE_DIR}/ServerFiles/arkserver"
  if [ -d "$server_files_dir" ]; then
    local file_ownership=$(stat -c '%u:%g' "$server_files_dir")
    local file_uid=$(echo "$file_ownership" | cut -d: -f1)
    local file_gid=$(echo "$file_ownership" | cut -d: -f2)
    
    # Check if image_tag is for beta (which uses 7777:7777)
    if [[ "$image_tag" == *"_beta" || "$image_tag" == "2_1_latest" ]]; then
      local container_uid=7777
      local container_gid=7777
      
      # If files are owned by 1000:1000 but container uses 7777:7777
      if [ "$file_uid" = "1000" ] && [ "$file_gid" = "1000" ]; then
        echo "❌ ERROR: PERMISSION MISMATCH DETECTED!"
        echo "Your server files are owned by UID:GID ${file_uid}:${file_gid} (1000:1000)"
        echo "But your container image '$image_tag' expects UID:GID ${container_uid}:${container_gid} (7777:7777)"
        echo ""
        echo "This will cause permission issues between the host and container."
        
        # For restart operations, continue with a warning instead of exiting
        if [[ "$RESTART_IN_PROGRESS" == "true" ]]; then
          echo "⚠️ WARNING: Continuing despite permission mismatch because this is part of a restart operation."
          echo "Some features may not work correctly until permissions are fixed."
          echo ""
        else
          echo "The server will NOT be started to prevent potential data corruption or access problems."
          echo ""
          echo "To fix this, you have two options:"
          echo "1. Change file ownership to match the container:"
          echo "   sudo chown -R 7777:7777 ${BASE_DIR}"
          echo "   (Recommended for beta branch and 2_1_latest images)"
          echo ""
          echo "2. Change to the stable branch with 1000:1000 permissions:"
          echo "   ./POK-manager.sh -stable"
          echo "   (This will revert to using the 2_0_latest image that matches your current file ownership)"
          echo ""
          echo "You can also run: ./POK-manager.sh -migrate"
          echo "This will help you migrate your server files to the new 7777:7777 ownership structure."
          exit 1
        fi
      fi
    # Check if image_tag is for stable 2_0 (which uses 1000:1000)
    elif [[ "$image_tag" == "2_0_latest" ]]; then
      local container_uid=1000
      local container_gid=1000
      
      # If files are owned by 7777:7777 but container uses 1000:1000
      if [ "$file_uid" = "7777" ] && [ "$file_gid" = "7777" ]; then
        echo "❌ ERROR: PERMISSION MISMATCH DETECTED!"
        echo "Your server files are owned by UID:GID ${file_uid}:${file_gid} (7777:7777)"
        echo "But your container image '$image_tag' expects UID:GID ${container_uid}:${container_gid} (1000:1000)"
        echo ""
        echo "This will cause permission issues between the host and container."
        echo "The server will NOT be started to prevent potential data corruption or access problems."
        echo ""
        echo "To fix this, you have two options:"
        echo "1. Change file ownership to match the container:"
        echo "   sudo chown -R 1000:1000 ${BASE_DIR}"
        echo "   (Only use this if you specifically need the 2_0_latest image with 1000:1000 permissions)"
        echo ""
        echo "2. Change to the beta branch or use 2_1_latest to match your file ownership:"
        echo "   ./POK-manager.sh -beta"
        echo "   (This will use the newer image that matches your current file ownership)"
        exit 1
      fi
    fi
  fi
  
  # Update the docker-compose.yaml file to use the correct image tag
  update_docker_compose_image_tag "$docker_compose_file" "$image_tag"
  
  # Check permission issues with the compose file
  if [ ! -r "$docker_compose_file" ]; then
    echo "❌ ERROR: Cannot read the Docker Compose file due to permission issues."
    echo "Current user: $(id -un) (UID:$(id -u), GID:$(id -g))"
    echo "File owner: $(stat -c '%U:%G' "$docker_compose_file")"
    echo ""
    echo "You can fix this by:"
    echo "1. Running with the correct user who owns the files:"
    local file_owner=$(stat -c '%u' "$docker_compose_file")
    local possible_users=$(getent passwd "$file_owner" | cut -d: -f1)
    if [ -n "$possible_users" ]; then
      echo "   - Switch to user '$possible_users' with: su - $possible_users"
      echo "   - Then run: ./POK-manager.sh -start $instance_name"
    fi
    echo ""
    echo "2. Running with sudo:"
    echo "   sudo ./POK-manager.sh -start $instance_name"
    echo ""
    echo "3. Changing file ownership to match your current user:"
    echo "   sudo chown -R $(id -u):$(id -g) ./Instance_${instance_name}"
    exit 1
  fi
  
  # Check for PUID/PGID settings in the compose file
  local compose_puid=$(grep -o "PUID=[0-9]*" "$docker_compose_file" | head -1 | awk -F= '{print $2}')
  local compose_pgid=$(grep -o "PGID=[0-9]*" "$docker_compose_file" | head -1 | awk -F= '{print $2}')
  
  # Check if the PUID/PGID in the compose file are commented out
  if grep -q "^[[:space:]]*#[[:space:]]*-[[:space:]]*PUID=" "$docker_compose_file" || grep -q "^[[:space:]]*#[[:space:]]*-[[:space:]]*PGID=" "$docker_compose_file"; then
    echo "⚠️ WARNING: PUID/PGID settings are commented out in your Docker Compose file."
    echo "This may cause permission issues. Consider uncommenting them."
    echo ""
  fi
  
  # If not running as sudo, check for permission mismatches
  if ! is_sudo; then
    # Get the server files directory for this instance
    local instance_dir="${BASE_DIR}/Instance_${instance_name}"
    
    if [ -d "$instance_dir" ]; then
      local dir_ownership="$(stat -c '%u:%g' "$instance_dir")"
      local dir_uid=$(echo "$dir_ownership" | cut -d: -f1)
      local dir_gid=$(echo "$dir_ownership" | cut -d: -f2)
      local current_uid=$(id -u)
      local current_gid=$(id -g)
      
      # Check if the current user's UID/GID don't match the directory ownership
      if [ "$current_uid" -ne "$dir_uid" ] || [ "$current_gid" -ne "$dir_gid" ]; then
        echo "⚠️ WARNING: Your current user (UID:$current_uid, GID:$current_gid) doesn't match the instance directory ownership (UID:$dir_uid, GID:$dir_gid)."
        echo "This may cause permission issues when starting or accessing the server."
        echo ""
      fi
      
      # Check if compose PUID/PGID don't match the directory ownership
      if [ -n "$compose_puid" ] && [ -n "$compose_pgid" ] && ([ "$compose_puid" -ne "$dir_uid" ] || [ "$compose_pgid" -ne "$dir_gid" ]); then
        echo "⚠️ WARNING: The PUID/PGID in your Docker Compose file ($compose_puid:$compose_pgid) don't match the instance directory ownership ($dir_uid:$dir_gid)."
        echo "This may cause permission issues with server files."
        echo ""
      fi
    fi
  fi
  
  get_docker_compose_cmd
  echo "Using $DOCKER_COMPOSE_CMD for ${instance_name}..."
  
  # Rest of the existing function
  if [ -f "$docker_compose_file" ]; then
    local use_sudo
    local config_file=$(get_config_file_path)
    if [ -f "$config_file" ]; then
      use_sudo=$(cat "$config_file")
    else
      use_sudo="true"
    fi
    
    if [ "$use_sudo" = "true" ]; then
      echo "Using 'sudo' for Docker commands..."
      sudo docker pull acekorneya/asa_server:${image_tag} || {
        echo "❌ ERROR: Failed to pull the Docker image. Check your internet connection and Docker configuration."
        exit 1
      }
      check_vm_max_map_count
      sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" up -d || {
        echo "❌ ERROR: Failed to start the server container."
        echo "Check the Docker Compose file and ensure Docker is correctly configured."
        echo "You can view more detailed logs with: sudo $DOCKER_COMPOSE_CMD -f \"$docker_compose_file\" logs"
        exit 1
      }
    else
      docker pull acekorneya/asa_server:${image_tag} || {
        local pull_exit_code=$?
        if [ $pull_exit_code -eq 1 ] && [[ $(docker pull acekorneya/asa_server:${image_tag} 2>&1) =~ "permission denied" ]]; then
          echo "Permission denied error occurred while pulling the Docker image."
          echo "It seems the user is not set up correctly to run Docker commands without 'sudo'."
          echo "Falling back to using 'sudo' for Docker commands."
          echo "To grant your user permission to run Docker commands, run:"
          echo "   sudo usermod -aG docker $(id -un)"
          echo "Then log out and back in for changes to take effect."
          sudo docker pull acekorneya/asa_server:${image_tag} || {
            echo "❌ ERROR: Failed to pull the Docker image even with sudo. Check your internet connection and Docker configuration."
            exit 1
          }
          check_vm_max_map_count
          sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" up -d || {
            echo "❌ ERROR: Failed to start the server container even with sudo."
            exit 1
          }
        else
          echo "Failed to pull the Docker image. Please check your Docker configuration."
          exit 1
        fi
      }
      
      check_vm_max_map_count
      $DOCKER_COMPOSE_CMD -f "$docker_compose_file" up -d || {
        local compose_exit_code=$?
        if [ $compose_exit_code -eq 1 ] && [[ $($DOCKER_COMPOSE_CMD -f "$docker_compose_file" up -d 2>&1) =~ "permission denied" ]]; then
          echo "Permission denied error occurred while starting the container."
          echo "Falling back to using 'sudo'."
          sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" up -d || {
            echo "❌ ERROR: Failed to start the server container even with sudo."
            exit 1
          }
        else
          echo "❌ ERROR: Failed to start the server container."
          echo "Check the Docker Compose file and ensure Docker is correctly configured."
          exit 1
        fi
      }
    fi
    
    echo "✅ Server ${instance_name} started successfully with image tag ${image_tag}."
    echo "You can view logs while container is running with: ./POK-manager.sh -logs -live ${instance_name}"
  else
    echo "❌ ERROR: Docker Compose file not found for instance ${instance_name}."
    exit 1
  fi
}

# Function to stop an instance
stop_instance() {
  local instance_name="$1"
  local base_dir="${BASE_DIR}"
  local instance_dir="${base_dir}/Instance_${instance_name}"
  local docker_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
  local container_name="asa_${instance_name}"
  
  # Check if the docker-compose file exists
  if [ ! -f "$docker_compose_file" ]; then
    # Try to find any docker-compose file in the instance directory
    local found_compose_files=($(find "${instance_dir}" -maxdepth 1 -name 'docker-compose-*.yaml' 2>/dev/null || true))
    
    if [ ${#found_compose_files[@]} -gt 0 ]; then
      # Take the first one found
      local found_compose_file="${found_compose_files[0]}"
      local found_instance_name=$(basename "$found_compose_file" | sed 's/docker-compose-//g' | sed 's/\.yaml//g')
      
      echo "⚠️ Found a docker-compose file for instance '$found_instance_name' in folder for '$instance_name'"
      echo "This may happen if you renamed the folder manually instead of using the script's rename feature."
      echo "Using the found docker-compose file: $found_compose_file"
      
      # Get the container name from the found docker-compose file
      if grep -q "container_name:" "$found_compose_file"; then
        # Extract container name handling both quoted and unquoted formats
        local found_container=""
        if grep -q "container_name: \"" "$found_compose_file"; then
          # Extract quoted container name
          found_container=$(grep "container_name:" "$found_compose_file" | sed 's/.*container_name: "\(.*\)".*/\1/')
        else
          # Extract unquoted container name
          found_container=$(grep "container_name:" "$found_compose_file" | sed 's/.*container_name: \(.*\)/\1/')
        fi
        
        if [ -n "$found_container" ]; then
          container_name="$found_container"
          echo "Using container name from docker-compose file: $container_name"
        fi
      fi
      
      docker_compose_file="$found_compose_file"
    fi
  fi
  
  # Get container ID using our more robust method
  local container_id=$(get_instance_container_id "$instance_name")

  # If we couldn't find a container for the instance_name, try with the found_instance_name if available
  if [ -z "$container_id" ] && [ -n "$found_instance_name" ]; then
    container_id=$(get_instance_container_id "$found_instance_name")
    if [ -n "$container_id" ]; then
      echo "Found running container for '$found_instance_name' instead of '$instance_name'"
    fi
  fi

  echo "-----Stopping ${instance_name} Server-----"
  
  # Check if the container is running
  if [ -n "$container_id" ]; then
    echo "Server is running. Attempting quick save before stopping..."
    
    # Attempt a quick saveworld with timeout - run in background and kill if it takes too long
    (
      # Use timeout to limit how long the RCON command can run
      timeout 3s docker exec "$container_name" /bin/bash -c "/home/pok/scripts/rcon_interface.sh -saveworld" >/dev/null 2>&1
      save_exit_code=$?
      if [ $save_exit_code -eq 124 ]; then
        echo "Save command timed out, continuing with container stop"
      elif [ $save_exit_code -ne 0 ]; then
        echo "Save command failed or not available, continuing with container stop"
      else
        echo "Save command sent successfully"
      fi
    ) &
    
    # Wait briefly for save to complete (maximum 5 seconds)
    echo "Waiting up to 5 seconds for save to complete..."
    sleep 5
  else
    echo "Container is not running, proceeding with stop."
  fi

  # Get sudo preference
  local use_sudo
  local config_file=$(get_config_file_path)
  if [ -f "$config_file" ]; then
    use_sudo=$(cat "$config_file")
  else
    use_sudo="true"
  fi

  # Stop the container with default timeout
  echo "Stopping container..."
  if [ "$use_sudo" = "true" ]; then
    if [ -f "$docker_compose_file" ]; then
      sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down || {
        echo "Warning: Error occurred while stopping the container using docker-compose down"
        # Fallback to docker stop if docker-compose fails
        sudo docker stop "$container_name" || {
          echo "Error: Failed to stop container using fallback method"
          return 1
        }
      }
    else
      sudo docker stop "$container_name" || {
        echo "Error: Failed to stop container"
        return 1
      }
    fi
  else
    if [ -f "$docker_compose_file" ]; then
      $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down || {
        local exit_code=$?
        if [ $exit_code -eq 1 ] && [[ $($DOCKER_COMPOSE_CMD -f "$docker_compose_file" down 2>&1) =~ "permission denied" ]]; then
          echo "Permission denied error occurred. Falling back to sudo..."
          sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down || {
            echo "Error: Failed to stop container even with sudo"
            return 1
          }
        else
          echo "Error: Failed to stop container with docker-compose"
          echo "Attempting fallback to docker stop..."
          docker stop "$container_name" || sudo docker stop "$container_name" || {
            echo "Error: All stop attempts failed"
            return 1
          }
        fi
      }
    else
      docker stop "$container_name" || {
        local exit_code=$?
        if [ $exit_code -eq 1 ] && [[ $(docker stop "$container_name" 2>&1) =~ "permission denied" ]]; then
          echo "Permission denied error occurred. Falling back to sudo..."
          sudo docker stop "$container_name" || {
            echo "Error: Failed to stop container even with sudo"
            return 1
          }
        else
          echo "Error: Failed to stop container"
          return 1
        fi
      }
    fi
  fi

  echo "Instance ${instance_name} stopped successfully."
  return 0
}

list_running_instances() {
  local instances=($(list_instances))
  local running_instances=()

  for instance in "${instances[@]}"; do
    local container_name="asa_${instance}"
    if docker inspect --format '{{.State.Status}}' "${container_name}" 2>/dev/null | grep -q 'running'; then
      running_instances+=("$instance")
    fi
  done

  echo "${running_instances[@]}"
}
execute_rcon_command() {
  local action="$1"
  local wait_time="${3:-1}" # Default wait time set to 1 if not specified
  shift # Remove the action from the argument list.

  # Check for common typos of -all like -al, -a, -aall, etc.
  if [[ "$1" =~ ^-a+l*$ ]]; then
    echo "Note: Interpreted '$1' as '-all'"
    shift
    local message="$*" # Remaining arguments form the message/command
    local target_all=true
  elif [[ "$1" == "-all" ]]; then
    shift
    local message="$*" # Remaining arguments form the message/command
    local target_all=true
  else
    local instance_name="$1"
    shift
    local message="$*" # Remaining arguments form the message/command
    local target_all=false
  fi

  # New validation to check for extra dash in RCON command
  if [[ "$message" =~ ^- ]]; then
    echo "Error: RCON command should not start with a dash. Please use '-custom <RCON command>' instead."
    echo "Usage: ./POK-manager.sh -custom <RCON command> <instance_name|-all>"
    return 1
  fi

  if [[ "$target_all" == "true" ]]; then
    # Get list of running instances
    local running_instances=($(list_running_instances))
    
    # Check if there are any running instances before processing the command
    if [ -n "$running_instances" ]; then
      if [[ "$action" == "-shutdown" ]]; then
        # Validate wait_time or set default
        if [ -z "$wait_time" ]; then
          echo "No shutdown time specified. Using default of 1 minute."
          wait_time=1
        fi
        
        # Validate that wait_time is a number
        if ! [[ "$wait_time" =~ ^[0-9]+$ ]]; then
          echo "Error: Invalid shutdown time '$wait_time'. Must be a positive number."
          echo "Using default of 1 minute instead."
          wait_time=1
        fi
        
        # Use the enhanced shutdown command for better visuals and consistent experience
        echo "Using enhanced shutdown functionality for all instances..."
        enhanced_shutdown_command "$wait_time" "-all"
        
        # enhanced_shutdown_command exits the script when done, so no additional code is needed here
        return
      elif [[ "$action" == "-restart" ]]; then
        # Check if there are any running instances before processing the command
        if [ -n "$(list_running_instances)" ]; then
          # First, check if there's a mix of API and non-API instances
          local api_instances=()
          local non_api_instances=()
          
          for instance in $(list_running_instances); do
            local docker_compose_file="${BASE_DIR}/Instance_${instance}/docker-compose-${instance}.yaml"
            
            # Check if API=TRUE in the docker-compose file
            if [ -f "$docker_compose_file" ] && (grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"); then
              api_instances+=("$instance")
            else
              non_api_instances+=("$instance")
            fi
          done
          
          # If mixed API modes, show warning
          if [ ${#api_instances[@]} -gt 0 ] && [ ${#non_api_instances[@]} -gt 0 ]; then
            echo "⚠️ WARNING: Mixed API modes detected (both TRUE and FALSE). ⚠️"
            echo "When restarting with mixed API modes, the running containers will be stopped,"
            echo "server files WILL be updated, and containers will be brought back up."
            echo "If a game update is available, it WILL be applied during this process."
            echo ""
            echo "This process follows these steps automatically:"
            echo "1. Stop all containers"
            echo "2. Update server files"
            echo "3. Start all containers"
            echo ""
            echo "This ensures all server files are updated correctly while minimizing downtime."
            sleep 3
          fi
          
          # Use the enhanced restart command for all instances
          echo "Using enhanced restart functionality for all instances..."
          enhanced_restart_command "$message" "-all"
        else
          echo "---- No Running Instances Found for command: $action -----"
          echo " To start an instance, use the -start -all or -start <instance_name> command."
        fi
        # Don't exit immediately - the enhanced restart function will handle everything
      else
        # For other commands (-status, -saveworld, etc.)
        # Create an associative array to store the output for each instance
        declare -A instance_outputs
        echo "----- Processing $action command for all running instances. Please wait... -----"
        for instance in $(list_running_instances); do
          if ! validate_instance "$instance"; then
            echo "Instance $instance is not running or does not exist. Skipping..."
            continue
          fi

          if [[ "$action" == "-status" ]]; then
            local container_name="asa_${instance}"
            local pdb_file="/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
            local update_flag="/home/pok/update.flag"

            if ! docker exec "$container_name" test -f "$pdb_file"; then
              if docker exec "$container_name" test -f "$update_flag"; then
                echo "Instance $instance is still updating/installing. Please wait until the update is complete before checking the status."
                continue
              else
                echo "Instance $instance has not fully started yet. Please wait a few minutes before checking the status."
                echo "If the instance is still not running, please check the logs for more information."
                echo "you can use the -logs -live $instance command to follow the logs."
                continue
              fi
            fi
          fi

          # Capture the command output in a variable
          instance_outputs["$instance"]=$(run_in_container "$instance" "$action" "$message")
        done

        # Print the outputs in the desired format
        for instance in "${!instance_outputs[@]}"; do
          echo "----- Server $instance: Command: ${action#-}${message:+ $message} -----"
          echo "${instance_outputs[$instance]}"
        done

        echo "----- All running instances processed with $action command. -----"
      fi
    else
      echo "---- No Running Instances Found for command: $action -----"
      echo " To start an instance, use the -start -all or -start <instance_name> command."
    fi
  else
    # Handle single instance
    # Check if the instance name starts with a dash but isn't a valid command flag
    if [[ "$instance_name" == -* ]] && ! [[ "${instance_name,,}" == "-all" ]]; then
      echo "Warning: '$instance_name' appears to be an invalid flag or typo."
      echo "If you meant to target all instances, use '-all' instead."
      echo "Otherwise, instance names shouldn't start with a dash (-)"
      echo ""
      read -p "Would you like to process all running instances instead? (y/N): " process_all
      if [[ "$process_all" =~ ^[Yy]$ ]]; then
        # Recursively call this function with -all
        execute_rcon_command "$action" "-all" "$wait_time" "$message"
        return
      else
        echo "Command canceled. Please try again with a valid instance name."
        return 1
      fi
    fi

    # Validate the instance for a single-instance command
    if validate_instance "$instance_name"; then
      echo "Processing $action command on $instance_name..."

      if [[ "$action" == "-status" ]]; then
        local container_name="asa_${instance_name}"
        local pdb_file="/home/pok/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
        local update_flag="/home/pok/update.flag"

        if ! docker exec "$container_name" test -f "$pdb_file"; then
          if docker exec "$container_name" test -f "$update_flag"; then
            echo "Instance $instance_name is still updating/installing. Please wait until the update is complete before checking the status."
            return
          else
            echo "Instance $instance_name has not fully started yet. Please wait a few minutes before checking the status."
            return
          fi
        fi
      fi

      if [[ "$action" == "-shutdown" ]]; then
        # Validate wait_time or set default
        if [ -z "$wait_time" ]; then
          echo "No shutdown time specified. Using default of 1 minute."
          wait_time=1
        fi
        
        # Validate that wait_time is a number
        if ! [[ "$wait_time" =~ ^[0-9]+$ ]]; then
          echo "Error: Invalid shutdown time '$wait_time'. Must be a positive number."
          echo "Using default of 1 minute instead."
          wait_time=1
        fi
        
        # Use the enhanced shutdown command for better visuals and consistent experience
        echo "Using enhanced shutdown functionality for instance: $instance_name"
        enhanced_shutdown_command "$wait_time" "$instance_name"
        
        # enhanced_shutdown_command exits the script when done
        return
      elif [[ "$action" == "-restart" ]]; then
        # Use the enhanced restart command for a single instance
        echo "Using enhanced restart functionality for instance: $instance_name"
        
        # First check if there's a mix of API and non-API instances
        local all_api=true
        local all_non_api=true
        
        # Check if the current instance is API=TRUE
        local this_instance_api=false
        local docker_compose_file="${BASE_DIR}/Instance_${instance_name}/docker-compose-${instance_name}.yaml"
        if [ -f "$docker_compose_file" ] && (grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"); then
          this_instance_api=true
        fi
        
        # Check other running instances
        for instance in $(list_running_instances | grep -v "^$instance_name$"); do
          local other_docker_compose_file="${BASE_DIR}/Instance_${instance}/docker-compose-${instance}.yaml"
          
          if [ -f "$other_docker_compose_file" ] && (grep -q "^ *- API=TRUE" "$other_docker_compose_file" || grep -q "^ *- API:TRUE" "$other_docker_compose_file"); then
            # This instance is API=TRUE
            if [ "$this_instance_api" = "false" ]; then
              all_api=false  # Mixed mode detected
            fi
          else
            # This instance is API=FALSE
            if [ "$this_instance_api" = "true" ]; then
              all_non_api=false  # Mixed mode detected
            fi
          fi
        done
        
        # If mixed modes detected, show warning
        if [ "$all_api" = "false" ] && [ "$all_non_api" = "false" ]; then
          echo "⚠️ WARNING: Mixed API modes detected across running instances. ⚠️"
          echo "When restarting with mixed API modes, the running containers will be stopped,"
          echo "server files WILL be updated, and containers will be brought back up."
          echo "If a game update is available, it WILL be applied during this process."
          echo ""
          echo "This process follows these steps automatically:"
          echo "1. Stop all containers"
          echo "2. Update server files"
          echo "3. Start all containers"
          echo ""
          echo "This ensures all server files are updated correctly while minimizing downtime."
          sleep 3
        fi
        
        enhanced_restart_command "$message" "$instance_name"
        # Don't exit immediately - the enhanced restart function will handle everything
      elif [[ "$run_in_background" == "true" ]]; then
        run_in_container_background "$instance_name" "$action" "$message"
        exit 0 # Exit script after background job is complete
      else
        run_in_container "$instance_name" "$action" "$message"
      fi
    else
      echo "---- Instance $instance_name is not running or does not exist. -----"
      echo " To start an instance, use the -start -all or -start <instance_name> command."
    fi
  fi
}

# Updated function to wait for shutdown completion
wait_for_shutdown() {
  local instance="$1"
  local wait_time="${2:-1}"
  local container_name="asa_${instance}" # Assuming container naming convention
  local max_wait_seconds=180  # Maximum time to wait (3 minutes) regardless of wait_time
  local check_interval=5      # Check every 5 seconds
  local elapsed=0
  local pid_file_exists=true
  local complete_flag_exists=false
  local process_running=true

  # Start with a small delay to give time for any pending operations
  sleep 3

  echo "Monitoring shutdown progress for $instance..."
  
  # Loop until either:
  # 1. Both PID file is gone AND shutdown_complete.flag exists
  # 2. OR the maximum wait time is exceeded
  # 3. OR the container has already stopped
  while [ $elapsed -lt $max_wait_seconds ]; do
    # Check if container is still running
    if ! docker ps -q -f name=^/${container_name}$ > /dev/null; then
      echo "Container has already stopped."
      return 0
    fi
    
    # Check for the PID file
    if docker exec "$container_name" test -f /home/pok/${instance}_ark_server.pid 2>/dev/null; then
      pid_file_exists=true
    else
      pid_file_exists=false
    fi
    
    # Check for the shutdown complete flag
    if docker exec "$container_name" test -f /home/pok/shutdown_complete.flag 2>/dev/null; then
      complete_flag_exists=true
    else
      complete_flag_exists=false
    fi
    
    # Check if the game process is still running
    if ! docker exec "$container_name" pgrep -f "ArkAscendedServer.exe" > /dev/null 2>&1; then
      process_running=false
    else
      process_running=true
    fi
    
    # If the game process is not running AND either the PID file is gone OR the complete flag exists
    if [ "$process_running" = "false" ] && ([ "$pid_file_exists" = "false" ] || [ "$complete_flag_exists" = "true" ]); then
      echo "Server $instance has safely shut down. (Process stopped, PID: $pid_file_exists, Complete flag: $complete_flag_exists)"
      return 0
    fi
    
    # If we've waited more than 60 seconds and the game is still running but 
    # the shutdown was signaled, we might need to force it
    if [ $elapsed -gt 60 ] && [ "$process_running" = "true" ] && [ "$complete_flag_exists" = "true" ]; then
      echo "Server process is taking a long time to exit. Continuing with shutdown anyway."
      return 0
    fi
    
    # Provide status updates at 30-second intervals
    if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
      echo "Still waiting for $instance to shut down... ($elapsed seconds elapsed)"
      echo "Status: Process running: $process_running, PID file exists: $pid_file_exists, Complete flag: $complete_flag_exists"
    fi
    
    # Wait for the next check interval
    sleep $check_interval
    elapsed=$((elapsed + check_interval))
  done

  # If we got here, we timed out
  echo "Timeout waiting for $instance to shut down cleanly after $elapsed seconds."
  echo "Final status: Process running: $process_running, PID file exists: $pid_file_exists, Complete flag: $complete_flag_exists"
  return 1
}

# Add a new function to handle API-mode restart
api_restart_instance() {
  local instance_name=$1
  local message=${2:-"5"}  # Default restart message is 5 minutes

  echo "Detected API=TRUE for instance $instance_name"
  echo "Using special restart process for API mode..."
  
  # First, send the shutdown command with the provided countdown
  echo "Sending shutdown command with countdown: $message minutes"
  # Use the original run_in_container logic to send the shutdown command
  local container_name="asa_${instance_name}"
  local shutdown_command="/home/pok/scripts/rcon_interface.sh -shutdown '$message'"
  
  if docker ps -q -f name=^/${container_name}$ > /dev/null; then
    docker exec "$container_name" /bin/bash -c "$shutdown_command" || true
  else
    echo "Instance ${instance_name} is not running or does not exist."
    return 1
  fi
  
  # Wait for the shutdown to complete 
  local shutdown_wait=$((message * 60 + 30))  # Convert minutes to seconds + 30 seconds buffer
  echo "Waiting for shutdown to complete ($shutdown_wait seconds)..."
  sleep $shutdown_wait
  
  # Stop the container
  echo "Stopping container for instance $instance_name..."
  stop_instance "$instance_name"
  
  # Wait for container to fully stop
  echo "Waiting for container to completely stop..."
  sleep 10
  
  # Start the container again
  echo "Starting container for instance $instance_name..."
  start_instance "$instance_name"
  
  echo "✅ API instance $instance_name has been restarted using container restart strategy."
  echo "   This ensures a clean environment for API mode."
  return 0
}

# Adjust `run_in_container` to correctly construct and execute the Docker command
run_in_container() {
  local instance="$1"
  local cmd="$2"
  local args="${@:3}" # Capture all remaining arguments as the command args

  # If this is a restart command and the instance has API=TRUE, use our special restart function
  if [[ "$cmd" == "-restart" ]]; then
    # Get the docker-compose file path
    local base_dir="${BASE_DIR}"
    local docker_compose_file="${base_dir}/Instance_${instance}/docker-compose-${instance}.yaml"
    
    # Check if API=TRUE in the docker-compose file
    if [ -f "$docker_compose_file" ] && (grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"); then
      api_restart_instance "$instance" "$args"
      return $?
    fi
  fi

  local container_name="asa_${instance}" # Construct the container name
  local command="/home/pok/scripts/rcon_interface.sh ${cmd}"

  # Append args to command if provided
  if [ -n "$args" ]; then
    command+=" '${args}'" # Add quotes to encapsulate the arguments as a single string
  fi

  # Verify the container exists and is running, then execute the command and capture the output
  if docker ps -q -f name=^/${container_name}$ > /dev/null; then
    # Execute the command in the container and capture the output
    # Don't redirect output for shutdown and restart, show it directly to the user
    output=$(docker exec "$container_name" /bin/bash -c "$command")
    echo "$output" # Return the captured output
  else
    echo "Instance ${instance} is not running or does not exist."
  fi
}
run_in_container_background() {
  local instance="$1"
  local cmd="$2"
  local args="${@:3}" # Capture all remaining arguments as the command args

  local container_name="asa_${instance}" # Construct the container name
  local command="/home/pok/scripts/rcon_interface.sh ${cmd}"

  if [ -n "$args" ]; then
    command+=" '${args}'" # Add quotes to encapsulate the arguments as a single string
  fi

  #echo "----- Server ${instance}: Command: ${cmd#-}${args:+ $args} -----"

  # Verify the container exists and is running, then execute the command
  if docker ps -q -f name=^/${container_name}$ > /dev/null; then
    # Execute the command in the background and discard its output
    docker exec "$container_name" /bin/bash -c "$command" >/dev/null 2>&1
  else
    echo "Instance ${instance} is not running or does not exist."
  fi
}
get_build_id_from_acf() {
  local acf_file="${BASE_DIR}/ServerFiles/arkserver/appmanifest_2430930.acf"

  if [ -f "$acf_file" ]; then
    local build_id=$(grep -E "^\s+\"buildid\"\s+" "$acf_file" | grep -o '[[:digit:]]*')
    echo "$build_id"
  else
    echo "error: appmanifest_2430930.acf file not found"
    return 1
  fi
}
check_for_POK_updates() {
  # Get original args from the calling function
  local original_args=("${@}")
  
  # Skip update checks when running in non-interactive mode (e.g., cron jobs)
  if [ -t 0 ]; then
    echo "Checking for updates to POK-manager.sh..."
  else
    # When running non-interactively, only check for updates if explicitly requested
    if [ "$1" != "force" ]; then
      return
    fi
  fi
  
  # Check if we're in post-migration state with wrong user ID
  if [ "$(id -u)" -ne 0 ] && [ -f "${BASE_DIR}/config/POK-manager/migration_complete" ]; then
    # Check if config directory is owned by 7777 but we're not running as 7777
    if [ -d "${BASE_DIR}/config/POK-manager" ]; then
      local config_dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/config/POK-manager)"
      local config_dir_uid=$(echo "$config_dir_ownership" | cut -d: -f1)
      
      if [ "$config_dir_uid" = "7777" ] && [ "$(id -u)" -ne 7777 ]; then
        # Skip update check due to permission issues
        if [ -t 0 ]; then # Only show in interactive mode
          echo "Skipping update check due to post-migration permission issues"
        fi
        return
      fi
    fi
  fi
  
  # Check if we've just upgraded the script
  local just_upgraded="${BASE_DIR%/}/config/POK-manager/just_upgraded"
  local upgraded_version_file="${BASE_DIR%/}/config/POK-manager/upgraded_version"
  
  if [ -f "$just_upgraded" ]; then
    # Remove the flag file
    rm -f "$just_upgraded"
    
    # Check if we have a stored upgraded version
    if [ -f "$upgraded_version_file" ]; then
      local new_version=$(cat "$upgraded_version_file")
      # Update the version number in memory to match what we just upgraded to
      if [ -n "$new_version" ]; then
        POK_MANAGER_VERSION="$new_version"
        rm -f "$upgraded_version_file"
      fi
    fi
    
    # Extract version information from the current script
    local current_script_version=$(grep -m 1 "POK_MANAGER_VERSION=" "$0" | cut -d'"' -f2)
    if [ -n "$current_script_version" ]; then
      # Update the POK_MANAGER_VERSION variable with the actual current version
      POK_MANAGER_VERSION="$current_script_version"
    fi
    
    # Skip update check since we just upgraded
    echo " GitHub version: $POK_MANAGER_VERSION, Local version: $POK_MANAGER_VERSION"
    echo "----- POK-manager.sh is already up to date (version $POK_MANAGER_VERSION) -----"
    return
  fi
  
  # Determine which branch to use for updates
  local branch_name="master"
  if [ "$POK_MANAGER_BRANCH" = "beta" ]; then
    branch_name="beta"
    if [ -t 0 ]; then # Only show this message in interactive mode
      echo "Using beta branch for updates"
    fi
  fi
  
  # Add timestamp and random string as cache-busting parameters
  local timestamp=$(date +%s)
  local random_str=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)
  local script_url="https://raw.githubusercontent.com/Acekorneya/Ark-Survival-Ascended-Server/${branch_name}/POK-manager.sh?nocache=${timestamp}_${random_str}"
  local temp_file="/tmp/POK-manager.sh.${timestamp}.tmp"
  local update_info_file="${BASE_DIR}/config/POK-manager/update_available"
  
  # Ensure config directory exists with proper permissions
  mkdir -p "${BASE_DIR}/config/POK-manager"
  
  # Download the file using wget or curl with aggressive cache-busting
  local download_success=false
  if command -v wget &>/dev/null; then
    if wget -q --no-cache -O "$temp_file" "$script_url"; then
      download_success=true
    fi
  elif command -v curl &>/dev/null; then
    if curl -s -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" -o "$temp_file" "$script_url"; then
      download_success=true
    fi
  else
    echo "Neither wget nor curl is available. Unable to check for updates."
    return
  fi

  if [ "$download_success" = "true" ] && [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
    # Make sure the file is at least 1KB in size (sanity check)
    if [ $(stat -c%s "$temp_file") -ge 1024 ]; then
      # Extract version information from the downloaded file
      local new_version=$(grep -m 1 "POK_MANAGER_VERSION=" "$temp_file" | cut -d'"' -f2)
      
      if [ -n "$new_version" ]; then
        echo " GitHub version: $new_version, Local version: $POK_MANAGER_VERSION"
        
        # Compare versions using simple numeric comparison for reliability
        # Convert version strings to numbers for comparison
        local current_version=$POK_MANAGER_VERSION
        
        # Function to convert version to comparable number
        version_to_number() {
          local ver=$1
          local major=0
          local minor=0
          local patch=0
          
          # Parse the version into components
          if [[ $ver =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
            major=${BASH_REMATCH[1]}
            minor=${BASH_REMATCH[2]}
            patch=${BASH_REMATCH[3]}
          fi
          
          # Convert to a single number (allowing for versions up to 999.999.999)
          echo $((major * 1000000 + minor * 1000 + patch))
        }
        
        local current_num=$(version_to_number "$current_version")
        local new_num=$(version_to_number "$new_version")
        
        # Only notify if the new version is actually newer
        if [ $new_num -gt $current_num ]; then
          # Create update_available file so user knows an update is available
          echo "$new_version" > "$update_info_file"
          
          echo "************************************************************"
          echo "* A newer version of POK-manager.sh is available: $new_version *"
          echo "* Current version: $current_version                           *"
          
          # Ask if the user wants to upgrade only in interactive mode
          if [ -t 0 ]; then
            echo -n "* Would you like to upgrade now? (y/n) [15s timeout]: "
            # Add a 15-second timeout for the prompt
            read -t 15 -r upgrade_response || {
              echo ""
              echo "* Timeout reached. Continuing without upgrading."
              echo "* You can manually upgrade later with: ./POK-manager.sh -upgrade"
              echo "************************************************************"
              return
            }
            
            if [[ "$upgrade_response" =~ ^[Yy]$ ]]; then
              # Save the new version to the file so upgrade_pok_manager can use it
              echo "$new_version" > "${BASE_DIR}/config/POK-manager/upgraded_version"
              
              # Save the original command arguments to a file
              if [ ${#original_args[@]} -gt 0 ]; then
                printf "%s\n" "${original_args[@]}" > "${BASE_DIR}/config/POK-manager/last_command_args"
                echo "Original command saved for reuse after upgrade"
              fi
              
              # Save the downloaded file for later use
              cp "$temp_file" "${BASE_DIR}/config/POK-manager/new_version"
              chmod +x "${BASE_DIR}/config/POK-manager/new_version"
              
              # Call the upgrade function directly
              upgrade_pok_manager
              return
            else
              echo "* Run './POK-manager.sh -upgrade' later to perform the update     *"
              echo "* If an update causes issues, you can restore the previous        *"
              echo "* version with './POK-manager.sh -force-restore'                  *"
            fi
          else
            echo "* Run './POK-manager.sh -upgrade' to perform the update     *"
            echo "* If an update causes issues, you can restore with:         *"
            echo "* './POK-manager.sh -force-restore'                         *"
          fi
          echo "************************************************************"
          
          # Store the update information for later use
          echo "$new_version" > "$update_info_file"
          
          # Save the downloaded file for later use
          cp "$temp_file" "${BASE_DIR}/config/POK-manager/new_version"
          chmod +x "${BASE_DIR}/config/POK-manager/new_version"
        else
          if [ -t 0 ]; then # Only show in interactive mode
            echo "----- POK-manager.sh is already up to date (version $current_version) -----"
          fi
          
          # Remove any existing update info since we're up to date
          rm -f "$update_info_file"
          rm -f "${BASE_DIR}/config/POK-manager/new_version"
        fi
      else
        if [ -t 0 ]; then # Only show in interactive mode
          echo "WARNING: Could not determine version from downloaded file."
        fi
      fi
    else
      if [ -t 0 ]; then # Only show in interactive mode
        echo "WARNING: Downloaded file is too small to be valid."
      fi
    fi
    
    # Clean up the temporary file
    rm -f "$temp_file"
  else
    if [ -t 0 ]; then # Only show in interactive mode
      echo "Failed to download file from GitHub. Skipping update check."
    fi
    
    # Clean up any partial downloads
    if [ -f "$temp_file" ]; then
      rm -f "$temp_file"
    fi
  fi
}

is_sudo() {
  if [ "$EUID" -eq 0 ]; then
    return 0
  else
    return 1
  fi
}
get_current_build_id() {
  local app_id="2430930"
  
  # Create a temporary container to run SteamCMD
  echo "Creating temporary container to check for server updates..." >&2
  local temp_container_name="pok_steamcmd_check"
  local image_tag=$(get_docker_image_tag "")
  
  # Check if user is in docker group or is root to avoid using sudo
  local docker_cmd="docker"
  if ! (groups | grep -q '\bdocker\b' || [ "$(id -u)" -eq 0 ]); then
    docker_cmd="sudo docker"
  fi
  
  # Run a temporary container
  local temp_container_id=$($docker_cmd run -d --rm \
    --name "$temp_container_name" \
    "acekorneya/asa_server:${image_tag}" \
    sleep infinity)
  
  if [ -z "$temp_container_id" ]; then
    echo "error: could not create temporary container for SteamCMD check" >&2
    return 1
  fi
  
  # Wait a moment for container to initialize
  sleep 2
  
  # Get build ID from SteamCMD inside the container
  local steamcmd_output=$($docker_cmd exec "$temp_container_name" /opt/steamcmd/steamcmd.sh +login anonymous +app_info_print $app_id +quit 2>/dev/null)
  
  # Remove the temporary container
  $docker_cmd rm -f "$temp_container_name" > /dev/null 2>&1 || true
  
  # Extract the build ID using the same approach as common.sh
  local build_id=$(echo "$steamcmd_output" | 
                 grep -A 150 "\"branches\"" | 
                 grep -A 50 "\"public\"" | 
                 grep -m 1 -oP "\"buildid\"\s*\"*\K[0-9]+" | 
                 head -n 1 | 
                 tr -d '[:space:]')
  
  if [ -z "$build_id" ]; then
    echo "error: could not retrieve build ID from SteamCMD. Please check SteamCMD connection." >&2
    return 1
  fi
  
  # Final sanity check - ensure it only contains digits
  if ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
    echo "error: invalid build ID format: '$build_id'" >&2
    return 1
  fi
  
  echo "$build_id"
}

manage_backup_rotation() {
  local instance_name="$1"
  local max_backups="$2"
  local max_size_gb="$3"

  local backup_dir="${BASE_DIR}/backups/${instance_name}"

  # Convert max_size_gb to bytes for precise size comparison
  local max_size_bytes=$((max_size_gb * 1024 * 1024 * 1024))

  # Get a list of backup files sorted by modification time (oldest first)
  local backup_files=($(ls -tr "${backup_dir}/"*.tar.gz 2>/dev/null))
  
  # Calculate the total size of the backups
  local total_size_bytes=0
  for backup_file in "${backup_files[@]}"; do
    total_size_bytes=$((total_size_bytes + $(stat -c%s "$backup_file")))
  done
  
  echo "Current backup size for $instance_name: $(( total_size_bytes / 1024 / 1024 / 1024 ))GB / ${max_size_gb}GB ($(( total_size_bytes / 1024 / 1024 ))MB)"
  echo "Current backup count for $instance_name: ${#backup_files[@]} / ${max_backups}"

  # First priority: Enforce the MAX_SIZE_GB limit
  # Remove oldest backups until we're under the size limit
  while [ $total_size_bytes -gt $max_size_bytes ] && [ ${#backup_files[@]} -gt 0 ]; do
    # Remove the oldest backup
    local oldest_backup="${backup_files[0]}"
    local backup_size_bytes=$(stat -c%s "$oldest_backup")
    echo "Size limit exceeded: Removing old backup: $oldest_backup ($(( backup_size_bytes / 1024 / 1024 ))MB)"
    rm "$oldest_backup"
    total_size_bytes=$((total_size_bytes - backup_size_bytes))
    # Remove the oldest backup from the array
    backup_files=("${backup_files[@]:1}")
  done

  # Second priority: Enforce the MAX_BACKUPS limit only if we have space
  # Only remove backups if we're under the size limit but over the count limit
  if [ $total_size_bytes -le $max_size_bytes ]; then
    while [ ${#backup_files[@]} -gt $max_backups ] && [ ${#backup_files[@]} -gt 0 ]; do
      # Remove the oldest backup
      local oldest_backup="${backup_files[0]}"
      local backup_size_bytes=$(stat -c%s "$oldest_backup")
      echo "Count limit exceeded: Removing old backup: $oldest_backup ($(( backup_size_bytes / 1024 / 1024 ))MB)"
      rm "$oldest_backup"
      total_size_bytes=$((total_size_bytes - backup_size_bytes))
      # Remove the oldest backup from the array
      backup_files=("${backup_files[@]:1}")
    done
  fi

  # Final status report
  echo "After rotation: $(( total_size_bytes / 1024 / 1024 / 1024 ))GB / ${max_size_gb}GB, ${#backup_files[@]} / ${max_backups} backups"
}

read_backup_config() {
  local instance_name="$1"
  local config_file="${BASE_DIR}/config/POK-manager/backup_${instance_name}.conf"

  # Default values for cronjobs or when config doesn't exist
  max_backups=10
  max_size_gb=10

  # Check if the config file exists
  if [ -f "$config_file" ]; then
    source "$config_file"
    # Ensure we have values even if the config file is malformed
    max_backups=${MAX_BACKUPS:-10}
    max_size_gb=${MAX_SIZE_GB:-10}
    echo "Using backup configuration from: $config_file"
    echo "  - Maximum backups: $max_backups"
    echo "  - Maximum size: ${max_size_gb}GB"
  else
    # Create the config file with default values since it doesn't exist
    write_backup_config "$instance_name" "$max_backups" "$max_size_gb"
    echo "Created default backup configuration for instance $instance_name (MAX_BACKUPS=$max_backups, MAX_SIZE_GB=$max_size_gb)"
  fi
}

write_backup_config() {
  local instance_name="$1"
  local max_backups="$2"
  local max_size_gb="$3"

  # Get the parent directory ownership to match it for the config files
  local parent_uid=$(stat -c '%u' "${BASE_DIR}")
  local parent_gid=$(stat -c '%g' "${BASE_DIR}")
  
  # If we can't determine the parent directory ownership, use PUID/PGID
  if [ -z "$parent_uid" ] || [ "$parent_uid" -eq 0 ]; then
    parent_uid=$PUID
  fi
  if [ -z "$parent_gid" ] || [ "$parent_gid" -eq 0 ]; then
    parent_gid=$PGID
  fi

  # Write to the config directory in BASE_DIR
  local config_file="${BASE_DIR}/config/POK-manager/backup_${instance_name}.conf"
  local config_dir=$(dirname "$config_file")
  
  # Ensure the directory exists
  mkdir -p "$config_dir" 2>/dev/null || true
  
  if cat > "$config_file" <<EOF 2>/dev/null; then
# Backup configuration for instance $instance_name
# MAX_SIZE_GB is the primary constraint - backups will be removed to stay under this limit
# MAX_BACKUPS is a secondary constraint only applied if size limit allows
MAX_BACKUPS=$max_backups
MAX_SIZE_GB=$max_size_gb
EOF
    # Make sure the file is readable
    chmod 644 "$config_file" 2>/dev/null || true
    # Set proper ownership for the config file if running as root
    if [ "$(id -u)" -eq 0 ]; then
      chown $parent_uid:$parent_gid "$config_file" 2>/dev/null || true
    elif command -v sudo &>/dev/null; then
      sudo chown $parent_uid:$parent_gid "$config_file" 2>/dev/null || true
    fi
    
    echo "Backup configuration created at $config_file"
  else
    echo "Warning: Failed to create backup configuration file for instance $instance_name. Default values will be used: MAX_BACKUPS=10, MAX_SIZE_GB=10"
  fi
}

backup_instance() {
  local instance_name="$1"

  if [[ "$instance_name" == "-all" ]]; then
    local instances=($(list_instances))
    for instance in "${instances[@]}"; do
      # Always ensure backup config exists before backing up
      read_backup_config "$instance"
      backup_single_instance "$instance"
      manage_backup_rotation "$instance" "$max_backups" "$max_size_gb"
    done
  elif [ -z "$instance_name" ]; then
    echo "No instance name or '-all' flag specified. Defaulting to backing up all instances."
    local instances=($(list_instances))
    for instance in "${instances[@]}"; do
      # Always ensure backup config exists before backing up
      read_backup_config "$instance"
      backup_single_instance "$instance"
      manage_backup_rotation "$instance" "$max_backups" "$max_size_gb"
    done
  else
    # Always ensure backup config exists before backing up
    read_backup_config "$instance_name"
    backup_single_instance "$instance_name"
    manage_backup_rotation "$instance_name" "$max_backups" "$max_size_gb"
  fi

  # Adjust ownership and permissions for the backup directory
  local backup_dir="${BASE_DIR}/backups"
  adjust_ownership_and_permissions "$backup_dir"
}

backup_single_instance() {
  local instance_name="$1"
  # Remove the trailing slash from $MAIN_DIR if it exists
  local base_dir="${BASE_DIR}"
  local backup_dir="${base_dir}/backups/${instance_name}"
  
  # Get the current timezone using timedatectl
  local timezone="${USER_TIMEZONE:-$(timedatectl show -p Timezone --value)}"
  
  # Get the current timestamp based on the host's timezone
  local timestamp=$(TZ="$timezone" date +"%Y-%m-%d_%H-%M-%S")
  
  # Format the backup file name
  local backup_file="${instance_name}_backup_${timestamp}.tar.gz"
  
  # Create backup directory with proper permissions if it doesn't exist
  if [ ! -d "$backup_dir" ]; then
    echo "Creating backup directory for instance $instance_name..."
    mkdir -p "$backup_dir"
    
    # Set proper permissions on the backup directory
    if [ "$(id -u)" -eq 0 ]; then
      # Get the parent directory ownership to match it for the backup directory
      local parent_uid=$(stat -c '%u' "${BASE_DIR}")
      local parent_gid=$(stat -c '%g' "${BASE_DIR}")
      
      # If we can't determine the parent directory ownership, use PUID/PGID
      if [ -z "$parent_uid" ] || [ "$parent_uid" -eq 0 ]; then
        parent_uid=$PUID
      fi
      if [ -z "$parent_gid" ] || [ "$parent_gid" -eq 0 ]; then
        parent_gid=$PGID
      fi
      
      # Apply ownership
      chown $parent_uid:$parent_gid "$backup_dir"
    fi
  fi

  local instance_dir="${base_dir}/Instance_${instance_name}"
  local saved_arks_dir="${instance_dir}/Saved/SavedArks"
  if [ -d "$saved_arks_dir" ]; then
    echo "Creating backup for instance $instance_name..."
    tar -czf "${backup_dir}/${backup_file}" -C "$instance_dir/Saved" "SavedArks"
    echo "Backup created: ${backup_dir}/${backup_file}"
    
    # Set proper permissions on the backup file
    if [ "$(id -u)" -eq 0 ]; then
      # Get the parent directory ownership to match it for the backup file
      local parent_uid=$(stat -c '%u' "${BASE_DIR}")
      local parent_gid=$(stat -c '%g' "${BASE_DIR}")
      
      # If we can't determine the parent directory ownership, use PUID/PGID
      if [ -z "$parent_uid" ] || [ "$parent_uid" -eq 0 ]; then
        parent_uid=$PUID
      fi
      if [ -z "$parent_gid" ] || [ "$parent_gid" -eq 0 ]; then
        parent_gid=$PGID
      fi
      
      # Apply ownership
      chown $parent_uid:$parent_gid "${backup_dir}/${backup_file}"
    fi
  else
    echo "SavedArks directory not found for instance $instance_name. Skipping backup."
  fi
}
restore_instance() {
  local instance_name="$1"
  # Remove the trailing slash from $MAIN_DIR if it exists
  local base_dir=$(dirname "$(realpath "$0")")
  local backup_dir="${base_dir}/backups"

  if [ -z "$instance_name" ]; then
    echo "No instance name specified. Please select an instance to restore from the list below."
    
    # Get all instances with docker-compose files (actual existing instances)
    local valid_instances=($(list_instances))
    
    # Get all backup directories
    local backup_dirs=($(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;))
    
    # Initialize array to store instances that have both valid configs and backups
    local restorable_instances=()
    
    # Find the intersection of valid instances and backup directories
    for instance in "${valid_instances[@]}"; do
      if [[ " ${backup_dirs[@]} " =~ " ${instance} " ]]; then
        restorable_instances+=("$instance")
      fi
    done
    
    if [ ${#restorable_instances[@]} -eq 0 ]; then
      echo "No instances found with both valid configurations and backups."
      return
    fi
      
    # Show only the instances that have both configs and backups
    for ((i=0; i<${#restorable_instances[@]}; i++)); do
      echo "$((i+1)). ${restorable_instances[i]}"
    done
    
    read -p "Enter the number of the instance to restore: " choice  
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#restorable_instances[@]} ]; then
      instance_name="${restorable_instances[$((choice-1))]}"
    else
      echo "Invalid choice. Exiting."
      return
    fi
  fi

  local instance_backup_dir="${backup_dir}/${instance_name}"

  if [ -d "$instance_backup_dir" ]; then
    local backup_files=($(ls -1 "$instance_backup_dir"/*.tar.gz 2>/dev/null))
    if [ ${#backup_files[@]} -eq 0 ]; then
      echo "No backups found for instance $instance_name."
      return
    fi

    echo "Here is a list of all your backup archives for instance $instance_name:"
    for ((i=0; i<${#backup_files[@]}; i++)); do
      echo "$((i+1)) ------ File: $(basename "${backup_files[i]}")"
    done

    read -p "Please input the number of the archive you want to restore: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#backup_files[@]} ]; then
      local selected_backup="${backup_files[$((choice-1))]}"
      
      # Check if instance is running and get confirmation before stopping
      local is_running=false
      if [[ " $(list_running_instances) " =~ " $instance_name " ]]; then
        is_running=true
        echo ""
        echo "⚠️ WARNING: The server instance '$instance_name' is currently running."
        echo "This operation will stop the server to restore the backup."
        echo "Selected backup: $(basename "$selected_backup")"
        echo ""
        read -p "Do you want to continue with stopping the server and restoring this backup? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
          echo "Restore operation cancelled by user."
          return
        fi
        
        echo "Stopping the server instance '$instance_name'..."
        stop_instance "$instance_name"
      fi

      local instance_dir="${base_dir}/Instance_${instance_name}"
      local saved_arks_dir="${instance_dir}/Saved/SavedArks"

      echo "Restoring backup: $(basename "$selected_backup") ..."
      mkdir -p "$saved_arks_dir"
      tar -xzf "$selected_backup" -C "$instance_dir/Saved"
      adjust_ownership_and_permissions "$saved_arks_dir"
      echo "Backup restored successfully!"

      # Only start the server if it was running before
      if [ "$is_running" = true ]; then
        echo "Starting server..."
        start_instance "$instance_name"
        echo "Server should be up in a few minutes."
      else
        echo "The server instance was not running before the restore."
        echo "If you want to start it, use: ./POK-manager.sh -start $instance_name"
      fi
    else
      echo "Invalid choice. Restore operation cancelled."
    fi
  else
    echo "No backups found for instance $instance_name."
  fi
}
select_instance() {
  local instances=($(list_instances))
  if [ ${#instances[@]} -eq 0 ]; then
    echo "No instances found."
    exit 1
  fi
  echo "Available instances:"
  for ((i=0; i<${#instances[@]}; i++)); do
    echo "$((i+1)). ${instances[i]}"
  done
  while true; do
    read -p "Enter the number of the instance: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#instances[@]} ]; then
      echo "${instances[$((choice-1))]}"
      break
    else
      echo "Invalid choice. Please try again."
    fi
  done
}

validate_instance() {
  local instance_name="$1"
  
  # Check for common typos of -all
  if [[ "$instance_name" =~ ^-a+l*$ ]] || [[ "$instance_name" =~ ^-al+$ ]] || \
     [[ "$instance_name" =~ ^-aall?$ ]] || [[ "$instance_name" =~ ^-alll?$ ]]; then
    echo "Error: '$instance_name' appears to be a typo of '-all'."
    echo "If you want to target all instances, please use '-all' exactly."
    return 1
  fi
  
  # Check if instance name starts with a dash but isn't -all
  if [[ "$instance_name" == -* ]] && [[ "${instance_name,,}" != "-all" ]]; then
    echo "Error: '$instance_name' appears to be an invalid flag."
    echo "Instance names shouldn't start with a dash (-). If you meant to target all instances, use '-all'."
    return 1
  fi
  
  # Check if the container is running
  local container_name="asa_${instance_name}"
  if ! docker ps -q -f name=^/${container_name}$ > /dev/null; then
    # Container isn't running - provide helpful message
    if docker ps -a -q -f name=^/${container_name}$ > /dev/null; then
      echo "Instance $instance_name exists but is not currently running."
      echo "Use './POK-manager.sh -start $instance_name' to start it."
    else
      # Check if the instance directory exists at least
      local base_dir="${BASE_DIR}"
      local instance_dir="${base_dir}/Instance_${instance_name}"
      local docker_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
      
      if [ -d "$instance_dir" ]; then
        # Directory exists but expected docker-compose doesn't
        if [ ! -f "$docker_compose_file" ]; then
          # Check for any docker-compose file
          local found_compose_files=($(find "${instance_dir}" -maxdepth 1 -name 'docker-compose-*.yaml' 2>/dev/null || true))
          
          if [ ${#found_compose_files[@]} -gt 0 ]; then
            # Found a mismatched docker-compose file
            local found_compose_file="${found_compose_files[0]}"
            local found_instance_name=$(basename "$found_compose_file" | sed 's/docker-compose-//g' | sed 's/\.yaml//g')
            
            echo "⚠️ Warning: Found a mismatched docker-compose file in folder for instance '$instance_name'."
            echo "The docker-compose file is for instance '$found_instance_name'."
            echo "This can happen if you renamed a folder manually instead of using the rename feature."
            echo "Use './POK-manager.sh -start $instance_name' to fix this issue automatically."
            echo "When prompted, select option 1 to update all references in the docker-compose file."
            return 1
          fi
        fi
        
        echo "Instance $instance_name is configured but has never been started or is currently stopped."
        echo "Use './POK-manager.sh -start $instance_name' to start it."
      else
        echo "Instance $instance_name does not exist."
        echo "Use './POK-manager.sh -create $instance_name' to create a new instance."
      fi
    fi
    return 1
  fi
  
  return 0
}

display_logs() {
  local instance_name="$1"
  local live="$2"

  if ! validate_instance "$instance_name"; then
    instance_name=$(select_instance)
  fi

  display_single_instance_logs "$instance_name" "$live"
}

display_single_instance_logs() {
  local instance_name="$1"
  local live="$2"
  local container_name="asa_${instance_name}"

  if [[ "$live" == "-live" ]]; then
    echo "Displaying live logs for instance $instance_name. Press Ctrl+C to exit."
    docker logs -f "$container_name"
  else
    echo "Displaying logs for instance $instance_name:"
    docker logs "$container_name"
  fi
}
manage_service() {
  get_docker_compose_cmd
  local action=$1
  local instance_name="$2"
  local additional_args="${@:3}"
  # Ensure root privileges for specific actions
  if [[ "$action" == "-setup" ]]; then
  check_puid_pgid_user "$PUID" "$PGID"
  fi

  # Adjust Docker permissions only for actions that explicitly require Docker interaction
  case $action in
  -start | -stop | -update | -create | -edit | -restore | -logs | -backup | -restart | -shutdown | -status | -chat | -saveworld | -fix)
    adjust_docker_permissions
    ;;
  esac

  # Special handling for -start all and -stop all actions
  if [[ "$action" == "-start" || "$action" == "-stop" ]] && [[ "${instance_name,,}" == "-all" ]]; then
    perform_action_on_all_instances "$action"
    return
  fi

  # Handle actions
  case $action in
  -list)
    list_instances
    ;;
  -edit)
    edit_instance
    ;;
  -setup)
    root_tasks
    echo "Setup completed. Please run './POK-manager.sh -create <instance_name>' to create an instance."
    ;;
  -create)
    # No need for root privileges here unless specific actions require it
    instance_name=$(prompt_for_instance_name "$instance_name")
    check_puid_pgid_user "$PUID" "$PGID"
    generate_docker_compose "$instance_name" 
    adjust_ownership_and_permissions "$MAIN_DIR"
    # Ensure POK-manager.sh is executable
    start_instance "$instance_name"
    ;;
  -start)
    start_instance "$instance_name"
    ;;
  -backup)
    if [[ -z "$instance_name" ]]; then
      echo "No instance name or '-all' flag specified. Defaulting to backing up all instances."
      backup_instance "-all"
    elif [[ "${instance_name,,}" == "-all" ]]; then
      backup_instance "-all"
    else
      backup_instance "$instance_name"
    fi
    ;;
  -restore)
    restore_instance "$instance_name"
    ;;
  -stop)
    stop_instance "$instance_name"
    ;;
  -update)
    update_server_files_and_docker
    exit 0
    ;;
  -fix)
    # Check for root-owned files and fix permissions
    echo "Checking for root-owned files that could cause container permission issues..."
    
    # Check if running with sudo or root
    if [ "$(id -u)" -eq 0 ]; then
      # Make sure to fix the script itself first
      local script_path="$(realpath "$0")"
      echo "First ensuring POK-manager.sh has correct permissions..."
      
      # Get the expected ownership based on installation mode
      local ownership=$(get_expected_ownership)
      local expected_uid=$(echo "$ownership" | cut -d: -f1)
      local expected_gid=$(echo "$ownership" | cut -d: -f2)
      
      # Define the target owner variable before using it
      local target_owner="${expected_uid}:${expected_gid}"
      
      # If running with sudo, use the actual user if possible
      if [ -n "$SUDO_USER" ]; then
        # Only use the sudo user if they're the expected owner (makes sense for personal installs)
        local sudo_uid=$(id -u "$SUDO_USER")
        local sudo_gid=$(id -g "$SUDO_USER")
        
        # If the sudo user is the expected owner or a member of the expected group, use them
        if [ "$sudo_uid" = "$expected_uid" ] || id -G "$SUDO_USER" | grep -q -w "$expected_gid"; then
          target_owner="${sudo_uid}:${expected_gid}"
        fi
      fi
      
      echo "Setting POK-manager.sh ownership to $target_owner"
      # Force change ownership regardless of current state
      chown $target_owner "$script_path"
      chmod +x "$script_path"
      
      # Also fix the last_displayed_version.txt file if it exists
      if [ -f "$LAST_VERSION_FILE" ]; then
        echo "Setting $LAST_VERSION_FILE ownership to $target_owner"
        chown $target_owner "$LAST_VERSION_FILE"
      fi
      
      # Fix the config directory ownership if needed
      if [ -d "${BASE_DIR}/config/POK-manager" ]; then
        local config_dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/config/POK-manager)"
        if [ "$config_dir_ownership" != "$target_owner" ]; then
          echo "Setting config directory ownership to $target_owner"
          chown -R $target_owner "${BASE_DIR}/config/POK-manager"
        fi
      fi
    fi
    
    # Ensure ServerFiles directory has correct permissions to prevent SteamCMD error 0x602
    echo "Ensuring ServerFiles directory has correct ownership..."
    mkdir -p "${BASE_DIR}/ServerFiles/arkserver"
    adjust_ownership_and_permissions "${BASE_DIR}/ServerFiles/arkserver"
    
    # Then run the normal fix_root_owned_files function
    fix_root_owned_files
    
    echo ""
    echo "✅ Permission check and fix completed."
    echo "If you were running the script using sudo before, try running it without sudo now:"
    echo "./POK-manager.sh [your-command]"
    ;;
  -restart | -shutdown)
    execute_rcon_command "$action" "$instance_name" "${additional_args[@]}"
    ;;
  -saveworld |-status)
    execute_rcon_command "$action" "$instance_name"
    ;;
  -chat)
    local message="$instance_name"
    instance_name="$additional_args"
    execute_rcon_command "$action" "$instance_name" "$message"
    ;;
  -custom)
    local rcon_command="$instance_name"
    instance_name="$additional_args"
    execute_rcon_command "$action" "$instance_name" "$rcon_command"
    ;;
  -logs)
    local live=""
    if [[ "$instance_name" == "-live" ]]; then
      live="-live"
      instance_name="$additional_args"
    fi

    if [[ -z "$instance_name" ]]; then
      echo "Available running instances:"
      local instances=($(list_running_instances))
      if [ ${#instances[@]} -eq 0 ]; then
        echo "No running instances found."
        exit 1
      fi
      for ((i=0; i<${#instances[@]}; i++)); do
        echo "$((i+1)). ${instances[i]}"
      done
      while true; do
        read -p "Enter the number of the running instance: " choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#instances[@]} ]; then
          instance_name="${instances[$((choice-1))]}"
          break
        else
          echo "Invalid choice. Please try again."
        fi
      done
    fi
    display_logs "$instance_name" "$live"
    ;;
  -clearupdateflag)
    if [ -z "$instance_name" ] || [ "${instance_name,,}" == "-all" ]; then
      echo "Clearing update flags for all instances..."
      for instance in $(list_instances); do
        echo "Processing instance: $instance"
        docker exec -it "asa_${instance}" /bin/bash -c "/home/pok/scripts/rcon_interface.sh -clearupdateflag" || echo "Failed to clear update flag for $instance"
      done
    else
      echo "Clearing update flag for instance: $instance_name"
      docker exec -it "asa_${instance_name}" /bin/bash -c "/home/pok/scripts/rcon_interface.sh -clearupdateflag"
    fi
    ;;
  -API)
    if [[ -z "$instance_name" ]]; then
      echo "Error: -API requires a TRUE/FALSE value and an instance name or -all."
      echo "Usage: $0 -API <TRUE|FALSE> <instance_name|-all>"
      echo "Examples:"
      echo "  $0 -API TRUE my_instance    # Enable ArkServerAPI for 'my_instance'"
      echo "  $0 -API FALSE -all          # Disable ArkServerAPI for all instances"
      exit 1
    fi
    
    local api_state="$instance_name"
    instance_name="$additional_args"
    
    if [[ -z "$instance_name" ]]; then
      echo "Error: -API requires an instance name or -all after the TRUE/FALSE value."
      echo "Usage: $0 -API <TRUE|FALSE> <instance_name|-all>"
      echo "Examples:"
      echo "  $0 -API TRUE my_instance    # Enable ArkServerAPI for 'my_instance'"
      echo "  $0 -API FALSE -all          # Disable ArkServerAPI for all instances"
      exit 1
    fi
    
    configure_api "$api_state" "$instance_name"
    ;;
  -changelog)
    display_changelog
    ;;
  -rename)
    # Helper function to check if a container is running
    is_container_running() {
      local instance_name="$1"
      local container_name="asa_${instance_name}"
      if docker ps -q --filter "name=${container_name}" | grep -q .; then
        return 0  # Container is running
      else
        return 1  # Container is not running
      fi
    }

    # Helper function to stop a running container, rename instance, and optionally restart
    rename_instance() {
      local oldname="$1"
      local newname="$2"
      local old_folder="Instance_${oldname}"
      local new_folder="Instance_${newname}"
      local container_running=false
      local restart_after=false
      
      # Check if container is running and stop it if needed
      if is_container_running "$oldname"; then
        container_running=true
        echo "Container for '$oldname' is currently running."
        read -p "Do you want to stop it to proceed with the rename? (y/n): " should_stop
        if [[ "${should_stop,,}" == "y" ]]; then
          echo "Stopping container asa_${oldname}..."
          # Use the script's stop_instance function instead of direct docker stop
          stop_instance "$oldname"
          read -p "Would you like to restart the container after renaming? (y/n): " should_restart
          if [[ "${should_restart,,}" == "y" ]]; then
            restart_after=true
          fi
        else
          echo "Cannot rename a running container. Operation cancelled."
          return 1
        fi
      fi
      
      # Perform the rename operation
      mv "$old_folder" "$new_folder"
      [ "$(id -u)" -eq 0 ] && chown -R $PUID:$PGID "$new_folder" || sudo chown -R $PUID:$PGID "$new_folder"
      
      # Find all docker-compose files in the renamed folder
      local compose_files=()
      local restart_file=""
      
      while IFS= read -r -d $'\0' file; do
        if [[ "$file" == *docker-compose*.y*ml ]]; then
          compose_files+=("$file")
          # If we found a compose file, use it for restarting later
          restart_file="$file"
        fi
      done < <(find "$new_folder" -type f -name "*docker-compose*.y*ml" -print0)
      
      # Also check parent directory for docker-compose files related to this instance
      while IFS= read -r -d $'\0' file; do
        if [[ "$file" == *"${oldname}"* && "$file" == *docker-compose*.y*ml ]]; then
          compose_files+=("$file")
        fi
      done < <(find "$(dirname "$new_folder")" -maxdepth 1 -type f -name "*docker-compose*.y*ml" -print0)

      # Update the docker-compose files to reflect the new name
      for compose_file in "${compose_files[@]}"; do
        echo "Updating file: $compose_file"

        # Update volume paths in docker-compose files to use the new instance name
        # This is crucial for maintaining save data and config access
        sed -i "s|/home/factorioserver/ASA_Server/Instance_${oldname}/|/home/factorioserver/ASA_Server/Instance_${newname}/|g" "$compose_file"
        
        # Also update any other references to the old instance name in the compose file
        sed -i "s/${oldname}/${newname}/g" "$compose_file"
        
        # Handle file renaming if the compose file has the old name in its filename
        if [[ "$(basename "$compose_file")" == *"${oldname}"* ]]; then
          local new_filename="$(dirname "$compose_file")/$(basename "$compose_file" | sed "s/${oldname}/${newname}/g")"
          echo "Renaming file from $(basename "$compose_file") to $(basename "$new_filename")"
          mv "$compose_file" "$new_filename"
          
          # If this was the restart file, update the reference
          if [[ "$compose_file" == "$restart_file" ]]; then
            restart_file="$new_filename"
          fi
        fi
      done

      # Ensure the docker_compose_cmd config file is in the correct location
      local instance_config_dir="${new_folder}/config/POK-manager"
      local base_config_dir="${BASE_DIR}/config/POK-manager"
      
      # Create base config directory if it doesn't exist
      mkdir -p "$base_config_dir"
      
      # If docker_compose_cmd exists in instance config, move it to base config
      if [[ -f "${instance_config_dir}/docker_compose_cmd" ]]; then
        cp "${instance_config_dir}/docker_compose_cmd" "${base_config_dir}/docker_compose_cmd"
        echo "Copied docker_compose_cmd config to main config directory"
      fi

      echo "Renamed instance '${oldname}' to '${newname}' in folder and updated docker-compose configuration."
      
      # Restart the container if requested
      if [[ "$restart_after" == true ]]; then
        echo "Starting container with new name: asa_${newname}..."
        # Use the script's start_instance function instead of direct docker start
        start_instance "$newname"
        echo "Container started with new name."
      fi
      
      # This return statement ensures the function completes successfully
      # and allows the rename_all_instances function to continue with other renames
      return 0
    }

    # Check if the user wants to rename all instances (case-insensitive for '-all')
    if [[ -z "$2" ]]; then
      echo "Error: Missing required parameter. Usage: $0 -rename <instance_name|-all>"
      echo "Please specify an instance name or use '-all' to rename all instances."
      exit 1
    elif [[ "${2,,}" == "-all" ]]; then
      echo "Renaming all instances..."
      # Loop over instance directories; assuming they are named 'Instance_*'
      for instance_dir in Instance_*; do
        if [[ -d "$instance_dir" ]]; then
          # Extract old instance name from folder name (everything after 'Instance_')
          oldname=${instance_dir#Instance_}
          echo "Current instance: $oldname"
          read -p "Enter new name for instance '$oldname' (press enter to keep unchanged): " newname
          if [[ -n "$newname" ]]; then
            rename_instance "$oldname" "$newname"
          else
            echo "Instance '$oldname' remains unchanged."
          fi
        fi
      done
    else
      # Rename a single specified instance
      instance="$2"
      # Expect instance folder to be named 'Instance_<instance>'
      instance_folder="Instance_${instance}"
      if [[ ! -d "$instance_folder" ]]; then
        echo "Instance folder '$instance_folder' not found."
        exit 1
      fi
      echo "Current instance: $instance"
      read -p "Enter new name for instance '$instance' (press enter to keep unchanged): " newname
      if [[ -n "$newname" ]]; then
        rename_instance "$instance" "$newname"
      else
        echo "Instance '$instance' remains unchanged."
      fi
    fi
    exit 0
    ;;
  *)
    echo "Invalid action. Usage: $0 {action} [additional_args...] {instance_name}"
    echo "Actions include: -start, -stop, -update, -create, -setup, -status, -restart, -saveworld, -chat, -custom, -backup, -restore"
    exit 1
    ;;
  esac
}
# Define valid actions
declare -a valid_actions
valid_actions=("-create" "-start" "-stop" "-saveworld" "-shutdown" "-restart" "-status" "-update" "-list" "-beta" "-stable" "-version" "-upgrade" "-logs" "-backup" "-restore" "-migrate" "-setup" "-edit" "-custom" "-chat" "-clearupdateflag" "-API" "-validate_update" "-force-restore" "-emergency-restore" "-fix" "-api-recovery" "-changelog" "-rename")

display_usage() {
  echo "Usage: $0 {action} [instance_name|-all] [additional_args...]"
  echo
  echo "Actions:"
  echo "  -list                                     List all instances"
  echo "  -edit                                     Edit an instance's configuration"
  echo "  -setup                                    Perform initial setup tasks"
  echo "  -create <instance_name>                   Create a new instance"
  echo "  -start <instance_name|-all>               Start an instance or all instances"
  echo "  -stop <instance_name|-all>                Stop an instance or all instances"
  echo "  -shutdown [minutes] <instance_name|-all>  Shutdown an instance or all instances with an optional countdown"
  echo "  -update                                   Check for server files & Docker image updates (doesn't modify the script itself)"
  echo "  -upgrade                                  Upgrade POK-manager.sh script to the latest version (requires confirmation)"
  echo "  -force-restore                            Force restore POK-manager.sh from backup in case of update failure"
  echo "  -status <instance_name|-all>              Show the status of an instance or all instances"
  echo "  -restart [minutes] <instance_name|-all>   Restart an instance or all instances"
  echo "  -saveworld <instance_name|-all>           Save the world of an instance or all instances"
  echo "  -chat \"<message>\" <instance_name|-all>    Send a chat message to an instance or all instances"
  echo "  -custom <command> <instance_name|-all>    Execute a custom command on an instance or all instances"
  echo "  -backup [instance_name|-all]              Backup an instance or all instances (defaults to all if not specified)"
  echo "  -restore [instance_name]                  Restore an instance from a backup"
  echo "  -logs [-live] <instance_name>             Display logs for an instance (optionally live)"
  echo "  -beta                                     Switch to beta mode to use beta version Docker images"
  echo "  -stable                                   Switch to stable mode to use stable version Docker images"
  echo "  -migrate                                  Migrate file ownership from 1000:1000 to 7777:7777 for compatibility with 2_1 images"
  echo "  -clearupdateflag <instance_name|-all>     Clear a stale updating.flag file if an update was interrupted"
  echo "  -API <TRUE|FALSE> <instance_name|-all>    Enable or disable ArkServerAPI for specified instance(s)"
  echo "  -fix                                      Fix permissions on files owned by the wrong user that could cause container issues"
  echo "  -version                                  Display the current version of POK-manager"
  echo "  -api-recovery                             Check and recover API instances with container restart"
  echo "  -changelog                                Display the changelog"
  echo "  -rename <instance_name|-all>              Rename a single instance or all instances"
}

# Display version information
display_version() {
  # Extract version information directly from the script file to ensure accuracy
  local script_version=$(grep -m 1 "POK_MANAGER_VERSION=" "$0" | cut -d'"' -f2)
  if [ -n "$script_version" ]; then
    # Update the global variable to ensure consistency
    POK_MANAGER_VERSION="$script_version"
  fi
  
  echo "POK-manager.sh version ${POK_MANAGER_VERSION} (${POK_MANAGER_BRANCH})"
  echo "Default PUID: ${PUID}, PGID: ${PGID}"
  local image_tag=$(get_docker_image_tag)
  echo "Docker image: acekorneya/asa_server:${image_tag}"
  
  # Fetch and display patch notes for the current version
  local changelog=$(fetch_changelog)
  if [ $? -eq 0 ]; then
    echo ""
    echo "===== PATCH NOTES ====="
    
    # Check if this is a development branch
    if is_development_branch "$changelog" "$POK_MANAGER_VERSION"; then
      echo "This is a development version ahead of current available versions."
      echo "No specific patch notes available for version $POK_MANAGER_VERSION."
    else
      local notes=$(extract_version_patch_notes "$changelog" "$POK_MANAGER_VERSION")
      if [ -n "$notes" ]; then
        echo -e "$notes"
      else
        echo "No patch notes found for version $POK_MANAGER_VERSION."
      fi
    fi
  else
    echo ""
    echo "Could not fetch patch notes from GitHub."
  fi
}

# Function to fetch changelog from GitHub
fetch_changelog() {
  local branch_name="master"
  if [ "$POK_MANAGER_BRANCH" = "beta" ]; then
    branch_name="beta"
  fi
  
  # Add timestamp and random string as cache-busting parameters
  local timestamp=$(date +%s)
  local random_str=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)
  local changelog_url="https://raw.githubusercontent.com/Acekorneya/Ark-Survival-Ascended-Server/${branch_name}/changelog.txt?nocache=${timestamp}_${random_str}"
  local temp_file="/tmp/changelog.${timestamp}.tmp"
  
  # Download the changelog using wget or curl with aggressive cache-busting
  local download_success=false
  if command -v wget &>/dev/null; then
    if wget -q --no-cache --no-check-certificate -O "$temp_file" "$changelog_url"; then
      download_success=true
    fi
  elif command -v curl &>/dev/null; then
    if curl -s -k -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" -o "$temp_file" "$changelog_url"; then
      download_success=true
    fi
  else
    echo "Neither wget nor curl is available. Unable to fetch changelog."
    return 1
  fi
  
  if [ "$download_success" = "true" ] && [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
    # Make sure the file is at least 100 bytes in size (sanity check)
    if [ $(stat -c%s "$temp_file") -ge 100 ]; then
      # Preserve line endings when reading the content
      local content=$(cat "$temp_file")
      rm -f "$temp_file"
      echo "$content"
      return 0
    else
      echo "Downloaded changelog file is too small. May be incomplete."
      rm -f "$temp_file"
      return 1
    fi
  else
    echo "Failed to download changelog."
    return 1
  fi
}

# Function to extract patch notes for a specific version
extract_version_patch_notes() {
  local changelog="$1"
  local version="$2"
  local in_section=false
  local section_content=""
  
  # Process the changelog line by line
  while IFS= read -r line; do
    # If we found a new section header
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      # If we were already in a section, we've reached the end of it
      if [ "$in_section" = true ]; then
        break
      fi
      
      # Check if this is the section we're looking for
      if [[ "$line" =~ ^##[[:space:]]Version[[:space:]]$version([[:space:]]|\() ]] || [[ "$line" =~ ^##[[:space:]]\[$version\] ]]; then
        in_section=true
        section_content+="$line"$'\n'
      fi
    # If we're in the correct section, add the line to the content
    elif [ "$in_section" = true ]; then
      section_content+="$line"$'\n'
    fi
  done <<< "$changelog"
  
  echo -e "$section_content"
}

# Function to extract patch notes between two versions
extract_patch_notes_between_versions() {
  local changelog="$1"
  local last_version="$2"
  local current_version="$3"
  
  # Parse the changelog and extract all version numbers
  local versions=$(echo "$changelog" | grep -E "^## Version |^## \[" | sed -E 's/^## Version ([0-9]+\.[0-9]+\.[0-9]+).*$/\1/; s/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*$/\1/')
  
  # Create a temporary file with all versions
  local temp_versions="/tmp/versions.${RANDOM}.tmp"
  echo "$versions" > "$temp_versions"
  
  # Find versions between last_version and current_version
  local in_range=false
  local versions_to_show=""
  
  while read -r version; do
    if [ "$version" = "$current_version" ]; then
      in_range=true
      versions_to_show="$version $versions_to_show"
    elif [ "$in_range" = true ] && [ "$version" != "$last_version" ]; then
      versions_to_show="$versions_to_show $version"
    elif [ "$version" = "$last_version" ]; then
      in_range=false
      break
    fi
  done < "$temp_versions"
  
  rm -f "$temp_versions"
  
  # Extract patch notes for each version in the range
  local all_notes=""
  for ver in $versions_to_show; do
    local notes=$(extract_version_patch_notes "$changelog" "$ver")
    if [ -n "$notes" ]; then
      all_notes+="$notes"$'\n\n'
    fi
  done
  
  echo -e "$all_notes"
}

# Function to check if the current version is a development branch
is_development_branch() {
  local changelog="$1"
  local current_version="$2"
  
  # Check if the version exists in the changelog
  local version_exists=$(echo "$changelog" | grep -E "Version $current_version|\\[$current_version\\]")
  
  if [ -z "$version_exists" ]; then
    return 0  # It's a development version
  else
    return 1  # It's a known version
  fi
}

# Function to show patch notes if version has changed
show_patch_notes_if_updated() {
  # Skip if not in interactive mode
  if [ ! -t 0 ]; then
    return
  fi
  
  # Get the last displayed version
  local last_version=""
  if [ -f "$LAST_VERSION_FILE" ]; then
    last_version=$(cat "$LAST_VERSION_FILE")
  fi
  
  # If no last version or same as current, skip
  if [ -z "$last_version" ] || [ "$last_version" = "$POK_MANAGER_VERSION" ]; then
    return
  fi
  
  # Fetch changelog
  local changelog=$(fetch_changelog)
  if [ $? -ne 0 ]; then
    return
  fi
  
  echo ""
  echo "===== WHAT'S NEW IN POK-MANAGER VERSION $POK_MANAGER_VERSION ====="
  
  # Check if this is a development branch
  if is_development_branch "$changelog" "$POK_MANAGER_VERSION"; then
    echo "This is a development version ahead of current available versions."
    echo "You've upgraded from version $last_version to $POK_MANAGER_VERSION."
  else
    # Extract patch notes between versions
    local notes=$(extract_patch_notes_between_versions "$changelog" "$last_version" "$POK_MANAGER_VERSION")
    if [ -n "$notes" ]; then
      echo -e "$notes"
    else
      echo "No specific patch notes available for the upgrade from $last_version to $POK_MANAGER_VERSION."
    fi
  fi
  
  echo ""
  
  # Update the last displayed version
  echo "$POK_MANAGER_VERSION" > "$LAST_VERSION_FILE"
  
  # Ensure proper file ownership when running as root
  if [ "$(id -u)" -eq 0 ]; then
    # Get expected ownership
    local ownership=$(get_expected_ownership)
    local expected_uid=$(echo "$ownership" | cut -d: -f1)
    local expected_gid=$(echo "$ownership" | cut -d: -f2)
    
    # Apply ownership to the file
    chown ${expected_uid}:${expected_gid} "$LAST_VERSION_FILE"
  fi
}

# Function to set beta/stable mode
set_beta_mode() {
  local mode="$1" # "beta" or "stable"
  local config_dir="${BASE_DIR}/config/POK-manager"
  local new_tag=""
  
  mkdir -p "$config_dir"
  
  if [ "$mode" = "beta" ]; then
    echo "Setting POK-manager to beta mode"
    echo "beta" > "${config_dir}/beta_mode"
    POK_MANAGER_BRANCH="beta"
    new_tag="2_1_beta"
  else
    echo "Setting POK-manager to stable mode"
    rm -f "${config_dir}/beta_mode"
    POK_MANAGER_BRANCH="stable"
    
    # Default to the new version
    local image_version="2_1"
    
    # Check if server files exist and determine ownership
    local server_files_dir="${BASE_DIR}/ServerFiles/arkserver"
    if [ -d "$server_files_dir" ]; then
      local file_ownership=$(stat -c '%u:%g' "$server_files_dir")
      
      # If files are owned by 1000:1000, use the 2_0 image for compatibility
      if [ "$file_ownership" = "1000:1000" ]; then
        image_version="2_0"
      fi
    fi
    
    new_tag="${image_version}_latest"
  fi
  
  # Update all docker-compose.yaml files to use the new image tag
  echo "Updating docker-compose files for all instances to use ${new_tag} tag..."
  
  # Find docker-compose files - check multiple locations
  
  # First, look in the Instance_* directories
  local instance_compose_files=()
  for instance_dir in "${BASE_DIR}"/Instance_*/; do
    if [ -d "$instance_dir" ]; then
      local instance_name=$(basename "$instance_dir" | sed 's/Instance_//')
      
      # Check both possible locations for the docker-compose file
      local compose_file1="${instance_dir}/docker-compose-${instance_name}.yaml"
      local compose_file2="${BASE_DIR}/docker-compose-${instance_name}.yaml"
      
      if [ -f "$compose_file1" ]; then
        instance_compose_files+=("$compose_file1")
      fi
      
      if [ -f "$compose_file2" ]; then
        instance_compose_files+=("$compose_file2")
      fi
    fi
  done
  
  # Also check for docker-compose files directly in the base directory
  for compose_file in "${BASE_DIR}"/docker-compose-*.yaml; do
    if [ -f "$compose_file" ]; then
      instance_compose_files+=("$compose_file")
    fi
  done
  
  if [ ${#instance_compose_files[@]} -eq 0 ]; then
    echo "No docker-compose files found. No updates needed."
  else
    echo "Found ${#instance_compose_files[@]} docker-compose files to update."
    
    # Update each found docker-compose file
    for compose_file in "${instance_compose_files[@]}"; do
      local instance_name=$(basename "$compose_file" | sed -E 's/docker-compose-(.*)\.yaml/\1/')
      echo "Updating docker-compose file for instance: ${instance_name}"
      
      # Use the dedicated function to update the image tag
      update_docker_compose_image_tag "$compose_file" "$new_tag"
    done
  fi
  
  echo "POK-manager is now in ${mode} mode. Docker images with tag '${new_tag}' will be used."
  
  # Provide information about PUID/PGID settings
  local legacy_puid=1000
  local legacy_pgid=1000
  
  if [ "$mode" = "beta" ]; then
    echo "Using PUID:PGID=7777:7777 for beta mode (2_1_beta image)"
  else
    # For stable mode, check which image tag version we're using
    local image_version="2_0"
    
    # Check if server files exist and determine ownership
    local server_files_dir="${BASE_DIR}/ServerFiles/arkserver"
    if [ -d "$server_files_dir" ]; then
      local file_ownership=$(stat -c '%u:%g' "$server_files_dir")
      
      # If files are NOT owned by 1000:1000, we're using 2_1_latest
      if [ "$file_ownership" != "1000:1000" ]; then
        image_version="2_1"
      fi
    fi
    
    if [ "$image_version" = "2_1" ]; then
      echo "Using PUID:PGID=7777:7777 for stable mode (2_1_latest image)"
    else
      echo "Using PUID:PGID=1000:1000 for stable mode (2_0_latest image)"
    fi
  fi
  echo "Docker Compose files will maintain their existing PUID/PGID settings for backward compatibility."
  
  echo "Please restart any running containers to apply the changes."
}

# Function to check for beta mode
check_beta_mode() {
  local config_dir="${BASE_DIR}/config/POK-manager"
  
  if [ -f "${config_dir}/beta_mode" ]; then
    POK_MANAGER_BRANCH="beta"
    return 0  # Beta mode is enabled
  else
    POK_MANAGER_BRANCH="stable"
    return 1  # Beta mode is not enabled
  fi
}

# Add the upgrade function
upgrade_pok_manager() {
  # Store the original command arguments right at the beginning
  local original_args=("$@")
  
  echo "Checking for updates to POK-manager.sh..."
  
  # Create the config directory if it doesn't exist
  mkdir -p "${BASE_DIR%/}/config/POK-manager"
  
  # Check if we have write permission to the base directory
  if [ ! -w "${BASE_DIR}" ]; then
    echo "ERROR: You don't have write permission to the base directory (${BASE_DIR})."
    echo "This is likely because the directory is owned by a different user."
    echo ""
    local dir_owner=$(stat -c '%u:%g' "${BASE_DIR}")
    echo "Current directory ownership: $dir_owner"
    echo "Your current user: $(id -un) ($(id -u):$(id -g))"
    echo ""
    echo "You have two options:"
    echo "1. Run with sudo: sudo ./POK-manager.sh -upgrade"
    echo "2. Fix the directory ownership to match your user:"
    echo "   sudo chown $(id -u):$(id -g) ${BASE_DIR}"
    echo ""
    echo "If you've migrated to the 7777:7777 user, the directory should be owned by 7777:7777."
    echo "Run: sudo chown 7777:7777 ${BASE_DIR}"
    return 1
  fi
  
  # Keep track of the script's original path
  local original_script="$0"
  
  # Create a backup name
  local safe_backup="${BASE_DIR%/}/config/POK-manager/pok-manager.backup"
  
  # Backup the current script
  cp "$original_script" "$safe_backup"
  echo "Backed up current script to $safe_backup"
  
  # Store the original command arguments for potential reuse
  local command_args_file="${BASE_DIR%/}/config/POK-manager/last_command_args"
  
  # Get the original script's permissions to maintain them
  local original_perms=$(stat -c "%a" "$original_script")
  
  # Check if a new version was downloaded during check_for_POK_updates
  local new_version_file="${BASE_DIR%/}/config/POK-manager/new_version"
  local temp_file=""
  
  # Source of the update: direct download or pre-downloaded file
  if [ -f "$new_version_file" ]; then
    echo "Using pre-downloaded update file"
    temp_file="$new_version_file"
  else
    # Determine which branch to use for updates
    local branch_name="master"
    if [ "$POK_MANAGER_BRANCH" = "beta" ]; then
      branch_name="beta"
      echo "Using beta branch for updates"
    fi
    
    # Add timestamp and random string as cache-busting parameters
    local timestamp=$(date +%s)
    local random_str=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)
    local script_url="https://raw.githubusercontent.com/Acekorneya/Ark-Survival-Ascended-Server/${branch_name}/POK-manager.sh?nocache=${timestamp}_${random_str}"
    temp_file="/tmp/POK-manager.sh.${timestamp}.tmp"
    
    # Download the new script
    local download_success=false
    if command -v wget &>/dev/null; then
      if wget -q --no-cache --no-check-certificate -O "$temp_file" "$script_url"; then
        download_success=true
      fi
    elif command -v curl &>/dev/null; then
      if curl -s -k -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" -o "$temp_file" "$script_url"; then
        download_success=true
      fi
    else
      echo "Error: Neither wget nor curl is available. Unable to download updates."
      return 1
    fi
    
    if ! [ "$download_success" = "true" ]; then
      echo "Error: Failed to download the latest script. Update aborted."
      return 1
    fi
  fi
  
  # Create a file to signal that we're in a potential rollback situation
  touch "${BASE_DIR%/}/config/POK-manager/rollback_source"
  
  # Process command arguments into a string for easy display
  local command_args=""
  if [ ${#original_args[@]} -gt 0 ]; then
    command_args="${original_args[*]}"
  fi
  
  # Store any original commands for after the update
  if [ -f "$command_args_file" ]; then
    # We already have saved command args from the check_for_POK_updates function
    echo "Command arguments were already saved for reuse after update"
  elif [ ${#original_args[@]} -gt 0 ]; then
    # Save the original command arguments to a file
    printf "%s\n" "${original_args[@]}" > "$command_args_file"
    echo "Original command saved for reuse after update"
  fi
  
  # Verify the downloaded file is good by checking for required content
  if [ "$download_success" = "true" ] && [ -s "$temp_file" ]; then
    # Make sure the downloaded file is valid by checking key elements
    if grep -q "POK_MANAGER_VERSION=" "$temp_file" && grep -q "upgrade_pok_manager" "$temp_file"; then
      # Extract new version number
      local new_version=$(grep -m 1 "POK_MANAGER_VERSION=" "$temp_file" | cut -d'"' -f2)
      
      if [ -n "$new_version" ]; then
        # Make downloaded file executable
        chmod +x "$temp_file"
        
        # Get original owner information
        local current_user=$(id -u)
        local original_owner=$(stat -c "%u:%g" "$original_script")
        local target_owner="$original_owner"
        
        # If running with sudo, use the SUDO_USER's UID:GID or fall back to PUID:PGID
        if [ "$(id -u)" -eq 0 ]; then
          if [ -n "$SUDO_USER" ]; then
            local sudo_uid=$(id -u "$SUDO_USER")
            local sudo_gid=$(id -g "$SUDO_USER")
            target_owner="${sudo_uid}:${sudo_gid}"
          elif [ -n "$PUID" ] && [ -n "$PGID" ]; then
            # If PUID/PGID are set, use them
            target_owner="${PUID}:${PGID}"
          else
            # Default to 1000:1000 (common first user) or 7777:7777 if migrated
            if [ -f "${BASE_DIR}/config/POK-manager/migration_complete" ]; then
              target_owner="7777:7777"
            else
              target_owner="1000:1000"
            fi
          fi
        fi
        
        # Replace the original script with the new one
        mv -f "$temp_file" "$original_script"
        chmod "$original_perms" "$original_script"
        
        # Ensure proper ownership - this is critical when run with sudo
        if [ "$(id -u)" -eq 0 ]; then
          echo "Setting ownership of POK-manager.sh to $target_owner"
          chown $target_owner "$original_script"
        fi
        
        # Save the new version to a file so it can be loaded on restart
        echo "$new_version" > "${BASE_DIR%/}/config/POK-manager/upgraded_version"
        
        # Create a flag file to indicate we just upgraded
        touch "${BASE_DIR%/}/config/POK-manager/just_upgraded"
        
        # Create a flag to indicate this update completed successfully
        # This will be checked by check_for_rollback to prevent unnecessary rollbacks
        touch "${BASE_DIR%/}/config/POK-manager/update_completed"
        
        # Remove the rollback flag since we've successfully updated
        rm -f "${BASE_DIR%/}/config/POK-manager/rollback_source"
        
        echo "Update successful. POK-manager.sh has been updated to version $new_version"
        echo "Restarting script to load updated version..."
        
        # Add this message:
        echo ""
        echo "----------------------------------------------------------"
        echo "NOTICE: The POK-manager has been successfully upgraded!"
        
        # Extract the stored command arguments
        local saved_args=""
        if [ -f "$command_args_file" ]; then
          saved_args=$(cat "$command_args_file")
          if [ -n "$saved_args" ]; then
            echo "Your original command will be executed with the new version."
            echo ""
            echo "Command: $0 $saved_args"
          fi
        fi
        echo "----------------------------------------------------------"
        echo ""
        
        # If running interactively, add a pause
        if [ -t 0 ]; then
          echo -n "Press Enter to continue..."
          read -r dummy
        fi
        
        # Execute the original script with any saved arguments
        if [ -f "$command_args_file" ]; then
          # Read the saved arguments line by line into an array
          mapfile -t saved_cmd_args < "$command_args_file"
          # Remove the saved args file to prevent reuse
          rm -f "$command_args_file"
          # Execute with the saved arguments
          exec "$0" "${saved_cmd_args[@]}"
        else
          # Just execute the updated script with no arguments
          exec "$0"
        fi
        
      else
        echo "Error: Could not determine version from downloaded file."
        return 1
      fi
    else
      echo "Error: Downloaded file does not appear to be a valid POK-manager.sh script."
      return 1
    fi
  else
    echo "Error: Downloaded file is too small or invalid. Update failed."
    # Only clean up the temp file if we downloaded it ourselves
    if [ "$temp_file" != "$new_version_file" ] && [ -f "$temp_file" ]; then
      rm -f "$temp_file"
    fi
    return 1
  fi
}

# Function to handle automatic rollback if script fails to run
check_for_rollback() {
  # Only check for rollbacks if both the flag file and backup file exist
  local rollback_file="${BASE_DIR%/}/config/POK-manager/rollback_source"
  local backup_file="${BASE_DIR%/}/config/POK-manager/pok-manager.backup"
  local update_completed="${BASE_DIR%/}/config/POK-manager/update_completed"
  
  # If update_completed exists, it means the previous update was successful
  # Remove the rollback flag and the update_completed flag, then continue
  if [ -f "$update_completed" ]; then
    rm -f "$rollback_file" 2>/dev/null
    rm -f "$update_completed" 2>/dev/null
    return
  fi
  
  if [ -f "$rollback_file" ] && [ -f "$backup_file" ]; then
    echo "⚠️ WARNING: Detected an incomplete update process."
    echo "Automatically restoring from backup..."
    
    # Retrieve saved command arguments if available
    local saved_args=()
    local command_args_file="${BASE_DIR%/}/config/POK-manager/last_command_args"
    if [ -f "$command_args_file" ]; then
      mapfile -t saved_args < "$command_args_file"
      echo "Found saved command arguments, will reuse them after restore"
    fi
    
    # Perform the actual restore
    if cp "$backup_file" "$0"; then
      chmod +x "$0"
      echo "✅ Rollback complete. The script has been restored from backup."
      
      # Clean up the rollback file
      rm -f "$rollback_file"
      
      # Clean up other update-related files for a fresh start
      rm -f "${BASE_DIR%/}/config/POK-manager/upgraded_version" 2>/dev/null
      rm -f "${BASE_DIR%/}/config/POK-manager/just_upgraded" 2>/dev/null
      rm -f "${BASE_DIR%/}/config/POK-manager/update_completed" 2>/dev/null
      
      # Re-execute the script with either saved or original arguments
      if [ ${#saved_args[@]} -gt 0 ]; then
        exec "$0" "${saved_args[@]}"
      else
        exec "$0" "$@"
      fi
    else
      echo "❌ Failed to restore from backup. Please try manually:"
      echo "sudo ./POK-manager.sh -force-restore"
    fi
  fi
}

# Function to force restore from backup
force_restore_from_backup() {
  local backup_path="${BASE_DIR%/}/config/POK-manager/pok-manager.backup"
  
  if [ -f "$backup_path" ]; then
    echo "Restoring POK-manager.sh from backup..."
    
    # Copy the backup file to the original script location
    if cp "$backup_path" "$0"; then
      chmod +x "$0"
      echo "✅ Restoration complete. The script has been restored to the backup version."
      
      # Clear any update flags or temporary files to start fresh
      rm -f "${BASE_DIR%/}/config/POK-manager/upgraded_version" 2>/dev/null
      rm -f "${BASE_DIR%/}/config/POK-manager/just_upgraded" 2>/dev/null
      rm -f "${BASE_DIR%/}/config/POK-manager/rollback_source" 2>/dev/null
      rm -f "${BASE_DIR%/}/config/POK-manager/branch_switched" 2>/dev/null
      
      # Read the version from the restored script for display
      local restored_version=$(grep -m 1 "POK_MANAGER_VERSION=" "$0" | cut -d'"' -f2)
      if [ -n "$restored_version" ]; then
        echo "Restored to version: $restored_version"
      fi
      
      echo "You can now run the script normally."
    else
      echo "❌ ERROR: Failed to copy backup file. You may need to run with sudo:"
      echo "sudo ./POK-manager.sh -force-restore"
    fi
  else
    echo "❌ ERROR: No backup file found at $backup_path"
    echo "Cannot restore the script. You may need to re-download it from GitHub."
  fi
}

# Function to update server files and Docker images (but not the script itself)
# This is called by the -update command
update_server_files_and_docker() {
  echo "===== CHECKING FOR UPDATES ====="
  echo "----- Checking for POK-manager.sh script updates -----"
  local update_info_file="${BASE_DIR}/config/POK-manager/update_available"
  
  # Check for POK-manager.sh updates without automatic installation
  check_for_POK_updates "force"
  
  # If updates are available, notify the user
  if [ -f "$update_info_file" ]; then
    local new_version=$(cat "$update_info_file")
    echo "********************************************************************"
    if [ "$new_version" != "unknown" ]; then
      echo "* A newer version of POK-manager.sh is available: $new_version (current: $POK_MANAGER_VERSION)"
    else
      echo "* An update to POK-manager.sh is available"
    fi
    echo "* Run './POK-manager.sh -upgrade' to upgrade the script (this won't happen automatically)"
    echo "* Note: If an update fails, you can restore the previous version with:"
    echo "*       './POK-manager.sh -force-restore' or './POK-manager.sh -emergency-restore'"
    echo "********************************************************************"
  else
    echo "POK-manager.sh script is up to date"
  fi

  echo "----- Checking for ARK server files & Docker image updates -----"
  echo "Note: This WILL update server files and Docker images, but NOT the script itself"

  # Pull the latest Docker image to ensure we have the latest version
  local image_tag=$(get_docker_image_tag "")
  echo "Using Docker image tag: ${image_tag}"
  pull_docker_image ""

  # Create a temporary container for update process
  echo "Creating a temporary container for update..."
  local temp_container_id=""
  local instance_for_update="pok_update_temp_container"
  
  # Create environment variables array for the container
  local env_vars=(
    "-e TZ=UTC"
    "-e INSTANCE_NAME=pok_update_temp"
  )
  
  # Check if user is in docker group or is root to avoid using sudo
  if groups | grep -q '\bdocker\b' || [ "$(id -u)" -eq 0 ]; then
    # User is in docker group or is root, no need for sudo
    temp_container_id=$(docker run -d --rm \
      -v "${BASE_DIR%/}/ServerFiles/arkserver:/home/pok/arkserver" \
      ${env_vars[@]} \
      --name "$instance_for_update" \
      "acekorneya/asa_server:${image_tag}" \
      sleep infinity)
  else
    # User is not in docker group and not root, need sudo
    temp_container_id=$(sudo docker run -d --rm \
      -v "${BASE_DIR%/}/ServerFiles/arkserver:/home/pok/arkserver" \
      ${env_vars[@]} \
      --name "$instance_for_update" \
      "acekorneya/asa_server:${image_tag}" \
      sleep infinity)
  fi
  
  if [ -z "$temp_container_id" ]; then
    echo "Failed to create temporary container for update. Aborting."
    exit 1
  fi
  
  echo "Temporary container created with ID: $temp_container_id"
  echo "Waiting for container initialization..."
  sleep 5  # Allow container to initialize
  
  # Initialize the container environment
  echo "Initializing container environment..."
  if groups | grep -q '\bdocker\b' || [ "$(id -u)" -eq 0 ]; then
    docker exec "$instance_for_update" bash -c 'mkdir -p /home/pok/arkserver/ShooterGame/Binaries/Win64/logs' || true
    docker exec "$instance_for_update" bash -c 'mkdir -p /home/pok/arkserver/ShooterGame/Saved/Config/WindowsServer' || true
    docker exec "$instance_for_update" bash -c 'mkdir -p /home/pok/arkserver/ShooterGame/Saved/SavedArks' || true
  else
    sudo docker exec "$instance_for_update" bash -c 'mkdir -p /home/pok/arkserver/ShooterGame/Binaries/Win64/logs' || true
    sudo docker exec "$instance_for_update" bash -c 'mkdir -p /home/pok/arkserver/ShooterGame/Saved/Config/WindowsServer' || true
    sudo docker exec "$instance_for_update" bash -c 'mkdir -p /home/pok/arkserver/ShooterGame/Saved/SavedArks' || true
  fi

  # Check current and latest build IDs
  echo "Checking for server updates..."
  local current_build_id=$(get_build_id_from_acf)
  local latest_build_id=$(get_current_build_id)
  
  echo "Current build ID: $current_build_id"
  echo "Latest build ID:  $latest_build_id"
  
  # Function to handle the SteamCMD update with retries
  perform_steamcmd_update() {
    local max_retries=3
    local retry_count=0
    local success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
      retry_count=$((retry_count + 1))
      echo "SteamCMD update attempt $retry_count of $max_retries..."
      
      # Use docker directly if user is in docker group or is root
      if groups | grep -q '\bdocker\b' || [ "$(id -u)" -eq 0 ]; then
        if docker exec "$instance_for_update" /opt/steamcmd/steamcmd.sh +force_install_dir "/home/pok/arkserver" +login anonymous +app_update 2430930 +quit; then
          echo "SteamCMD update completed successfully inside container."
          
          # Make sure the appmanifest file is properly copied
          if docker exec "$instance_for_update" bash -c '[ -f "/home/pok/arkserver/steamapps/appmanifest_2430930.acf" ] && cp "/home/pok/arkserver/steamapps/appmanifest_2430930.acf" "/home/pok/arkserver/"'; then
            echo "Copied appmanifest_2430930.acf to the correct location inside container."
          else
            echo "Warning: appmanifest_2430930.acf not found in steamapps directory or could not be copied."
          fi
          
          success=true
        else
          echo "SteamCMD update failed. Attempt $retry_count of $max_retries."
          if [ $retry_count -lt $max_retries ]; then
            echo "Retrying in 10 seconds..."
            sleep 10
          fi
        fi
      else
        if sudo docker exec "$instance_for_update" /opt/steamcmd/steamcmd.sh +force_install_dir "/home/pok/arkserver" +login anonymous +app_update 2430930 +quit; then
          echo "SteamCMD update completed successfully inside container."
          
          # Make sure the appmanifest file is properly copied
          if sudo docker exec "$instance_for_update" bash -c '[ -f "/home/pok/arkserver/steamapps/appmanifest_2430930.acf" ] && cp "/home/pok/arkserver/steamapps/appmanifest_2430930.acf" "/home/pok/arkserver/"'; then
            echo "Copied appmanifest_2430930.acf to the correct location inside container."
          else
            echo "Warning: appmanifest_2430930.acf not found in steamapps directory or could not be copied."
          fi
          
          success=true
        else
          echo "SteamCMD update failed. Attempt $retry_count of $max_retries."
          if [ $retry_count -lt $max_retries ]; then
            echo "Retrying in 10 seconds..."
            sleep 10
          fi
        fi
      fi
    done
    
    return $([ "$success" = true ] && echo 0 || echo 1)
  }
  
  # Check if the server files are installed or need update
  if [ ! -f "${BASE_DIR%/}/ServerFiles/arkserver/appmanifest_2430930.acf" ]; then
    echo "---- ARK server files not found. Installing server files using SteamCMD -----"
    
    if perform_steamcmd_update; then
      echo "----- ARK server files installed successfully -----"
    else
      echo "Failed to install ARK server files after multiple attempts. Please check the logs for more information."
    fi
  elif [ "$current_build_id" != "$latest_build_id" ]; then
    echo "---- New server build available: $latest_build_id (current: $current_build_id) -----"
    
    if perform_steamcmd_update; then
      # Check if the server files were updated successfully
      local updated_build_id=$(get_build_id_from_acf)
      echo "Updated build ID: $updated_build_id"
      if [ "$updated_build_id" == "$latest_build_id" ]; then
        echo "----- ARK server files updated successfully to build id: $latest_build_id -----"
      else
        echo "----- Server files were updated but build ID doesn't match expected ($updated_build_id vs $latest_build_id) -----"
        echo "----- This could be due to a delay in Steam database updates or other issues -----"
      fi
    else
      echo "Failed to update ARK server files after multiple attempts. Please check the logs for more information."
    fi
  else
    echo "----- ARK server files are already up to date with build id: $current_build_id -----"
  fi
  
  # Clean up temporary container
  echo "Removing temporary update container..."
  if groups | grep -q '\bdocker\b' || [ "$(id -u)" -eq 0 ]; then
    docker rm -f "$instance_for_update" > /dev/null 2>&1 || true
  else
    sudo docker rm -f "$instance_for_update" > /dev/null 2>&1 || true
  fi

  echo "----- Update process completed -----"
}

# Function to help users migrate file ownership
migrate_file_ownership() {
  echo "===== File Ownership Migration Tool ====="
  echo "This tool will help you migrate your file ownership from 1000:1000 to 7777:7777"
  echo "for compatibility with the new default Docker image."
  echo ""
  echo "⚠️ WARNING: This process will:"
  echo "  1. STOP ALL RUNNING SERVER INSTANCES"
  echo "  2. Change ownership of all your server files"
  echo "  3. Update your servers to use the newer 2.1 Docker image"
  echo ""
  echo "Don't worry - this is a simple process to improve your server's compatibility,"
  echo "and we'll guide you through each step!"
  echo ""
  
  # Check if we have sudo access
  if ! is_sudo; then
    echo "This operation requires sudo privileges."
    echo "Please run this command with sudo: sudo ./POK-manager.sh -migrate"
    
    # Add a more detailed explanation about why sudo is needed and what will happen
    echo ""
    echo "IMPORTANT NOTE ABOUT MIGRATION:"
    echo "After migration, your files will be owned by UID:GID 7777:7777 to match the container."
    echo "If you don't have a user with UID 7777 on your system, you'll be prompted to create one."
    echo "Without a matching user, you'll need to use sudo to run the script after migration."
    return 1
  fi
  
  # Check for running instances
  local running_instances=($(list_running_instances))
  if [ ${#running_instances[@]} -gt 0 ]; then
    echo "The following server instances are currently running:"
    for instance in "${running_instances[@]}"; do
      echo "  - $instance"
    done
    echo ""
    echo "These instances need to be stopped before migration can proceed."
    read -p "Stop all running instances now? (Y/n): " stop_confirm
    if [[ "$stop_confirm" =~ ^[Nn]$ ]]; then
      echo "Migration cancelled. Please stop all instances manually and try again."
      return 1
    fi
    
    echo "Stopping all running instances..."
    # Use the same approach as perform_action_on_all_instances for stopping
    for instance in "${running_instances[@]}"; do
      echo "Stopping instance: $instance"
      # Get the docker compose file path
      local docker_compose_file="${BASE_DIR}/Instance_${instance}/docker-compose-${instance}.yaml"
      
      # If the compose file exists, use docker-compose down
      if [ -f "$docker_compose_file" ]; then
        get_docker_compose_cmd
        if is_sudo; then
          $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down
        else
          sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down
        fi
      else
        # Otherwise use docker stop
        if is_sudo; then
          docker stop -t 30 "asa_${instance}"
        else
          sudo docker stop -t 30 "asa_${instance}"
        fi
      fi
      echo "Instance ${instance} stopped successfully."
    done
    
    echo "✅ All instances have been stopped successfully."
    echo ""
  else
    echo "No running instances detected. Proceeding with migration."
    echo ""
  fi
  
  # First list the specific directories that we know need to be changed
  # (for better user information and backwards compatibility)
  local dirs_to_change=()
  
  # Check if ServerFiles exists
  if [ -d "${BASE_DIR}/ServerFiles" ]; then
    dirs_to_change+=("${BASE_DIR}/ServerFiles")
  fi
  
  # Check for instance directories
  for instance_dir in "${BASE_DIR}"/Instance_*/; do
    if [ -d "$instance_dir" ]; then
      dirs_to_change+=("$instance_dir")
      
      # Create API_Logs directory for each instance if it doesn't exist
      local api_logs_dir="${instance_dir}/API_Logs"
      if [ ! -d "$api_logs_dir" ]; then
        echo "Creating API_Logs directory for instance: $(basename "$instance_dir")"
        mkdir -p "$api_logs_dir"
      fi
    fi
  done
  
  # Check for Cluster directory
  if [ -d "${BASE_DIR}/Cluster" ]; then
    dirs_to_change+=("${BASE_DIR}/Cluster")
  fi
  
  # Ensure config/POK-manager directory exists and is included
  mkdir -p "${BASE_DIR}/config/POK-manager"
  dirs_to_change+=("${BASE_DIR}/config/POK-manager")
  
  # Show the user which directories will be changed
  echo "The following directories will have their ownership changed to 7777:7777:"
  for dir in "${dirs_to_change[@]}"; do
    echo "  - $dir"
  done
  
  # Additional directories that will be changed
  echo -e "\nAdditionally, all other files and folders in the base directory will have their ownership changed."
  echo "The base directory (${BASE_DIR}) will also have its ownership changed to 7777:7777."
  
  # Ask for confirmation
  read -p "Proceed with migration? (Y/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Migration cancelled."
    return 1
  fi
  
  # Change ownership of each directory
  echo "Changing file ownership to 7777:7777..."
  
  # First process the specific directories we listed
  for dir in "${dirs_to_change[@]}"; do
    echo "Processing: $dir"
    chown -R 7777:7777 "$dir"
  done
  
  # Now process all other files and directories in BASE_DIR except POK-manager.sh
  echo "Processing remaining files and directories in ${BASE_DIR}"
  
  # Find and change ownership of all other files/directories in BASE_DIR except POK-manager.sh
  find "${BASE_DIR}" -maxdepth 1 -not -name "POK-manager.sh" -not -path "${BASE_DIR}" | while read item; do
    if [[ ! " ${dirs_to_change[@]} " =~ " ${item} " ]]; then
      echo "Processing: $item"
      chown -R 7777:7777 "$item"
    fi
  done
  
  # IMPORTANT: Change ownership of the BASE_DIR itself
  echo "Changing ownership of base directory: ${BASE_DIR}"
  chown 7777:7777 "${BASE_DIR}"
  
  # Ensure POK-manager.sh has correct ownership and permissions
  echo "Setting correct permissions for POK-manager.sh"
  chown 7777:7777 "${BASE_DIR}/POK-manager.sh"
  chmod 755 "${BASE_DIR}/POK-manager.sh"
  
  # Update docker-compose files to include API_Logs volume
  echo "Updating docker-compose files to include API_Logs volume..."
  for instance_dir in "${BASE_DIR}"/Instance_*/; do
    if [ -d "$instance_dir" ]; then
      local instance_name=$(basename "$instance_dir" | sed 's/Instance_//')
      local docker_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
      local api_logs_dir="${instance_dir}/API_Logs"
      
      # Ensure API_Logs directory exists and has proper ownership
      if [ ! -d "$api_logs_dir" ]; then
        echo "Creating API_Logs directory for instance: $instance_name"
        mkdir -p "$api_logs_dir"
      fi
      
      # Set proper ownership on the API_Logs directory (7777:7777 during migration)
      echo "Setting proper ownership on API_Logs directory"
      chown -R 7777:7777 "$api_logs_dir"
      chmod 755 "$api_logs_dir"
      
      if [ -f "$docker_compose_file" ]; then
        # Check if the API_Logs volume is already in the docker-compose file
        if ! grep -q "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file"; then
          echo "Adding API_Logs volume mapping to docker-compose file for instance: $instance_name"
          
          # Create a temporary file
          local tmp_file="${docker_compose_file}.tmp"
          
          # Get absolute path for the instance directory
          local abs_instance_dir=$(realpath "$instance_dir")
          
          # Use sed to add the API_Logs volume after the Saved volume with absolute path
          sed -e "/Saved:.*ShooterGame\/Saved/ a\\      - \"$abs_instance_dir/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs\"" "$docker_compose_file" > "$tmp_file"
          
          # Replace the original file with the updated one
          mv -f "$tmp_file" "$docker_compose_file"
          chown 7777:7777 "$docker_compose_file"
        fi
      fi
    fi
  done
  
  # Create a flag file to indicate migration has completed successfully
  touch "${BASE_DIR}/config/POK-manager/migration_complete"
  chown 7777:7777 "${BASE_DIR}/config/POK-manager/migration_complete"
  
  echo "✅ File ownership migration complete."
  echo ""
  echo "Your files are now compatible with the 2_1_latest Docker image."
  
  # Set to beta mode to ensure we use the new 2.1 image
  set_beta_mode "stable"
  echo "Updated all docker-compose files to use the 2_1_latest image."
  
  # Check if a user with UID 7777 already exists
  local existing_user=$(getent passwd 7777 | cut -d: -f1)
  
  if [ -z "$existing_user" ]; then
    echo ""
    echo "⚠️ IMPORTANT: No user with UID 7777 was found on this system."
    echo "This means you'll need to run this script with sudo each time, which is not ideal."
    echo ""
    echo "Would you like to create a dedicated user with UID/GID 7777 for managing your server?"
    echo "This will allow you to run the script without sudo after the migration."
    echo ""
    read -p "Create a user with UID/GID 7777 now? (y/N): " create_user
    
    if [[ "$create_user" =~ ^[Yy]$ ]]; then
      # Get username from user
      echo ""
      read -p "Enter username for the new user (default: pokuser): " new_username
      new_username=${new_username:-pokuser}
      
      echo "Creating group with GID 7777..."
      groupadd -g 7777 "$new_username" || { echo "Failed to create group. You may need to manually create a user with UID/GID 7777."; exit 1; }
      
      echo "Creating user with UID 7777..."
      useradd -u 7777 -g 7777 -m -s /bin/bash "$new_username" || { echo "Failed to create user. You may need to manually create a user with UID/GID 7777."; exit 1; }
      
      # Add the new user to the sudo group
      echo "Adding user to sudo group for Docker management..."
      # Try adding to sudo group first (most distros)
      if getent group sudo >/dev/null; then
        usermod -aG sudo "$new_username" && echo "✅ Added user to the sudo group successfully"
      # If sudo group doesn't exist, try wheel group (some distros like CentOS)
      elif getent group wheel >/dev/null; then
        usermod -aG wheel "$new_username" && echo "✅ Added user to the wheel group successfully"
      # If neither exists, try admin group (some Debian-based distros)
      elif getent group admin >/dev/null; then
        usermod -aG admin "$new_username" && echo "✅ Added user to the admin group successfully"
      # If no standard sudo group is found, create a sudoers entry directly
      else
        echo "$new_username ALL=(ALL) ALL" > /etc/sudoers.d/"$new_username"
        chmod 440 /etc/sudoers.d/"$new_username"
        echo "✅ Created a custom sudoers entry for the user"
      fi
      
      # Also add the user to the docker group if it exists
      if getent group docker >/dev/null; then
        usermod -aG docker "$new_username" && echo "✅ Added user to the docker group successfully"
      fi
      
      if id "$new_username" &>/dev/null; then
        # Prompt for password
        echo ""
        echo "Please set a password for the new user '$new_username':"
        
        # Use passwd to set the password interactively
        passwd "$new_username"
        
        if [ $? -eq 0 ]; then
          echo ""
          echo "✅ User '$new_username' created successfully with UID/GID 7777:7777 and password set"
          echo "This user has been added to the sudo group and can run sudo commands."
          echo "You can now switch to this user to manage your server:"
          echo "  su - $new_username"
          echo "  cd $(realpath ${BASE_DIR}) && ./POK-manager.sh"
          
          # Also show the sudo option
          echo "Or with sudo:"
          echo "  sudo su - $new_username"
          echo "  cd $(realpath ${BASE_DIR}) && ./POK-manager.sh"
          
          echo ""
          echo "NOTE: You may need to log out and log back in for the group changes to take effect."
        else
          echo ""
          echo "⚠️ User created but password setting failed. You can set it manually with:"
          echo "  sudo passwd $new_username"
        fi
      fi
    else
      echo ""
      echo "⚠️ No user created. You'll need to run this script with sudo from now on,"
      echo "or manually create a user with UID/GID 7777:7777 later."
      echo ""
      echo "To manually create a user with these IDs and sudo privileges, you can run:"
      echo "  sudo groupadd -g 7777 pokuser"
      echo "  sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser"
      echo "  sudo usermod -aG sudo pokuser  # Add to sudo group"
      echo "  sudo passwd pokuser            # Set a password"
    fi
  else
    echo ""
    echo "A user with UID 7777 already exists: $existing_user"
    
    # Check if the existing user is already in the sudo group
    if groups "$existing_user" | grep -qE '\b(sudo|wheel|admin)\b'; then
      echo "User $existing_user is already in a sudo-capable group."
    else
      echo "User $existing_user is not in a sudo-capable group."
      read -p "Add $existing_user to sudo group? (y/N): " add_to_sudo
      
      if [[ "$add_to_sudo" =~ ^[Yy]$ ]]; then
        # Try adding to sudo group first (most distros)
        if getent group sudo >/dev/null; then
          usermod -aG sudo "$existing_user" && echo "✅ Added user to the sudo group successfully"
        # If sudo group doesn't exist, try wheel group (some distros like CentOS)
        elif getent group wheel >/dev/null; then
          usermod -aG wheel "$existing_user" && echo "✅ Added user to the wheel group successfully"
        # If neither exists, try admin group (some Debian-based distros)
        elif getent group admin >/dev/null; then
          usermod -aG admin "$existing_user" && echo "✅ Added user to the admin group successfully"
        # If no standard sudo group is found, create a sudoers entry directly
        else
          echo "$existing_user ALL=(ALL) ALL" > /etc/sudoers.d/"$existing_user"
          chmod 440 /etc/sudoers.d/"$existing_user"
          echo "✅ Created a custom sudoers entry for the user"
        fi
        
        echo "NOTE: You may need to log out and log back in for the group changes to take effect."
      fi
    fi
    
    # Check if the existing user is already in the docker group
    if groups "$existing_user" | grep -q '\bdocker\b'; then
      echo "User $existing_user is already in the docker group."
    else
      echo "User $existing_user is not in the docker group."
      read -p "Add $existing_user to docker group? (y/N): " add_to_docker
      
      if [[ "$add_to_docker" =~ ^[Yy]$ ]]; then
        if getent group docker >/dev/null; then
          usermod -aG docker "$existing_user" && echo "✅ Added user to the docker group successfully"
          echo "NOTE: You may need to log out and log back in for the group changes to take effect."
        else
          echo "Docker group does not exist. Make sure Docker is installed correctly."
        fi
      fi
    fi
    
    echo "You can switch to this user to manage your server:"
    echo "  sudo su - $existing_user"
    echo "  cd $(realpath ${BASE_DIR}) && ./POK-manager.sh"
  fi
  
  # If there were previously running instances, ask if they should be restarted
  if [ ${#running_instances[@]} -gt 0 ]; then
    echo ""
    echo "The following server instances were stopped during migration:"
    for instance in "${running_instances[@]}"; do
      echo "  - $instance"
    done
    
    echo ""
    read -p "Would you like to restart these servers now with the new 2.1 image? (Y/n): " restart_servers
    
    if [[ ! "$restart_servers" =~ ^[Nn]$ ]]; then
      echo "Restarting servers with the new 2.1 image..."
      for instance in "${running_instances[@]}"; do
        echo "Starting instance: $instance"
        start_instance "$instance"
      done
      echo "✅ All servers have been restarted with the new 2.1 image."
    else
      echo "Servers have not been restarted. You can start them later with:"
      echo "  ./POK-manager.sh -start -all"
      echo "or start individual servers with:"
      echo "  ./POK-manager.sh -start <instance_name>"
    fi
  fi
  
  echo ""
  echo "✨ Migration complete! Your ARK server is now using the new 2.1 image with 7777:7777 permissions. ✨"
  echo ""
  echo "Note: If you want to go back to the 1000:1000 ownership, you can run:"
  echo "sudo chown -R 1000:1000 ${BASE_DIR}"
}
# Function to check for post-migration permission issues
check_post_migration_permissions() {
  local command_args="$1"
  
  # Check if migration flag exists
  if [ -f "${BASE_DIR}/config/POK-manager/migration_complete" ]; then
    # Check if files have been reverted to legacy 1000:1000 ownership
    local legacy_uid=1000
    local legacy_gid=1000
    local reverted_to_legacy=true
    
    # Check ServerFiles ownership
    if [ -d "${BASE_DIR}/ServerFiles/arkserver" ]; then
      local server_ownership="$(stat -c '%u:%g' ${BASE_DIR}/ServerFiles/arkserver)"
      if [ "$server_ownership" != "${legacy_uid}:${legacy_gid}" ]; then
        reverted_to_legacy=false
      fi
    else
      # If ServerFiles doesn't exist, can't determine if reverted
      reverted_to_legacy=false
    fi
    
    # Check config directory ownership if still potentially reverted
    if [ "$reverted_to_legacy" = "true" ] && [ -d "${BASE_DIR}/config/POK-manager" ]; then
      local config_ownership="$(stat -c '%u:%g' ${BASE_DIR}/config/POK-manager)"
      if [ "$config_ownership" != "${legacy_uid}:${legacy_gid}" ]; then
        reverted_to_legacy=false
      fi
    fi
    
    # If all critical directories are back to legacy ownership, remove the migration flag
    if [ "$reverted_to_legacy" = "true" ]; then
      echo "Detected that files have been reverted to legacy ownership (1000:1000)."
      echo "Removing migration flag to prevent permission warnings."
      rm -f "${BASE_DIR}/config/POK-manager/migration_complete"
      echo ""
    fi
  fi
  
  # Only run permission checks if we're not root and migration has been completed
  if [ "$(id -u)" -ne 0 ] && [ -f "${BASE_DIR}/config/POK-manager/migration_complete" ]; then
    # Check if server files exist
    if [ -d "${BASE_DIR}/ServerFiles/arkserver" ]; then
      local dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/ServerFiles/arkserver)"
      local dir_uid=$(echo "$dir_ownership" | cut -d: -f1)
      local dir_gid=$(echo "$dir_ownership" | cut -d: -f2)
      local current_uid=$(id -u)
      local current_gid=$(id -g)
      
      # Only show error if there's an actual permission mismatch
      if [ "$dir_uid" -ne "$current_uid" ] || [ "$dir_gid" -ne "$current_gid" ]; then
        echo ""
        echo "⚠️ PERMISSION MISMATCH DETECTED ⚠️"
        echo "Your server files are owned by UID:GID ${dir_uid}:${dir_gid},"
        echo "but you're running this script as user '$(id -un)' with UID:GID ${current_uid}:${current_gid}."
        echo ""
        echo "This will cause permission errors. You have two options:"
        echo ""
        echo "1. Run with sudo (easiest temporary solution):"
        echo "   sudo ./POK-manager.sh $command_args"
        echo ""
        
        # Check if a user with the directory's UID exists
        local dir_user=$(getent passwd "$dir_uid" | cut -d: -f1 2>/dev/null)
        if [ -n "$dir_user" ]; then
          echo "2. Switch to the user with UID ${dir_uid} (recommended):"
          echo "   sudo su - $dir_user"
          echo "   cd $(pwd) && ./POK-manager.sh $command_args"
        else
          echo "2. Consider creating a user with UID:GID ${dir_uid}:${dir_gid} to match file ownership"
          echo "   Or change file ownership to match your current user:"
          echo "   sudo chown -R ${current_uid}:${current_gid} ${BASE_DIR}"
        fi
        echo ""
        # Exit with status code 1 to indicate an error
        exit 1
      fi
    fi
    
    # Also verify if config directory permissions are correct
    if [ -d "${BASE_DIR}/config/POK-manager" ]; then
      local config_dir_ownership="$(stat -c '%u:%g' ${BASE_DIR}/config/POK-manager)"
      local config_dir_uid=$(echo "$config_dir_ownership" | cut -d: -f1)
      local config_dir_gid=$(echo "$config_dir_ownership" | cut -d: -f2)
      local current_uid=$(id -u)
      local current_gid=$(id -g)
      
      # Only show error if there's an actual permission mismatch
      if [ "$config_dir_uid" -ne "$current_uid" ] || [ "$config_dir_gid" -ne "$current_gid" ]; then
        echo ""
        echo "⚠️ PERMISSION MISMATCH DETECTED ⚠️"
        echo "Your config directory is owned by UID:GID ${config_dir_uid}:${config_dir_gid},"
        echo "but you're running this script as user '$(id -un)' with UID:GID ${current_uid}:${current_gid}."
        echo ""
        echo "This will cause permission errors. You have two options:"
        echo ""
        echo "1. Run with sudo (easiest temporary solution):"
        echo "   sudo ./POK-manager.sh $command_args"
        echo ""
        
        # Check if a user with the config directory's UID exists
        local dir_user=$(getent passwd "$config_dir_uid" | cut -d: -f1 2>/dev/null)
        if [ -n "$dir_user" ]; then
          echo "2. Switch to the user with UID ${config_dir_uid} (recommended):"
          echo "   sudo su - $dir_user"
          echo "   cd $(pwd) && ./POK-manager.sh $command_args"
        else
          echo "2. Consider creating a user with UID:GID ${config_dir_uid}:${config_dir_gid} to match file ownership"
          echo "   Or change config directory ownership to match your current user:"
          echo "   sudo chown -R ${current_uid}:${current_gid} ${BASE_DIR}/config"
        fi
        echo ""
        # Exit with status code 1 to indicate an error
        exit 1
      fi
    fi
  fi
}

# Function to check if POK-manager.sh has permission issues
check_script_permissions() {
  local script_path="$(realpath "$0")"
  
  # Check if script is executable
  if [ ! -x "$script_path" ]; then
    echo "⚠️ WARNING: POK-manager.sh is not executable!"
    echo "This will cause issues running commands. Please fix with:"
    echo "sudo chmod +x \"$script_path\""
    echo "Then try running your command again."
    return 1
  fi
  
  # Check if script is owned by root but running as non-root
  local script_owner="$(stat -c '%u:%g' "$script_path")"
  if [ "$script_owner" = "0:0" ] && [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ WARNING: POK-manager.sh is owned by root, but you're running as $(id -un)"
    echo "This will cause permission issues. Please fix with:"
    echo "sudo ./POK-manager.sh -fix"
    echo "Then try running your command again."
    return 1
  fi
  
  # Check if script has the correct PUID/PGID matching the config files
  local expected_owner=$(get_expected_ownership)
  local expected_uid=$(echo "$expected_owner" | cut -d: -f1)
  local expected_gid=$(echo "$expected_owner" | cut -d: -f2)
  local script_uid=$(echo "$script_owner" | cut -d: -f1)
  local script_gid=$(echo "$script_owner" | cut -d: -f2)
  
  # Skip this check if running as root (as we'll fix it in the -fix command)
  if [ "$(id -u)" -ne 0 ] && [ "$script_uid" != "$expected_uid" -o "$script_gid" != "$expected_gid" ]; then
    echo "⚠️ WARNING: POK-manager.sh has incorrect ownership!"
    echo "Current ownership: $script_uid:$script_gid, Expected: $expected_uid:$expected_gid"
    echo "This may cause permission issues. Please fix with:"
    echo "sudo ./POK-manager.sh -fix"
    echo "Then try running your command again."
    return 1
  fi
  
  return 0
}

main() {
  # Store the original command arguments right at the beginning
  local original_args=("$@")
  
  # Force check and fix for script permissions if running with sudo
  if [ "$(id -u)" -eq 0 ]; then
    local is_fix_command=false
    
    # Check if this is a -fix command
    for arg in "$@"; do
      if [ "$arg" = "-fix" ]; then
        is_fix_command=true
        break
      fi
    done
    
    # If not already fixing, check and fix script ownership immediately
    if [ "$is_fix_command" = "false" ]; then
      # Get the expected ownership
      local ownership=$(get_expected_ownership)
      local expected_uid=$(echo "$ownership" | cut -d: -f1)
      local expected_gid=$(echo "$ownership" | cut -d: -f2)
      local script_path="$(realpath "$0")"
      local script_owner="$(stat -c '%u:%g' "$script_path")"
      local script_uid=$(echo "$script_owner" | cut -d: -f1)
      local script_gid=$(echo "$script_owner" | cut -d: -f2)
      
      if [ "$script_uid" != "$expected_uid" ] || [ "$script_gid" != "$expected_gid" ]; then
        echo "Auto-fixing script permissions to $expected_uid:$expected_gid..."
        chown $expected_uid:$expected_gid "$script_path"
      fi
    fi
  fi
  
  # Check script permissions first
  check_script_permissions || {
    # If critical permission issues exist, ask if user wants to auto-fix
    if [ -t 0 ] && [ "$(id -u)" -ne 0 ]; then
      echo ""
      echo -n "Would you like to attempt to fix permissions with sudo? (y/n): "
      read -r fix_response
      if [[ "$fix_response" =~ ^[Yy]$ ]]; then
        echo "Running sudo ./POK-manager.sh -fix to fix permissions..."
        sudo "$0" -fix
        echo "Permission fix completed. Please try your command again."
        exit 0
      fi
    fi
  }
  
  # Check for updates before anything else
  check_for_POK_updates "${original_args[@]}"
  
  # Display the POK-Manager logo
  display_logo
  
  # Check if docker-compose files have paths that need updating
  check_volume_paths
  
  # Show patch notes if we've upgraded to a new version
  # This will only display patch notes once after an update and track the last displayed version
  show_patch_notes_if_updated
  
  # Check for saved command arguments from a previous run
  local command_args_file="${BASE_DIR%/}/config/POK-manager/last_command_args"
  if [ -f "$command_args_file" ] && [ "$#" -eq 0 ]; then
    # Only use saved args if no arguments were provided to the current execution
    local saved_args=()
    mapfile -t saved_args < "$command_args_file"
    if [ ${#saved_args[@]} -gt 0 ]; then
      echo "Reusing your previous command: ${saved_args[*]}"
      # Remove the file to prevent reuse in future runs
      rm -f "$command_args_file"
      # Execute with the saved arguments
      exec "$0" "${saved_args[@]}"
      # This line shouldn't be reached, but just in case
      exit 0
    fi
  fi
  
  # Extract the command portion without PUID/PGID
  local command_args=""
  
  # Skip the script name in $0
  for arg in "$@"; do
    command_args="${command_args} ${arg}"
  done
  
  # Remove leading space
  command_args="${command_args# }"
  
  # Ensure we're always using the correct version number from the script file itself
  # This ensures consistency even after upgrades
  local script_version=$(grep -m 1 "POK_MANAGER_VERSION=" "$0" | cut -d'"' -f2)
  if [ -n "$script_version" ]; then
    # Update the global variable to ensure consistency
    POK_MANAGER_VERSION="$script_version"
  fi
  
  # Check if we have a stored upgraded version from a recent upgrade
  local upgraded_version_file="${BASE_DIR%/}/config/POK-manager/upgraded_version"
  if [ -f "$upgraded_version_file" ]; then
    local upgraded_version=$(cat "$upgraded_version_file")
    if [ -n "$upgraded_version" ]; then
      # Use the upgraded version instead of what's in the script
      POK_MANAGER_VERSION="$upgraded_version"
      # Remove the file so we don't keep using it
      rm -f "$upgraded_version_file"
    fi
  fi
  
  # First, check if we need to perform an emergency rollback
  # This needs to be done before any other operations
  if [[ "$1" == "-emergency-restore" ]]; then
    echo "Emergency restore requested. Attempting to recover from backup..."
    local backup_path="${BASE_DIR%/}/config/POK-manager/pok-manager.backup"
    if [ -f "$backup_path" ]; then
      cp "$backup_path" "$0"
      chmod +x "$0"
      echo "✅ Emergency restoration complete. The script has been restored to the backup version."
      echo "You can now run the script normally."
      exit 0
    else
      echo "❌ ERROR: No backup file found at $backup_path"
      echo "Cannot restore the script. You may need to re-download it from GitHub."
      exit 1
    fi
  fi
  
  # Check for rollback early - before ANY other operations
  # This ensures we can recover even if basic script processing is broken
  check_for_rollback "$@"
  
  # Add a post-migration permissions check - MUST be first before any file operations
  check_post_migration_permissions "$command_args"
  
  # Check for required user and group at the start
  check_puid_pgid_user "$PUID" "$PGID" "$command_args"
  
  # Check if we're in beta mode
  check_beta_mode
  
  if [ "$#" -lt 1 ]; then
    display_usage
    exit 1
  fi

  local action="$1"
  shift # Remove the action from the argument list
  local instance_name="${1:-}" # Default to empty if not provided
  local additional_args="${@:2}" # Capture any additional arguments

  # Handle validation update check
  if [[ "$action" == "-validate_update" ]]; then
    # Just return success - this is only called to verify a freshly updated script runs properly
    exit 0
  fi
  
  # Handle force restore from backup
  if [[ "$action" == "-force-restore" ]]; then
    force_restore_from_backup
    exit 0
  fi

  # Check if the provided action is valid
  local is_valid=false
  for valid_action in "${valid_actions[@]}"; do
    if [[ "$action" == "$valid_action" ]]; then
      is_valid=true
      break
    fi
  done
  
  if [[ "$is_valid" == "false" ]]; then
    echo "Invalid action '${action}'."
    display_usage
    exit 1
  fi

  # Special cases for beta/stable/version/upgrade commands
  if [[ "$action" == "-beta" ]]; then
    set_beta_mode "beta"
exit 0
  elif [[ "$action" == "-stable" ]]; then
    set_beta_mode "stable"
    exit 0
  elif [[ "$action" == "-version" ]]; then
    display_version
    exit 0
  elif [[ "$action" == "-upgrade" ]]; then
    upgrade_pok_manager
    exit 0
  elif [[ "$action" == "-migrate" ]]; then
    migrate_file_ownership
    exit 0
  fi

  # Check if instance_name or -all is provided for actions that require it
  if [[ "$action" =~ ^(-start|-stop|-saveworld|-status)$ ]] && [[ -z "$instance_name" ]]; then
    echo "Error: $action requires an instance name or -all."
    echo "Usage: $0 $action <instance_name|-all>"
    exit 1
  elif [[ "$action" =~ ^(-shutdown|-restart)$ ]]; then
    if [[ -z "$instance_name" ]]; then
      echo "Error: $action requires a timer (in minutes) and an instance name or -all."
      echo "Usage: $0 $action <minutes> <instance_name|-all>"
      exit 1
    elif [[ "$instance_name" =~ ^[0-9]+$ ]]; then
      if [[ -z "$additional_args" ]]; then
        echo "Error: $action requires an instance name or -all after the timer."
        echo "Usage: $0 $action <minutes> <instance_name|-all>"
        exit 1
      else
        # Store the timer value separately
        local timer="$instance_name"
        instance_name="$additional_args"
        additional_args=("$timer")
      fi
    fi
  fi

  # Special check for -chat action
  if [[ "$action" == "-chat" ]]; then
    if [[ "$#" -lt 2 ]]; then
      echo "Error: -chat requires a quoted message and an instance name or -all"
      echo "Usage: $0 -chat \"<message>\" <instance_name|-all>"
      exit 1
    fi
    if [[ -z "$instance_name" ]]; then
      echo "Error: -chat requires an instance name or -all."
      echo "Usage: $0 -chat \"<message>\" <instance_name|-all>"
      exit 1
    fi
  fi

  # Special check for -custom action
  if [[ "$action" == "-custom" ]]; then
    if [[ -z "$instance_name" && "$instance_name" != "-all" ]]; then
      echo "Error: -custom requires an instance name or -all."
      echo "Usage: $0 -custom <additional_args> <instance_name|-all>"
      exit 1
    fi
  fi

  # Pass to the manage_service function
  manage_service "$action" "$instance_name" "$additional_args"
}

# Function to determine Docker image tag based on branch
get_docker_image_tag() {
  local instance_name="$1"
  
  # If running in beta mode, use beta suffix, otherwise use latest
  local branch_suffix="latest"
  local is_beta=false
  
  if check_beta_mode; then
    branch_suffix="beta"
    is_beta=true
  fi
  
  # Default to the new version
  local image_tag_version="2_1"
  
  # If we're in beta mode, always use 2_1_beta regardless of file ownership
  if $is_beta; then
    image_tag_version="2_1"
  else
    # For stable branch, check file ownership to determine backward compatibility
    # If server files directory exists, check ownership to determine backward compatibility
    local server_files_dir="${BASE_DIR}/ServerFiles/arkserver"
    if [ -d "$server_files_dir" ]; then
      local file_ownership=$(stat -c '%u:%g' "$server_files_dir")
      
      # If files are owned by 1000:1000, use the 2_0 image for compatibility
      if [ "$file_ownership" = "1000:1000" ]; then
        image_tag_version="2_0"
        # If running interactively, inform the user - but only to stderr so it doesn't get captured
        if [ -t 0 ]; then
          echo "ℹ️ Detected legacy file ownership (1000:1000). Using compatible image version." >&2
        fi
      fi
    fi
  fi
  
  echo "${image_tag_version}_${branch_suffix}"
}

# Function to enable or disable ArkServerAPI for instances
configure_api() {
  local api_state="$1"
  local instance_name="$2"
  local base_dir=$(dirname "$(realpath "$0")")
  local docker_compose_file="${base_dir}/Instance_${instance_name}/docker-compose-${instance_name}.yaml"
  local instance_dir="${base_dir}/Instance_${instance_name}"
  
  # Check if instance exists
  if [ ! -f "$docker_compose_file" ]; then
    echo "  ❌ Instance '$instance_name' does not exist (docker-compose file not found)"
    return 1
  fi
  
  # Check if the docker-compose file has the INSTANCE_NAME line, which we'll use as anchor
  if ! grep -q "INSTANCE_NAME" "$docker_compose_file"; then
    echo "  ❌ Docker compose file appears to be invalid (missing INSTANCE_NAME)"
    return 1
  fi
  
  # Remove any existing API lines first to prevent duplicates
  # Use a temporary file to ensure sed works across different systems
  local temp_file="${docker_compose_file}.tmp"
  
  # Remove both standard API lines and blank API lines, including both = and : syntax
  grep -v "^ *- API=\|^ *- API:" "$docker_compose_file" > "$temp_file"
  mv "$temp_file" "$docker_compose_file"
  
  # Now add the API line after INSTANCE_NAME
  if sed -i "/- INSTANCE_NAME/a \ \ \ \ \ \ - API=$api_state" "$docker_compose_file"; then
    echo "  ✅ Updated API setting to $api_state for instance: $instance_name"
    
    # Now handle the API_Logs volume mapping based on the API setting
    if [ "$api_state" = "TRUE" ]; then
      # Check if the API_Logs volume mapping is missing and API is now enabled
      if ! grep -q "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file"; then
        # Create a temporary file
        local tmp_file="${docker_compose_file}.tmp"
        
        # Get absolute path for consistency with other volume paths
        local abs_instance_dir=$(realpath "$instance_dir")
        
        # Use sed to add the API_Logs volume after the Saved volume with absolute path
        # Fix: Add closing double quote at the end of the path
        sed -e "/Saved:.*ShooterGame\/Saved/ a\\      - \"$abs_instance_dir/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs\"" "$docker_compose_file" > "$tmp_file"
        
        # Replace the original file with the updated one
        mv -f "$tmp_file" "$docker_compose_file"
        echo "  ✅ Added API_Logs volume mapping for instance: $instance_name"
      else
        # Check if the path is relative (starts with ./) and convert to absolute
        if grep -q "^ *- \"\./Instance_" "$docker_compose_file"; then
          echo "  ⚠️ Found relative API_Logs path, converting to absolute path"
          
          # Create a temporary file
          local tmp_file="${docker_compose_file}.tmp"
          
          # Get absolute path for consistency with other volume paths
          local abs_instance_dir=$(realpath "$instance_dir")
          
          # Use sed to replace the relative path with absolute path
          sed -e "s|^ *- \"\./Instance_${instance_name}/API_Logs|      - \"$abs_instance_dir/API_Logs|g" "$docker_compose_file" > "$tmp_file"
          
          # Replace the original file with the updated one
          mv -f "$tmp_file" "$docker_compose_file"
          echo "  ✅ Converted API_Logs path to absolute for instance: $instance_name"
        fi
      fi
    else
      # If API is now disabled, remove the API_Logs volume mapping
      if grep -q "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file"; then
        # Create a temporary file
        local tmp_file="${docker_compose_file}.tmp"
        
        # Remove the API_Logs line
        grep -v "API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs" "$docker_compose_file" > "$tmp_file"
        
        # Replace the original file with the updated one
        mv -f "$tmp_file" "$docker_compose_file"
        echo "  ✅ Removed API_Logs volume mapping for instance: $instance_name"
      fi
    fi
    
    return 0
  else
    echo "  ❌ Failed to update API setting for instance: $instance_name"
    return 1
  fi
}

# Function to detect files owned by incorrect users
detect_root_owned_files() {
  local base_dir="${BASE_DIR}"
  local dirs_to_check=()
  local found_incorrect_files=false
  
  # Check if ServerFiles exists
  if [ -d "${base_dir}/ServerFiles" ]; then
    dirs_to_check+=("${base_dir}/ServerFiles")
  fi
  
  # Check for instance directories
  for instance_dir in "${base_dir}"/Instance_*/; do
    if [ -d "$instance_dir" ]; then
      dirs_to_check+=("$instance_dir")
    fi
  done
  
  # Check for Cluster directory
  if [ -d "${base_dir}/Cluster" ]; then
    dirs_to_check+=("${base_dir}/Cluster")
  fi
  
  # Ensure config/POK-manager directory is included
  if [ -d "${base_dir}/config/POK-manager" ]; then
    dirs_to_check+=("${base_dir}/config/POK-manager")
  fi
  
  echo "Checking for files with incorrect ownership that could cause container issues..."
  
  # Check each directory for files with incorrect ownership
  for dir in "${dirs_to_check[@]}"; do
    # Find files not owned by expected user (7777:7777 or 1000:1000)
    local incorrect_files=($(find "$dir" \( ! -user 7777 -o ! -group 7777 \) -a \( ! -user 1000 -o ! -group 1000 \) -type f -o \( ! -user 7777 -o ! -group 7777 \) -a \( ! -user 1000 -o ! -group 1000 \) -type d 2>/dev/null))
    
    if [ ${#incorrect_files[@]} -gt 0 ]; then
      if [ "$found_incorrect_files" = "false" ]; then
        echo "⚠️ WARNING: Found files/directories with incorrect ownership that could cause permission issues:"
        found_incorrect_files=true
      fi
      
      echo "  Directory: $dir"
      echo "  Found ${#incorrect_files[@]} files/directories with incorrect ownership"
      
      # List the first 5 files for reference (to avoid overwhelming output)
      local count=0
      for file in "${incorrect_files[@]}"; do
        if [ $count -lt 5 ]; then
          local file_owner=$(stat -c '%u:%g' "$file")
          echo "    - $file (owned by user:group $file_owner)"
          ((count++))
        else
          echo "    - ... and $((${#incorrect_files[@]} - 5)) more"
          break
        fi
      done
    fi
  done
  
  if [ "$found_incorrect_files" = "true" ]; then
    echo ""
    echo "These incorrectly owned files can cause permission issues with your container."
    echo "We'll attempt to automatically fix these issues using sudo."
    echo ""
    echo "If the automatic fix fails, you can manually run:"
    echo "  sudo ./POK-manager.sh -fix"
    echo ""
    return 0
  else
    echo "No files with incorrect ownership found that would cause container issues. 👍"
    return 1
  fi
}

# Function to fix incorrectly owned files
fix_root_owned_files() {
  # Check if running with sudo
  if ! is_sudo; then
    echo "❌ ERROR: This command requires sudo privileges to fix file ownership issues."
    echo "Please run: sudo ./POK-manager.sh -fix"
    return 1
  fi
  
  local base_dir="${BASE_DIR}"
  local dirs_to_fix=()
  local found_incorrect_files=false
  local fixed_count=0
  
  echo "🔍 Scanning for files with incorrect ownership..."
  
  # First, fix the POK-manager.sh script itself if needed
  local script_path="$(realpath "$0")"
  local script_owner="$(stat -c '%u:%g' "$script_path")"
  if [ "$script_owner" != "$PUID:$PGID" ]; then
    echo "Found POK-manager.sh owned by $script_owner, fixing to $PUID:$PGID..."
    chown $PUID:$PGID "$script_path"
    chmod +x "$script_path"
    echo "✓ Fixed ownership of POK-manager.sh to $PUID:$PGID"
    ((fixed_count++))
    found_incorrect_files=true
  else
    # Always ensure the script is executable regardless of ownership
    chmod +x "$script_path"
  fi
  
  # Check if ServerFiles exists
  if [ -d "${base_dir}/ServerFiles" ]; then
    dirs_to_fix+=("${base_dir}/ServerFiles")
  fi
  
  # Check for instance directories
  for instance_dir in "${base_dir}"/Instance_*/; do
    if [ -d "$instance_dir" ]; then
      dirs_to_fix+=("$instance_dir")
    fi
  done
  
  # Check for Cluster directory
  if [ -d "${base_dir}/Cluster" ]; then
    dirs_to_fix+=("${base_dir}/Cluster")
  fi
  
  # Ensure config/POK-manager directory is included
  if [ -d "${base_dir}/config" ]; then
    dirs_to_fix+=("${base_dir}/config")
  fi
  if [ -d "${base_dir}/config/POK-manager" ]; then
    dirs_to_fix+=("${base_dir}/config/POK-manager")
  fi
  
  # Fix permissions in each directory
  for dir in "${dirs_to_fix[@]}"; do
    echo "Checking directory: $dir"
    
    # Find files with incorrect ownership
    local incorrect_files=($(find "$dir" \( ! -user 7777 -o ! -group 7777 \) -a \( ! -user 1000 -o ! -group 1000 \) -type f -o \( ! -user 7777 -o ! -group 7777 \) -a \( ! -user 1000 -o ! -group 1000 \) -type d 2>/dev/null))
    
    if [ ${#incorrect_files[@]} -gt 0 ]; then
      found_incorrect_files=true
      echo "  Found ${#incorrect_files[@]} files/directories with incorrect ownership in $dir"
      echo "  Changing ownership to $PUID:$PGID..."
      
      # Change ownership of all files found
      for file in "${incorrect_files[@]}"; do
        local original_owner=$(stat -c '%u:%g' "$file")
        chown $PUID:$PGID "$file"
        ((fixed_count++))
        
        # For large numbers of files, don't output each one
        if [ $fixed_count -le 20 ]; then
          echo "  ✓ Fixed: $file (changed from $original_owner to $PUID:$PGID)"
        elif [ $fixed_count -eq 21 ]; then
          echo "  ✓ Fixed additional files (not showing all for brevity)..."
        fi
      done
    fi
  done
  
  if [ "$found_incorrect_files" = "true" ]; then
    echo "✅ Successfully fixed $fixed_count files with incorrect ownership. Your container should now work correctly."
    # Verify fix was successful by checking if any incorrectly owned files remain
    if detect_remaining_root_files; then
      echo "⚠️ Warning: Some files with incorrect ownership could not be fixed. The container may still have permission issues."
      return 2  # Partial success
    else
      echo "All permission issues have been resolved!"
      return 0  # Complete success
    fi
  else
    echo "No files with incorrect ownership found. No changes were made."
    return 0  # No action needed
  fi
}

# Helper function to check if any root-owned files remain
detect_remaining_root_files() {
  local base_dir="${BASE_DIR}"
  local dirs_to_check=()
  
  # Check the same directories as in fix_root_owned_files
  if [ -d "${base_dir}/ServerFiles" ]; then
    dirs_to_check+=("${base_dir}/ServerFiles")
  fi
  
  for instance_dir in "${base_dir}"/Instance_*/; do
    if [ -d "$instance_dir" ]; then
      dirs_to_check+=("$instance_dir")
    fi
  done
  
  if [ -d "${base_dir}/Cluster" ]; then
    dirs_to_check+=("${base_dir}/Cluster")
  fi
  
  if [ -d "${base_dir}/config/POK-manager" ]; then
    dirs_to_check+=("${base_dir}/config/POK-manager")
  fi
  
  # Quick check for any remaining root-owned files
  for dir in "${dirs_to_check[@]}"; do
    if find "$dir" -user 0 -group 0 -type f -o -user 0 -group 0 -type d 2>/dev/null | grep -q .; then
      return 0  # Found remaining root-owned files
    fi
  done
  
  return 1  # No remaining root-owned files
}

# Add a function to handle automatic recovery for API mode instances
handle_api_recovery() {
  # This function is called when the monitor script detects a server is not running
  # and needs to be recovered. For API mode, we'll use the container restart approach.
  
  # Add this function after the api_restart_instance function
  
  # Check all running instances for API=TRUE and monitor status
  echo "Checking for API instances that need recovery..."
  
  for instance in $(list_instances); do
    # Get the docker-compose file path
    local base_dir=$(dirname "$(realpath "$0")")
    local docker_compose_file="${base_dir}/Instance_${instance}/docker-compose-${instance}.yaml"
    
    # Skip if docker-compose file doesn't exist
    if [ ! -f "$docker_compose_file" ]; then
      continue
    fi
    
    # Check if API=TRUE in the docker-compose file
    if grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"; then
      # Check if the container exists but the ARK server process is not running
      local container_name="asa_${instance}"
      
      # Check if container is running
      if docker ps -q -f name=^/${container_name}$ > /dev/null; then
        echo "API instance $instance container is running, checking server process..."
        
        # Check if ARK server process is running inside the container
        local server_running=$(docker exec "$container_name" /bin/bash -c "pgrep -f 'AsaApiLoader.exe\|ArkAscendedServer.exe' >/dev/null 2>&1 && echo 'running' || echo 'stopped'")
        
        if [ "$server_running" = "stopped" ]; then
          echo "⚠️ API instance $instance container is running but server process is not!"
          echo "Performing recovery by restarting the container..."
          
          # Stop the container
          stop_instance "$instance"
          
          # Wait for container to fully stop
          sleep 10
          
          # Start the container again
          start_instance "$instance"
          
          echo "✅ API instance $instance has been recovered using container restart strategy."
        fi
      fi
    fi
  done
}

# Add a cron-friendly recovery command that can be run periodically
if [ "$1" = "-api-recovery" ]; then
  handle_api_recovery
  exit 0
fi

# Add enhanced restart functionality with verification and mixed-mode support
enhanced_restart_command() {
  local minutes_arg="$1"
  local instance_arg="$2"
  local skip_update=false  # New parameter to control whether to skip the update
  
  # Default to 5 minutes if not specified
  local countdown_minutes="${minutes_arg:-5}"
  
  # Determine if we should skip updating server files when a specific instance is specified
  if [[ "${instance_arg,,}" != "-all" ]]; then
    skip_update=true
    echo "Restarting specific instance: Updates will be skipped to minimize downtime"
    
    # Enhanced validation for a specific instance
    # Check if the instance directory exists
    local instance_dir="${BASE_DIR}/Instance_${instance_arg}"
    local docker_compose_file="${instance_dir}/docker-compose-${instance_arg}.yaml"
    
    if [ ! -d "$instance_dir" ]; then
      echo "❌ ERROR: Instance directory not found at $instance_dir"
      echo "The instance '${instance_arg}' does not exist. Please check for typos."
      
      # List available instances to help the user
      echo ""
      echo "Available instances:"
      local available_instances=($(list_instances))
      if [ ${#available_instances[@]} -eq 0 ]; then
        echo "  No instances found. Use './POK-manager.sh -create <instance_name>' to create one."
      else
        for i in "${available_instances[@]}"; do
          echo "  - $i"
        done
      fi
      exit 1
    fi
    
    # Check if the docker-compose file exists
    if [ ! -f "$docker_compose_file" ]; then
      echo "❌ ERROR: Docker Compose file not found at $docker_compose_file"
      echo "The instance '${instance_arg}' exists but its configuration file is missing."
      exit 1
    fi
  fi
  
  # Initialize arrays to track different types of instances
  local api_instances=()
  local non_api_instances=()
  local instances_to_process=()
  
  # Define colors for the countdown (same as shutdown)
  local status_color="\033[1;36m" # Cyan for status
  local time_color="\033[1;33m" # Yellow for time
  local reset_color="\033[0m"
  local action_color="\033[1;35m" # Magenta for action status
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  
  # Determine which instances to process
  if [[ "${instance_arg,,}" == "-all" ]]; then
    # Get all running instances
    instances_to_process=($(list_running_instances))
    if [ ${#instances_to_process[@]} -eq 0 ]; then
      echo "No running instances found."
      exit 1  # Exit with error status
    fi
    echo "Processing all running instances for restart: ${instances_to_process[*]}"
  else
    # We already validated the instance exists above, so now just check if it's running
    if docker ps -q -f name=^/asa_${instance_arg}$ > /dev/null; then
      instances_to_process=("$instance_arg")
      echo "Processing instance for restart: $instance_arg"
    else
      # Instance exists but is not running
      echo "⚠️ Warning: Instance '$instance_arg' exists but is not currently running."
      echo "Do you want to start it before performing the restart operation?"
      read -p "Start the instance? (y/n): " start_choice
      if [[ "$start_choice" =~ ^[Yy]$ ]]; then
        echo "Starting instance $instance_arg..."
        start_instance "$instance_arg"
        sleep 5  # Give it a moment to start
        instances_to_process=("$instance_arg")
      else
        echo "Operation canceled. The instance must be running to perform a restart."
        exit 1
      fi
    fi
  fi
  
  # Categorize instances based on API mode
  for instance in "${instances_to_process[@]}"; do
    local docker_compose_file="${BASE_DIR}/Instance_${instance}/docker-compose-${instance}.yaml"
    
    # Check if API=TRUE in the docker-compose file
    if [ -f "$docker_compose_file" ] && (grep -q "^ *- API=TRUE" "$docker_compose_file" || grep -q "^ *- API:TRUE" "$docker_compose_file"); then
      api_instances+=("$instance")
      echo "Instance $instance has API=TRUE"
    else
      non_api_instances+=("$instance")
      echo "Instance $instance has API=FALSE"
    fi
  done
  
  # Set restart mode based on the mix of instances
  local restart_mode="standard"
  if [ ${#api_instances[@]} -gt 0 ] && [ ${#non_api_instances[@]} -gt 0 ]; then
    restart_mode="mixed"
    echo "⚠️ Mixed API modes detected. Using coordinated restart approach for all instances."
    echo ""
    echo "⚠️ IMPORTANT UPDATE INFORMATION: ⚠️"
    echo "When restarting instances with mixed API modes (TRUE and FALSE), the running containers will be stopped,"
    echo "server files WILL be updated, and containers will be brought back up."
    echo "If a game update is available, it WILL be applied during this process."
    echo ""
    echo "This process follows these steps automatically:"
    echo "1. Stop all containers"
    echo "2. Update server files"
    echo "3. Start all containers"
    echo ""
    echo "This ensures all server files are updated correctly while minimizing downtime."
    echo "Continuing with restart in 5 seconds..."
    sleep 5
  elif [ ${#api_instances[@]} -gt 0 ]; then
    restart_mode="api-only"
    echo "All instances have API=TRUE. Using container-level restart approach."
  else
    restart_mode="standard"
    echo "All instances have API=FALSE. Using standard in-game restart approach."
  fi
  
  # First, notify all instances of the pending restart
  echo "🔔 Notifying all servers of restart in $countdown_minutes minutes..."
  
  # Prepare a special message for mixed mode
  local restart_message=""
  if [ "$restart_mode" = "mixed" ]; then
    restart_message="SERVER ANNOUNCEMENT: Prepare for restart in ${countdown_minutes} minutes. Please note: This restart will NOT include game updates."
  else
    restart_message="SERVER ANNOUNCEMENT: Prepare for restart in ${countdown_minutes} minutes. Please finish your current activities."
  fi
  
  for instance in "${instances_to_process[@]}"; do
    echo "  - Notifying ${instance}..."
    # For both API and non-API instances, send a chat notification
    run_in_container_background "$instance" "-chat" "$restart_message" >/dev/null 2>&1
  done
  
  # Handle different restart modes
  case "$restart_mode" in
    "mixed"|"api-only"|"standard")
      # Use the same countdown mechanism for all modes
      # Start countdown
      local total_seconds=$((countdown_minutes * 60))
      local remaining_seconds=$total_seconds
      # Generate notification points: 5-minute intervals + standard final countdown
      local notification_points=()
      
      # Add 5-minute intervals (in seconds) from countdown_minutes down to 5 minutes
      local current_minutes=$countdown_minutes
      while [ $current_minutes -ge 5 ]; do
        if [ $((current_minutes % 5)) -eq 0 ]; then
          notification_points+=($((current_minutes * 60)))
        fi
        current_minutes=$((current_minutes - 1))
      done
      
      # Add standard final countdown points (3min, 1min, 30sec, final 10 seconds)
      notification_points+=(180 60 30 10 9 8 7 6 5 4 3 2 1)
      
      # Sort notification points in descending order (remove duplicates)
      IFS=$'\n' notification_points=($(printf '%s\n' "${notification_points[@]}" | sort -nr | uniq))
      unset IFS
      local spinner_idx=0
      
      echo -e "${status_color}⏱️${reset_color} Beginning restart countdown: $countdown_minutes minutes"
      
      # Loop until countdown completes
      while [ $remaining_seconds -gt 0 ]; do
        # Update the spinner
        local current_spinner=${spinner[$spinner_idx]}
        spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
        
        # Format the remaining time
        local minutes=$((remaining_seconds / 60))
        local seconds=$((remaining_seconds % 60))
        local eta_display="${minutes}m ${seconds}s"
        
        # Clear line and print the countdown with spinner (same style as shutdown)
        printf "\r${status_color}%s${reset_color} ${action_color}Restarting:${reset_color} ${time_color}ETA: %-8s${reset_color}" "$current_spinner" "$eta_display"
        
        # Check for notification points
        for point in "${notification_points[@]}"; do
          if [ $remaining_seconds -eq $point ]; then
            local display_time=""
            if [ $point -ge 60 ]; then
              display_time="$((point / 60)) minute(s)"
            else
              display_time="$point seconds"
            fi
            # Add a newline and print the notification without disrupting the countdown
            echo ""
            echo -e "${status_color}Server notification: ${time_color}${display_time} remaining${reset_color}"
            
            # Send notification to all instances
            for instance in "${instances_to_process[@]}"; do
              run_in_container_background "$instance" "-chat" "Server restart in $display_time!"
            done
            break
          fi
        done
        
        sleep 1
        remaining_seconds=$((remaining_seconds - 1))
      done
      
      # Show completion message
      echo -e "\r${status_color}✓${reset_color} ${action_color}Restarting:${reset_color} ${time_color}Countdown complete!${reset_color}                 "
      echo ""
      
      echo -e "${status_color}🔄${reset_color} Beginning coordinated restart process..."
      
      # 1. Save world for all instances
      echo -e "${status_color}💾${reset_color} Saving world data for all instances..."
      local save_error=false
      for instance in "${instances_to_process[@]}"; do
        echo "  - Saving world for ${instance}..."
        # Check if the container exists before attempting to save
        if docker ps -q -f name=^/asa_${instance}$ > /dev/null; then
          run_in_container "$instance" "-saveworld"
        else
          echo "  ⚠️ Warning: Container for ${instance} is not running, skipping save operation"
          save_error=true
        fi
      done
      
      # Give some time for saves to complete
      if [ "$save_error" = true ]; then
        echo -e "${status_color}⚠️${reset_color} Some instances couldn't be saved. Continuing with restart process..."
      else
        echo -e "${status_color}⏳${reset_color} Waiting for saves to complete (10 seconds)..."
      fi
      sleep 10
      
      # 2. Stop all instances
      echo -e "${status_color}🛑${reset_color} Stopping all instances..."
      local stop_error=false
      for instance in "${instances_to_process[@]}"; do
        echo "  - Stopping ${instance}..."
        # Check if the container exists before attempting to stop
        if docker ps -a -q -f name=^/asa_${instance}$ > /dev/null; then
          stop_instance "$instance"
        else
          echo "  ⚠️ Warning: Container for ${instance} does not exist, skipping stop operation"
          stop_error=true
        fi
      done
      
      # 3. Update server files if needed
      echo -e "${status_color}🔍${reset_color} Checking for server file updates..."
      if [ "$skip_update" = false ]; then
        update_server_files_and_docker
      else
        echo "Skipping server updates as a specific instance was selected"
      fi
      
      # 4. Start all instances
      echo -e "${status_color}🚀${reset_color} Starting all instances..."
      local start_error=false
      for instance in "${instances_to_process[@]}"; do
        echo "  - Starting ${instance}..."
        # Verify the instance directory and docker-compose file exist before starting
        local instance_dir="${BASE_DIR}/Instance_${instance}"
        local docker_compose_file="${instance_dir}/docker-compose-${instance}.yaml"
        
        if [ ! -d "$instance_dir" ]; then
          echo "  ❌ ERROR: Instance directory not found at $instance_dir"
          start_error=true
          continue
        fi
        
        if [ ! -f "$docker_compose_file" ]; then
          echo "  ❌ ERROR: Docker Compose file not found at $docker_compose_file"
          start_error=true
          continue
        fi
        
        start_instance "$instance"
      done
      
      # 5. Verify all instances restarted successfully
      if [ "$start_error" = true ]; then
        echo -e "${status_color}⚠️${reset_color} Some instances could not be started. Please check the errors above."
      else
        echo -e "${status_color}✅${reset_color} Verifying all instances are running..."
      fi
      ;;
      
    "standard")
      # For non-API instances, use the in-game restart command
      echo "📢 Sending restart command with countdown: $countdown_minutes minutes"
      
      for instance in "${non_api_instances[@]}"; do
        echo "🔄 Sending restart command to instance: $instance"
        run_in_container "$instance" "-restart" "$countdown_minutes"
      done
      
      # Calculate how long to wait for restart
      local total_wait_seconds=$((countdown_minutes * 60 + 120))  # Add 2 minutes for server restart process
      local wait_interval=30  # Check every 30 seconds
      local wait_attempts=$((total_wait_seconds / wait_interval))
      
      echo "⏳ Waiting for restart to complete (~$((total_wait_seconds / 60)) minutes)..."
      
      # Wait for restart to complete
      local restart_verified=false
      for ((i=1; i<=wait_attempts; i++)); do
        local all_restarted=true
        local failed_instances=()
        
        for instance in "${non_api_instances[@]}"; do
          if ! validate_instance "$instance"; then
            all_restarted=false
            failed_instances+=("$instance")
          fi
        done
        
        if [ "$all_restarted" = true ]; then
          echo "✅ All non-API instances have successfully restarted!"
          restart_verified=true
          break
        else
          echo "⏳ Waiting for instances to restart: ${failed_instances[*]} (Check $i/$wait_attempts)"
          sleep $wait_interval
        fi
      done
      
      if [ "$restart_verified" = false ]; then
        echo "⚠️ WARNING: Some instances may not have restarted properly: ${failed_instances[*]}"
        echo "Please check these instances manually."
        exit 1  # Exit with error status
      fi
      ;;
    "api-only")
      # For API=TRUE instances, use the container restart approach
      # Use the same countdown loop as we just defined for "mixed" mode
      # Start countdown
      local total_seconds=$((countdown_minutes * 60))
      local remaining_seconds=$total_seconds
      # Generate notification points: 5-minute intervals + standard final countdown
      local notification_points=()
      
      # Add 5-minute intervals (in seconds) from countdown_minutes down to 5 minutes
      local current_minutes=$countdown_minutes
      while [ $current_minutes -ge 5 ]; do
        if [ $((current_minutes % 5)) -eq 0 ]; then
          notification_points+=($((current_minutes * 60)))
        fi
        current_minutes=$((current_minutes - 1))
      done
      
      # Add standard final countdown points (3min, 1min, 30sec, final 10 seconds)
      notification_points+=(180 60 30 10 9 8 7 6 5 4 3 2 1)
      
      # Sort notification points in descending order (remove duplicates)
      IFS=$'\n' notification_points=($(printf '%s\n' "${notification_points[@]}" | sort -nr | uniq))
      unset IFS
      local spinner_idx=0
      
      echo -e "${status_color}⏱️${reset_color} Beginning restart countdown: $countdown_minutes minutes"
      
      # Loop until countdown completes
      while [ $remaining_seconds -gt 0 ]; do
        # Update the spinner
        local current_spinner=${spinner[$spinner_idx]}
        spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
        
        # Format the remaining time
        local minutes=$((remaining_seconds / 60))
        local seconds=$((remaining_seconds % 60))
        local eta_display="${minutes}m ${seconds}s"
        
        # Clear line and print the countdown with spinner (same style as shutdown)
        printf "\r${status_color}%s${reset_color} ${action_color}Restarting:${reset_color} ${time_color}ETA: %-8s${reset_color}" "$current_spinner" "$eta_display"
        
        # Check for notification points
        for point in "${notification_points[@]}"; do
          if [ $remaining_seconds -eq $point ]; then
            local display_time=""
            if [ $point -ge 60 ]; then
              display_time="$((point / 60)) minute(s)"
            else
              display_time="$point seconds"
            fi
            # Add a newline and print the notification without disrupting the countdown
            echo ""
            echo -e "${status_color}Server notification: ${time_color}${display_time} remaining${reset_color}"
            break
          fi
        done
        
        sleep 1
        remaining_seconds=$((remaining_seconds - 1))
      done
      ;;
    "mixed")
      # For mixed API mode, we need to handle both API and non-API instances
      # Start countdown for API instances
  esac
  
  echo "🎮 Server restart operation completed for all instances."
  exit 0  # Add explicit exit with success status to ensure function terminates
}

# Function for enhanced shutdown command with better visuals (similar to restart)
enhanced_shutdown_command() {
  local minutes_arg="$1"
  local instance_arg="$2"
  
  # Default to 1 minute if not specified
  local countdown_minutes="${minutes_arg:-1}"
  
  # Validate countdown_minutes is a positive number
  if ! [[ "$countdown_minutes" =~ ^[0-9]+$ ]]; then
    echo "Invalid shutdown time: $countdown_minutes. Using default of 1 minute."
    countdown_minutes=1
  fi
  
  # Define colors for the countdown
  local status_color="\033[1;36m" # Cyan for status
  local time_color="\033[1;33m" # Yellow for time
  local reset_color="\033[0m"
  local success_color="\033[1;32m" # Green for success
  local warning_color="\033[1;33m" # Yellow for warnings
  local action_color="\033[1;35m" # Magenta for action status
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spinner_idx=0
  
  # Determine which instances to process
  local instances_to_process=()
  
  if [[ "${instance_arg,,}" == "-all" ]]; then
    # Get all running instances
    instances_to_process=($(list_running_instances))
    if [ ${#instances_to_process[@]} -eq 0 ]; then
      echo "No running instances found."
      exit 1  # Exit with error status
    fi
    echo "Processing all running instances for shutdown: ${instances_to_process[*]}"
  else
    # Verify the specific instance exists and is running
    if ! validate_instance "$instance_arg"; then
      echo "Instance '$instance_arg' is not running or does not exist."
      exit 1  # Exit with error status
    fi
    instances_to_process=("$instance_arg")
    echo "Processing instance for shutdown: $instance_arg"
  fi
  
  # Notify all servers of the shutdown
  echo "🔔 Notifying all servers of shutdown in $countdown_minutes minutes..."
  for instance in "${instances_to_process[@]}"; do
    echo "  - Notifying $instance..."
    # Send RCON commands to notify of shutdown
    run_in_container_background "$instance" "-chat" "Server shutdown in $countdown_minutes minute(s)!" >/dev/null 2>&1
  done
  
  # Start the enhanced countdown
  echo "⏱️ Beginning shutdown countdown: $countdown_minutes minutes"
  
  # Convert minutes to seconds for countdown
  local total_seconds=$((countdown_minutes * 60))
  local seconds_remaining=$total_seconds
  
  # List of notification points in seconds
  local notification_points=(
    $((60 * 5))  # 5 minutes
    $((60 * 3))  # 3 minutes
    $((60 * 1))  # 1 minute
    30           # 30 seconds
    10 9 8 7 6 5 4 3 2 1  # Final countdown
  )
  
  # Countdown loop
  while [ $seconds_remaining -gt 0 ]; do
    local minutes=$((seconds_remaining / 60))
    local seconds=$((seconds_remaining % 60))
    
    # Update spinner
    local current_spinner=${spinner[$spinner_idx]}
    spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
    
    # Display countdown
    printf "\r${current_spinner} ${action_color}Shutting down:${reset_color} ${time_color}ETA: %dm %ds${reset_color}   " $minutes $seconds
    
    # Check if we need to send a notification
    for point in "${notification_points[@]}"; do
      if [ $seconds_remaining -eq $point ]; then
        echo ""  # New line for notification
        if [ $point -ge 60 ]; then
          local min_val=$((point / 60))
          echo "Server notification: $min_val minute(s) remaining"
          # Send to all servers
          for instance in "${instances_to_process[@]}"; do
            run_in_container_background "$instance" "-chat" "Server shutdown in $min_val minute(s)!" >/dev/null 2>&1
          done
        else
          echo "Server notification: $point seconds remaining"
          # Send to all servers
          for instance in "${instances_to_process[@]}"; do
            run_in_container_background "$instance" "-chat" "Server shutdown in $point seconds!" >/dev/null 2>&1
          done
        fi
        break
      fi
    done
    
    sleep 1
    ((seconds_remaining--))
  done
  
  # Countdown complete
  echo -e "\r✓ Shutting down: Countdown complete!                 "
  echo ""
  
  # Final notification
  for instance in "${instances_to_process[@]}"; do
    run_in_container_background "$instance" "-chat" "Server is shutting down NOW!" >/dev/null 2>&1
  done
  
  # Begin shutdown process
  echo "🛑 Beginning coordinated shutdown process..."
  echo "💾 Saving world data for all instances..."
  
  for instance in "${instances_to_process[@]}"; do
    echo "  - Saving world for $instance..."
    run_in_container "$instance" "-saveworld" >/dev/null 2>&1 &
  done
  
  # Wait for saves to complete
  echo "⏳ Waiting for saves to complete (10 seconds)..."
  sleep 10
  
  # Stop all instances
  echo "🛑 Stopping all instances..."
  for instance in "${instances_to_process[@]}"; do
    echo "  - Stopping $instance..."
    stop_instance "$instance"
  done
  
  echo "✅ All servers have been shut down successfully."
  
  # Exit gracefully
  exit 0
}

# Function to display the changelog
display_changelog() {
  local changelog_file="${BASE_DIR}/config/POK-manager/changelog.txt"
  local changelog_dir=$(dirname "$changelog_file")
  
  echo "Downloading latest changelog from GitHub..."
  
  mkdir -p "$changelog_dir"
  
  # Check if we're in beta mode
  local branch="master"
  if check_beta_mode; then
    branch="beta"
  fi
  
  # Generate a unique timestamp and random string to prevent caching
  local timestamp=$(date +%s)
  local random_str=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)
  local changelog_url="https://raw.githubusercontent.com/Acekorneya/Ark-Survival-Ascended-Server/$branch/changelog.txt?nocache=${timestamp}_${random_str}"
  
  # Always attempt to download the latest changelog
  local download_success=false
  if command -v wget &>/dev/null; then
    if wget -q --no-cache -O "$changelog_file" "$changelog_url"; then
      download_success=true
    fi
  elif command -v curl &>/dev/null; then
    if curl -s -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" -o "$changelog_file" "$changelog_url"; then
      download_success=true
    fi
  fi
  
  if [ "$download_success" != "true" ]; then
    echo "Failed to download the latest changelog. Please check your internet connection."
    # Check if we have a cached version to fall back to
    if [ -f "$changelog_file" ]; then
      echo "Using cached changelog (may be outdated)..."
    else
      echo "No cached changelog available."
      echo "You can manually view the changelog at: https://github.com/Acekorneya/Ark-Survival-Ascended-Server/blob/$branch/changelog.txt"
      return 1
    fi
  else
    echo "Latest changelog downloaded successfully."
  fi
  
  # Display the changelog with nice formatting
  echo "======================================================="
  echo "                 POK-MANAGER CHANGELOG                 "
  echo "======================================================="
  echo ""
  cat "$changelog_file"
  echo ""
  echo "======================================================="
}

# Invoke the main function with all passed arguments
main "$@"
