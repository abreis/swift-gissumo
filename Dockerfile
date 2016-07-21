FROM ubuntu:14.04
MAINTAINER Andre Braga Reis <andrebragareis@gmail.com>

## Runscript 
# docker run -itd --name gissumo --volume sgsdata:/work abreis/swiftgissumo

# Ready package manager
RUN apt-get update

# Install:
# - build tools, essentials
# - swift dependencies
# - sumo dependencies
# - gnuplot
# - xml validator
# - postgresql, postgis

RUN apt-get install -y \
build-essential curl nano \
libpython2.7 libedit2 libxml2 libicu52 \
libxerces-c-dev libproj-dev libgdal-dev python \
gnuplot-nox \
libxml2-utils \
postgresql-9.3-postgis-2.1

WORKDIR "/root"

# SUMO 0.27 (fetch, compile, install, clean)
RUN curl -L -o sumo-src-0.27.0.tar.gz http://downloads.sourceforge.net/project/sumo/sumo/version%200.27.0/sumo-src-0.27.0.tar.gz
RUN tar xzf sumo-src-0.27.0.tar.gz && cd sumo-0.27.0 && ./configure && make -j5 && make install && rm -f sumo-src-0.27.0.tar.gz
 
# Swift 2.2.1 (fetch, install, clean)
RUN curl -O https://swift.org/builds/swift-2.2.1-release/ubuntu1404/swift-2.2.1-RELEASE/swift-2.2.1-RELEASE-ubuntu14.04.tar.gz
RUN tar xzf swift*.tar.gz --directory / --strip-components=1 && rm -rf swift*.tar.gz

# Clean up package manager
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add script and data folders
ADD ./scripts /root/scripts
ADD ./data /root/data

# Share a folder with the host in which to store results
VOLUME /work

CMD ["/bin/bash"]
