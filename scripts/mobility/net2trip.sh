#!/bin/bash
set -e

if [ "$#" -ne 5 ]; then 
	echo "Usage: $0 <net file> <stop time> <period> <seed> <output trip file>"
	exit 1
fi

NETFILE=$1
STOPTIME=$2
PERIOD=$3
SEED=$4
TRIPFILE=$5

if [ -z "$SUMO_HOME" ]; then 
	echo "Error: Please set and export SUMO_HOME."
	exit 1
fi

# Generate trips on default net
# On a smaller map, increasing fringe-factor can cause cars to pool up
# around city edges and cause congestion
${SUMO_HOME}/tools/randomTrips.py \
 --net-file=${NETFILE} \
 --output-trip-file=${TRIPFILE} \
 --begin=0 \
 --end=${STOPTIME} \
 --fringe-factor=1 \
 --min-distance 100.0 \
 --period=${PERIOD} \
 --seed=${SEED} 
