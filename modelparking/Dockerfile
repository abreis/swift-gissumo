FROM ubuntu:16.04
MAINTAINER Andre Braga Reis <andrebragareis@gmail.com>

## Runscript
# docker run -itd --name sumo --volume sumodata:/work abreis/sumo
# For external control add "-p 8813:8813"

# Ready package manager
RUN apt-get update

# Install:
# - essentials
# - sumo dependencies
# - xml validator
RUN apt-get install -y \
software-properties-common \
curl nano python python3 libxml2-utils 

# Install SUMO
RUN add-apt-repository ppa:sumo/stable
RUN apt-get update
RUN apt-get install -y sumo sumo-tools sumo-doc

# Clean up package manager
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add script, data and src folders, Makefile, main.sh
WORKDIR "/root"
ADD ./scripts /root/scripts
ADD ./interact /root/interact
ADD main.sh /root

# Share a folder with the host in which to store results
VOLUME /work

# Expose the SUMO port for external tools
# EXPOSE 8813

CMD ["/bin/bash"]
