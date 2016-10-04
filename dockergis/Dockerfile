FROM ubuntu:14.04
MAINTAINER Andre Braga Reis <andrebragareis@gmail.com>

## Runscript 
# docker run -itd --name gis --volume gisdata:/work -p 5432:5432 abreis/gis

# Ready package manager
RUN apt-get update

# Install:
# - build tools, essentials
# - postgresql, postgis

RUN apt-get install -y \
build-essential curl nano \
postgresql-9.3-postgis-2.1

WORKDIR "/root"

# Clean up package manager
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add script, data and src folders, Makefile, main.sh
ADD ./scripts /root/scripts
ADD ./data /root/data
ADD main.sh /root

# Share a folder with the host in which to store results
VOLUME /work

# Expose the PostgreSQL port for external tools
EXPOSE 5432

CMD ["/bin/bash"]
