
### Documentation for Ark Survival Ascended Server Docker Image

#### Docker Image Details

This Docker image is designed to run a dedicated server for the game Ark Survival Ascended. It's based on `scottyhardy/docker-wine` to enable the running of Windows applications. The image uses a bash script to handle startup, server installation, server update ,and setting up environment variables.

#### Docker Hub Repository: https://hub.docker.com/r/acekorneya/asa_server

---

#### Environment Variables

| Variable                 | Default                    | Description                                              |
| ------------------------ | -------------------------- | -------------------------------------------------------- |
| `PUID`                   | `1001`                     | The UID to run server as                                 |
| `PGID`                   | `1001`                     | The GID to run server as                                 |
| `MAP_NAME`               | `TheIsland`                | The map name (`TheIsland')           |
| `SESSION_NAME`           |   `Server_name`                        | The session name for the server                          |
| `SERVER_ADMIN_PASSWORD`  |  `MyPassword`                          | The admin password for the server                        |                                               |
| `ASA_PORT`               | `7777`                     | The game port for the server                             |
| `QUERY_PORT`             | `27015`                    | The query port for the server                            |
| `MAX_PLAYERS`            | `127`                       | Max allowed players                                      |
| `CLUSTER_ID`             |  `cluster`                 | The Cluster ID for the server                            |

---

#### Additional Information

- **PUID and PGID**: These are important for setting the permissions of the folders that Docker will use. Make sure to set these values based on your host machine's user and group IDs.
  
- **Folder Creation**: Before starting the Docker Compose file, make sure to manually create any folders that you'll be using for volumes, especially if you're overriding the default folders.

---

#### Ports

| Port         | Description                            |
| ------------ | -------------------------------------- |
| `7777/tcp`   | Game port                              |
| `7777/udp`   | Game port                              |
| `27015/tcp`  | Query port                             |
| `27015/udp`  | Query port                             |

---

#### Volumes
When you run the docker compose up it should create this folders in the same folder as the docker-compose.yaml file unless changed by the user

| Volume Path                                           | Description                                    |
| ---------------------------------------------------- | ---------------------------------------------- |
| `./ASA`              | Game files                                     |
| `./ARK Survival Ascended Dedicated Server` | Server files                           |
| `./Cluster`           | Cluster files                                  |

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
      - PUID=1001
      - PGID=1001
      - BATTLEEYE=FALSE  # Set to TRUE to use BattleEye, FALSE to not use BattleEye
      - MAP_NAME=TheIsland
      - SESSION_NAME=Server_name
      - SERVER_ADMIN_PASSWORD=MyPassword
      - ASA_PORT=7777
      - QUERY_PORT=27015
      - MAX_PLAYERS=70
      - CLUSTER_ID=cluster
      - MOD_IDS=          # Add your mod IDs here, separated by commas, e.g., "123456789,987654321"
    ports:
      - "7777:7777/tcp"
      - "7777:7777/udp"
      - "27015:27015/tcp"
      - "27015:27015/udp"
    volumes:
      - "./ASA:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame"
      - "./ARK Survival Ascended Dedicated Server:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server"
      - "./Cluster:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ShooterGame"
    memswap_limit: 16G  
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

#### Comments
as of right now you will need to copy the Game.Ini Files from a single player game and place them in the same Folder as the GameUserSetting.Ini

#### updating Sever 
docker compose down 
docker compose up 
then the program should automatically start updating the server when it starts up again

## Star History

<a href="https://star-history.com/#Acekorneya/Ark-Survival-Ascended-Server&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acekorneya/Ark-Survival-Ascended-Server&type=Date" />
  </picture>
</a>

