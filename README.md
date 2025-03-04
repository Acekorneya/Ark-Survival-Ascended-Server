# POK Ark Survival Ascended Server Management Script

<div align="center">

[![Docker Pulls](https://img.shields.io/docker/pulls/acekorneya/asa_server.svg)](https://hub.docker.com/r/acekorneya/asa_server)
[![Docker Stars](https://img.shields.io/docker/stars/acekorneya/asa_server.svg)](https://hub.docker.com/r/acekorneya/asa_server)
[![GitHub Stars](https://img.shields.io/github/stars/Acekorneya/Ark-Survival-Ascended-Server.svg?style=social&label=Star)](https://github.com/Acekorneya/Ark-Survival-Ascended-Server)
[![Join Discord](https://img.shields.io/discord/825471546386726912?label=discord&logo=discord&logoColor=white)](https://discord.gg/9GJKWjQuXy)

**The complete all-in-one solution for hosting Ark Survival Ascended servers on Linux**

</div>

## Overview

POK-manager is a powerful, user-friendly tool for easily managing Ark Survival Ascended servers on Linux systems. With a simple command-line interface, it handles all the complex tasks of setting up, configuring, and maintaining your ARK servers.

### Key Features

- **Easy Setup** - Just one command to set up a complete server environment
- **Multiple Instances** - Run several ARK servers on the same machine
- **Auto-Updates** - Keep your servers up-to-date automatically
- **Mods Support** - Simple configuration for mod installation
- **Advanced Features** - Backup/restore, API support, clustering, and more
- **Automated Installation** - Handles most dependencies (Docker, Docker Compose) for you

### For New Users

If you're looking for a Linux-based ARK server manager that:
- Doesn't require extensive Linux knowledge
- Handles Docker container setup for you
- Provides a simple command interface
- Makes backups, updates, and configuration easy

Then POK-manager is the ideal solution for your Ark Survival Ascended server needs!

## Introduction

POK-manager.sh is a powerful and user-friendly script for managing Ark Survival Ascended Server instances using Docker. It simplifies the process of creating, starting, stopping, updating, and performing various operations on server instances, making it easy for both beginners and experienced users to manage their servers effectively.

The script is designed with ease of use in mind - it will automatically check for and install most required dependencies (like Docker, Docker Compose, and yq) if they're not already present on your system. This means you only need Git initially to download the manager, and it will handle most of the complex setup steps for you.

## Quick Start Guide for New Linux Users

If you're new to Linux or Docker, this guide will help you get started quickly. Just copy and paste these commands:

```bash
# Install dependencies
sudo apt-get update && sudo apt-get install -y git

# Create the dedicated server user with correct permissions
sudo groupadd -g 7777 pokuser
sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
sudo passwd pokuser  # You'll be prompted to create a password

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
./POK-manager.sh -setup

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

Before using POK-manager.sh, ensure that you have the following prerequisites installed on your Linux system:

- [Docker](https://docs.docker.com/engine/install/) (POK-manager.sh will attempt to install this if not found)
- [Docker Compose](https://docs.docker.com/compose/install/) (POK-manager.sh will attempt to install this if not found)
- [Git](https://git-scm.com/downloads) (Required to download POK-manager)
- [yq](https://github.com/mikefarah/yq?tab=readme-ov-file#install) (POK-manager.sh will attempt to install this if not found)
- `sudo` access
- CPU - FX Series AMD Or Intel Second Gen Sandy Bridge CPU
- 16GB of RAM (or more) for each instance
- 80 GB for Server data
- Linux Host OS (Ubuntu, Debian, Arch)

> **Note**: POK-manager.sh is designed to automatically install most required dependencies (Docker, Docker Compose, and yq) if they're not found on your system. You'll only need Git initially to download the manager.

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
   # Create the user group with GID 7777
   sudo groupadd -g 7777 pokuser
   
   # Create the user with UID 7777
   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
   
   # Set a password for the new user (you'll need this to log in)
   sudo passwd pokuser
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

4. **Install Git** (if not already installed):
   ```bash
   # This will prompt for your password if needed
   sudo apt-get update
   sudo apt-get install git
   ```

5. **Create a directory for your server** (optional but recommended):
   ```bash
   mkdir -p ~/asa_server
   cd ~/asa_server
   ```

6. **Download and set up POK-manager.sh**:
   ```bash
   git clone https://github.com/Acekorneya/Ark-Survival-Ascended-Server.git && \
   mv Ark-Survival-Ascended-Server/POK-manager.sh . && \
   chmod +x POK-manager.sh && \
   mv Ark-Survival-Ascended-Server/defaults . && \
   rm -rf Ark-Survival-Ascended-Server
   ```

7. **Run the setup command**:
   ```bash
   ./POK-manager.sh -setup
   ```
   Since you're already running as the pokuser with UID 7777, this should work without permission issues.

8. **Create your first server instance**:
   ```bash
   ./POK-manager.sh -create my_server
   ```

### Alternative Installation Options

1. **For experienced users** who want to download and set up in a single step:
   
   First, ensure you have a user with the correct UID/GID:
   ```bash
   # Create the user group with GID 7777
   sudo groupadd -g 7777 pokuser
   
   # Create the user with UID 7777
   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
   
   # IMPORTANT: Set a password for the user (you'll need this to switch to pokuser)
   sudo passwd pokuser
   ```
   
   Then, choose one of these options:
   
   - Option 1: Run the following command to download and set up POK-manager.sh in a single step:
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
   
   After setting up, switch to the pokuser account to run the script:
   ```bash
   sudo su - pokuser
   
   # Navigate to where you downloaded POK-manager (if needed)
   cd /path/to/your/POK-manager
   
   # Run the setup
   ./POK-manager.sh -setup
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
   sudo chown -R 7777:7777 /path/to/your/POK-manager/directory
   ```

4. **Fix permission issues during runtime**:
   - If you encounter "Permission denied" or "Files not found" errors when starting the container, run:
     ```bash
     sudo chown -R 7777:7777 /path/to/your/POK-manager/ServerFiles
     sudo chown -R 7777:7777 /path/to/your/POK-manager/Instance_*
     ```

5. **Remember**: Running as root doesn't bypass the need for correct file ownership. The container still requires files owned by UID 7777 or 1000 to function properly.

#### For Non-Root Users (Recommended)
If you're running as a non-root user (recommended for security):

1. **Create a dedicated user** with the correct UID/GID:
   ```bash
   sudo groupadd -g 7777 pokuser
   sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
   sudo passwd pokuser  # Set a password for the user (IMPORTANT - don't skip this step!)
   ```

2. **Switch to this user** to run commands:
   ```bash
   sudo su - pokuser
   ```

3. **Files automatically have the correct ownership** when created by this user.

4. **Run without sudo** when logged in as this user:
   ```bash
   ./POK-manager.sh <command>
   ```

This approach provides better security while ensuring permissions are automatically correct.

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
- `-status <instance_name|-all>`: Shows the status of a specific server instance or all instances.
- `-restart [minutes] <instance_name|-all>`: Restarts a specific server instance or all instances with an optional countdown in minutes.
- `-saveworld <instance_name|-all>`: Saves the world of a specific server instance or all instances.
- `-chat "<message>" <instance_name|-all>`: Sends a chat message to a specific server instance or all instances.
- `-custom <command> <instance_name|-all>`: Executes a custom command on a specific server instance or all instances.
- `-backup [instance_name|-all]`: Backs up a specific server instance or all instances (defaults to all if not specified).
- `-restore [instance_name]`: Restores a server instance from a backup.
- `-logs [-live] <instance_name>`: Displays logs for a specific server instance (optionally live).
- `-beta`: Switches to beta mode, using the beta branch for updates and beta Docker images.
- `-stable`: Switches to stable mode, using the master branch for updates and stable Docker images.
- `-API <TRUE|FALSE> <instance_name|-all>`: Enables or disables AsaApi for specified instance(s).
- `-api-recovery`: Check and recover API instances with container restart - useful for automatic monitoring via cron.
- `-version`: Displays the current version of POK-manager.

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
   - Replace `/path/to/command` with the actual command you want to run.

   For example, to save the world state of an instance named "my_instance" every 30 minutes, add the following line:
   ```
   */30 * * * * /path/to/POK-manager.sh -saveworld my_instance
   ```
   This command will run every 30 minutes, on the hour and half-hour (e.g., 12:00, 12:30, 1:00, 1:30, etc.).

   To create a backup of an instance named "my_instance" every 6 hours, add the following line:
   ```
   0 */6 * * * /path/to/POK-manager.sh -backup my_instance
   ```
   This command will run every 6 hours, starting at midnight (e.g., 12:00 AM, 6:00 AM, 12:00 PM, 6:00 PM).

3. Save the changes and exit the editor. The cron jobs will now run automatically at the specified intervals.

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
| `RANDOM_STARTUP_DELAY`        | `TRUE`            | Add a random delay (0-30s) during startup to prevent update conflicts when multiple instances start simultaneously |
| `BATTLEEYE`                   | `TRUE`            | Set to TRUE to use BattleEye, FALSE to not use BattleEye                                  |
| `API`                         | `FALSE`           | Set to TRUE to install and use AsaApi, FALSE to disable AsaApi                |
| `RCON_ENABLED`                | `TRUE`            | Needed for Graceful Shutdown                                                              |
| `DISPLAY_POK_MONITOR_MESSAGE` | `FALSE`           | TRUE to Show the Server Monitor Messages / Update Monitor Shutdown                        |
| `UPDATE_SERVER`               | `TRUE`            | Enable or disable update checks                                                           |
| `CHECK_FOR_UPDATE_INTERVAL`   | `24`              | Check for Updates interval in hours                                                       |
| `UPDATE_WINDOW_MINIMUM_TIME`  | `12:00 AM`        | Defines the minimum time, relative to server time, when an update check should run        |
| `UPDATE_WINDOW_MAXIMUM_TIME`  | `11:59 PM`        | Defines the maximum time, relative to server time, when an update check should run        |
| `RESTART_NOTICE_MINUTES`      | `30`