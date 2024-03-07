
### Documentation for Ark Survival Ascended Server Docker Image

🚀 **Enhanced Beta Script Setup Guide: ARK Survival Ascended Server** 🚀

Hi everyone, I'm excited to introduce my new beta script for managing your ARK server instances. The script takes care of server clustering for you, just make sure the cluster ID is the same. You can view all available commands by running `POK-manager.sh`. More documentation will be provided soon, but in the meantime, feel free to play around with it and let me know if you find any issues.

**1. Create or Modify User for Container**

- For a new user named `pokuser`:
```bash
sudo useradd -u 1000 -g 1000 -m -s /bin/bash pokuser
```

- To modify an existing user:
```bash
sudo usermod -u 1000 <existing_username>
sudo groupmod -g 1000 <existing_username>
```

**2. Configure System Settings**

- Set `vm.max_map_count` temporarily:
```bash
sudo sysctl -w vm.max_map_count=262144
```

- For permanent setup, add `vm.max_map_count=262144` to `/etc/sysctl.conf`, save, and apply changes:
```bash
sudo sysctl -p
```

**3. Adjust Permissions (Optional)**

- Adjust folder permissions if not using a separate user:
```bash
sudo chown -R 1000:1000 /path/to/your/instance/folder
```

**4. Download & Setup**

- Simplified download and setup command:
```bash
git clone -b beta --single-branch https://github.com/Acekorneya/Ark-Survival-Ascended-Server.git && sudo chown -R 1000:1000 Ark-Survival-Ascended-Server && sudo mv Ark-Survival-Ascended-Server/POK-manager.sh . && sudo chmod +x POK-manager.sh && sudo mv Ark-Survival-Ascended-Server/defaults . && sudo rm -rf Ark-Survival-Ascended-Server
```
This command accomplishes several tasks efficiently:
  - Clones the beta version of the ARK Survival Ascended Server.
  - Changes the ownership of the downloaded files to `pokuser`.
  - Moves the `POK-manager.sh` script to the current directory and makes it executable.
  - Moves the `defaults` directory to the current directory.
  - Cleans up by removing the cloned repository folder.

**5. Run the POK-manager.sh Script**

- To set up and start your ARK server instance:
```bash
./POK-manager.sh -setup
./POK-manager.sh -create <instance_name>
```

**6. View Server Status**

- To view the server status:
```bash
./POK-manager.sh -status -all
```
or for a specific instance:
```bash
./POK-manager.sh -status <instance_name>
```

**All Available Commands**

- To explore all the script's capabilities:
```bash
./POK-manager.sh
```

**Note:** Use `sudo` with `POK-manager.sh` commands if you've set up folder permissions using it.

This guide is designed to streamline your setup process. Please report any feedback or issues you encounter to help us refine the beta script. 

⚠ **Important Notice:** As this is a beta version, please proceed with caution. Though we've addressed many bugs, there may still be unforeseen issues.


⚡ **Additional Note:** The requirement for setting the PUID and PGID can be bypassed by prefixing commands with `sudo`. For example, you can use `sudo ./POK-manager.sh` for operations without needing to adjust the user's UID and GID. This is especially useful for quick tests or when you prefer not to modify user settings.


#### Docker Image Details

This Docker image is designed to run a dedicated server for the game Ark Survival Ascended.

#### Docker Hub Repository: https://hub.docker.com/r/acekorneya/asa_server

---

#### Environment Variables

| Variable                      | Default           | Description                                                                               |
| ------------------------------| ------------------| ------------------------------------------------------------------------------------------|
| `PUID`                        | `1001`            | The UID to run server as                                                                  |
| `PGID`                        | `1001`            | The GID to run server as                                                                  |
| `BATTLEEYE`                   | `TRUE`            | Set to TRUE to use BattleEye, FALSE to not use BattleEye                                  |
| `TZ`                       | `America/Los_Angeles`| Timezone setting: Change this to your local timezone.                                     |
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
| `CLUSTER_ID`                  | `cluster`         | The Cluster ID for Server Transfers                                                       | 
| `PASSIVE_MODS`                | `123456`          | Replace with your passive mods IDs                                                        |
| `MOD_IDS`                     | `123456`          | Add your mod IDs here, separated by commas, e.g., 123456789,987654321                     |
| `CUSTOM_SERVER_ARGS`          |                   | If You need to add more Custom Args -ForceRespawnDinos -ForceAllowCaveFlyers              |

---

#### Additional Information

