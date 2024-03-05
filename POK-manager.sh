#!/bin/bash
BASE_DIR="$(dirname "$(realpath "$0")")/"
MAIN_DIR="$BASE_DIR"
SERVER_FILES_DIR="./ServerFiles/arkserver"
CLUSTER_DIR="./Cluster"
instance_dir="./Instance_${instance_name}"
# Set PUID and PGID to match the container's expected values
PUID=1000
PGID=1000
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
    "BattleEye"|"RCON Enabled"|"POK Monitor Message"|"Update Server"|"MOTD Enabled")
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

  if [ ! -d "$dir" ]; then
    echo "Error: Directory does not exist: $dir"
    return 1
  fi

  echo "Checking and adjusting ownership and permissions for $dir..."
  chown -R 1000:1000 "$dir"
  find "$dir" -type d -exec chmod 755 {} \;
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
    echo "Run 'sudo sysctl -w vm.max_map_count=262144' to temporarily fix this issue."
    echo "For a permanent fix, add 'vm.max_map_count=262144' to /etc/sysctl.conf and run 'sudo sysctl -p'."
    exit 1
  fi
}
check_puid_pgid_user() {
  local puid="$1"
  local pgid="$2"

  # Check if the script is run with sudo (EUID is 0)
  if [ "${EUID}" -eq 0 ]; then
    echo "Running with sudo privileges. Skipping PUID and PGID check."
    return
  fi

  local current_uid=$(id -u)
  local current_gid=$(id -g)
  local current_user=$(id -un)

  if [ "${current_uid}" -ne "${puid}" ] || [ "${current_gid}" -ne "${pgid}" ]; then
    echo "You are not running the script as the user with the correct PUID (${puid}) and PGID (${pgid})."
    echo "Your current user '${current_user}' has UID ${current_uid} and GID ${current_gid}."
    echo "Please switch to the correct user or update your current user's UID and GID to match the required values."
    echo "Alternatively, you can run the script with sudo to bypass this check: sudo .POK-manager.sh <commands>"
    exit 1
  fi
  # Check if a user with the specified PUID exists
  local puid_user=$(getent passwd "${puid}" | cut -d: -f1)
  if [ -z "${puid_user}" ]; then
    echo "No user found with UID (${puid}). You may need to create a user with this UID or change an existing user's UID."
    echo "To create a new user with the specified UID, run the following command:"
    echo "sudo useradd -u (${puid}) -m -s /bin/bash <username>"
    echo "Replace <username> with your preferred username."
    exit 1
  else
    echo "Found user with UID ${puid}: ${puid_user}. Proceeding..."
  fi

  # Check if a group with the specified PGID exists
  local pgid_group=$(getent group "${pgid}" | cut -d: -f1)
  if [ -z "${pgid_group}" ]; then
    echo "No group found with GID (${pgid}_. You may need to create a group with this GID or change an existing group's GID."
    echo "To create a new group with the specified GID, run the following command:"
    echo "sudo groupadd -g (${pgid}_ <groupname>"
    echo "Replace <groupname> with your preferred group name."
    exit 1
  else
    echo "Found group with GID ${pgid}: ${pgid_group}. Proceeding..."
  fi

  # Check if the user is a member of the group
  local user_groups=$(groups "${puid_user}")
  if ! echo "${user_groups}" | grep -qw "${pgid_group}"; then
    echo "The user '${puid_user}' is not a member of the group '${pgid_group}'. You may need to add the user to the group."
    echo "To add the user to the group, run the following command:"
    echo "sudo usermod -aG ${pgid_group} ${puid_user}"
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
    chown 1000:1000 "${config_dir}/GameUserSettings.ini"
  fi

  # Copy Game.ini if it does not exist
  if [ ! -f "${config_dir}/Game.ini" ]; then
    echo "Copying default Game.ini"
    cp ./defaults/Game.ini "$config_dir"
    chown 1000:1000 "${config_dir}/Game.ini"
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
  # Check vm.max_map_count
  #check_vm_max_map_count
  check_puid_pgid_user "$PUID" "$PGID"
  check_dependencies
  install_yq
  adjust_ownership_and_permissions "$BASE_DIR"
  
  echo "Root tasks completed. You're now ready to create an instance."
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

  # Ensure the instance directory exists
  mkdir -p "${instance_dir}"

  # Start writing the Docker Compose configuration
  cat > "$docker_compose_file" <<-EOF
version: '2.4'

services:
  asaserver:
    build: .
    image: acekorneya/asa_server:beta
    container_name: asa_${instance_name} 
    restart: unless-stopped
    environment:
      - INSTANCE_NAME=${instance_name}
EOF

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
    volumes:
      - "${base_dir}/ServerFiles/arkserver:/home/pok/arkserver"
      - "${instance_dir}/Saved:/home/pok/arkserver/ShooterGame/Saved"
$(if [ -n "${config_values[Cluster ID]}" ]; then echo "      - \"${base_dir}/Cluster:/home/pok/arkserver/ShooterGame/Saved/clusters\"" ; fi)
    mem_limit: ${config_values[Memory Limit]}
EOF
}

