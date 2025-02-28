#!/bin/bash
# Version information
POK_MANAGER_VERSION="2.1.0"
POK_MANAGER_BRANCH="stable" # Can be "stable" or "beta"

# Get the base directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BASE_DIR="$SCRIPT_DIR"

# Check for beta mode early
if [ -f "${BASE_DIR}/config/POK-manager/beta_mode" ]; then
  POK_MANAGER_BRANCH="beta"
fi

# Define colors for pretty output
RED='\033[0;31m'

# Set PUID and PGID to match the container's expected values
# Legacy default was 1000:1000, new default is 7777:7777
PUID=${CONTAINER_PUID:-7777}
PGID=${CONTAINER_PGID:-7777}

# Define the order in which the settings should be displayed
declare -a config_order=(
    "Memory Limit" 
    "BattleEye"
    "RCON Enabled"
    "POK Monitor Message"
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
    ["RCON Enabled"]="TRUE"
    ["POK Monitor Message"]="FALSE"
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
    ["Custom Server Args"]="-UseDynamicConfig"
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

validate_generic() {
  local input="$1"
  # This function can be expanded to escape special characters or check for injection patterns
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
    "BattleEye"|"RCON Enabled"|"POK Monitor Message"|"Update Server"|"MOTD Enabled"|"Show Admin Commands In Chat")
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
      else
        echo "Unsupported Linux distribution. Please install Docker manually and run the script again."
        exit 1
      fi
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
    read -p "Do you want to install Docker Compose? [y/N]: " install_compose
    if [[ "$install_compose" =~ ^[Yy]$ ]]; then
      # Detect the OS and install Docker Compose accordingly
      if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y docker-compose
      elif command -v dnf &>/dev/null; then
        # Fedora
        sudo dnf install -y docker-compose
      elif command -v yum &>/dev/null; then
        # CentOS/RHEL
        sudo yum install -y docker-compose
      else
        echo "Unsupported Linux distribution. Please install Docker Compose manually and run the script again."
        exit 1
      fi
      DOCKER_COMPOSE_CMD="docker-compose"
    else
      echo "Docker Compose installation declined. Please install Docker Compose manually to proceed."
      exit 1
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

get_docker_compose_cmd() {
  local cmd_file="./config/POK-manager/docker_compose_cmd"
  local config_dir="./config/POK-manager"
  mkdir -p "$config_dir"
  if [ ! -f "$cmd_file" ]; then
    touch "$cmd_file"
  fi
  if [ -f "$cmd_file" ]; then
    DOCKER_COMPOSE_CMD=$(cat "$cmd_file")
    echo "Using Docker Compose command: '$DOCKER_COMPOSE_CMD' (read from file)."
  elif [ -z "$DOCKER_COMPOSE_CMD" ]; then
    # Check for the Docker Compose V2 command availability ('docker compose')
    if docker compose version &>/dev/null; then
      DOCKER_COMPOSE_CMD="docker compose"
    elif docker-compose --version &>/dev/null; then
      # Fallback to Docker Compose V1 command if V2 is not available
      DOCKER_COMPOSE_CMD="docker-compose"
    else
      echo "Neither 'docker compose' (V2) nor 'docker-compose' (V1) command is available."
      echo "Please ensure Docker Compose is correctly installed."
      exit 1
    fi

    echo "Using Docker Compose command: '$DOCKER_COMPOSE_CMD'."
  fi
}


get_config_file_path() {
  local config_dir="./config/POK-manager"
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

  # Set executable bit for POK-manager.sh
  chmod +x "$(dirname "$(realpath "$0")")/POK-manager.sh"

  echo "Ownership and permissions adjustment on $dir completed."
}

# Check vm.max_map_count
check_vm_max_map_count() {
  local required_map_count=262144
  local current_map_count=$(cat /proc/sys/vm/max_map_count)
  if [ "$current_map_count" -lt "$required_map_count" ]; then
    echo "ERROR: vm.max_map_count is too low ($current_map_count). Needs to be at least $required_map_count."
    echo "Please run the following command to temporarily set the value:"
    echo "  sudo sysctl -w vm.max_map_count=262144"
    echo "To set the value permanently, add the following line to /etc/sysctl.conf and run 'sudo sysctl -p':"
    echo "  vm.max_map_count=262144"
    exit 1
  fi
}

check_puid_pgid_user() {
  local puid="$1"
  local pgid="$2"
  local original_command="$3"  # This contains the original command (e.g., "-stop -all")
  local legacy_puid=1000
  local legacy_pgid=1000

  # Check if the script is run with sudo (EUID is 0)
  if is_sudo; then
    echo "Running with sudo privileges. Skipping PUID and PGID check."
    return
  fi

  local current_uid=$(id -u)
  local current_gid=$(id -g)
  local current_user=$(id -un)

  # Display important information about container permissions
  echo "ℹ️ INFORMATION: The default container user changed from 1000:1000 to 7777:7777 in version 2.1+"
  echo "This change improves compatibility with most Linux distributions that use 1000:1000 for the first user."
  echo "For best results, server files should be owned by user with UID:GID matching the container settings."
  echo ""
  
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
        fi
        echo ""
        echo "2. Run with sudo to bypass permission checks:"
        echo "   sudo ./POK-manager.sh $original_command"
        echo "   (This works but isn't ideal for regular use)"
        echo ""
        echo "3. Update file ownership to the new default (7777:7777):"
        echo "   sudo chown -R 7777:7777 ${BASE_DIR}/ServerFiles ${BASE_DIR}/Instance_* ${BASE_DIR}/Cluster"
        echo "   (Recommended for new setups to match container defaults)"
        echo ""
        echo "4. Change file ownership to match your current user:"
        echo "   sudo chown -R ${current_uid}:${current_gid} ${BASE_DIR}/ServerFiles ${BASE_DIR}/Instance_* ${BASE_DIR}/Cluster"
        echo "   (Then update docker-compose files to use your UID:GID)"
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
      fi
      echo ""
      echo "2. Run with sudo to bypass permission checks:"
      echo "   sudo ./POK-manager.sh $original_command"
      echo "   (This works but isn't ideal for regular use)"
      echo ""
      echo "3. Update file ownership to the new default (7777:7777):"
      echo "   sudo chown -R 7777:7777 ${BASE_DIR}/ServerFiles ${BASE_DIR}/Instance_* ${BASE_DIR}/Cluster"
      echo "   (Recommended for new setups to match container defaults)"
      echo ""
      echo "4. Change file ownership to match your current user:"
      echo "   sudo chown -R ${current_uid}:${current_gid} ${BASE_DIR}/ServerFiles ${BASE_DIR}/Instance_* ${BASE_DIR}/Cluster"
      echo "   (Then update docker-compose files to use your UID:GID)"
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
    echo "You have these options:"
    echo ""
    echo "1. Run with sudo to bypass permission checks:"
    echo "   sudo ./POK-manager.sh $original_command"
    echo "   (This works but isn't ideal for regular use)"
    echo ""
    echo "2. Update file ownership to the new default (7777:7777):"
    echo "   sudo chown -R 7777:7777 ${BASE_DIR}/ServerFiles ${BASE_DIR}/Instance_* ${BASE_DIR}/Cluster"
    echo "   (Recommended for new setups to match container defaults)"
    echo ""
    echo "3. Change file ownership to match your current user:"
    echo "   sudo chown -R ${current_uid}:${current_gid} ${BASE_DIR}/ServerFiles ${BASE_DIR}/Instance_* ${BASE_DIR}/Cluster"
    echo "   (Then update docker-compose files to use your UID:GID)"
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
    fi
    echo ""
    exit 1
  fi
}


copy_default_configs() {
  # Define the directory where the configuration files will be stored
  local config_dir="${base_dir}/Instance_${instance_name}/Saved/Config/WindowsServer"
  local base_dir=$(dirname "$(realpath "$0")")

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
  local base_dir=$(dirname "$(realpath "$0")")
  check_vm_max_map_count
  check_puid_pgid_user "$PUID" "$PGID"
  check_dependencies
  install_jq
  install_yq
  install_steamcmd
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
  sudo docker pull "$image_name"
}

read_docker_compose_config() {
  local instance_name="$1"
  local base_dir=$(dirname "$(realpath "$0")")
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
    "RCON_ENABLED") config_key="RCON Enabled" ;;
    "DISPLAY_POK_MONITOR_MESSAGE") config_key="POK Monitor Message" ;;
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
  local base_dir=$(dirname "$(realpath "$0")")
  local instance_dir="${base_dir}/Instance_${instance_name}"
  local docker_compose_file="${instance_dir}/docker-compose-${instance_name}.yaml"
  local image_tag=$(get_docker_image_tag "$instance_name")

  # Ensure the instance directory exists
  mkdir -p "${instance_dir}"

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

  # Add the PUID/PGID comments or values based on the determined image tag
  if [[ "$image_tag" == 2_0* ]]; then
    # For 2_0 images, the default is 1000:1000
    cat >> "$docker_compose_file" <<-EOF
      # User/Group settings for legacy compatibility with 2_0 images (1000:1000)
      - PUID=1000                          # User ID for container processes and file ownership
      - PGID=1000                          # Group ID for container processes and file ownership
