FROM ubuntu:16.04
MAINTAINER Andre Braga Reis <andrebragareis@gmail.com>

## Runscript 

# Ready package manager, install build tools, SUMO dependencies, gnuplot5
RUN apt-get update
RUN apt-get install -y curl nano 
RUN apt-get install -y build-essential libxerces-c-dev
RUN apt-get install -y gnuplot5-nox

# Fetch, patch, compile and install SUMO 0.26
ADD http://downloads.sourceforge.net/project/sumo/sumo/version%200.26.0/sumo-src-0.26.0.tar.gz /root/
RUN cd /root/ && tar xzf sumo-src-0.26.0.tar.gz && cd sumo-0.26.0 && \
sed '/#include <assert.h>/a #include <cmath>' -i src/utils/vehicle/IntermodalRouter.h && \
./configure && make -j5 && make install


# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