# Function to check and optionally adjust Docker command permissions
adjust_docker_permissions() {
  local config_file=$(get_config_file_path)

  if [ -f "$config_file" ]; then
    local use_sudo=$(cat "$config_file")
    if [ "$use_sudo" = "false" ]; then
      echo "User has chosen to run Docker commands without 'sudo'."
      return
    fi
  fi

  if groups $USER | grep -q '\bdocker\b'; then
    echo "User $USER is already in the docker group."
    read -r -p "Would you like to run Docker commands without 'sudo'? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      echo "false" > "$config_file"
      echo "User preference saved. You may need to log out and back in for this to take effect."
      return
    fi
  fi

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

# Check for root privileges
require_root_privileges() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "This action requires root privileges. Please run the script with 'sudo'."
    exit 1
  fi
}

# Function to start an instance
start_instance() {
  local instance_name=$1
  local docker_compose_file="./Instance_${instance_name}/docker-compose-${instance_name}.yaml"
  echo "-----Starting ${instance_name} Server-----"
  if [ -f "$docker_compose_file" ]; then
    echo "Using $DOCKER_COMPOSE_CMD for ${instance_name}..."
    $DOCKER_COMPOSE_CMD -f "$docker_compose_file" up -d
    echo "-----Server Started for ${instance_name} -----"
    echo "You can check the status of your server by running -status -all or -status ${instance_name}."
    if [ $? -ne 0 ]; then
      echo "Failed to start ${instance_name} using Docker Compose."
      exit 1
    fi
  else
    echo "Docker compose file for ${instance_name} does not exist. Please create it first."
    exit 1
  fi
}

