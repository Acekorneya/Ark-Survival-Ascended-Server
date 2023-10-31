# Use an image that has Wine installed to run Windows applications
FROM scottyhardy/docker-wine

# Arguments and environment variables
ARG USERNAME=anonymous
ARG APPID=2430930
ARG PUID=1001
ARG PGID=1001
ENV WINEPREFIX /usr/games/.wine
ENV WINEDEBUG -all
ENV PROGRAM_FILES "$WINEPREFIX/drive_c/POK"
ENV ASA_DIR "$PROGRAM_FILES/Steam/steamapps/common/ARK Survival Ascended Dedicated Server/"

# Create required directories
RUN mkdir -p "$PROGRAM_FILES"

# Change user shell and set ownership
RUN usermod --shell /bin/bash games && chown -R games:games /usr/games
# Modify user and group IDs
RUN groupmod -o -g $PGID games && \
    usermod -o -u $PUID -g games games

# Install jq and curl
USER root
RUN apt-get update && \
    apt-get install -y jq curl && \
    rm -rf /var/lib/apt/lists/*
    
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

# Copy the launch script
COPY launch_ASA.sh /usr/games/launch_ASA.sh

# Remove Windows-style carriage returns from the script
RUN sed -i 's/\r//' /usr/games/launch_ASA.sh

# Make the script executable
RUN chmod +x /usr/games/launch_ASA.sh

# Set the entry point
ENTRYPOINT ["/usr/games/launch_ASA.sh"]
