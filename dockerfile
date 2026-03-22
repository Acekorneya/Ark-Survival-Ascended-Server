FROM ubuntu:22.04

# IMPORTANT: These values are set at build time and CANNOT be changed at runtime
# The container has fixed user IDs:
# - 2_0_latest image: PUID=1000, PGID=1000
# - 2_1_latest image: PUID=7777, PGID=7777
# Host file ownership MUST match these values to avoid permission issues
ARG PUID=7777
ARG PGID=7777
ARG PROTON_VERSION=GE-Proton10-32

# Set a default timezone, can be overridden at runtime
ENV TZ=UTC
ENV PUID=${PUID}
ENV PGID=${PGID}
ENV PROTON_USE_ESYNC=1 
ENV DEBIAN_FRONTEND=noninteractive
# Set specific Wine version to ensure consistency
ENV WINEDLLOVERRIDES="version=n,b;vcrun2022=n,b"
ENV WINEPREFIX="/home/pok/.steam/steam/steamapps/compatdata/2430930/pfx"
ENV DISPLAY=:0.0
ENV HEALTHCHECK_PORT=8080

# Install necessary packages and setup for WineHQ repository
RUN set -ex; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    jq curl wget tar unzip nano gzip iproute2 procps software-properties-common dbus \
    python3-minimal \
    tzdata \
    # tzdata package provides timezone database for TZ environment variable support \
    lib32gcc-s1 libglib2.0-0 libglib2.0-0:i386 libvulkan1 libvulkan1:i386 \
    libnss3 libnss3:i386 libgconf-2-4 libgconf-2-4:i386 \
    libfontconfig1 libfontconfig1:i386 libfreetype6 libfreetype6:i386 \
    libcups2 libcups2:i386 \
    gnupg2 ca-certificates \
    # Add X server packages for headless operation
    xvfb x11-xserver-utils xauth libgl1-mesa-dri libgl1-mesa-glx \
    # Add necessary libraries for Wine and VC++
    libldap-2.5-0:i386 libldap-2.5-0 libgnutls30:i386 libgnutls30 \
    libxml2:i386 libxml2 libasound2:i386 libasound2 libpulse0:i386 libpulse0 \
    libopenal1:i386 libopenal1 libncurses6:i386 libncurses6 \
    # DO NOT ENABLE screen package - causes log display issues which is needed by the POK-manager.sh script
    # cabextract is essential for winetricks vcrun2019 installation
    cabextract winbind; \
    # Setup WineHQ repository
    mkdir -pm755 /etc/apt/keyrings; \
    wget -O - https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key; \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources; \
    apt-get update; \
    # Install latest stable Wine
    apt-get install -y --install-recommends winehq-stable; \
    # Cleanup to keep the image lean
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Setup winetricks for Visual C++ Redistributable installation
RUN set -ex; \
    wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O /usr/local/bin/winetricks && \
    chmod +x /usr/local/bin/winetricks

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
    curl -sL "$DOWNLOAD_URL" -o /tmp/proton.tar.gz; \
    mkdir -p /tmp/proton-extract; \
    mkdir -p /home/pok/.steam/steam/compatibilitytools.d; \
    tar -xzf /tmp/proton.tar.gz -C /tmp/proton-extract; \
    ACTUAL_VERSION=$(basename "$(find /tmp/proton-extract -maxdepth 1 -mindepth 1 -type d | head -n 1)"); \
    mv /tmp/proton-extract/* /home/pok/.steam/steam/compatibilitytools.d/; \
    ln -sf /home/pok/.steam/steam/compatibilitytools.d/$ACTUAL_VERSION /home/pok/.steam/steam/compatibilitytools.d/GE-Proton-Current; \
    ln -sf /home/pok/.steam/steam/compatibilitytools.d/$ACTUAL_VERSION /home/pok/.steam/steam/compatibilitytools.d/GE-Proton8-21; \
    ln -sf /home/pok/.steam/steam/compatibilitytools.d/$ACTUAL_VERSION /home/pok/.steam/steam/compatibilitytools.d/GE-Proton9-25; \
    rm -rf /tmp/proton-extract /tmp/proton.tar.gz

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

# Setup and pre-initialize Wine environment for AsaApi
RUN set -ex; \
    # Create a complete Wine prefix structure
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/windows/system32; \
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files/Common\ Files; \
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files\ \(x86\)/Common\ Files; \
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/users/steamuser/Temp; \
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/dosdevices; \
    # Create proper symlinks for dosdevices
    ln -sf "../drive_c" /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/dosdevices/c:; \
    ln -sf "/dev/null" /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/dosdevices/d::; \
    ln -sf "/dev/null" /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/dosdevices/e::; \
    ln -sf "/dev/null" /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/dosdevices/f::; \
    # Create comprehensive Visual C++ structure for AsaApi (aligned with VS 2022 redistributables)
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT; \
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT; \
    mkdir -p /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/windows/system32/vcruntime; \
    # Create VC++ dummy files so ASA API loaders detect the redistributable during first boot
    touch /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/msvcp140.dll; \
    touch /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x64/Microsoft.VC143.CRT/vcruntime140.dll; \
    touch /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT/msvcp140.dll; \
    touch /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35211/x86/Microsoft.VC143.CRT/vcruntime140.dll; \
    # Create wine registry files with proper configuration
    echo "WINE REGISTRY Version 2" > /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/system.reg; \
    echo ";; All keys relative to \\\\Machine" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/system.reg; \
    echo "#arch=win64" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/system.reg; \
    echo "" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/system.reg; \
    echo "WINE REGISTRY Version 2" > /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg; \
    echo ";; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg; \
    echo "#arch=win64" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg; \
    echo "[Software\\\\Wine\\\\DllOverrides]" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg; \
    echo "\"*version\"=\"native,builtin\"" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg; \
    echo "\"vcrun2019\"=\"native,builtin\"" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg; \
    echo "" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/user.reg; \
    echo "WINE REGISTRY Version 2" > /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/userdef.reg; \
    echo ";; All keys relative to \\\\User\\\\DefUser" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/userdef.reg; \
    echo "#arch=win64" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/userdef.reg; \
    echo "" >> /home/pok/.steam/steam/steamapps/compatdata/2430930/pfx/userdef.reg; \
    # Create tracked_files to mark prefix as initialized
    touch /home/pok/.steam/steam/steamapps/compatdata/2430930/tracked_files

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
    # Ensure Wine prefix has correct permissions
    chown -R pok:pok /home/pok/.steam/steam/steamapps/compatdata/2430930; \
    chmod -R 755 /home/pok/.steam/steam/steamapps/compatdata/2430930; \
    # Make AsaApi directories executable
    mkdir -p /home/pok/arkserver/ShooterGame/Binaries/Win64/AsaApi; \
    chmod -R 755 /home/pok/arkserver/ShooterGame/Binaries/Win64/AsaApi; \
    chmod -R +x /home/pok/arkserver/ShooterGame/Binaries/Win64; \
    # Ensure winetricks can run for user pok
    chmod +x /usr/local/bin/winetricks

# Download and pre-install VC++ Redistributable (14.44.35211.0)
USER pok
RUN set -ex; \
    mkdir -p /tmp/vcredist; \
    cd /tmp/vcredist; \
    wget -q https://aka.ms/vs/17/release/vc_redist.x64.exe; \
    wget -q https://aka.ms/vs/17/release/vc_redist.x86.exe; \
    # Prefer vcrun2022 for latest VC++ runtime; fall back to vcrun2019 if winetricks lacks the verb
    WINEPREFIX="/home/pok/.steam/steam/steamapps/compatdata/2430930/pfx" \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    winetricks -q vcrun2022 || winetricks -q vcrun2019 || true; \
    # Install the official redistributables quietly for both architectures
    WINEPREFIX="/home/pok/.steam/steam/steamapps/compatdata/2430930/pfx" \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    wine64 /tmp/vcredist/vc_redist.x64.exe /quiet /norestart || true; \
    WINEPREFIX="/home/pok/.steam/steam/steamapps/compatdata/2430930/pfx" \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    wine /tmp/vcredist/vc_redist.x86.exe /quiet /norestart || true; \
    rm -rf /tmp/vcredist

USER root
# Copy scripts, defaults, and Require_Files folders into the container, ensure they are executable
COPY --chown=pok:pok scripts/ /home/pok/scripts/
COPY --chown=pok:pok defaults/ /home/pok/defaults/
COPY --chown=pok:pok require_files/ /home/pok/require_files/
RUN find /home/pok/scripts -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +

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
  CMD curl -fsS "http://127.0.0.1:${HEALTHCHECK_PORT}/healthz" >/dev/null || exit 1

# Use tini as the entrypoint  
ENTRYPOINT ["/tini", "--", "/home/pok/scripts/init.sh"]