EOF
  else
    # For 2_1 images, the default is 7777:7777
    cat >> "$docker_compose_file" <<-EOF
      # User/Group settings - Default is now 7777:7777, uncomment and set to 1000:1000 for legacy compatibility if needed
      # - PUID=7777                          # User ID for container processes and file ownership
      # - PGID=7777                          # Group ID for container processes and file ownership
EOF
  fi

  # Iterate over the config_order to maintain the order in Docker Compose
  for key in "${config_order[@]}"; do
    # Convert the friendly name to the actual environment variable key
    case "$key" in
      "BattleEye") env_key="BATTLEEYE" ;;
      "RCON Enabled") env_key="RCON_ENABLED" ;;
      "POK Monitor Message") env_key="DISPLAY_POK_MONITOR_MESSAGE" ;;
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
    echo -e "\n⚠️ IMPORTANT: This instance will use the 2_0 image with PUID:PGID 1000:1000."
    echo "Make sure your files are owned by a user with UID:GID 1000:1000 or modify the PUID/PGID settings in the compose file."
  else
    echo -e "\n⚠️ IMPORTANT: This instance will use the 2_1 image with PUID:PGID 7777:7777."
    echo "Make sure your files are owned by a user with UID:GID 7777:7777 or uncomment and modify the PUID/PGID settings in the compose file."
  fi
}

# Function to check and optionally adjust Docker command permissions
adjust_docker_permissions() {
  local config_file=$(get_config_file_path)

  if [ -f "$config_file" ]; then
    local use_sudo
    use_sudo=$(cat "$config_file")
    if [ "$use_sudo" = "false" ]; then
      echo "User has chosen to run Docker commands without 'sudo'."
      return
    fi
  else
    if groups $USER | grep -q '\bdocker\b'; then
      echo "User $USER is already in the docker group."
      read -r -p "Would you like to run Docker commands without 'sudo'? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Changing ownership of /var/run/docker.sock to $USER..."
        sudo chown $USER /var/run/docker.sock
        echo "false" > "$config_file"
        echo "User preference saved. You can now run Docker commands without 'sudo'."
        return
      fi
    else
      read -r -p "Config file not found. Do you want to add user $USER to the 'docker' group? [y/N] " add_to_group
      if [[ "$add_to_group" =~ ^[Yy]$ ]]; then
        echo "Adding user $USER to the 'docker' group..."
        sudo usermod -aG docker $USER
        echo "User $USER has been added to the 'docker' group."
        
        echo "Changing ownership of /var/run/docker.sock to $USER..."
        sudo chown $USER /var/run/docker.sock
        
        echo "You can now run Docker commands without 'sudo'."
        echo "false" > "$config_file"
        
        return
      else
        echo "true" > "$config_file"
        echo "Please ensure to use 'sudo' for Docker commands or run this script with 'sudo'."
        return
      fi
    fi
  fi

  echo "true" > "$config_file"
  echo "Please ensure to use 'sudo' for Docker commands or run this script with 'sudo'."
}

get_docker_preference() {
  local config_file=$(get_config_file_path)

  if [ -f "$config_file" ]; then
    local use_sudo
    use_sudo=$(cat "$config_file")
    echo "$use_sudo"
  else
    echo "true"
  fi
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
  echo "Performing '${action}' on all instances..."

  # Find all instance directories
  local instance_dirs=($(find ./Instance_* -maxdepth 0 -type d))

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
  local base_dir=$(dirname "$(realpath "$0")")
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
  local compose_files=($(find ./Instance_* -name 'docker-compose-*.yaml'))
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
  local instance_name=$1
  local docker_compose_file="./Instance_${instance_name}/docker-compose-${instance_name}.yaml"
  local image_tag=$(get_docker_image_tag "$instance_name")
  
  echo "-----Starting ${instance_name} Server with image tag ${image_tag}-----"
  
  # First check if the docker-compose file exists
  if [ ! -f "$docker_compose_file" ]; then
    echo "❌ ERROR: Docker Compose file not found at $docker_compose_file"
    echo "Make sure the instance ${instance_name} exists and is properly configured."
    exit 1
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
    local instance_dir="./Instance_${instance_name}"
    
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
            echo "❌ ERROR: Failed to start the server container."
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
    echo "You can view logs with: ./POK-manager.sh -logs ${instance_name}"
  else
    echo "❌ ERROR: Docker Compose file not found for instance ${instance_name}."
    exit 1
  fi
}

