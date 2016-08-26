#!/bin/bash
set -e

if [ "$#" -ne 4 ]; then 
	echo "Usage: $0 <route file> <net file> <stop time> <output fcd file>"
	exit 1
fi

ROUTEFILE=$1
NETFILE=$2
STOPTIME=$3
FCDFILE=$4

if [ -z "$SUMO_HOME" ]; then 
	echo "Error: Please set and export SUMO_HOME."
	exit 1
fi

# Simulate mobility with SUMO
sumo --net-file ${NETFILE} \
 --route-files ${ROUTEFILE} \
 --begin 0 \
 --end ${STOPTIME} \
 --step-length 1.0 \
 --fcd-output.geo \
 --fcd-output ${FCDFILE}
