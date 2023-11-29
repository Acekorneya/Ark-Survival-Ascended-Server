# Use an image that has Wine installed to run Windows applications
FROM scottyhardy/docker-wine

# Add ARG for PUID and PGID with a default value
ARG PUID=1001
ARG PGID=1001

# Arguments and environment variables
ENV PUID ${PUID}
ENV PGID ${PGID}
ENV WINEPREFIX /usr/games/.wine
ENV WINEDEBUG err-all
ENV PROGRAM_FILES "$WINEPREFIX/drive_c/POK"
ENV ASA_DIR "$PROGRAM_FILES/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/"

# Create required directories
RUN mkdir -p "$PROGRAM_FILES"

# Change user shell and set ownership
RUN usermod --shell /bin/bash games && chown -R games:games /usr/games

# Modify user and group IDs
RUN groupmod -o -g $PGID games && \
    usermod -o -u $PUID -g games games

# Install jq, curl, and dependencies for rcon-cli
USER root

RUN apt-get update && \
    apt-get install -y jq curl unzip nano && \
    rm -rf /var/lib/apt/lists/* && \
    curl -L https://github.com/itzg/rcon-cli/releases/download/1.6.3/rcon-cli_1.6.3_linux_amd64.tar.gz | tar xvz && \
    mv rcon-cli /usr/local/bin/ && \
    chmod +x /usr/local/bin/rcon-cli

# Switch to games user
USER games

# Set the working directory
WORKDIR /usr/games

# Install SteamCMD
RUN wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip \
    && unzip steamcmd.zip -d "$PROGRAM_FILES/Steam" \
    && rm steamcmd.zip

# Debug: Output the directory structure for Program Files to debug
RUN ls -R "$WINEPREFIX/drive_c/POK"

# Install Steam app dependencies
RUN ln -s "$PROGRAM_FILES/Steam" /usr/games/Steam && \
    mkdir -p /usr/games/Steam/steamapps/common && \
    find /usr/games/Steam/steamapps/common -maxdepth 0 -not -name "Steamworks Shared" 

# Explicitly set the ownership of WINEPREFIX directory to games
RUN chown -R games:games "$WINEPREFIX"

# Switch back to root for final steps
USER root

# Copy scripts folder into the container
COPY scripts/ /usr/games/scripts/
# Copy defaults folder into the container
COPY defaults/ /usr/games/defaults/

# Remove Windows-style carriage returns from the scripts
RUN sed -i 's/\r//' /usr/games/scripts/*.sh

# Make scripts executable
RUN chmod +x /usr/games/scripts/*.sh

# Set the entry point to Supervisord
ENTRYPOINT ["/usr/games/scripts/init.sh"]
