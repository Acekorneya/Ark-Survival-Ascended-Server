FROM ubuntu:20.04

# Accept PUID and PGID environment variables to allow runtime specification
ARG PUID=1000
ARG PGID=1000

# Set a default timezone, can be overridden at runtime
ENV TZ=UTC
ENV PUID=${PUID}
ENV PGID=${PGID}
ENV PROTON_USE_ESYNC=1 

# Install necessary packages
RUN set -ex; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    jq curl wget tar unzip nano gzip iproute2 procps software-properties-common dbus \
    lib32gcc-s1 libglib2.0-0 libglib2.0-0:i386 libvulkan1 libvulkan1:i386 \
    libnss3 libnss3:i386 libgconf-2-4 libgconf-2-4:i386 \
    libfontconfig1 libfontconfig1:i386 libfreetype6 libfreetype6:i386 \
    libcups2 libcups2:i386; \
    # Cleanup to keep the image lean
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Create the pok group and user, assign home directory, and add to the 'users' group  
RUN set -ex; \
    groupadd -g ${PGID} pok && \
    useradd -d /home/pok -u ${PUID} -g pok -G users -m pok; \
    mkdir /home/pok/arkserver

# Setup working directory
WORKDIR /opt/steamcmd
RUN set -ex; \
    wget -qO- https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar zxvf -

# Setup the Proton GE
WORKDIR /usr/local/bin
RUN set -ex; \
    curl -sLOJ "$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)"; \
    tar -xzf GE-Proton*.tar.gz --strip-components=1; \
    rm GE-Proton*.*

# Setup machine-id for Proton
RUN set -ex; \
    rm -f /etc/machine-id; \
    dbus-uuidgen --ensure=/etc/machine-id; \
    rm /var/lib/dbus/machine-id; \
    dbus-uuidgen --ensure

WORKDIR /tmp/
# Setup rcon-cli
RUN set -ex; \
    wget -qO- https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz | tar xvz && \
    mv rcon-0.10.3-amd64_linux/rcon /usr/local/bin/rcon-cli && \
    chmod +x /usr/local/bin/rcon-cli

# Install tini
ARG TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

RUN set -ex; \
    chown -R pok:pok /home/pok; \
    chown -R pok:pok /home/pok/arkserver; \
    chown -R pok:pok /opt/steamcmd

# Copy scripts and defaults folders into the container, ensure they are executable
COPY --chown=pok:pok scripts/ /home/pok/scripts/
COPY --chown=pok:pok defaults/ /home/pok/defaults/
RUN  chmod +x /home/pok/scripts/*.sh
# Switch back to pok to run the entrypoint script
USER pok
WORKDIR /home/pok

# Use tini as the entrypoint  
ENTRYPOINT ["/tini", "--", "/home/pok/scripts/init.sh"]
