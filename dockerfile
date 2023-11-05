# Start with a base Ubuntu image
FROM ubuntu:20.04

# Add ARG for PUID and PGID with a default value
ARG PUID=1001
ARG PGID=1001

# Arguments and environment variables
ENV PUID ${PUID}
ENV PGID ${PGID}
ENV PROGRAM_FILES "/usr/games/POK"
ENV ASA_DIR "$PROGRAM_FILES/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/"

# Install required tools and dependencies
RUN apt-get update && \
    apt-get install -y wget jq curl tar software-properties-common unzip xvfb && \
    rm -rf /var/lib/apt/lists/*

# Modify user and group IDs
RUN if getent group games ; then groupmod -o -g $PGID games; else groupadd -g $PGID games; fi && \
    if getent passwd games ; then usermod -o -u $PUID -g games games; else useradd -u $PUID -g games -s /bin/bash games; fi

# Switch to root user for operations requiring elevated privileges
USER root

# Create required directories for ProtonGE
RUN mkdir -p "$PROGRAM_FILES/proton-ge-custom"

# Ensure the games user has permissions on the created directories
RUN chown -R games:games "$PROGRAM_FILES"

# Ensure the games user has permissions on /usr/games
RUN chown -R games:games /usr/games

# Switch back to games user for subsequent operations
USER games

# Set the working directory
WORKDIR /usr/games

# Download and unzip SteamCMD
RUN wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip \
    && unzip steamcmd.zip -d "${PROGRAM_FILES}/Steam" \
    && rm steamcmd.zip

# Set up directories and permissions
RUN mkdir -p "$ASA_DIR" && \
    chown -R games:games "$ASA_DIR"

# Download and extract the specified ProtonGE release
RUN curl -L https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton8-22/GE-Proton8-22.tar.gz | tar xz -C "$PROGRAM_FILES/proton-ge-custom"

# Switch back to root for final steps
USER root

# Copy scripts folder into the container
COPY scripts/ /usr/games/scripts/

# Remove Windows-style carriage returns from the scripts and make them executable
RUN sed -i 's/\r//' /usr/games/scripts/*.sh && \
    chmod +x /usr/games/scripts/*.sh

# Set the entry point
ENTRYPOINT ["/usr/games/scripts/init.sh"]