# Function to stop an instance
stop_instance() {
  local instance_name=$1
  local docker_compose_file="./Instance_${instance_name}/docker-compose-${instance_name}.yaml"

  echo "-----Stopping ${instance_name} Server-----"

  local use_sudo
  local config_file=$(get_config_file_path)
  if [ -f "$config_file" ]; then
    use_sudo=$(cat "$config_file")
  else
    use_sudo="true"
  fi

  if [ "$use_sudo" = "true" ]; then
    echo "Using 'sudo' for Docker commands..."
    if [ -f "$docker_compose_file" ]; then
      sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down
    else
      sudo docker stop -t 30 "asa_${instance_name}"
    fi
  else
    if [ -f "$docker_compose_file" ]; then
      $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down || {
        local exit_code=$?
        if [ $exit_code -eq 1 ] && [[ $($DOCKER_COMPOSE_CMD -f "$docker_compose_file" down 2>&1) =~ "permission denied" ]]; then
          echo "Permission denied error occurred while stopping the instance."
          echo "It seems the user is not set up correctly to run Docker commands without 'sudo'."
          echo "Falling back to using 'sudo' for Docker commands."
          sudo $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down
        else
          echo "An error occurred while stopping the instance:"
          echo "$($DOCKER_COMPOSE_CMD -f "$docker_compose_file" down 2>&1)"
          exit 1
        fi
      }
    else
      docker stop -t 30 "asa_${instance_name}" || {
        local exit_code=$?
        if [ $exit_code -eq 1 ] && [[ $(docker stop -t 30 "asa_${instance_name}" 2>&1) =~ "permission denied" ]]; then
          echo "Permission denied error occurred while stopping the container."
          echo "It seems the user is not set up correctly to run Docker commands without 'sudo'."
          echo "Falling back to using 'sudo' for Docker commands."
          sudo docker stop -t 30 "asa_${instance_name}"
        else
          echo "An error occurred while stopping the container:"
          echo "$(docker stop -t 30 "asa_${instance_name}" 2>&1)"
          exit 1
        fi
      }
    fi
  fi

  echo "Instance ${instance_name} stopped successfully."
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

  if [[ "$1" == "-all" ]]; then
    shift # Remove the -all flag
    local message="$*" # Remaining arguments form the message/command

    if [[ "$action" == "-shutdown" ]]; then
      local eta_seconds=$((wait_time * 60)) # Convert wait time to seconds
      local eta_time=$(date -d "@$(($(date +%s) + eta_seconds))" "+%Y-%m-%d %H:%M:%S") # Calculate ETA as a human-readable timestamp

      # Check if there are any running instances before processing the command
      if [ -n "$(list_running_instances)" ]; then
        for instance in $(list_running_instances); do
          echo "----- Server $instance: Command: ${action#-}${message:+ $message} -----"
          echo "Waiting for server $instance to finish with countdown... ETA: $eta_time"
          echo "Shutdown command sent to $instance. ETA: $wait_time minute(s)."
          inject_shutdown_flag_and_shutdown "$instance" "$message" "$wait_time" &
        done

        # Inform the user not to exit POK-manager and start the live countdown
        echo "Please do not exit POK-manager until the countdown is finished."

        # Start the live countdown in a background process
        (
          for ((i=eta_seconds; i>=0; i--)); do
            # Clear the line
            echo -ne "\033[2K\r"

            # Format the remaining time as minutes and seconds
            minutes=$((i / 60))
            seconds=$((i % 60))

            # Print the countdown
            echo -ne "ETA: ${minutes}m ${seconds}s\r"
            sleep 1
          done
          # Print a newline after the countdown is finished
          echo
        ) &

        wait # Wait for all background processes to complete
        echo "----- All running instances processed with $action command. -----"
        echo "Commands dispatched. Script exiting..."
        exit 0 # Exit the script after the countdown and shutdown processes are complete
      else
        echo "---- No Running Instances Found for command: $action -----"
        echo " To start an instance, use the -start -all or -start <instance_name> command."
        exit 1 # Exit the script with an error status
      fi
    elif [[ "$action" == "-restart" ]]; then
      # Check if there are any running instances before processing the command
      if [ -n "$(list_running_instances)" ]; then
        for instance in $(list_running_instances); do
          echo "----- Server $instance: Command: ${action#-}${message:+ $message} -----"
          run_in_container_background "$instance" "$action" "$message" &
        done
        echo "----- All running instances processed with $action command. -----"
      else
        echo "---- No Running Instances Found for command: $action -----"
        echo " To start an instance, use the -start -all or -start <instance_name> command."
      fi
      #echo "Commands dispatched. Script exiting..."
      exit 0 # Exit the script immediately after sending the restart command
    fi

    # Check if there are any running instances before processing the command
    if [ -n "$(list_running_instances)" ]; then
      # Create an associative array to store the output for each instance
      declare -A instance_outputs
      echo "----- Processing $action command for all running instances Please wait... -----"
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
    else
      echo "---- No Running Instances Found for command: $action -----"
      echo " To start an instance, use the -start -all or -start <instance_name> command."
    fi
  else
    local instance_name="$1"
    shift # Remove the instance name
    local message="$*" # Remaining arguments form the message/command

    # Check if the instance is running before processing the command
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
        local eta_seconds=$((wait_time * 60)) # Convert wait time to seconds
        local eta_time=$(date -d "@$(($(date +%s) + eta_seconds))" "+%Y-%m-%d %H:%M:%S") # Calculate ETA as a human-readable timestamp
        echo "Waiting for server $instance_name to finish with countdown... ETA: $eta_time"
        echo "Shutdown command sent to $instance_name. ETA: $wait_time minute(s)."
        inject_shutdown_flag_and_shutdown "$instance_name" "$message" "$wait_time" &

        # Start the live countdown in a background process
        (
          for ((i=eta_seconds; i>=0; i--)); do
            # Clear the line
            echo -ne "\033[2K\r"

            # Format the remaining time as minutes and seconds
            minutes=$((i / 60))
            seconds=$((i % 60))

            # Print the countdown
            echo -ne "ETA: ${minutes}m ${seconds}s\r"
            sleep 1
          done
          # Print a newline after the countdown is finished
          echo
        ) &

        wait # Wait for the shutdown process to complete
        echo "----- Shutdown Complete for instance: $instance_name -----"
        echo "Commands dispatched. Script exiting..."
        exit 0 # Exit the script after the countdown and shutdown process are complete
      elif [[ "$action" == "-restart" ]]; then
        run_in_container_background "$instance_name" "$action" "$message" &
        echo "Commands dispatched. Script exiting..."
        exit 0 # Exit the script immediately after sending the restart command
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
  #echo "Commands dispatched. Script exiting..."
}

# Updated function to wait for shutdown completion
wait_for_shutdown() {
  local instance="$1"
  local wait_time="$2"
  local container_name="asa_${instance}" # Assuming container naming convention

  # Loop until the PID file is removed
  while docker exec "$container_name" test -f /home/pok/${instance}_ark_server.pid; do
    sleep 5 # Check every 5 seconds. Adjust as necessary.
  done

  echo "Server $instance is ready for shutdown."
}

