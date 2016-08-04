#!/bin/bash
# Preliminary tests. Traffic generation. Loading of XML data.
set -e
WORKDIR=/work

export SUMO_HOME=$( find /root/ -type d -name 'sumo-*' -print -quit )
if [ ! -d "$SUMO_HOME" ]; then echo "SUMO home folder not found." ; exit 1; fi

SEED=123456
NETFILE=${WORKDIR}/map.net.xml
TRIPFILE=${WORKDIR}/trips.xml
ROUTEFILE=${WORKDIR}/routes.xml
FCDFILE=${WORKDIR}/fcdout.xml

## Generate trips on default net
${SUMO_HOME}/tools/randomTrips.py \
 --net-file=${NETFILE} \
 --output-trip-file=${TRIPFILE} \
 --begin=0 \
 --end=600 \
 --fringe-factor=2 \
 --min-distance 250.0 \
 --period=1.0 \
 --seed=${SEED} 
# the following trigger a call to route2trips
# --route-file=${WORKDIR}/routes.xml \
# --validate

## Generate route file with duarouter
duarouter --net-file ${NETFILE} \
 --trip-files ${TRIPFILE} \
 --output-file ${ROUTEFILE} \
 --remove-loops \
 --ignore-errors \
 --repair \
 --seed=${SEED} \
 --verbose


## Simulate mobility with SUMO
sumo --net-file ${NETFILE} \
 --route-files ${ROUTEFILE} \
 --begin 0 \
 --end 600 \
 --step-length 1.0 \
 --fcd-output.geo \
 --fcd-output ${FCDFILE}
	
# Please note that most of the car-following models were developed 
# for simulation step lengths of one second. The modelled dynamics 
# may not work properly if a different time step length is used.


