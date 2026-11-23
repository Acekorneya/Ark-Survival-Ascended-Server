FROM ubuntu:24.04 AS winprobe-builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc-mingw-w64-x86-64 && \
    rm -rf /var/lib/apt/lists/*
COPY require_files/pok_https_probe.c /tmp/pok_https_probe.c
RUN x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -municode \
    /tmp/pok_https_probe.c -o /tmp/pok_https_probe.exe -lwinhttp

FROM ubuntu:24.04

# IMPORTANT: These values are set at build time and CANNOT be changed at runtime
# The container has fixed user IDs:
# - 2_0_latest image: PUID=1000, PGID=1000
# - 2_1_latest image: PUID=7777, PGID=7777
# Host file ownership MUST match these values to avoid permission issues
ARG PUID=7777
ARG PGID=7777
ARG PROTON_VERSION=GE-Proton10-34

# Set a default timezone, can be overridden at runtime
ENV TZ=UTC
ENV PUID=${PUID}
ENV PGID=${PGID}
ENV PROTON_USE_ESYNC=1 
ENV DEBIAN_FRONTEND=noninteractive
ENV WINEDLLOVERRIDES="version=n,b"
ENV WINEPREFIX="/home/pok/.steam/steam/steamapps/compatdata/2430930/pfx"
ENV DISPLAY=:0.0
ENV HEALTHCHECK_PORT=8080

# Install the Linux dependencies required by SteamCMD and the pinned GE-Proton.
RUN set -ex; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    jq curl wget tar unzip nano gzip iproute2 procps software-properties-common dbus \
    python3-minimal \
    tzdata locales \
    # tzdata package provides timezone database for TZ environment variable support \
    lib32gcc-s1 libglib2.0-0 libglib2.0-0:i386 libvulkan1 libvulkan1:i386 \
    libnss3 libnss3:i386 \
    libfontconfig1 libfontconfig1:i386 libfreetype6 libfreetype6:i386 \
    libcups2 libcups2:i386 \
    gnupg2 ca-certificates \
    # Add X server packages for headless operation
    xvfb x11-xserver-utils xauth libgl1-mesa-dri libgl1 \
    # Add necessary libraries for Wine and VC++
    libldap2:i386 libldap2 libgnutls30:i386 libgnutls30 \
    libxml2:i386 libxml2 libasound2t64:i386 libasound2t64 libpulse0:i386 libpulse0 \
    libopenal1:i386 libopenal1 libncurses6:i386 libncurses6 winbind; \
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
    locale-gen en_US.UTF-8; \
    update-locale LANG=en_US.UTF-8; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create the pok group and user, assign home directory, and add to the 'users' group  
RUN set -ex; \
    groupadd -g ${PGID} pok && \
    useradd -d /home/pok -u ${PUID} -g pok -G users -m pok; \
    mkdir -p /home/pok/arkserver /home/pok/.steam/steam/compatibilitytools.d; \
    # Create critical directories for ASA API
    mkdir -p /home/pok/arkserver/ShooterGame/Binaries/Win64/logs; \
    mkdir -p /home/pok/arkserver/ShooterGame/Saved/Config/WindowsServer; \
    mkdir -p /home/pok/arkserver/ShooterGame/Saved/SavedArks; \
    mkdir -p /home/pok/arkserver/ShooterGame/Saved/Logs

# Setup working directory for steamcmd
WORKDIR /opt/steamcmd
RUN set -ex; \
    wget -qO- https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar zxvf -

# Setup the Proton GE with proper version handling
WORKDIR /usr/local/bin
RUN set -ex; \
    if [ "$PROTON_VERSION" = "latest" ]; then \
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | grep '.tar.gz"' | cut -d\" -f4 | head -n 1); \
    else \
    DOWNLOAD_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${PROTON_VERSION}.tar.gz"; \
    fi; \
    ARCHIVE_NAME="${DOWNLOAD_URL##*/}"; \
    CHECKSUM_URL="${DOWNLOAD_URL%.tar.gz}.sha512sum"; \
    CHECKSUM_NAME="${CHECKSUM_URL##*/}"; \
    curl -fsSL "$DOWNLOAD_URL" -o "/tmp/$ARCHIVE_NAME"; \
    curl -fsSL "$CHECKSUM_URL" -o "/tmp/$CHECKSUM_NAME"; \
    (cd /tmp && sha512sum -c "$CHECKSUM_NAME"); \
    mkdir -p /tmp/proton-extract; \
    mkdir -p /home/pok/.steam/steam/compatibilitytools.d; \
    tar -xzf "/tmp/$ARCHIVE_NAME" -C /tmp/proton-extract; \
    ACTUAL_VERSION=$(basename "$(find /tmp/proton-extract -maxdepth 1 -mindepth 1 -type d | head -n 1)"); \
    mv /tmp/proton-extract/* /home/pok/.steam/steam/compatibilitytools.d/; \
    ln -sf /home/pok/.steam/steam/compatibilitytools.d/$ACTUAL_VERSION /home/pok/.steam/steam/compatibilitytools.d/GE-Proton-Current; \
    printf '%s\n' "$ACTUAL_VERSION" > /home/pok/.steam/steam/compatibilitytools.d/.pok-proton-version; \
    rm -rf /tmp/proton-extract "/tmp/$ARCHIVE_NAME" "/tmp/$CHECKSUM_NAME"

# Setup machine-id for Proton
RUN set -ex; \
    rm -f /etc/machine-id; \
    dbus-uuidgen --ensure=/etc/machine-id; \
    rm -f /var/lib/dbus/machine-id; \
    dbus-uuidgen --ensure

WORKDIR /tmp/
# Setup rcon-cli
RUN set -ex; \
    wget -qO /tmp/rcon.tar.gz https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz; \
    echo "6962a641ebf9a5957bd0cda1b8acf3e34a23686ae709f6c6a14ac3898521a5cc  /tmp/rcon.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/rcon.tar.gz -C /tmp; \
    mv /tmp/rcon-0.10.3-amd64_linux/rcon /usr/local/bin/rcon-cli; \
    chmod +x /usr/local/bin/rcon-cli; \
    rm -rf /tmp/rcon.tar.gz /tmp/rcon-0.10.3-amd64_linux

# Install tini
ARG TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Set proper permissions for everything
RUN set -ex; \
    # Set proper permissions for user pok
    chown -R pok:pok /home/pok; \
    chown -R pok:pok /home/pok/arkserver; \
    chown -R pok:pok /home/pok/.steam; \
    chown -R pok:pok /opt/steamcmd; \
    # Ensure all critical directories have proper permissions
    find /home/pok/arkserver -type d -exec chmod 755 {} \;; \
    # Make logs directory world-writable to avoid permission issues
    chmod -R 775 /home/pok/arkserver/ShooterGame/Binaries/Win64/logs; \
    chmod -R 775 /home/pok/arkserver/ShooterGame/Saved/Logs; \
    # Make AsaApi directories executable
    mkdir -p /home/pok/arkserver/ShooterGame/Binaries/Win64/AsaApi; \
    chmod -R 755 /home/pok/arkserver/ShooterGame/Binaries/Win64/AsaApi; \
    chmod -R +x /home/pok/arkserver/ShooterGame/Binaries/Win64

# Initialize the prefix and install the official VC++ redistributables using
# the same pinned Proton runtime used to launch ASA.
USER pok
RUN set -ex; \
    mkdir -p /tmp/vcredist; \
    cd /tmp/vcredist; \
    wget -q https://aka.ms/vs/17/release/vc_redist.x64.exe; \
    export XDG_RUNTIME_DIR=/tmp/pok-runtime; \
    export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/pok/.steam/steam; \
    export STEAM_COMPAT_DATA_PATH=/home/pok/.steam/steam/steamapps/compatdata/2430930; \
    export STEAM_COMPAT_APP_ID=2430930 SteamAppId=2430930 SteamGameId=2430930; \
    export WINEDLLOVERRIDES="mscoree,mshtml="; \
    mkdir -p "$XDG_RUNTIME_DIR" "$STEAM_COMPAT_DATA_PATH"; chmod 700 "$XDG_RUNTIME_DIR"; \
    export DISPLAY=:99; Xvfb :99 -screen 0 1024x768x16 >/tmp/xvfb-build.log 2>&1 & sleep 1; \
    /home/pok/.steam/steam/compatibilitytools.d/GE-Proton-Current/proton runinprefix cmd.exe /c ver || test -s "$WINEPREFIX/system.reg"; \
    /home/pok/.steam/steam/compatibilitytools.d/GE-Proton-Current/proton runinprefix /tmp/vcredist/vc_redist.x64.exe /quiet /norestart || echo "VC++ x64 installer returned nonzero; verifying installed DLLs"; \
    test -s "$WINEPREFIX/system.reg"; \
    test -f "$WINEPREFIX/drive_c/windows/system32/vcruntime140.dll"; \
    test -f "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; \
    printf '%s\n' "$PROTON_VERSION" > "$STEAM_COMPAT_DATA_PATH/.pok-proton-prefix-version"; \
    rm -rf /tmp/vcredist

USER root
# Install Node.js 20 LTS for EOS token helpers
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy scripts, defaults, and Require_Files folders into the container, ensure they are executable
COPY --chown=pok:pok scripts/ /home/pok/scripts/
COPY --chown=pok:pok defaults/ /home/pok/defaults/
COPY --chown=pok:pok require_files/ /home/pok/require_files/
COPY --from=winprobe-builder --chown=pok:pok /tmp/pok_https_probe.exe /home/pok/require_files/pok_https_probe.exe
RUN find /home/pok/scripts -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
RUN cd /home/pok/scripts/helpers && npm install --production
RUN find /home/pok/scripts/helpers -type f \( -name "*.py" -o -name "*.js" \) -exec chmod +x {} +

# Create essential runtime directories with proper permissions
RUN set -ex; \
    mkdir -p /home/pok/logs; \
    chown -R pok:pok /home/pok/logs; \
    chmod -R 755 /home/pok/logs; \
    # Create convenience symlinks for monitoring logs
    ln -sf "/home/pok/arkserver/ShooterGame/Saved/Logs/ShooterGame.log" "/home/pok/shooter_game.log" 2>/dev/null || true; \
    # Setup X11 directories 
    mkdir -p /tmp/.X11-unix; \
    chmod 1777 /tmp/.X11-unix; \
    # Prepare for Xvfb in container
    touch /tmp/.X0-lock; \
    chmod 1777 /tmp/.X0-lock; \
    chown pok:pok /tmp/.X0-lock; \
    # Final permission check
    chown -R pok:pok /home/pok; \
    chown -R pok:pok /home/pok/arkserver/ShooterGame/Binaries/Win64/logs; \
    chmod -R 775 /home/pok/arkserver/ShooterGame/Binaries/Win64/logs

# Switch back to pok to run the entrypoint script
USER pok
WORKDIR /home/pok

HEALTHCHECK --interval=30s --timeout=10s --start-period=30m --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${HEALTHCHECK_PORT:-8080}/healthz" >/dev/null || exit 1

# Use tini as the entrypoint  
ENTRYPOINT ["/tini", "--", "/home/pok/scripts/init.sh"]
