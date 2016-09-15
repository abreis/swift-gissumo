#!/bin/bash
set -e

if [ "$#" -ne 4 ]; then
	echo "Usage: $0 <osm file> <stop time> <period> <seed>"
	exit 1
fi

WORKDIR=./mobilitydata
SCRIPTDIR=$(dirname $0)
mkdir -p ${WORKDIR}

OSMFILE=$1
STOPTIME=$2
PERIOD=$3
SEED=$4

BASENAME=${WORKDIR}/$(basename $(basename $OSMFILE .xml) .osm)
PARAMS="stop${STOPTIME}period${PERIOD}seed${SEED}"
NETFILE=${BASENAME}.net.xml
TRIPFILE=${BASENAME}.${PARAMS}.trip.xml
ROUTEFILE=${BASENAME}.${PARAMS}.route.xml
FCDFILE=${BASENAME}.${PARAMS}.fcd.xml
LOGFILE=${BASENAME}.${PARAMS}.log

printf "$(date)\n\n" > ${LOGFILE}

if [ ! -f $NETFILE ]; then
	printf "\n\nGenerating net file...\n" >> ${LOGFILE}
	${SCRIPTDIR}/osm2net.sh ${OSMFILE} ${NETFILE} >> ${LOGFILE} 2>&1
fi

if [ ! -f $TRIPFILE ]; then
	printf "\n\nGenerating trip file...\n" >> ${LOGFILE}
	${SCRIPTDIR}/net2trip.sh ${NETFILE} ${STOPTIME} ${PERIOD} ${SEED} ${TRIPFILE} >> ${LOGFILE} 2>&1
fi

if [ ! -f $ROUTEFILE ]; then
	printf "\n\nGenerating route file...\n" >> ${LOGFILE}
	${SCRIPTDIR}/trip2route.sh ${TRIPFILE} ${NETFILE} ${SEED} ${ROUTEFILE} >> ${LOGFILE} 2>&1
fi

if [ ! -f $FCDFILE ]; then
	printf "\n\nGenerating fcd file...\n" >> ${LOGFILE}
	${SCRIPTDIR}/route2fcd.sh ${ROUTEFILE} ${NETFILE} ${STOPTIME} ${FCDFILE} >> ${LOGFILE} 2>&1
fi
