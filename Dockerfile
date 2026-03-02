FROM        --platform=$TARGETOS/$TARGETARCH debian:trixie-slim

LABEL       author="David Wolfe (Red-Thirten)" maintainer="red_thirten@yahoo.com"

LABEL       org.opencontainers.image.source="https://github.com/pelican-eggs/yolks"
LABEL       org.opencontainers.image.licenses=AGPL-3.0-or-later

## Update base packages and install dependencies
ENV         DEBIAN_FRONTEND=noninteractive
RUN         dpkg --add-architecture i386 \
            && apt-get update \
            && apt-get upgrade -y \
            && apt-get install -y \
                # Basic packages
                curl \
                tzdata \
                locales \
                gettext-base \
                ca-certificates \
                tini \
                # SteamCMD req. packages
                lib32gcc-s1 \
                # Arma 3 req. packages
                # libssl-dev \
                # libsdl2-2.0-0 \
                # libsdl2-2.0-0:i386 \
                # libstdc++6 \
                # libstdc++6:i386 \
                # lib32stdc++6 \
                libnss-wrapper \
                libnss-wrapper:i386 \
                # Arma 3 opt. packages (eg. DB mods)
                libtbbmalloc2 \
                libtbbmalloc2:i386

## Configure locale
RUN         update-locale lang=en_US.UTF-8 \
            && dpkg-reconfigure --frontend noninteractive locales

## Prepare NSS Wrapper for the entrypoint as a workaround for Arma 3 requiring a valid UID
ENV         NSS_WRAPPER_PASSWD=/tmp/passwd NSS_WRAPPER_GROUP=/tmp/group
RUN         touch ${NSS_WRAPPER_PASSWD} ${NSS_WRAPPER_GROUP} \
            && chgrp 0 ${NSS_WRAPPER_PASSWD} ${NSS_WRAPPER_GROUP} \
            && chmod g+rw ${NSS_WRAPPER_PASSWD} ${NSS_WRAPPER_GROUP}
ADD         passwd.template /passwd.template

## Setup user and working directory
RUN         useradd -m -d /home/container -s /bin/bash container
USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

## Copy over entrypoint.sh and set permissions
COPY        --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh

## Start with Tini to pass future stop signals correctly
STOPSIGNAL  SIGINT
ENTRYPOINT  ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]