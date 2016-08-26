#!/bin/bash
set -e

if [ "$#" -ne 4 ]; then 
	echo "Usage: $0 <trip file> <net file> <seed> <output route file>"
	exit 1
fi

TRIPFILE=$1
NETFILE=$2
SEED=$3
ROUTEFILE=$4

if [ -z "$SUMO_HOME" ]; then 
	echo "Error: Please set and export SUMO_HOME."
	exit 1
fi

# Generate route file with duarouter
duarouter --net-file ${NETFILE} \
 --trip-files ${TRIPFILE} \
 --output-file ${ROUTEFILE} \
 --remove-loops \
 --ignore-errors \
 --repair \
 --seed=${SEED} \
 --verbose