inject_shutdown_flag_and_shutdown() {
  local instance="$1"
  local message="$2"
  local container_name="asa_${instance}" # Assuming container naming convention
  local base_dir=$(dirname "$(realpath "$0")")
  local instance_dir="${base_dir}/Instance_${instance}"
  local docker_compose_file="${instance_dir}/docker-compose-${instance}.yaml"

  # Check if the container exists and is running
  if docker ps -q -f name=^/${container_name}$ > /dev/null; then
    # Inject shutdown.flag into the container
    docker exec "$container_name" touch /home/pok/shutdown.flag

    # Send the shutdown command to rcon_interface
    run_in_container "$instance" "-shutdown" "$message" >/dev/null 2>&1

    # Wait for shutdown completion
    wait_for_shutdown "$instance" "$wait_time"

    # Shutdown the container using docker-compose
    $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down
    echo "----- Shutdown Complete for instance: $instance-----"
  else
    echo "Instance ${instance} is not running or does not exist."
  fi
}

# Adjust `run_in_container` to correctly construct and execute the Docker command
run_in_container() {
  local instance="$1"
  local cmd="$2"
  local args="${@:3}" # Capture all remaining arguments as the command args

  local container_name="asa_${instance}" # Construct the container name
  local command="/home/pok/scripts/rcon_interface.sh ${cmd}"

  # Append args to command if provided
  if [ -n "$args" ]; then
    command+=" '${args}'" # Add quotes to encapsulate the arguments as a single string
  fi

  # Verify the container exists and is running, then execute the command and capture the output
  if docker ps -q -f name=^/${container_name}$ > /dev/null; then
    if [[ "$cmd" == "-shutdown" || "$cmd" == "-restart" ]]; then
      # Redirect all output to a variable for -shutdown and -restart commands
      output=$(docker exec "$container_name" /bin/bash -c "$command")
    else
      # Capture the output for all other commands
      output=$(docker exec "$container_name" /bin/bash -c "$command")
    fi
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
  local acf_file="$BASE_DIR/ServerFiles/arkserver/appmanifest_2430930.acf"

  if [ -f "$acf_file" ]; then
    local build_id=$(grep -E "^\s+\"buildid\"\s+" "$acf_file" | grep -o '[[:digit:]]*')
    echo "$build_id"
  else
    echo "error: appmanifest_2430930.acf file not found"
    return 1
  fi
}
check_for_POK_updates() {
  # Skip update checks when running in non-interactive mode (e.g., cron jobs)
  if [ -t 0 ]; then
    echo "Checking for updates to POK-manager.sh..."
  else
    # When running non-interactively, only check for updates if explicitly requested
    if [ "$1" != "force" ]; then
      return
    fi
  fi
  
  # Determine which branch to use for updates
  local branch_name="master"
  if [ "$POK_MANAGER_BRANCH" = "beta" ]; then
    branch_name="beta"
    if [ -t 0 ]; then # Only show this message in interactive mode
      echo "Using beta branch for updates"
    fi
  fi
  
  # Add timestamp as cache-busting parameter
  local timestamp=$(date +%s)
  local script_url="https://raw.githubusercontent.com/Acekorneya/Ark-Survival-Ascended-Server/${branch_name}/POK-manager.sh?t=${timestamp}"
  local temp_file="/tmp/POK-manager.sh"
  local update_info_file="${BASE_DIR}/config/POK-manager/update_available"
  
  mkdir -p "${BASE_DIR}/config/POK-manager"

  local download_output
  local http_code
  
  if command -v curl &>/dev/null; then
    download_output=$(curl -s -w "%{http_code}" -o "$temp_file" "$script_url")
    http_code=${download_output: -3}  # Get the last 3 characters (HTTP status code)
  elif command -v wget &>/dev/null; then
    wget -q -O "$temp_file" "$script_url"
    # wget doesn't return HTTP codes the same way, so we check if the file exists and has content
    if [ -s "$temp_file" ]; then
      http_code="200"
    else
      http_code="404"  # Default error code for wget
    fi
  else
    echo "Neither wget nor curl is available. Unable to check for updates."
    return
  fi

  if [ "$http_code" = "200" ] && [ -f "$temp_file" ]; then
    # Check if the downloaded file is at least 1KB in size
    if [ -s "$temp_file" ] && [ $(stat -c%s "$temp_file") -ge 1024 ]; then
      # Extract version information from the downloaded file
      local new_version=$(grep -m 1 "POK_MANAGER_VERSION=" "$temp_file" | cut -d'"' -f2)
      
      echo "DEBUG: GitHub version: $new_version, Local version: $POK_MANAGER_VERSION" >&2
      echo "DEBUG: GitHub URL: $script_url" >&2
      
      if [ -n "$new_version" ]; then
        # Compare versions using sort for proper semantic versioning comparison
        local current_version="$POK_MANAGER_VERSION"
        
        # Function to convert version string to comparable number
        version_to_number() {
          local ver=$1
          
          # Parse the version string directly to extract major, minor, and patch
          IFS='.' read -r major minor patch <<< "$ver"
          
          # Default values if any part is missing
          major=${major:-0}
          minor=${minor:-0}
          patch=${patch:-0}
          
          # Debug output
          echo "DEBUG: Parsing version $ver into: major=$major, minor=$minor, patch=$patch" >&2
          
          # Convert to a single number for comparison
          echo $((major * 1000000 + minor * 1000 + patch))
        }
        
        local current_num=$(version_to_number "$current_version")
        local new_num=$(version_to_number "$new_version")
        
        echo "DEBUG: Numeric comparison - Local: $current_num, GitHub: $new_num" >&2
        
        # Only notify if the new version is actually newer
        if [ $new_num -gt $current_num ]; then
          echo "************************************************************"
          echo "* A newer version of POK-manager.sh is available: $new_version *"
          echo "* Current version: $current_version                           *"
          
          # Ask if the user wants to upgrade if we're in interactive mode
          if [ -t 0 ]; then
            echo -n "* Would you like to upgrade now? (y/n): "
            read -r upgrade_response
            if [[ "$upgrade_response" =~ ^[Yy]$ ]]; then
              # Call the upgrade function
              upgrade_pok_manager
              return
            else
              echo "* Run './POK-manager.sh -upgrade' later to perform the update     *"
            fi
          else
            echo "* Run './POK-manager.sh -upgrade' to perform the update     *"
          fi
          echo "************************************************************"
          
          # Store the update information for later use
          echo "$new_version" > "$update_info_file"
          # Copy the downloaded script to a temporary location for later use
          cp "$temp_file" "${BASE_DIR}/config/POK-manager/new_version"
          chmod +x "${BASE_DIR}/config/POK-manager/new_version"
          
          # Clean up
          rm "$temp_file"
        else
          if [ -t 0 ]; then # Only show this in interactive mode
            echo "----- POK-manager.sh is already up to date (version $current_version) -----"
          fi
          rm "$temp_file"
          # Remove the update info file if it exists but no update is available
          rm -f "$update_info_file"
          rm -f "${BASE_DIR}/config/POK-manager/new_version"
        fi
      else
        # If we can't extract a version but files differ, just notify about the difference
        if ! cmp -s "$0" "$temp_file"; then
          # Check if the files are functionally different by comparing checksums of content 
          # excluding comments, whitespace, and empty lines
          local file1_checksum=$(grep -v "^#" "$0" | grep -v "^$" | tr -d '[:space:]' | md5sum | cut -d' ' -f1)
          local file2_checksum=$(grep -v "^#" "$temp_file" | grep -v "^$" | tr -d '[:space:]' | md5sum | cut -d' ' -f1)
          
          echo "DEBUG: File checksums - Local: $file1_checksum, GitHub: $file2_checksum" >&2
          
          if [ "$file1_checksum" != "$file2_checksum" ]; then
            echo "************************************************************"
            echo "* An update to POK-manager.sh is available                 *"
            echo "* Run './POK-manager.sh -upgrade' to perform the update    *"
            echo "************************************************************"
            
            # Store the update information for later use
            echo "unknown" > "$update_info_file"
            # Copy the downloaded script to a temporary location for later use
            cp "$temp_file" "${BASE_DIR}/config/POK-manager/new_version"
            chmod +x "${BASE_DIR}/config/POK-manager/new_version"
          else
            if [ -t 0 ]; then # Only show this in interactive mode
              echo "----- POK-manager.sh is already up to date -----"
            fi
            # Remove the update info file if it exists but no update is available
            rm -f "$update_info_file"
            rm -f "${BASE_DIR}/config/POK-manager/new_version"
          fi
          
          # Clean up
          rm "$temp_file"
        else
          if [ -t 0 ]; then # Only show this in interactive mode
            echo "----- POK-manager.sh is already up to date -----"
          fi
          rm "$temp_file"
          # Remove the update info file if it exists but no update is available
          rm -f "$update_info_file"
          rm -f "${BASE_DIR}/config/POK-manager/new_version"
        fi
      fi
    else
      if [ -t 0 ]; then # Only show this in interactive mode
        echo "Downloaded file is either empty or too small. Skipping update check."
      fi
      rm "$temp_file"
    fi
  else
    if [ -t 0 ]; then # Only show this in interactive mode
      if [ "$http_code" = "404" ]; then
        echo "Error: File not found on GitHub (404). This might happen if you're using a branch that doesn't exist."
        echo "Current branch setting: $branch_name"
      else
        echo "Failed to download the update (HTTP code: $http_code). Skipping update check."
      fi
    fi
    rm -f "$temp_file"
  fi
}

