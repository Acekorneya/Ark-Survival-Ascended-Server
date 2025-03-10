# POK Ark Survival Ascended Server Management Script

<p align="center">
  <img src="https://ark.wiki.gg/images/thumb/0/0a/ASA_Logo_transparent.png/630px-ASA_Logo_transparent.png" alt="Ark Survival Ascended Logo" width="600">
</p>

[![Docker Pulls](https://img.shields.io/docker/pulls/acekorneya/asa_server?style=for-the-badge&logo=docker&logoColor=white&color=2496ED)](https://hub.docker.com/r/acekorneya/asa_server)
[![GitHub Stars](https://img.shields.io/github/stars/Acekorneya/Ark-Survival-Ascended-Server?style=for-the-badge&logo=github&color=yellow)](https://github.com/Acekorneya/Ark-Survival-Ascended-Server)
[![Discord](https://img.shields.io/badge/Discord-Join%20Us-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/9GJKWjQuXy)
[![Version](https://img.shields.io/badge/Version-2.1.xx-blue?style=for-the-badge&logo=docker&logoColor=white)](https://github.com/Acekorneya/Ark-Survival-Ascended-Server)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/acekorneyab)

## Introduction

POK-manager.sh is a powerful and user-friendly script for managing Ark Survival Ascended Server instances using Docker. It simplifies the process of creating, starting, stopping, updating, and performing various operations on server instances, making it easy for both beginners and experienced users to manage their servers effectively.

### Key Features

- 🚀 **Easy Setup**: Simple one-command installation and server creation
- 🔄 **Automatic Updates**: Keep your ARK server up-to-date with minimal effort
- 🌐 **Multi-Server Support**: Manage multiple server instances from a single script
- 🧰 **Powerful Tools**: Backups, restores, chat commands, and more
- 🔌 **AsaApi Support**: Easily enable and manage server plugins
- 🔒 **Secure**: Runs with correct permissions and without requiring root

## Quick Start Guide for New Linux Users

If you're new to Linux or Docker, this guide will help you get started quickly. Just copy and paste these commands:

```bash
# Install dependencies
sudo apt-get update && sudo apt-get install -y git

# Create the dedicated server user with correct permissions
# IMPORTANT: You must create the group BEFORE creating the user
sudo groupadd -g 7777 pokuser
sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
sudo passwd pokuser  # Create a secure password when prompted
# NOTE: You will need to type the password twice to confirm it
# The password won't be visible as you type for security reasons

# IMPORTANT: If you're on a cloud provider (Google Cloud VM, etc.)
# Add the new user to sudoers for required permissions
sudo usermod -aG sudo pokuser  # For Ubuntu/Debian-based systems
# OR
# sudo usermod -aG wheel pokuser  # For CentOS/RHEL-based systems

# CRITICAL: Set required system parameters
# Method 1: Temporary setting (will reset after reboot)
sudo sysctl -w vm.max_map_count=262144

# Method 2: Permanent setting (recommended)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Switch to the pokuser account
sudo su - pokuser

# Create a directory for your server files
mkdir -p ~/asa_server
cd ~/asa_server

# Download and set up POK-manager
git clone https://github.com/Acekorneya/Ark-Survival-Ascended-Server.git && \
mv Ark-Survival-Ascended-Server/POK-manager.sh . && \
chmod +x POK-manager.sh && \
mv Ark-Survival-Ascended-Server/defaults . && \
rm -rf Ark-Survival-Ascended-Server

# Run the setup command
sudo ./POK-manager.sh -setup
# NOTE: POK-manager will automatically install Docker and other dependencies if they're not found

# Create your first server instance
./POK-manager.sh -create my_server
```

After these steps, you'll have a working Ark Survival Ascended server setup. See the detailed [Installation](#installation) section for more information.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Critical System Requirements](#critical-system-requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Commands](#commands)
  - [Examples](#examples)
    - [Creating an Instance](#creating-an-instance)
    - [Starting and Stopping Instances](#starting-and-stopping-instances)
    - [Sending Chat Messages](#sending-chat-messages)
    - [Scheduling Automatic Restarts with Cron](#scheduling-automatic-restarts-with-cron)
    - [Scheduling Automatic Tasks with Cron](#scheduling-automatic-tasks-with-cron)
    - [Custom RCON Commands](#custom-rcon-commands)
    - [Backing Up and Restoring Instances](#backing-up-and-restoring-instances)
- [User Permissions](#user-permissions)
- [Upgrading to Version 2.1+](#upgrading-to-version-21)
- [Beta Testing](#beta-testing)
- [Safe Update Mechanism](#safe-update-mechanism)
- [Docker Compose Configuration](#docker-compose-configuration)
- [Ports](#ports)
- [Troubleshooting](#troubleshooting)
- [Hypervisor](#hypervisors)
- [Links](#links)
- [Support](#support)
- [Conclusion](#conclusion)
- [Support the Project](#support-the-project) 
- [Star History](#star-history)

## Prerequisites

Before using POK-manager.sh, ensure that you have the following prerequisites on your Linux system:

- Linux Host OS (Ubuntu, Debian, Arch) 
- `sudo` access
- Git (for initial download only)
- CPU - FX Series AMD Or Intel Second Gen Sandy Bridge CPU
- 16GB of RAM (or more) for each instance
- 80 GB for Server data

**Note:** POK-manager.sh will automatically install the following dependencies if they're not found on your system:
- [Docker](https://docs.docker.com/engine/install/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [yq](https://github.com/mikefarah/yq?tab=readme-ov-file#install)

This automatic dependency installation makes setup much easier for new users. All you need to start is Git and sudo access.

## Critical System Requirements

### Memory Mapping Configuration

ARK Survival Ascended Server has specific system requirements that **must** be met for the container to run properly:

```bash
# The vm.max_map_count parameter MUST be increased to at least 262144
```

You have two methods to apply this setting:

1. **Temporary Setting** (resets after system reboot):
   ```bash
   sudo sysctl -w vm.max_map_count=262144
   ```
   Use this if you're on a hosting provider that doesn't allow permanent changes.

2. **Permanent Setting** (recommended):
   ```bash
   echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```

⚠️ **IMPORTANT NOTE**: Without this setting, your ARK server container WILL crash or fail to start, typically with "Allocator Stats" errors in the logs. This is a host-level requirement that cannot be fixed within the container itself.

## Installation

### Beginner-Friendly Installation Guide (Recommended)

If you're new to Linux, follow these step-by-step instructions for a smooth setup:

1. **Create a dedicated user** with the correct UID/GID for the server:
   ```bash
   # IMPORTANT: You must create the group FIRST, then create the user
   # Create the user group with GID 7777
   sudo groupadd -g 7777 pokuser
   
   # Create the user with UID 7777
   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
   
   # Set a password for the new user
   sudo passwd pokuser
   
   # When prompted:
   # 1. Enter a secure password (will not be visible as you type)
   # 2. Re-enter the same password to confirm
   # 3. Make note of this password as you'll need it to log in as pokuser

   # IMPORTANT FOR CLOUD ENVIRONMENTS (Google Cloud VM, AWS, etc.):
   # The pokuser needs sudo access to run some commands
   # Add the user to the sudo group (Ubuntu/Debian) or wheel group (CentOS/RHEL)
   
   # For Ubuntu/Debian systems:
   sudo usermod -aG sudo pokuser
   
   # For CentOS/RHEL systems:
   # sudo usermod -aG wheel pokuser
   ```

2. **Configure system settings** for Ark server:
   ```bash
   # CRITICAL REQUIREMENT - The ARK server container will not work properly without this setting
   
   # Method 1: Temporary setting (will reset after reboot)
   sudo sysctl -w vm.max_map_count=262144
   
   # Method 2: Permanent setting (recommended)
   echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```
   > ⚠️ **IMPORTANT**: This step is absolutely necessary. The ARK server container will fail to run properly without this system parameter adjustment. If you're on a hosting provider that doesn't allow editing sysctl.conf, use Method 1 but note you'll need to reapply it after each system reboot.

3. **Switch to the pokuser account**:
   ```bash
   sudo su - pokuser
   ```

4. **Create a directory for your server** (optional but recommended):
   ```bash
   mkdir -p ~/asa_server
   cd ~/asa_server
   ```

5. **Download and set up POK-manager.sh**:
   ```bash
   git clone https://github.com/Acekorneya/Ark-Survival-Ascended-Server.git && \
   mv Ark-Survival-Ascended-Server/POK-manager.sh . && \
   chmod +x POK-manager.sh && \
   mv Ark-Survival-Ascended-Server/defaults . && \
   rm -rf Ark-Survival-Ascended-Server
   ```

6. **Run the setup command**:
   ```bash
   ./POK-manager.sh -setup
   ```
   
   During this step, POK-manager will:
   - Check for required dependencies (Docker, Docker Compose, yq)
   - Automatically install any missing dependencies
   - Configure Docker to work with the pokuser account
   - Prepare the environment for your ARK server
   
   Since you're already running as the pokuser with UID 7777, this should work without permission issues.

7. **Create your first server instance**:
   ```bash
   ./POK-manager.sh -create my_server
   ```
   
   Follow the prompts to configure your server. You can accept the defaults or customize settings as needed.

### Alternative Installation Options

1. **For experienced users** who want to download and set up in a single step:
   - Option 1: Run the following command to download and set up POK-manager.sh:
     ```bash
     git clone https://github.com/Acekorneya/Ark-Survival-Ascended-Server.git && sudo chown -R 7777:7777 Ark-Survival-Ascended-Server && sudo mv Ark-Survival-Ascended-Server/POK-manager.sh . && sudo chmod +x POK-manager.sh && sudo mv Ark-Survival-Ascended-Server/defaults . && sudo rm -rf Ark-Survival-Ascended-Server
     ```

   - Option 2: Follow these step-by-step commands:
     ```bash
     git clone https://github.com/Acekorneya/Ark-Survival-Ascended-Server.git
     sudo chown -R 7777:7777 Ark-Survival-Ascended-Server
     sudo mv Ark-Survival-Ascended-Server/POK-manager.sh .
     sudo chmod +x POK-manager.sh
     sudo mv Ark-Survival-Ascended-Server/defaults .
     sudo rm -rf Ark-Survival-Ascended-Server
     ```

### Beta Branch Installation (Optional)

If you want to test the latest features before they're officially released, you can install from the beta branch. Note that beta versions may contain experimental features and are not guaranteed to be stable.

```bash
# Clone from the beta branch (for testing purposes)
git clone -b beta https://github.com/Acekorneya/Ark-Survival-Ascended-Server.git && \
mv Ark-Survival-Ascended-Server/POK-manager.sh . && \
chmod +x POK-manager.sh && \
mv Ark-Survival-Ascended-Server/defaults . && \
rm -rf Ark-Survival-Ascended-Server
```

⚠️ **WARNING**: The beta branch may contain untested code and could potentially cause issues with your server. Only use the beta branch if you're willing to troubleshoot problems and report bugs. For production servers, we recommend using the stable branch (default installation commands above).

After installing from the beta branch, you can enable beta mode to receive beta updates:
```bash
./POK-manager.sh -beta
```

You can always switch back to the stable branch with:
```bash
./POK-manager.sh -stable
```

### Installation Tips for Different User Types

#### For Root Users
If you're installing as the root user or plan to run everything with sudo, follow these steps:

1. **Important**: The container always runs internally as user 7777 (or 1000 for legacy versions), even when run as root.

2. **Always use sudo with the script**:
   ```bash
   sudo ./POK-manager.sh <command>
   ```

3. **Set correct permissions for all files during setup**:
   ```bash
   # For newer installations (2.1+)
   sudo chown -R 7777:7777 /path/to/your/POK-manager/directory
   
   # For legacy installations (2.0)
   sudo chown -R 1000:1000 /path/to/your/POK-manager/directory
   ```

4. **Fix permission issues during runtime**:
   - If you encounter "Permission denied" or "Files not found" errors when starting the container, run:
     ```bash
     sudo chown -R 7777:7777 /path/to/your/POK-manager/ServerFiles
     sudo chown -R 7777:7777 /path/to/your/POK-manager/Instance_*
     ```

5. **Remember**: Running as root doesn't bypass the need for correct file ownership. The container still requires files owned by UID 7777 or 1000 to function properly.

#### For Non-Root Users (Recommended)
For better security and proper permissions, we strongly recommend running as a non-root user:

1. **Create a dedicated user** with the correct UID/GID:
   ```bash
   # Create the user group with GID 7777 (for newer 2.1+ installations)
   sudo groupadd -g 7777 pokuser
   
   # Create the user with matching UID
   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
   
   # Set a password for this user
   sudo passwd pokuser
   # Enter and confirm a secure password when prompted
   ```

2. **Add the user to the Docker group** (so it can run Docker commands):
   ```bash
   sudo usermod -aG docker pokuser
   ```

3. **Switch to this user** to run commands:
   ```bash
   sudo su - pokuser
   ```

4. **Files automatically have the correct ownership** when created by this user.

5. **Run without sudo** when logged in as this user:
   ```bash
   ./POK-manager.sh <command>
   ```

This approach provides better security while ensuring permissions are automatically correct. Most server issues are related to incorrect permissions, and using the dedicated user account prevents these problems.

## Usage

### Commands

- `-list`: Lists all available server instances.
- `-edit`: Allows editing the configuration of a specific server instance.
- `-setup`: Performs the initial setup tasks required for running server instances.
- `-create <instance_name>`: Creates a new server instance.
- `-start <instance_name|-all>`: Starts a specific server instance or all instances.
- `-stop <instance_name|-all>`: Stops a specific server instance or all instances.
- `-shutdown [minutes] <instance_name|-all>`: Shuts down a specific server instance or all instances with an optional countdown in minutes.
- `-update`: Checks for server files & Docker image updates (doesn't modify the script itself).
- `-upgrade`: Upgrades POK-manager.sh script to the latest version (requires confirmation).
- `-force-restore`: Forces restoration of POK-manager.sh from backup in case of update failure.
- `-status <instance_name|-all>`: Shows the status of a specific server instance or all instances.
- `-restart [minutes] <instance_name|-all>`: Restarts a specific server instance or all instances with an optional countdown in minutes.
- `-saveworld <instance_name|-all>`: Saves the world of a specific server instance or all instances.
- `-chat "<message>" <instance_name|-all>`: Sends a chat message to a specific server instance or all instances.
- `-custom <command> <instance_name|-all>`: Executes a custom command on a specific server instance or all instances.
- `-backup [instance_name|-all]`: Backs up a specific server instance or all instances (defaults to all if not specified).
- `-restore [instance_name]`: Restores a server instance from a backup.
- `-logs [-live] <instance_name>`: Displays logs for a specific server instance (optionally live).
- `-beta`: Switches to beta mode to use beta version Docker images.
- `-stable`: Switches to stable mode to use stable version Docker images.
- `-migrate`: Migrates file ownership from 1000:1000 to 7777:7777 for compatibility with 2_1 images.
- `-clearupdateflag <instance_name|-all>`: Clears a stale updating.flag file if an update was interrupted.
- `-API <TRUE|FALSE> <instance_name|-all>`: Enables or disables ArkServerAPI for specified instance(s).
- `-fix`: Fixes permissions on files owned by root (0:0) that could cause container issues.
- `-version`: Displays the current version of POK-manager.
- `-api-recovery`: Checks and recovers API instances with container restart.
- `-changelog`: Displays the changelog.
- `-rename <instance_name|-all>`: Renames a single instance or all instances.

### Examples

#### Creating an Instance
```bash
./POK-manager.sh -setup
./POK-manager.sh -create my_instance
```

#### Starting and Stopping Instances
```bash
./POK-manager.sh -start my_instance
./POK-manager.sh -stop my_instance
```

#### Sending Chat Messages
```bash
./POK-manager.sh -chat "Hello, world!" my_instance
```

#### Scheduling Automatic Restarts with Cron
To schedule automatic restarts using cron, add an entry to your crontab file. Here are a few examples:

- Restart all instances every day at 3 AM with a 10-minute countdown:
  ```
  0 3 * * * /path/to/POK-manager.sh -restart 10 -all
  ```

- Restart a specific instance every Sunday at 12 AM with a 5-minute countdown:
  ```
  0 0 * * 0 /path/to/POK-manager.sh -restart 5 my_instance
  ```

> **Note:** When using `-restart` with instances that have `API=TRUE`, the script automatically uses a special restart process that stops and starts the container instead of using the in-game restart command. This ensures proper restarting for API-enabled servers.

- Save the world of all instances every 30 minutes:
  ```
  */30 * * * * /path/to/POK-manager.sh -saveworld -all
  ```

- Automatic recovery for API-enabled instances every 15 minutes:
  ```
  */15 * * * * /path/to/POK-manager.sh -api-recovery
  ```
  This specialized command checks all API=TRUE instances and automatically restarts any container where the server process has crashed but the container is still running. This is particularly useful for API mode servers which can sometimes crash while their containers remain active.

#### Custom RCON Commands
You can execute custom RCON commands using the `-custom` flag followed by the command and the instance name or `-all` for all instances. Here are a few examples:

- List all players on all instances:
  ```bash
  ./POK-manager.sh -custom "listplayers" -all
  ```

- Give an item to a player on a specific instance:
  ```bash
  ./POK-manager.sh -custom "giveitem \"Blueprint'/Game/Mods/ArkModularWeapon/Weapons/IronSword/PrimalItem_IronSword.PrimalItem_IronSword'\" 1 0 0" my_instance
  ```

- Send a message to all players on a specific instance (using chat):
  ```bash
  ./POK-manager.sh -chat "Hello, players!" my_instance
  ```

> **Note:** Ark Survival Ascended (ASA) RCON commands are different from Ark Survival Evolved (ASE). Many commands from ASE are not supported in ASA or have different syntax. For example, the `broadcast` command doesn't work in ASA; instead, use `-chat` which implements the `ServerChat` command. The available commands in ASA are limited and finding working commands often requires trial and error. When using `-custom`, be prepared to experiment with different command formats.

#### Scheduling Automatic Tasks with Cron

Cron is a time-based job scheduler in Unix-like operating systems that allows you to run commands or scripts automatically at specified intervals. You can use cron to schedule tasks like automated backups or saving the world state of your Ark Survival Ascended Server instances.

To set up a cron job for running POK-manager.sh commands, follow these steps:

1. Open the terminal and type `crontab -e` to edit your user's crontab file. If prompted, choose an editor (e.g., nano).

2. In the crontab file, add a new line for each command you want to schedule. The format of a cron job is as follows:
   ```
   * * * * * /path/to/command
   ```
   - The asterisks (`*`) represent the minute, hour, day of the month, month, and day of the week, respectively.
   - Replace `/path/to/command` with the actual full path to POK-manager.sh and the command you want to run.

   **Important:** Always use the complete absolute path to your POK-manager.sh script in crontab entries. Since version 2.1.5x, you can directly use commands with the `-all` parameter without needing to change directories first.

   For example, to save the world state of all instances every 30 minutes:
   ```
   */30 * * * * /absolute/path/to/POK-manager.sh -saveworld -all
   ```
   
   To restart all instances every day at 3 AM with a 10-minute warning:
   ```
   0 3 * * * /absolute/path/to/POK-manager.sh -restart 10 -all
   ```
   This command will run every 3 hours, starting at midnight (e.g., 12:00 AM, 6:00 AM, 12:00 PM, 6:00 PM).

3. Save the changes and exit the editor. The cron jobs will now run automatically at the specified intervals.

> **Note:** Starting with version 2.1.5x, POK-manager can now correctly identify server instances when run from cron jobs or systemd timers, even with the `-all` parameter. You no longer need to create wrapper scripts to change directories before running commands.

Here are a few more examples of commonly used cron job schedules:

- Every minute: `* * * * *`
- Every hour: `0 * * * *`
- Every day at midnight: `0 0 * * *`
- Every Sunday at 3:00 AM: `0 3 * * 0`
- Every month on the 1st day at 5:30 AM: `30 5 1 * *`

You can use online cron job generators like [Crontab Guru](https://crontab.guru/) to help you create and validate your cron job schedules.

Remember to replace `/path/to/POK-manager.sh` with the actual path to your POK-manager.sh script, and adjust the instance names and commands according to your requirements.

By scheduling automatic tasks with cron, you can ensure regular backups, world saves, and other maintenance tasks are performed without manual intervention, providing a more reliable and convenient server management experience.

#### Backing Up and Restoring Instances
POK-manager.sh provides commands for backing up and restoring server instances. Here's how you can use them:

- Backup a specific instance:
  ```bash
  ./POK-manager.sh -backup my_instance
  ```

- Backup all instances:
  ```bash
  ./POK-manager.sh -backup -all
  ```

- Restore a specific instance from a backup:
  ```bash
  ./POK-manager.sh -restore my_instance
  ```

When you run the `-backup` command for the first time, POK-manager.sh will prompt you to specify the maximum number of backups to keep and the maximum size limit (in GB) for each instance's backup folder. These settings will be saved in a configuration file (`backup_<instance_name>.conf`) located in the `config/POK-manager` directory.

Subsequent runs of the `-backup` command will use the saved configuration. If you want to change the backup settings, you can manually edit the configuration file or delete it to be prompted again.

The `-backup` command creates a compressed tar archive of the `SavedArks` directory for each instance, which contains the saved game data. The backups are stored in the `backups/<instance_name>` directory.

The `-restore` command allows you to restore a specific instance from a backup. When you run the command, POK-manager.sh will display a list of available backup archives for the specified instance. You can choose the desired backup by entering its corresponding number. The script will then extract the backup and replace the current `SavedArks` directory with the backed-up version.

Note: Restoring a backup will overwrite the current saved game data for the specified instance.

## User Permissions

**Important Information About Container Permissions:**

The container runs with a fixed user ID (UID) and group ID (GID) that is set when the Docker image is built:

- 2_0_latest images use UID:GID 1000:1000
- 2_1_latest images use UID:GID 7777:7777 (default since version 2.1)

**These values cannot be changed at runtime.** For proper file access, the files on your host system must be owned by a user with a matching UID:GID.

### Running as Root User

If you're running the container as the root user, you **must still ensure** that file permissions are set correctly:

1. **Container User vs. Host User**: Even when you run commands as root, the container itself still runs internally as UID 7777 (or 1000 for older versions). The files must have this ownership to be accessible.

2. **Using sudo with POK-manager.sh**: When running as root, use the following format to ensure proper permissions are maintained:
   ```bash
   sudo ./POK-manager.sh <command>
   ```

3. **Permission Troubleshooting**: If you encounter "Permission denied" errors or "Server files not found" errors during startup, you likely have a permission issue. Fix it with:
   ```bash
   # For 2.1+ users (recommended)
   sudo chown -R 7777:7777 /path/to/your/POK-manager/directory
   
   # For 2.0 legacy users
   sudo chown -R 1000:1000 /path/to/your/POK-manager/directory
   ```

4. **Auto-fixing on Startup**: If the container detects permission issues during startup, it will try to fix them automatically, but this may not always succeed if the container doesn't have the right permissions to change ownership. In such cases, you'll need to manually fix permissions from the host.

> **Important**: Even if you are logged in as root or using sudo, your server files MUST be owned by the user ID that the container runs as (7777 or 1000). This is a fundamental requirement that cannot be bypassed.

### File Ownership Requirements

To prevent permission issues, your server files **must** have the correct ownership on the host machine:

```bash
# For 2_0_latest images (legacy compatibility)
sudo chown -R 1000:1000 /path/to/your/POK-manager/directory

# For 2_1_latest images (recommended)
sudo chown -R 7777:7777 /path/to/your/POK-manager/directory
```

### Migration Options

If you're upgrading from an earlier version, you have these options:

1. **Automatic Detection:** The script will automatically detect your file ownership and use the appropriate Docker image:
   - Files owned by 1000:1000 → Uses acekorneya/asa_server:2_0_latest (compatible with older settings)
   - Files owned by other UIDs → Uses acekorneya/asa_server:2_1_latest (new default)

2. **Option 1: Continue using 1000:1000 (backward compatibility):**
   ```bash
   # Ensure your files are owned by 1000:1000
   sudo chown -R 1000:1000 /path/to/your/POK-manager/directory
   ```

3. **Option 2: Migrate to the new 7777:7777 user (recommended):**
   ```bash
   # Use the built-in migration tool
   sudo ./POK-manager.sh -migrate
   
   # Or manually change ownership of your existing files
   sudo chown -R 7777:7777 /path/to/your/POK-manager/directory
   ```

### For New Users

New installations will default to the 7777:7777 user ID and group ID. This prevents running as root and enhances security while avoiding conflicts with the common default user ID (1000) on many Linux distributions.

When you create new instances, the script will automatically detect the appropriate image to use based on your file ownership and will provide guidance on setting the correct permissions.

## Docker Compose Configuration

When creating a new server instance using POK-manager.sh, a Docker Compose configuration file (`docker-compose-<instance_name>.yaml`) is generated. Here's an example of the generated file:

#### Environment Variables

| Variable                      | Default           | Description                                                                               |
| ------------------------------| ------------------| ------------------------------------------------------------------------------------------|
| `INSTANCE_NAME`               | `Instance_name`   | The name of the instance                                                                  |
| `TZ`                          | `America/Los_Angeles`| Timezone setting: Change this to your local timezone.                                  |
| `RANDOM_STARTUP_DELAY`        | `TRUE`            | Add a random delay (0-10s) during startup to prevent update conflicts when multiple instances start simultaneously |
| `BATTLEEYE`                   | `TRUE`            | Set to TRUE to use BattleEye, FALSE to not use BattleEye                                  |
| `API`                         | `FALSE`           | Set to TRUE to install and use AsaApi, FALSE to disable AsaApi                |
| `RCON_ENABLED`                | `TRUE`            | Needed for Graceful Shutdown                                                              |
| `DISPLAY_POK_MONITOR_MESSAGE` | `FALSE`           | TRUE to Show the Server Monitor Messages / Update Monitor Shutdown                        |
| `UPDATE_SERVER`               | `TRUE`            | Enable or disable update checks                                                           |
| `CHECK_FOR_UPDATE_INTERVAL`   | `24`              | Check for Updates interval in hours                                                       |
| `UPDATE_WINDOW_MINIMUM_TIME`  | `12:00 AM`        | Defines the minimum time, relative to server time, when an update check should run        |
| `UPDATE_WINDOW_MAXIMUM_TIME`  | `11:59 PM`        | Defines the maximum time, relative to server time, when an update check should run        |
| `RESTART_NOTICE_MINUTES`      | `30`              | Duration in minutes for notifying players before a server restart due to updates          |
| `ENABLE_MOTD`                 | `FALSE`           | Enable or disable Message of the Day                                                      |
| `MOTD`                        |                   | Message of the Day                                                                        |
| `MOTD_DURATION`               | `30`              | Duration for the Message of the Day                                                       |
| `MAP_NAME`                    | `TheIsland`       | The map name (`TheIsland') Or Custom Map Name Can Be Enter aswell                         |
| `SESSION_NAME`                | `Server_name`     | The session name for the server                                                           |
| `SERVER_ADMIN_PASSWORD`       | `MyPassword`      | The admin password for the server                                                         |
| `SERVER_PASSWORD`             |                   | Set a server password or leave it blank (ONLY NUMBERS AND CHARACTERS ARE ALLOWED BY DEVS) |
| `ASA_PORT`                    | `7777`            | The game port for the server                                                              |
| `RCON_PORT`                   | `27020`           | Rcon Port Use for Most Server Operations                                                  |
| `MAX_PLAYERS`                 | `127`             | Max allowed players                                                                       |
| `NOTIFY_ADMIN_COMMANDS_IN_CHAT`| `FALSE`          | Set to TRUE to notify admin commands in chat, FALSE to disable notifications              |
| `CLUSTER_ID`                  | `cluster`         | The Cluster ID for Server Transfers                                                       | 
| `PASSIVE_MODS`                | `123456`          | Replace with your passive mods IDs                                                        |
| `MOD_IDS`                     | `123456`          | Add your mod IDs here, separated by commas, e.g., 123456789,987654321                     |
| `CUSTOM_SERVER_ARGS`          |                   | If You need to add more Custom Args -ForceRespawnDinos -ForceAllowCaveFlyers              |

**Note:** User IDs (PUID) and Group IDs (PGID) are fixed at build time and cannot be changed at runtime:
- 2_0_latest images use PUID:GID 1000:1000
- 2_1_latest images use PUID:GID 7777:7777

Host file ownership must match these values to prevent permission issues.

---

```yaml
version: '2.4'

services:
  asaserver:
    build: .
    image: acekorneya/asa_server:2_0_latest
    container_name: asa_my_instance
    restart: unless-stopped
    environment:
      - INSTANCE_NAME=my_instance            # The name of the instance
      - TZ=America/Los_Angeles               # Timezone setting: Change this to your local timezone. Ex.America/New_York, Europe/Berlin, Asia/Tokyo
      - RANDOM_STARTUP_DELAY=TRUE            # Add a random delay (0-30s) during startup to prevent update conflicts when multiple instances start simultaneously
      - BATTLEEYE=FALSE                      # Set to TRUE to use BattleEye, FALSE to not use BattleEye
      - API=FALSE                            # Set to TRUE to install and use AsaApi, FALSE to disable AsaApi
      - RCON_ENABLED=TRUE                    # Needed for Graceful Shutdown / Updates / Server Notifications
      - DISPLAY_POK_MONITOR_MESSAGE=FALSE    # Or TRUE to Show the Server Monitor Messages / Update Monitor 
      - UPDATE_SERVER=TRUE                   # Enable or disable update checks
      - CHECK_FOR_UPDATE_INTERVAL=24         # Check for Updates interval in hours
      - UPDATE_WINDOW_MINIMUM_TIME=12:00 AM  # Defines the minimum time, relative to server time, when an update check should run
      - UPDATE_WINDOW_MAXIMUM_TIME=11:59 PM  # Defines the maximum time, relative to server time, when an update 
      - RESTART_NOTICE_MINUTES=30            # Duration in minutes for notifying players before a server restart due to updates
      - ENABLE_MOTD=FALSE                    # Enable or disable Message of the Day
      - MOTD=                                # Message of the Day
      - MOTD_DURATION=30                     # Duration for the Message of the Day
      - MAP_NAME=TheIsland                   # TheIsland, ScorchedEarth, TheCenter, Aberration / TheIsland_WP, ScorchedEarth_WP, TheCenter_WP, Aberration_WP / Are the current official maps available
      - SESSION_NAME=Server_name             # The name of the server session
      - SERVER_ADMIN_PASSWORD=MyPassword     # The admin password for the server 
      - SERVER_PASSWORD=                     # Set a server password or leave it blank (ONLY NUMBERS AND CHARACTERS ARE ALLOWED BY DEVS)
      - ASA_PORT=7777                        # The port for the server
      - RCON_PORT=27020                      # The port for the RCON
      - MAX_PLAYERS=70                       # The maximum number of players allowed on the server
      - SHOW_ADMIN_COMMANDS_IN_CHAT=FALSE    # Set to TRUE to notify admin commands in chat, FALSE to disable notifications
      - CLUSTER_ID=cluster                   # The cluster ID for the server
      - MOD_IDS=                             # Add your mod IDs here, separated by commas, e.g., 123456789,987654321
      - PASSIVE_MODS=                        # Replace with your passive mods IDs
      - CUSTOM_SERVER_ARGS=                  # If You need to add more Custom Args -ForceRespawnDinos -ForceAllowCaveFlyers
    ports:
      - "7777:7777/tcp"
      - "7777:7777/udp"
      - "27020:27020/tcp"
    volumes:
      - "./ServerFiles/arkserver:/home/pok/arkserver"
      - "./Instance_my_instance/Saved:/home/pok/arkserver/ShooterGame/Saved"
      - "./Cluster:/home/pok/arkserver/ShooterGame/Saved/clusters"
    mem_limit: 16G
```

## Using AsaApi

POK-manager now supports [AsaApi](https://github.com/ArkServerApi/AsaApi), a powerful API framework that enables server plugins to enhance and extend your ARK server's functionality.

### Enabling AsaApi

To enable AsaApi on your server:

1. You can use the dedicated command to enable the API for one or all instances:
   ```bash
   # Enable AsaApi for a specific instance
   ./POK-manager.sh -API TRUE my_instance
   
   # Enable AsaApi for all instances
   ./POK-manager.sh -API TRUE -all
   
   # Disable AsaApi for a specific instance
   ./POK-manager.sh -API FALSE my_instance
   ```
   The script will automatically update the configuration and offer to restart the instance(s) for you.

   The command is user-friendly and flexible with input formats:
   ```bash
   # These all ENABLE the API
   ./POK-manager.sh -API TRUE my_instance
   ./POK-manager.sh -API true my_instance
   
   # These all DISABLE the API
   ./POK-manager.sh -API FALSE my_instance
   ./POK-manager.sh -API false my_instance
   ```
2. If you're creating a new instance, you can enable it during the configuration process.

3. For existing instances, you can also modify the docker-compose file using the edit command:
   ```bash
   ./POK-manager.sh -edit         # Select your instance to edit the config
   ./POK-manager.sh -stop my_instance
   ./POK-manager.sh -start my_instance
   ```

### How AsaApi Installation Works

When you enable the API feature:

1. The container will automatically download the latest version of AsaApi from the official GitHub repository (https://github.com/ArkServerApi/AsaApi/releases/latest)
2. The API will be installed to the correct location in your server files
3. The Visual C++ 2019 Redistributable (required by AsaApi) will be automatically installed in the Proton environment
4. The server will start using AsaApiLoader.exe instead of ArkAscendedServer.exe
5. On subsequent starts, the container will check for AsaApi updates and install them if available

### Special Handling for API Mode Restarts

AsaApi instances require special handling when restarting. POK-manager includes a specialized restart mechanism for API=TRUE instances:

#### API Mode Restart Process

When using the `-restart` command on an instance with API=TRUE, POK-manager:

1. Detects that the instance is in API mode
2. Sends a shutdown command with the specified countdown
3. Waits for the server to completely shut down
4. Stops the Docker container entirely
5. Starts a fresh container

This approach ensures a clean environment for API mode restarts, which solves common issues where API-enabled servers fail to restart properly when using the in-game restart command.

```bash
# Restart an API-enabled instance with a 5-minute countdown
./POK-manager.sh -restart 5 my_api_instance

# This automatically uses the container-level restart approach
```

#### Automatic Recovery for API Instances

POK-manager includes an automatic recovery system specifically designed for API mode instances:

1. A new `-api-recovery` command that checks all API=TRUE instances:
   - Verifies if the ARK server process is running inside the container
   - If the container is running but the server process is not, it restarts the container
   - This provides automatic recovery for crashed API mode servers

2. You can set up automatic monitoring via cron:
   ```
   # Check every 15 minutes and recover any API instances that have crashed
   */15 * * * * /path/to/POK-manager.sh -api-recovery
   ```

3. This is particularly useful for servers that occasionally crash but don't trigger a container failure.

This approach provides a robust solution for API mode servers, ensuring they can properly restart and automatically recover from crashes.

### Windows Dependencies in Linux Environment

AsaApi requires Windows-specific dependencies (specifically Microsoft Visual C++ 2019 Redistributable) to function. Despite running in a Linux environment, our solution handles this by:

1. Automatically downloading the required Visual C++ 2019 Redistributable installer
2. Using Wine/Proton to install it within the Proton environment that runs the Windows-based ARK server
3. Setting appropriate Wine DLL overrides to ensure the API loads properly
4. Performing verification tests to confirm the API can load successfully

This approach allows you to use AsaApi seamlessly in our Linux-based container without having to manually install any Windows dependencies.

### Installing Plugins

AsaApi plugins can be installed manually. Here's how:

1. Download the plugin file(s) from a trusted source
2. Place the plugin files in your server's plugins directory:
   ```
   ./ServerFiles/arkserver/ShooterGame/Binaries/Win64/plugins/
   ```
3. The plugin directory structure should follow the AsaApi requirements

4. Restart your server for the changes to take effect:
   ```bash
   ./POK-manager.sh -restart 5 my_instance   # Restart with 5-minute countdown
   ```

### Managing Plugin Configurations

Plugin configurations depend on the specific plugin being used. When the AsaApi is updated, any plugin files in the plugins directory should be preserved.

To edit a plugin's configuration:

1. Navigate to the plugin's directory
2. Edit the appropriate configuration file
3. Save your changes and restart the server

### Persistent Plugins

Plugin installations and configurations persist across server updates and container restarts, as they are stored in the volume-mounted server directory.

### Troubleshooting AsaApi

If you encounter issues with AsaApi or plugins:

1. Check the server logs for any error messages:
   ```bash
   ./POK-manager.sh -logs -live my_instance
   ```
   
   The AsaApi logs can be found in:
   ```
   ./ServerFiles/arkserver/ShooterGame/Binaries/Win64/logs/
   ```

2. Verify that the API is correctly installed:
   ```bash
   ls -la ./ServerFiles/arkserver/ShooterGame/Binaries/Win64/AsaApiLoader.exe
   ```

3. Ensure plugin files are in the correct location and have the right permissions

4. Common AsaApi issues in our Linux/Proton environment:
   - Missing Visual C++ Redistributable: The system will try to install it automatically
   - Wine/Proton configuration: Try manually updating the docker image with `./POK-manager.sh -update`
   - Plugin compatibility: Some plugins may not work with our Linux/Proton setup or with the current version of ARK

5. If the API still doesn't work, try reinstalling it:
   ```bash
   # Disable API for the instance
   ./POK-manager.sh -API FALSE my_instance
   # Restart the server
   ./POK-manager.sh -restart 1 my_instance
   # Wait for the server to fully restart
   # Enable API again
   ./POK-manager.sh -API TRUE my_instance
   # Restart the server once more
   ./POK-manager.sh -restart 1 my_instance
   ```

**Note:** Using plugins can affect server performance and stability. It's recommended to thoroughly test plugins before using them on a production server.

## Safe Update Mechanism

POK-manager uses a safe update mechanism to ensure stability and prevent unexpected changes from affecting your server setup:

1. **Update Detection**: When you run a command interactively, POK-manager checks for updates
2. **Notification Only**: If an update is available, the script notifies you without automatically installing it
3. **Explicit Consent**: You must run the `-upgrade` command to explicitly accept an update
4. **Non-Interactive Safety**: When running via cron jobs, update checks are skipped by default
5. **Backup Creation**: Before applying an update, the script creates a backup of the current version

This approach ensures that:
- Your production servers won't be unexpectedly updated in an automated process
- You have full control over when updates are applied
- You can revert to a previous version if needed

### Understanding `-update` vs `-upgrade`

There are two separate update-related commands with different purposes:

- **`-update`**: This checks for ARK server files and Docker image updates, but doesn't modify the POK-manager.sh script itself. Use this to keep your game servers updated.

- **`-upgrade`**: This specifically upgrades the POK-manager.sh script to the latest version (after confirmation). Use this when you want to get new features or fixes for the management script itself.

### To update POK-manager:

```bash
# Check for updates and apply if available (with confirmation)
./POK-manager.sh -upgrade
```

### To restore a previous version:

If an update causes issues, you can restore the previous version:

```bash
# Replace the current script with the backup
cp ./config/POK-manager/pok-manager.backup ./POK-manager.sh
chmod +x ./POK-manager.sh
```

## Ports

The following ports are used by the Ark Survival Ascended Server:

- `7777:7777/tcp`: Game port
- `7777:7777/udp`: Game port

the following ports are used by RCON

- `27020:27020/tcp`: RCON port

Note: The query port is not needed for Ark Ascended.

## Troubleshooting

### User ID and Setup Issues

If you encounter this error when running the `-setup` command:
```
You are not running the script as the user with the correct PUID (7777) and PGID (7777).
Your current user has UID X and GID Y.
Please switch to the correct user or update your current user's UID and GID to match the required values.
```

Follow these steps to resolve it:

1. **Verify your current user ID**:
   ```bash
   id
   ```
   This shows your current user's UID and GID.

2. **Fix by either**:
   
   a. **Using sudo** (quick fix, not recommended for regular use):
   ```bash
   sudo ./POK-manager.sh -setup
   ```
   
   b. **Switching to the pokuser account** (preferred):
   ```bash
   # First make sure the user exists with correct ID
   sudo groupadd -g 7777 pokuser
   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
   sudo passwd pokuser  # Set a password for the user
   # Enter and confirm a secure password when prompted
   
   # Then switch to that user
   sudo su - pokuser
   
   # Navigate to your POK-manager directory
   cd /path/to/your/POK-manager
   
   # Run the setup
   ./POK-manager.sh -setup
   ```

3. **Verifying your pokuser has access to docker**:
   ```bash
   # Add pokuser to the docker group
   sudo usermod -aG docker pokuser
   
   # Log out and back in, or run:
   newgrp docker
   ```

### Sudoers Issues in Cloud Environments

If you encounter this error:
```
pokuser is not in the sudoers file.
This incident has been reported to the administrator.
```

This means the pokuser account doesn't have sudo permissions, which is needed for some operations:

1. **For cloud providers (Google Cloud VM, AWS, etc.)**:
   ```bash
   # You must log in as your default cloud user (the one with sudo permissions)
   # Then add pokuser to the sudo group:
   
   # For Ubuntu/Debian:
   sudo usermod -aG sudo pokuser
   
   # For CentOS/RHEL:
   sudo usermod -aG wheel pokuser
   
   # You might need to set up sudo without password (USE WITH CAUTION):
   echo "pokuser ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/pokuser
   sudo chmod 440 /etc/sudoers.d/pokuser
   ```

2. **If you're already using the cloud provider's default user**:
   You can either:
   - Use that user to run POK-manager with sudo (less secure but simpler)
   - Or modify the script to use your existing user's UID/GID instead of 7777

3. **Simplified approach for cloud environments**:
   If setting up a dedicated pokuser account is problematic, you can run:
   ```bash
   # Find your current user's UID and GID
   id
   
   # Then run the setup with your current UID/GID
   sudo ./POK-manager.sh -setup
   
   # And run docker commands with sudo
   sudo docker-compose -f docker-compose-my_instance.yaml up -d
   ```

### Common Permission Issues

If you encounter any of these errors:
```
E: List directory /var/lib/apt/lists/partial is missing. - Acquire (13: Permission denied)
Error: Server files not found. Please ensure the server is properly installed.
```

These indicate permission problems in the container:

1. **Check your current file ownership**:
   ```bash
   # See who owns your server files
   ls -la ./ServerFiles
   ```

2. **Fix File Ownership on Host**:
   ```bash
   # For 2.1+ containers (recommended)
   sudo chown -R 7777:7777 /path/to/your/POK-manager/directory
   
   # For 2.0 legacy containers
   sudo chown -R 1000:1000 /path/to/your/POK-manager/directory
   ```

3. **Permission Issues with Root User**: If you're running as root, remember the container still needs files owned by UID 7777 or 1000:
   ```bash
   # Always run the script with
   sudo ./POK-manager.sh <command>
   
   # Never run with
   ./POK-manager.sh <command>    # May cause permission issues when running as root
   ```

4. **Volume Mount Permission Issues**: If using custom volume mounts in Docker, ensure they are accessible to the container's user:
   ```bash
   # For Docker volume mounts
   sudo chown -R 7777:7777 /your/custom/volume/path
   ```

5. **Steam Installation Directory**: If SteamCMD fails to download or install the server, ensure these directories exist and have correct permissions:
   ```bash
   sudo mkdir -p /home/pok/.steam/steam
   sudo chown -R 7777:7777 /home/pok/.steam
   ```

6. **Server Startup Issues**: If the server fails to start after installation, check permissions on the server directories:
   ```bash
   sudo chmod -R 755 /path/to/your/POK-manager/ServerFiles
   sudo chown -R 7777:7777 /path/to/your/POK-manager/ServerFiles
   ```

Remember: The container runs as UID 7777 (newer versions) or 1000 (legacy versions) - regardless of which host user launches it. Files must have the correct ownership to be accessible to the container.

### Allocator Stats Error

If you encounter the following error in your logs:
```
asa_pve_Server | [2023.11.06-03.55.48:449][  1]Allocator Stats for binned2 are not in this build set BINNED2_ALLOCATOR_STATS 1 in MallocBinned2.cpp
```

This is caused by insufficient memory mapping limits on your system. **You must fix this for the server to run properly:**

Option 1: Apply temporarily (resets after system reboot):
```bash
sudo sysctl -w vm.max_map_count=262144
```

Option 2: Apply permanently (survives system reboots):
```bash
# Add to system configuration
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
# Apply the changes
sudo sysctl -p
```

⚠️ **This setting is critical** - without it, the ARK server container will crash or fail to start properly.

## Hypervisors
Proxmox VM

The default CPU type (kvm64) in proxmox for linux VMs does not seem to implement all features needed to run the server. When running the docker contain
In that case just change your CPU type to host in the hardware settings of your VM. After a restart of the VM the container should work without any issues.

## Docker Image Versions

POK-manager supports multiple Docker image versions to ensure backward compatibility:

| Image Tag | Default PUID:PGID | Description |
|-----------|-----------------|-------------|
| `2_0_latest` | 1000:1000 | Legacy image for backward compatibility with existing installations |
| `2_1_latest` | 7777:7777 | New default image that avoids conflicts with common user IDs |
| `2_0_beta` | 1000:1000 | Beta version of the legacy image |
| `2_1_beta` | 7777:7777 | Beta version of the new image |

The script automatically selects the appropriate image based on your file ownership:
- If your server files are owned by UID:GID 1000:1000, it will use the 2_0 image
- If your server files have any other ownership, it will use the 2_1 image

You can manually migrate from 2_0 to 2_1 by running:
```bash
sudo ./POK-manager.sh -migrate
```

This will update the ownership of all your server files to 7777:7777 for compatibility with the new images.

## Build-time vs Runtime Configuration

It's important to understand the difference between build-time arguments and runtime environment variables:

### Build-time Arguments (Cannot be changed at runtime)
These values are set when the Docker image is built and cannot be modified when starting a container:
- `PUID`: The user ID inside the container (fixed at 1000 for 2_0 images, 7777 for 2_1 images)
- `PGID`: The group ID inside the container (fixed at 1000 for 2_0 images, 7777 for 2_1 images)

### Runtime Environment Variables
These values can be changed in your docker-compose.yaml file and take effect when the container starts:
- All the other environment variables listed in the Environment Variables table

To ensure proper file access between the host and container, the ownership of your files on the host 
must match the PUID:PGID values of the Docker image you're using.

## Links

- [Docker Installation](https://docs.docker.com/engine/install/)
- [Docker Compose Installation](https://docs.docker.com/compose/install/)
- [Git Downloads](https://git-scm.com/downloads)
- [Ark Survival Ascended Server Docker Image](https://hub.docker.com/r/acekorneya/asa_server)
- [Server Configuration](https://ark.wiki.gg/wiki/Server_configuration)
- [POK-manager.sh GitHub Repository](https://github.com/Acekorneya/Ark-Survival-Ascended-Server)

## Support

If you need assistance or have any questions, please join our Discord server: [KNY SERVERS](https://discord.gg/9GJKWjQuXy)

## Conclusion

POK-manager.sh is a comprehensive and user-friendly solution for managing Ark Survival Ascended Server instances using Docker. With its wide range of commands and ease of use, it simplifies the process of setting up, configuring, and maintaining server instances. Whether you're a beginner or an experienced user, POK-manager.sh provides a streamlined approach to server management, allowing you to focus on enjoying the game with your community. If you encounter any issues or have questions, don't hesitate to reach out for support on our Discord server.

We Also have Ark Servers for people who dont have the requirements to host a full cluster of all the Ark Maps when they release.

🎮 Join Our Community Cluster Server:

- Server Name: POK-Community-CrossARK. 

- Running all Official Maps in Cluster and More to Come as they release and added to the cluster. 
- PVE: A peaceful environment for your adventures.
- Flyer Carry Enabled: Explore the skies with your tamed creatures.
- Official Server Rates: Balanced gameplay for an enjoyable experience.
- Always Updated and Events run on time of released
- Active Mods: We're here to assist you whenever you need it.
- Discord Community: Connect with our community and stay updated.
- NO CRYPOD RESTRICTION USE THEM ANYWHERE!..

Make sure to select "SHOW PLAYER SERVER" To be able to find it in unofficials Servers 

## Support the Project

If you find POK-manager.sh useful and would like to support its development, you can buy me a coffee! Your support is greatly appreciated and helps me continue maintaining and improving the project.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/acekorneyab)

Your contributions will go towards:
- Implementing new features and enhancements
Thank you for your support!

---


## Star History

<a href="https://star-history.com/#Acekorneya/Ark-Survival-Ascended-Server&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
  </picture>
</a>

