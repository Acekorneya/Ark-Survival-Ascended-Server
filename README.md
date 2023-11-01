
### Documentation for Ark Survival Ascended Server Docker Image

#### Docker Image Details

This Docker image is designed to run a dedicated server for the game Ark Survival Ascended. It's based on `scottyhardy/docker-wine` to enable the running of Windows applications. The image uses a bash script to handle startup, server installation, server update ,and setting up environment variables.

#### Repository: https://github.com/Acekorneya/Ark-Survival-Ascended-Server

---

#### Environment Variables

| Variable                 | Default                    | Description                                              |
| ------------------------ | -------------------------- | -------------------------------------------------------- |
| `PUID`                   | `1001`                     | The UID to run server as                                 |
| `PGID`                   | `1001`                     | The GID to run server as                                 |
| `MAP_NAME`               | `TheIsland`                | The map name (`TheIsland')           |
| `SESSION_NAME`           |   `Server_name`                        | The session name for the server                          |
| `SERVER_ADMIN_PASSWORD`  |  `MyPassword`                          | The admin password for the server                        |                                               |
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
Make sure to create this 3 folders in the same folder as the docker-compose.yaml and make sure to name them EXACTLY the same as Volume Path name below

| Volume Path                                           | Description                                    |
| ---------------------------------------------------- | ---------------------------------------------- |
| `./ASA`              | Game files                                     |
| `./ARK Survival Ascended Dedicated Server` | Server files                           |
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
  asaserver:
    build: .
    image: asa_server:latest
    container_name: asa_pve_Server
    restart: unless-stopped
    environment:
      - PUID=1001
      - PGID=1001
      - MAP_NAME=TheIsland
      - SESSION_NAME=Server_name
      - SERVER_ADMIN_PASSWORD=MyPassword
      - ASA_PORT=7777
      - QUERY_PORT=27015
      - MAX_PLAYERS=70
      - CLUSTER_ID=cluster
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