install_steamcmd() {
  local steamcmd_dir="$BASE_DIR/config/POK-manager/steamcmd"
  local steamcmd_script="$steamcmd_dir/steamcmd.sh"
  local steamcmd_binary="$steamcmd_dir/linux32/steamcmd"

  if [ ! -f "$steamcmd_script" ] || [ ! -f "$steamcmd_binary" ]; then
    echo "SteamCMD not found. Attempting to install SteamCMD..."

    mkdir -p "$steamcmd_dir"

    if [ -f /etc/debian_version ]; then
      # Debian or Ubuntu
      sudo dpkg --add-architecture i386
      sudo apt-get update
      sudo apt-get install -y curl lib32gcc-s1
    elif [ -f /etc/redhat-release ]; then
      # Red Hat, CentOS, or Fedora
      if command -v dnf &>/dev/null; then
        sudo dnf install -y curl glibc.i686 libstdc++.i686
      else
        sudo yum install -y curl glibc.i686 libstdc++.i686
      fi
    elif [ -f /etc/arch-release ]; then
      # Arch Linux
      sudo pacman -Sy --noconfirm curl lib32-gcc-libs
    else
      echo "Unsupported Linux distribution. Please install curl and 32-bit libraries manually and run the setup again."
      return 1
    fi

    curl -s "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar -xz -C "$steamcmd_dir"

    # Set executable permissions on steamcmd.sh and steamcmd binary
    adjust_ownership_and_permissions "$steamcmd_dir"
    chmod +x "$steamcmd_script"
    chmod +x "$steamcmd_binary"

    if [ -f "$steamcmd_script" ] && [ -f "$steamcmd_binary" ]; then
      echo "SteamCMD has been successfully installed."
    else
      echo "Failed to install SteamCMD. Please install it manually and run the setup again."
      return 1
    fi
  else
    echo "SteamCMD is already installed."
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
  local build_id=$(curl -sX GET "https://api.steamcmd.net/v1/info/$app_id" | jq -r ".data.\"$app_id\".depots.branches.public.buildid")
  echo "$build_id"
}
ensure_steamcmd_executable() {
  local steamcmd_dir="$BASE_DIR/config/POK-manager/steamcmd"
  local steamcmd_script="$steamcmd_dir/steamcmd.sh"
  local steamcmd_binary="$steamcmd_dir/linux32/steamcmd"

  if [ -f "$steamcmd_script" ]; then
    if [ ! -x "$steamcmd_script" ]; then
      echo "Making SteamCMD script executable..."
      chmod +x "$steamcmd_script"
    fi
  else
    echo "SteamCMD script not found. Please make sure it is installed correctly."
    exit 1
  fi

  if [ -f "$steamcmd_binary" ]; then
    if [ ! -x "$steamcmd_binary" ]; then
      echo "Making SteamCMD binary executable..."
      chmod +x "$steamcmd_binary"
    fi
  else
    echo "SteamCMD binary not found. Please make sure it is installed correctly."
    exit 1
  fi
}