- **UPDATE_WINDOW_MINIMUM_TIME and UPDATE_WINDOW_MAXIMUM_TIME**: Combined, these two values can allow you to define a time window for when server updates should be performed. This can be useful to ensure update driven restarts only happen during off peak hours.


---

#### Ports

| Port         | Description                            |
| ------------ | -------------------------------------- |
| `7777/tcp`   | Game port                              |
| `7777/udp`   | Game port                              |

---
#### Comments
Query Port is not needed for Ark Ascended 

---

#### Recommended System Requirements

- CPU: min 2 CPUs
- RAM: > 16 GB
- Disk: ~50 GB

---

#### Usage

##### Docker Compose

```yaml
version: '2.4'

services:
  asaserver:
    build: .
    image: acekorneya/asa_server:latest
    container_name: asa_Server
    restart: unless-stopped
    environment:
      - PUID=1001                            # The UID to run server as
      - PGID=1001                            # The GID to run server as
      - TZ=America/Los_Angeles               # Timezone setting: Change this to your local timezone. Ex.America/New_York, Europe/Berlin, Asia/Tokyo
      - BATTLEEYE=FALSE                      # Set to TRUE to use BattleEye, FALSE to not use BattleEye
      - RCON_ENABLED=TRUE                    # Needed for Graceful Shutdown / Updates / Server Notifications
      - DISPLAY_POK_MONITOR_MESSAGE=FALSE    # TRUE to Show the Server Monitor Messages / Update Monitor 
      - UPDATE_SERVER=TRUE                   # Enable or disable update checks
      - CHECK_FOR_UPDATE_INTERVAL=24         # Check for Updates interval in hours
      - UPDATE_WINDOW_MINIMUM_TIME=12:00 AM  # Defines the minimum time, relative to server time, when an update check should run
      - UPDATE_WINDOW_MAXIMUM_TIME=11:59 PM  # Defines the maximum time, relative to server time, when an update check should run
      - RESTART_NOTICE_MINUTES=30            # Duration in minutes for notifying players before a server restart due to updates
      - ENABLE_MOTD=FALSE                    # Enable or disable Message of the Day
      - MOTD=                                # Message of the Day
      - MOTD_DURATION=30                     # Duration for the Message of the Day
      - MAP_NAME=TheIsland
      - SESSION_NAME=Server_name
      - SERVER_ADMIN_PASSWORD=MyPassword
      - SERVER_PASSWORD=                     # Set a server password or leave it blank (ONLY NUMBERS AND CHARACTERS ARE ALLOWED BY DEVS)
      - ASA_PORT=7777
      - RCON_PORT=27020
      - MAX_PLAYERS=70
      - CLUSTER_ID=cluster
      - PASSIVE_MODS=                        # Replace with your passive mods IDs
      - MOD_IDS=                             # Add your mod IDs here, separated by commas, e.g., 123456789,987654321
      - CUSTOM_SERVER_ARGS=                  # If You need to add more Custom Args -ForceRespawnDinos -ForceAllowCaveFlyers
    ports:
      - "7777:7777/tcp"
      - "7777:7777/udp"
    mem_limit: 16G 


```
#### Additional server settings 

Advanced Config
For custom settings, edit GameUserSettings.ini in <Instance_name>/Saved/Config/WindowsServer. Modify and restart the container.

---
### Temp Fix ###
IF you see this at the end of you logs 
```
asa_pve_Server | [2023.11.06-03.55.48:449][  1]Allocator Stats for binned2 are not in this build set BINNED2_ALLOCATOR_STATS 1 in MallocBinned2.cpp
```
you need to run this command first 
```
sysctl -w vm.max_map_count=262144
```
if you want to make it perment 
```
sudo -s echo "vm.max_map_count=262144" >> /etc/sysctl.conf && sysctl -p
```
### Hypervisors
If you are using Proxmox as your virtual host make sure to set the CPU Type to "host" in your VM elsewise you'll get errors with the server.

#### SERVER_MANAGER

you can also do automatic restart with CronJobs example below

```
 0 3 * * * /path/to/POK-manager.sh -restart 10 -all
```
 this will schedule a restart every day at 3 AM with a 10-minute countdown

#### UPDATING DOCKER IMAGE
Open a terminal or command prompt.

Update the image / POK-manager.sh / Serverfiles
```
./POK-manager.sh -update
```

## Discord Server 
https://discord.gg/9GJKWjQuXy
for Support 

## Star History

<a href="https://star-history.com/#Acekorneya/Ark-Survival-Ascended-Server&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
  </picture>
</a>