# Function to stop an instance
stop_instance() {
  local instance_name=$1
  local docker_compose_file="./Instance_${instance_name}/docker-compose-${instance_name}.yaml"

  echo "-----Stopping ${instance_name} Server-----"

  # If Docker Compose file exists, use Docker Compose to stop the service
  if [ -f "$docker_compose_file" ]; then
    $DOCKER_COMPOSE_CMD -f "$docker_compose_file" down
    if [ $? -eq 0 ]; then
      echo "${instance_name} stopped successfully."
    else
      echo "Failed to stop ${instance_name} using Docker Compose."
    fi
  else
    # Direct Docker command if Docker Compose file is missing
    local container_name="asa_${instance_name}"
    if docker ps -q -f name=^/${container_name}$ > /dev/null; then
      docker stop -t 30 "${container_name}" && echo "Container ${container_name} stopped successfully." || echo "Failed to stop container ${container_name}."
    else
      echo "Container ${container_name} is not running or does not exist. No action taken."
    fi
  fi
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
    echo "Processing $action command on $instance_name..."
    # Check if there are any running instances for the specified instance name
    if [ -z "$(list_running_instances | grep -w "$instance_name")" ]; then
      echo "---- No Running Instances Found for command: $action -----"
      echo " To start an instance, use the -start -all or -start <instance_name> command."
      return
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
# Function to update an instance
update_manager_and_instances() {
  echo "Initiating update for POK-manager.sh and all instances..."

  # Update POK-manager.sh
  echo "Checking for updates to POK-manager.sh..."
  local script_url="https://raw.githubusercontent.com/yourusername/your-repo/main/POK-manager.sh"
  local temp_file="/tmp/POK-manager.sh"

  if command -v wget &>/dev/null; then
    wget -q -O "$temp_file" "$script_url"
  elif command -v curl &>/dev/null; then
    curl -s -o "$temp_file" "$script_url"
  else
    echo "Neither wget nor curl is available. Unable to download the update for POK-manager.sh."
  fi

  if [ -f "$temp_file" ]; then
    if ! cmp -s "$0" "$temp_file"; then
      mv "$temp_file" "$0"
      echo "POK-manager.sh has been updated. Please make sure to make it executable again using 'chmod +x POK-manager.sh'."
    else
      echo "POK-manager.sh is already up to date."
      rm "$temp_file"
    fi
  fi

  # Pull the latest image
  echo "Pulling latest Docker image..."
  docker pull acekorneya/asa_server:beta

  # Find all running instances and update them
  local running_instances=($(list_running_instances))
  if [ ${#running_instances[@]} -eq 0 ]; then
    echo "No running instances found. Please start an instance to update the ARK server files."
    return 1 # Exit the function with an error state
  fi

  for instance_name in "${running_instances[@]}"; do
    local container_name="asa_${instance_name}"
    echo "Updating instance ${instance_name}..."

    # Execute the update script inside the container
    echo "Executing update script inside ${container_name}..."
    docker exec "$container_name" /bin/bash -c "/home/pok/scripts/update_server.sh"
    if [ $? -ne 0 ]; then
      echo "Failed to execute update script inside ${instance_name}."
    else
      echo "${instance_name} updated successfully."
    fi
  done
}
manage_service() {
  get_docker_compose_cmd
  local action=$1
  local instance_name=$2
  local additional_args="${@:3}"
  # Ensure root privileges for specific actions
  if [[ "$action" == "-setup" ]]; then
  check_puid_pgid_user
  fi

  # Adjust Docker permissions only for actions that explicitly require Docker interaction
  case $action in
  -start | -stop | -update | -create)
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
    check_puid_pgid_user
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
  -stop)
    stop_instance "$instance_name"
    ;;
  -update)
    update_manager_and_instances
    exit 0
    ;;
  -shutdown)
    execute_rcon_command "$action" "$additional_args" "$instance_name" 
    ;;
  -restart | -chat | -custom)
    execute_rcon_command "$action" "$additional_args" "$instance_name" 
    ;;
  -saveworld |-status)
    execute_rcon_command "$action" "$instance_name"
    ;;
  *)
    echo "Invalid action. Usage: $0 {action} {instance_name} [additional_args...]"
    echo "Actions include: -start, -stop, -update, -create, -setup, -status, -restart, -saveworld, -chat, -custom"
    exit 1
    ;;
  esac
}

# Define valid actions for the script
valid_actions=("-list" "-edit" "-setup" "-create" "-start" "-stop" "-shutdown" "-update" "-status" "-restart" "-saveworld" "-chat" "-custom")

main() {
  # Check for required user and group at the start
  check_puid_pgid_user "$PUID" "$PGID"
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 {action} [instance_name] [additional_args...]"
    echo "Actions include: ${valid_actions[*]}"
    exit 1
  fi

  local action="$1"
  local instance_name="${2:-}" # Default to empty if not provided
  local additional_args="${@:3}" # Capture any additional arguments

  # Check if the provided action is valid
  if [[ ! " ${valid_actions[*]} " =~ " ${action} " ]]; then
    echo "Invalid action '${action}'."
    echo "Valid actions are: ${valid_actions[*]}"
    exit 1
  fi

  # Special check for -chat action to ensure message is quoted
  if [[ "$action" == "-chat" ]]; then
    if [[ "$#" -gt 3 ]]; then # More arguments than expected
      echo "It seems like the chat message was not properly quoted."
      echo "Please ensure the chat message is enclosed in quotes. Example:"
      echo "./POK-manager.sh -chat \"Your message here\" [instance_name|-all]"
      exit 1
    fi
  fi

  # Pass to the manage_service function
  manage_service "$action" "$instance_name" "$additional_args"
}

# Invoke the main function with all passed arguments
main "$@"