manage_backup_rotation() {
  local instance_name="$1"
  local max_backups="$2"
  local max_size_gb="$3"

  local main_dir="${MAIN_DIR%/}"
  local backup_dir="${main_dir}/backups/${instance_name}"

  # Convert max_size_gb to bytes
  local max_size_bytes=$((max_size_gb * 1024 * 1024 * 1024))

  # Get a list of backup files sorted by modification time (oldest first)
  local backup_files=($(ls -tr "${backup_dir}/"*.tar.gz 2>/dev/null))

  # Check if the number of backups exceeds the maximum allowed
  while [ ${#backup_files[@]} -gt $max_backups ]; do
    # Remove the oldest backup
    local oldest_backup="${backup_files[0]}"
    echo "Removing old backup: $oldest_backup"
    rm "$oldest_backup"
    # Remove the oldest backup from the array
    backup_files=("${backup_files[@]:1}")
  done

  # Calculate the total size of the backups
  local total_size_bytes=0
  for backup_file in "${backup_files[@]}"; do
    total_size_bytes=$((total_size_bytes + $(stat -c%s "$backup_file")))
  done

  # Check if the total size exceeds the maximum allowed
  while [ $total_size_bytes -gt $max_size_bytes ]; do
    # Remove the oldest backup
    local oldest_backup="${backup_files[0]}"
    echo "Removing old backup due to size limit: $oldest_backup"
    local backup_size_bytes=$(stat -c%s "$oldest_backup")
    rm "$oldest_backup"
    total_size_bytes=$((total_size_bytes - backup_size_bytes))
    # Remove the oldest backup from the array
    backup_files=("${backup_files[@]:1}")
  done
}
read_backup_config() {
  local instance_name="$1"
  local config_file="${MAIN_DIR%/}/config/POK-manager/backup_${instance_name}.conf"

  if [ -f "$config_file" ]; then
    source "$config_file"
    max_backups=${MAX_BACKUPS:-10}
    max_size_gb=${MAX_SIZE_GB:-10}
  else
    max_backups=
    max_size_gb=
  fi
}

write_backup_config() {
  local instance_name="$1"
  local max_backups="$2"
  local max_size_gb="$3"

  local config_file="${MAIN_DIR%/}/config/POK-manager/backup_${instance_name}.conf"
  local config_dir=$(dirname "$config_file")
  
  mkdir -p "$config_dir"
  
  cat > "$config_file" <<EOF
MAX_BACKUPS=$max_backups
MAX_SIZE_GB=$max_size_gb
EOF
}

prompt_backup_config() {
  local instance_name="$1"
  read -p "Enter the maximum number of backups to keep for instance $instance_name: " max_backups
  read -p "Enter the maximum size limit (in GB) for instance $instance_name backups: " max_size_gb
  write_backup_config "$instance_name" "$max_backups" "$max_size_gb"
}

backup_instance() {
  local instance_name="$1"

  if [[ "$instance_name" == "-all" ]]; then
    local instances=($(list_instances))
    for instance in "${instances[@]}"; do
      read_backup_config "$instance"
      if [ -z "$max_backups" ] || [ -z "$max_size_gb" ]; then
        echo "Backup configuration missing or incomplete for instance $instance."
        prompt_backup_config "$instance"
      fi
      backup_single_instance "$instance"
      manage_backup_rotation "$instance" "$max_backups" "$max_size_gb"
    done
  else
    read_backup_config "$instance_name"
    if [ -z "$max_backups" ] || [ -z "$max_size_gb" ]; then
      echo "Backup configuration missing or incomplete for instance $instance_name."
      prompt_backup_config "$instance_name"
    fi
    backup_single_instance "$instance_name"
    manage_backup_rotation "$instance_name" "$max_backups" "$max_size_gb"
  fi

  # Adjust ownership and permissions for the backup directory
  local main_dir="${MAIN_DIR%/}"
  local backup_dir="${main_dir}/backups"
  adjust_ownership_and_permissions "$backup_dir"
}

backup_single_instance() {
  local instance_name="$1"
  # Remove the trailing slash from $MAIN_DIR if it exists
  local main_dir="${MAIN_DIR%/}"
  local backup_dir="${main_dir}/backups/${instance_name}"
  
  # Get the current timezone using timedatectl
  local timezone="${USER_TIMEZONE:-$(timedatectl show -p Timezone --value)}"
  
  # Get the current timestamp based on the host's timezone
  local timestamp=$(TZ="$timezone" date +"%Y-%m-%d_%H-%M-%S")
  
  # Format the backup file name
  local backup_file="${instance_name}_backup_${timestamp}.tar.gz"
  
  mkdir -p "$backup_dir"

  local instance_dir="${main_dir}/Instance_${instance_name}"
  local saved_arks_dir="${instance_dir}/Saved/SavedArks"
  if [ -d "$saved_arks_dir" ]; then
    echo "Creating backup for instance $instance_name..."
    tar -czf "${backup_dir}/${backup_file}" -C "$instance_dir/Saved" "SavedArks"
    echo "Backup created: ${backup_dir}/${backup_file}"
  else
    echo "SavedArks directory not found for instance $instance_name. Skipping backup."
  fi
}
restore_instance() {
  local instance_name="$1"
  # Remove the trailing slash from $MAIN_DIR if it exists
  local main_dir="${MAIN_DIR%/}"
  local backup_dir="${main_dir}/backups"

  if [ -z "$instance_name" ]; then
    echo "No instance name specified. Please select an instance to restore from the list below."
    local instances=($(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;))
    if [ ${#instances[@]} -eq 0 ]; then
      echo "No instances found with backups."
      return
    fi
      
    for ((i=0; i<${#instances[@]}; i++)); do
      echo "$((i+1)). ${instances[i]}"
    done
    echo "----- Warning: This will stop the server if it is running. -----"
    read -p "Enter the number of the instance to restore: " choice  
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#instances[@]} ]; then
      instance_name="${instances[$((choice-1))]}"
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

    if [[ " $(list_running_instances) " =~ " $instance_name " ]]; then
      echo "Stopping the server."
      stop_instance "$instance_name"
    fi

    echo "Here is a list of all your backup archives:"
    for ((i=0; i<${#backup_files[@]}; i++)); do
      echo "$((i+1)) ------ File: $(basename "${backup_files[i]}")"
    done

    read -p "Please input the number of the archive you want to restore: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#backup_files[@]} ]; then
      local selected_backup="${backup_files[$((choice-1))]}"
      local instance_dir="${main_dir}/Instance_${instance_name}"
      local saved_arks_dir="${instance_dir}/Saved/SavedArks"

      echo "$(basename "$selected_backup") is getting restored ..."
      mkdir -p "$saved_arks_dir"
      tar -xzf "$selected_backup" -C "$instance_dir/Saved"
      adjust_ownership_and_permissions "$saved_arks_dir"
      echo "Backup restored successfully!"

      echo "Starting server..."
      start_instance "$instance_name"
      echo "Server should be up in a few minutes."
    else
      echo "Invalid choice."
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
  if ! docker ps -q -f name=^/asa_${instance_name}$ > /dev/null; then
    echo "Instance $instance_name is not running or does not exist."
    return 1
  fi
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
  local instance_name=$2
  local additional_args="${@:3}"
  # Ensure root privileges for specific actions
  if [[ "$action" == "-setup" ]]; then
  check_puid_pgid_user "$PUID" "$PGID"
  fi

  # Adjust Docker permissions only for actions that explicitly require Docker interaction
  case $action in
  -start | -stop | -update | -create | -edit | -restore | -logs | -backup | -restart | -shutdown | -status | -chat | -saveworld)
    adjust_docker_permissions
    ;;
  esac

  # Special handling for -start all and -stop all actions
  if [[ "$action" == "-start" || "$action" == "-stop" ]] && [[ "$instance_name" == "-all" ]]; then
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
    elif [[ "$instance_name" == "-all" ]]; then
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
  *)
    echo "Invalid action. Usage: $0 {action} [additional_args...] {instance_name}"
    echo "Actions include: -start, -stop, -update, -create, -setup, -status, -restart, -saveworld, -chat, -custom, -backup, -restore"
    exit 1
    ;;
  esac
}
# Define valid actions
declare -a valid_actions
valid_actions=("-create" "-start" "-stop" "-saveworld" "-shutdown" "-restart" "-status" "-update" "-install" "-list" "-beta" "-stable" "-version" "-upgrade" "-console" "-logs" "-backup" "-restore" "-showconfig" "-migrate")

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
  echo "  -version                                  Display the current version of POK-manager"
}

# Display version information
display_version() {
  echo "POK-manager.sh version ${POK_MANAGER_VERSION} (${POK_MANAGER_BRANCH})"
  echo "Default PUID: ${PUID}, PGID: ${PGID}"
  local image_tag=$(get_docker_image_tag)
  echo "Docker image: acekorneya/asa_server:${image_tag}"
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
    new_tag="2_0_latest"
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
  
  if [ "${PUID}" = "${legacy_puid}" ] && [ "${PGID}" = "${legacy_pgid}" ]; then
    echo "Running in legacy compatibility mode with PUID:PGID=${PUID}:${PGID}"
    echo "Docker Compose files will maintain existing PUID/PGID settings."
  else
    echo "Using PUID:PGID=${PUID}:${PGID}"
    echo "Docker Compose files will maintain their existing PUID/PGID settings for backward compatibility."
    echo "New instances will use the commented out PUID/PGID values by default."
  fi
  
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
  echo "Checking for updates to POK-manager.sh..."
  
  # Create the config directory if it doesn't exist
  mkdir -p "${BASE_DIR%/}/config/POK-manager"
  
  # Backup the current script
  cp "$0" "${BASE_DIR%/}/config/POK-manager/pok-manager.backup"
  echo "Backed up current script to ${BASE_DIR%/}/config/POK-manager/pok-manager.backup"
  
  # Check if we're in beta mode
  local branch="master"
  if check_beta_mode; then
    branch="beta"
  fi
  
  # Download the latest version from GitHub
  echo "Downloading the latest version from GitHub ($branch branch)..."
  
  # URL to download from with cache-busting parameter
  local timestamp=$(date +%s)
  local script_url="https://raw.githubusercontent.com/Acekorneya/Ark-Survival-Ascended-Server/$branch/POK-manager.sh?t=${timestamp}"
  local download_output
  
  # Execute curl and capture both output and HTTP status code
  download_output=$(curl -s -w "%{http_code}" -o "${BASE_DIR%/}/POK-manager.sh.new" "$script_url")
  local http_code=${download_output: -3}  # Get the last 3 characters (HTTP status code)
  
  if [ "$http_code" = "200" ] && [ -s "${BASE_DIR%/}/POK-manager.sh.new" ]; then
    # Make the new file executable
    chmod +x "${BASE_DIR%/}/POK-manager.sh.new"
    
    # Replace the old file with the new one
    mv "${BASE_DIR%/}/POK-manager.sh.new" "$0"
    echo "Update successful. POK-manager.sh has been updated to the latest version."
  elif [ "$http_code" = "404" ]; then
    echo "Error: File not found on GitHub (404). Please check that the repository and branch exist:"
    echo "Repository: https://github.com/Acekorneya/Ark-Survival-Ascended-Server"
    echo "Branch: $branch"
    # Clean up the incomplete download
    rm -f "${BASE_DIR%/}/POK-manager.sh.new"
  else
    echo "Failed to download the update (HTTP code: $http_code). Please try again later or check your internet connection."
    # Clean up the incomplete download
    rm -f "${BASE_DIR%/}/POK-manager.sh.new"
    # Restore from backup if download failed
    cp "${BASE_DIR%/}/config/POK-manager/pok-manager.backup" "$0"
    echo "Restored from backup."
  fi
}

# Function to get the active container tag (latest or beta)
get_container_tag() {
  local instance_name="$1"
  
  # Determine the version based on instance name or file ownership
  local image_tag_version="2_1"  # Default to the new version
  
  # Check ownership of files to determine version compatibility
  if [ -d "${BASE_DIR}/ServerFiles/arkserver" ]; then
    local file_ownership=$(stat -c '%u:%g' "${BASE_DIR}/ServerFiles/arkserver")
    
    if [ "$file_ownership" = "1000:1000" ]; then
      image_tag_version="2_0"
    fi
  fi
  
  # If a beta flag file exists and POK_MANAGER_BRANCH is beta, use beta suffix
  if [ -f "${BASE_DIR}/config/POK-manager/beta_mode" ] && [ "$POK_MANAGER_BRANCH" = "beta" ]; then
    echo "${image_tag_version}_beta"
  else
    echo "${image_tag_version}_latest"
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
    echo "********************************************************************"
  else
    echo "POK-manager.sh script is up to date"
  fi

  echo "----- Checking for ARK server files & Docker image updates -----"
  echo "Note: This WILL update server files and Docker images, but NOT the script itself"

  # Pull the latest image - detect from any running instance or from file ownership
  # If there are running instances, use the first one's image
  local running_instances=($(list_running_instances))
  if [ ${#running_instances[@]} -gt 0 ]; then
    local instance_name="${running_instances[0]}"
    echo "Using instance '$instance_name' to determine appropriate Docker image"
    local image_tag=$(get_docker_image_tag "$instance_name")
    echo "Using Docker image tag: ${image_tag}"
    pull_docker_image "$instance_name"
  else 
    # No running instances, determine from file ownership
    echo "Determining Docker image based on file ownership"
    local image_tag=$(get_docker_image_tag "")
    echo "Using Docker image tag: ${image_tag}"
    pull_docker_image ""
  fi

  # Check if SteamCMD is installed, and install it if necessary
  install_steamcmd

  # Check if the server files are installed
  if [ ! -f "${BASE_DIR%/}/ServerFiles/arkserver/appmanifest_2430930.acf" ]; then
    echo "---- ARK server files not found. Installing server files using SteamCMD -----"
    ensure_steamcmd_executable # Make sure SteamCMD is executable
    if "${BASE_DIR%/}/config/POK-manager/steamcmd/steamcmd.sh" +force_install_dir "${BASE_DIR%/}/ServerFiles/arkserver" +login anonymous +app_update 2430930 +quit; then
      echo "----- ARK server files installed successfully -----"
      # Move the appmanifest_2430930.acf file to the correct location
      if [ -f "${BASE_DIR%/}/ServerFiles/arkserver/steamapps/appmanifest_2430930.acf" ]; then
        cp "${BASE_DIR%/}/ServerFiles/arkserver/steamapps/appmanifest_2430930.acf" "${BASE_DIR%/}/ServerFiles/arkserver/"
        echo "Copied appmanifest_2430930.acf to the correct location."
      else
        echo "appmanifest_2430930.acf not found in steamapps directory. Skipping move."
      fi
    else
      echo "Failed to install ARK server files using SteamCMD. Please check the logs for more information."
      exit 1
    fi
  else
    # Check for updates to the ARK server files
    local current_build_id=$(get_build_id_from_acf)
    local latest_build_id=$(get_current_build_id)

    if [ "$current_build_id" != "$latest_build_id" ]; then
      echo "---- New server build available: $latest_build_id Updating ARK server files -----"

      # Check if any running instance has the update_server.sh script
      local update_script_found=false
      for instance in $(list_running_instances); do
        if docker exec "asa_${instance}" test -f /home/pok/scripts/update_server.sh; then
          update_script_found=true
          echo "Running update_server.sh script in the container for instance: $instance"
          docker exec -it "asa_${instance}" /bin/bash -c "/home/pok/scripts/update_server.sh" | while read -r line; do
            echo "[$instance] $line"
          done
          break
        fi
      done

      if [ "$update_script_found" = false ]; then
        echo "No running instance found with the update_server.sh script. Updating server files using SteamCMD..."
        ensure_steamcmd_executable # Make sure SteamCMD is executable
        if "${BASE_DIR%/}/config/POK-manager/steamcmd/steamcmd.sh" +force_install_dir "${BASE_DIR%/}/ServerFiles/arkserver" +login anonymous +app_update 2430930 +quit; then
          echo "SteamCMD update completed successfully."
          # Move the appmanifest_2430930.acf file to the correct location
          if [ -f "${BASE_DIR%/}/ServerFiles/arkserver/steamapps/appmanifest_2430930.acf" ]; then
            cp "${BASE_DIR%/}/ServerFiles/arkserver/steamapps/appmanifest_2430930.acf" "${BASE_DIR%/}/ServerFiles/arkserver/"
            echo "Copied appmanifest_2430930.acf to the correct location."
          else
            echo "appmanifest_2430930.acf not found in steamapps directory. Skipping move."
          fi
        else
          echo "SteamCMD update failed. Please check the logs for more information."
          exit 1
        fi
      fi

      # Check if the server files were updated successfully
      local updated_build_id=$(get_build_id_from_acf)
      if [ "$updated_build_id" == "$latest_build_id" ]; then
        echo "----- ARK server files updated successfully to build id: $latest_build_id -----"
      else
        echo "----- Failed to update ARK server files to the latest build. Current build id: $updated_build_id -----"
        exit 1
      fi
    else
      echo "----- ARK server files are already up to date with build id: $current_build_id -----"
    fi
  fi

  echo "----- Update process completed -----"
}

# Function to update the Docker image tag in a docker-compose.yaml file
update_docker_compose_image_tag() {
  local compose_file="$1"
  local new_image_tag="$2"
  
  # Check if the file exists
  if [ ! -f "$compose_file" ]; then
    echo "Error: Docker compose file not found at $compose_file"
    return 1
  fi
  
  # Create a temporary file
  local tmp_file="${compose_file}.tmp"
  
  # Record the original ownership
  local file_owner=$(stat -c '%u' "$compose_file")
  local file_group=$(stat -c '%g' "$compose_file")
  
  # Read the file line by line and update the image tag
  while IFS= read -r line; do
    if [[ "$line" =~ image:[[:space:]]*acekorneya/asa_server:[0-9]+_[0-9]+_(latest|beta) ]] || 
       [[ "$line" =~ image:[[:space:]]*acekorneya/asa_server:.*$ ]]; then
      # Replace the image tag with the new one, ensuring we only output the exact tag string
      echo "    image: acekorneya/asa_server:${new_image_tag}" >> "$tmp_file"
    else
      # Keep the line as is
      echo "$line" >> "$tmp_file"
    fi
  done < "$compose_file"
  
  # Replace the original file with the updated one
  mv "$tmp_file" "$compose_file"
  
  # Restore the original ownership if running as sudo
  if is_sudo && [ -n "$file_owner" ] && [ -n "$file_group" ]; then
    chown "${file_owner}:${file_group}" "$compose_file"
  fi
  
  echo "Updated Docker Compose file to use image tag: ${new_image_tag}"
}

# Function to help users migrate file ownership
migrate_file_ownership() {
  echo "===== File Ownership Migration Tool ====="
  echo "This tool will help you migrate your file ownership from 1000:1000 to 7777:7777"
  echo "for compatibility with the new default Docker image."
  echo ""
  echo "⚠️ WARNING: This will change ownership of all your server files and may require elevated privileges."
  echo "Make sure all your server instances are stopped before proceeding."
  echo ""
  
  # Check if we have sudo access
  if ! is_sudo; then
    echo "This operation requires sudo privileges."
    echo "Please run this command with sudo: sudo ./POK-manager.sh -migrate"
    return 1
  fi
  
  # List all the directories that need ownership changes
  local dirs_to_change=()
  
  # Check if ServerFiles exists
  if [ -d "${BASE_DIR}/ServerFiles" ]; then
    dirs_to_change+=("${BASE_DIR}/ServerFiles")
  fi
  
  # Check for instance directories
  for instance_dir in "${BASE_DIR}"/Instance_*/; do
    if [ -d "$instance_dir" ]; then
      dirs_to_change+=("$instance_dir")
    fi
  done
  
  # Check for Cluster directory
  if [ -d "${BASE_DIR}/Cluster" ]; then
    dirs_to_change+=("${BASE_DIR}/Cluster")
  fi
  
  # Show the user which directories will be changed
  echo "The following directories will have their ownership changed to 7777:7777:"
  for dir in "${dirs_to_change[@]}"; do
    echo "  - $dir"
  done
  
  # Ask for confirmation
  read -p "Are you sure you want to proceed? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    return 1
  fi
  
  # Change ownership of each directory
  echo "Changing file ownership to 7777:7777..."
  for dir in "${dirs_to_change[@]}"; do
    echo "Processing: $dir"
    chown -R 7777:7777 "$dir"
  done
  
  echo "✅ File ownership migration complete."
  echo ""
  echo "Your files are now compatible with the 2_1_latest Docker image."
  echo "Any running servers will need to be restarted to use the new image."
  echo ""
  echo "Note: If you want to go back to the 1000:1000 ownership, you can run:"
  echo "sudo chown -R 1000:1000 ${BASE_DIR}/ServerFiles ${BASE_DIR}/Instance_* ${BASE_DIR}/Cluster"
  
  return 0
}

main() {
  # Extract the command portion without PUID/PGID
  local command_args=""
  
  # Skip the script name in $0
  for arg in "$@"; do
    command_args="${command_args} ${arg}"
  done
  
  # Remove leading space
  command_args="${command_args# }"
  
  # Check for required user and group at the start
  check_puid_pgid_user "$PUID" "$PGID" "$command_args"
  check_for_POK_updates
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
    # For stable branch, check file ownership to determine compatibility version
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

# Invoke the main function with all passed arguments
main "$@"
