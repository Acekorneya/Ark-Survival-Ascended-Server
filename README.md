
### Documentation for Ark Survival Ascended Server Docker Image

#### Docker Image Details

This Docker image is designed to run a dedicated server for the game Ark Survival Ascended. It's based on `scottyhardy/docker-wine` to enable the running of Windows applications. The image uses a bash script to handle startup, server installation, server update ,and setting up environment variables.

#### Docker Hub Repository: https://hub.docker.com/r/acekorneya/asa_server

---

#### Environment Variables

| Variable                      | Default           | Description                                                                               |
| ------------------------------| ------------------| ------------------------------------------------------------------------------------------|
| `PUID`                        | `1001`            | The UID to run server as                                                                  |
| `PGID`                        | `1001`            | The GID to run server as                                                                  |
| `BATTLEEYE`                   | `TRUE`            | Set to TRUE to use BattleEye, FALSE to not use BattleEye                                  |
| `RCON_ENABLED`                | `TRUE`            | Needed for Graceful Shutdown                                                              |
| `DISPLAY_POK_MONITOR_MESSAGE` | `TRUE`            | FALSE to suppress the Server Monitor Shutdown                                             |
| `UPDATE_SERVER`               | `TRUE`            | Enable or disable update checks                                                           |
| `CHECK_FOR_UPDATE_INTERVAL`   | `24`              | Check for Updates interval in hours                                                       |
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
| `CLUSTER_ID`                  | `cluster`         | The Cluster ID for the server                                                             | 
| `MOD_IDS`                     |                   | Add your mod IDs here, separated by commas, e.g., 123456789,987654321                     |
| `CUSTOM_SERVER_ARGS`          |                   | If You need to add more Custom Args -ForceRespawnDinos -ForceAllowCaveFlyers              |

---

#### Additional Information

- **PUID and PGID**: These are important for setting the permissions of the folders that Docker will use. Make sure to set these values based on your host machine's user and group ID
  
- **Folder Creation**: Before starting the Docker Compose file, make sure to manually create any folders that you'll be using for volumes, especially if you're overriding the default folders.

---

#### Ports

| Port         | Description                            |
| ------------ | -------------------------------------- |
| `7777/tcp`   | Game port                              |
| `7777/udp`   | Game port                              |

---

#### Volumes
When you run the docker compose up it should create this folders in the same folder as the docker-compose.yaml file unless changed by the user

| Volume Path                                          | Description                                   |
| ---------------------------------------------------- | ---------------------------------------------- |
| `./ASA`                                              | Game files                                     |
| `./ARK Survival Ascended Dedicated Server`           | Server files                                   |
| `./Cluster`                                          | Cluster files                                  |

---

#### Recommended System Requirements

- CPU: min 2 CPUs
- RAM: > 16 GB
- Disk: ~50 GB

---

#### Usage

##### Docker Compose

Create a `docker-compose.yaml` file and populate it with the service definition. 

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
      - BATTLEEYE=FALSE                      # Set to TRUE to use BattleEye, FALSE to not use BattleEye
      - RCON_ENABLED=TRUE                    # Needed for Graceful Shutdown / Updates / Server Notifications
      - DISPLAY_POK_MONITOR_MESSAGE=TRUE     # Or FALSE to suppress the Server Monitor / Update Monitor 
      - UPDATE_SERVER=TRUE                   # Enable or disable update checks
      - CHECK_FOR_UPDATE_INTERVAL=24         # Check for Updates interval in hours
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
      - MOD_IDS=                             # Add your mod IDs here, separated by commas, e.g., 123456789,987654321
      - CUSTOM_SERVER_ARGS=                  # If You need to add more Custom Args -ForceRespawnDinos -ForceAllowCaveFlyers
    ports:
      - "7777:7777/tcp"
      - "7777:7777/udp"
    volumes:
      - "./ASA:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame"
      - "./ARK Survival Ascended Dedicated Server:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server"
      - "./Cluster:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ShooterGame"
    mem_limit: 16G 


```

If you're planning to change the volume directories, create those directories manually before starting the service.

Then, run the following command to start the server:

```bash
sudo docker compose up
```

---

#### Additional server settings 

Advanced Config
For custom settings, edit GameUserSettings.ini in ASA/Saved/Config/WindowsServer. Modify and restart the container.

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
If you want to run Rcon_manager.sh download it just place it in the same folder as your docker-compose.yaml make it executable and launch it..

#### UPDATING DOCKER IMAGE
Open a terminal or command prompt.

romove old docker image 
```
docker rmi acekorneya/asa_server:latest
```
then run this command downloads the latest version of the Ark: Survival Ascended Docker image from Docker Hub.
```
docker pull acekorneya/asa_server:latest.
```
Restart the Docker Container

First, bring down your current container with 
```
docker-compose down.
```
Then, start it again using 
```
docker-compose up.
```
These commands stop the currently running container and start a new one with the updated image.

## Star History

<a href="https://star-history.com/#Acekorneya/Ark-Survival-Ascended-Server&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
  </picture>
</a>

