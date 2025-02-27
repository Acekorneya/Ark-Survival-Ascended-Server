# POK Ark Survival Ascended Server Management Script

## Introduction

POK-manager.sh is a powerful and user-friendly script for managing Ark Survival Ascended Server instances using Docker. It simplifies the process of creating, starting, stopping, updating, and performing various operations on server instances, making it easy for both beginners and experienced users to manage their servers effectively.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
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

- [Docker](https://docs.docker.com/engine/install/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Git](https://git-scm.com/downloads)
- [yq](https://github.com/mikefarah/yq?tab=readme-ov-file#install)
- `sudo` access
- CPU - FX Series AMD Or Intel Second Gen Sandy Bridge CPU
- 16GB of RAM (or more) for each instance
- 80 GB for Server data
- Linux Host OS (Ubuntu, Debian, Arch)

## Installation

1. Create or modify a user for the container:
   - For a new user named `pokuser` with the new default UID/GID (7777):
     ```bash
     sudo groupadd -g 7777 pokuser
     sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser
     ```
   - For backward compatibility with earlier versions (UID/GID 1000):
     ```bash
     sudo groupadd -g 1000 pokuser
     sudo useradd -u 1000 -g 1000 -m -s /bin/bash pokuser
     ```
   - See [Upgrading to Version 2.1+](#upgrading-to-version-21) for more details on PUID/PGID changes.

2. Configure system settings:
   - Set `vm.max_map_count` temporarily:
     ```bash
     sudo sysctl -w vm.max_map_count=262144
     ```
   - For permanent setup, add `vm.max_map_count=262144` to `/etc/sysctl.conf`, save, and apply changes:
     ```bash
     echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
     sudo sysctl -p
     ```

3. (Optional) Adjust folder permissions if not using a separate user:
   ```bash
   sudo chown -R 7777:7777 /path/to/your/instance/folder
   ```

4. Download and set up POK-manager.sh:
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

- Save the world of all instances every 30 minutes:
  ```
  */30 * * * * /path/to/POK-manager.sh -saveworld -all
  ```

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

**Important Change:** Starting with version 2.1, the default container user has changed from 1000:1000 to 7777:7777 to avoid conflicts with the default user ID on many Linux distributions.

### For Existing Users (Running Prior Versions)

If you're upgrading from an earlier version, you have two options:

1. **Continue using 1000:1000 (backward compatibility):**
   ```bash
   # Specify the PUID/PGID values when running POK-manager.sh
   CONTAINER_PUID=1000 CONTAINER_PGID=1000 ./POK-manager.sh <commands>
   
   # Or add these lines to your docker-compose files:
   - PUID=1000
   - PGID=1000
   ```

2. **Migrate to the new 7777:7777 user (recommended):**
   ```bash
   # Change ownership of your existing files
   sudo chown -R 7777:7777 ./ServerFiles ./Instance_* ./Cluster
   ```

### For New Users

POK-manager.sh can work with any user as long as it has the correct PUID and PGID (now 7777:7777 by default). This prevents running as root and enhances security.

If you prefer to use a different UID/GID, you can:

1. Set environment variables when running commands:
   ```bash
   CONTAINER_PUID=<your_uid> CONTAINER_PGID=<your_gid> ./POK-manager.sh <commands>
   ```

2. Modify your docker-compose files to include:
   ```yaml
   environment:
     - PUID=<your_uid>
     - PGID=<your_gid>
   ```

3. Run with `sudo` to bypass permission checks (not recommended for regular use):
   ```bash
   sudo ./POK-manager.sh <commands>
   ```

## Docker Compose Configuration

When creating a new server instance using POK-manager.sh, a Docker Compose configuration file (`docker-compose-<instance_name>.yaml`) is generated. Here's an example of the generated file:

#### Environment Variables

| Variable                      | Default           | Description                                                                               |
| ------------------------------| ------------------| ------------------------------------------------------------------------------------------|
| `INSTANCE_NAME`               | `Instance_name`   | The name of the instance                                                                  |
| `PUID`                        | `7777`            | User ID for container processes and file ownership (was 1000 in versions before 2.1)      |
| `PGID`                        | `7777`            | Group ID for container processes and file ownership (was 1000 in versions before 2.1)     |
| `BATTLEEYE`                   | `TRUE`            | Set to TRUE to use BattleEye, FALSE to not use BattleEye                                  |
| `TZ`                          | `America/Los_Angeles`| Timezone setting: Change this to your local timezone.                                  |
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
      - BATTLEEYE=FALSE                      # Set to TRUE to use BattleEye, FALSE to not use BattleEye
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

If you encounter the following error in your logs:
```
asa_pve_Server | [2023.11.06-03.55.48:449][  1]Allocator Stats for binned2 are not in this build set BINNED2_ALLOCATOR_STATS 1 in MallocBinned2.cpp
```

Run the following command to temporarily fix the issue:
```bash
sudo sysctl -w vm.max_map_count=262144
```

To make the change permanent, add the following line to `/etc/sysctl.conf` and apply the changes:
```bash
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## Hypervisors
Proxmox VM

The default CPU type (kvm64) in proxmox for linux VMs does not seem to implement all features needed to run the server. When running the docker contain
In that case just change your CPU type to host in the hardware settings of your VM. After a restart of the VM the container should work without any issues.

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

- Running Both Map in Cluster and More to Come as they release and added to the cluster. 
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
