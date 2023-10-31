
### Documentation for Ark Survival Ascended Server Docker Image

#### Docker Image Details

This Docker image is designed to run a dedicated server for the game Ark Survival Ascended. It's based on `scottyhardy/docker-wine` to enable the running of Windows applications. The image uses a bash script to handle startup, server installation, server update ,and setting up environment variables.

#### Repository: [Your GitHub Repository]

---

#### Environment Variables

| Variable                 | Default                    | Description                                              |
| ------------------------ | -------------------------- | -------------------------------------------------------- |
| `PUID`                   | `1001`                     | The UID to run server as                                 |
| `PGID`                   | `1001`                     | The GID to run server as                                 |
| `MAP_NAME`               | `TheIsland`                | The map name (`TheIsland')           |
| `SESSION_NAME`           |   `Server_name`                        | The session name for the server                          |
| `SERVER_ADMIN_PASSWORD`  |  `MyPassword`                          | The admin password for the server                        |
| `MULTI_HOME`             | `0.0.0.0`                  | Server IP                                                |
| `DNL_PORT`               | `7777`                     | The game port for the server                             |
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

| Volume Path                                           | Description                                    |
| ---------------------------------------------------- | ---------------------------------------------- |
| `./ASA`              | Game files                                     |
| `./ARK Survival Ascended Dedicated Server` | Server config files                           |
| `./Cluster`           | Cluster files                                  |

---

#### Recommended System Requirements

- CPU: min 2 CPUs
- RAM: > 16 GB
- Disk: ~20 GB

---

#### Usage

##### Docker Compose

Create a `docker-compose.yml` file and populate it with the service definition. 

```yaml
version: '2.4'

services:
  darkandlight:
    build: .
    image: asa_server:latest
    container_name: asa_pve_Server
    restart: unless-stopped
    environment:
      - PUID=1001
      - PGID=1001
      - MAP_NAME=TheIsland
      - SESSION_NAME=POK-PVE-Community-ARK-Server-NO-WIPE
      - SERVER_ADMIN_PASSWORD=kORNEYA512
      - MULTI_HOME=0.0.0.0
      - ASA_PORT=8780
      - QUERY_PORT=28017
      - MAX_PLAYERS=70
      - CLUSTER_ID=kny
    ports:
      - "8780:8780/tcp"
      - "8780:8780/udp"
      - "28017:28017/tcp"
      - "28017:28017/udp"
    volumes:
      - "./ASA:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame"
      - "./ARK Survival Ascended Dedicated Server:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ARK Survival Ascended Dedicated Server"
      - "/home/factorioserver/ASA_Cluster/Cluster:/usr/games/.wine/drive_c/POK/Steam/steamapps/common/ShooterGame"
    memswap_limit: 16G
    mem_limit: 12G  
```

If you're planning to change the volume directories, create those directories manually before starting the service.

Then, run the following command to start the server:

```bash
docker-compose up -d
```

---

#### Additional server settings 

Advanced Config
For custom settings, edit GameUserSettings.ini in Saved/Config/WindowsServer. Modify and restart the container.

---

#### Comments

