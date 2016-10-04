#!/bin/bash
set -e

SIMDIR=simulations
FCDDIR=fcddata

if [ ! -d ${FCDDIR} ]; then
	echo "No Floating Car Data."
	exit 1
fi

if [ -d ${SIMDIR} ]; then
	echo "Folder with previous simulations exists, move it before proceeding."
	exit 1
fi

if [ ! -f config.plist ]; then
	echo "Please provide a reference configuration file."
	exit 1
fi

if [ ! -f obstructionMask.payload ]; then
	echo "Please generate and provide an obstruction mask file."
	exit 1
fi

# Pull the latest binary
cp -f ../../build/gissumo_fast .

# Pull the config editor
cp -f ../../tools/configPlistEditor/build/configPlistEditor .

# Run Swift-GISSUMO on each Floating Car Data file
mkdir ${SIMDIR}
FCDCOUNT=$(find -L ${FCDDIR} -type f -iname '*.fcd.xml.gz' | wc -l)
SIMSREMAINING=${FCDCOUNT}
for GZFCDFILE in $(find -L ${FCDDIR} -type f -iname '*.fcd.xml.gz'); do
	# Create the base simulation directory
	SIMULATION=$(basename ${GZFCDFILE} .fcd.xml.gz)
	mkdir ${SIMDIR}/${SIMULATION}

	# Gunzip and copy the FCD file over
	FCDFILE=${SIMDIR}/${SIMULATION}/${SIMULATION}.fcd.xml
	cp -f ${GZFCDFILE} ${SIMDIR}/${SIMULATION}/
	gzip -d ${SIMDIR}/${SIMULATION}/${SIMULATION}.fcd.xml.gz

	# Copy the reference configuration file over
	CONFIGFILE=${SIMDIR}/${SIMULATION}/${SIMULATION}.config.plist
	cp config.plist ${CONFIGFILE}

	# Edit 'floatingCarDataFile' and 'statsFolder' on the .plist 
	./configPlistEditor ${CONFIGFILE} floatingCarDataFile ${FCDFILE}
	./configPlistEditor ${CONFIGFILE} stats.statsFolder ${SIMDIR}/${SIMULATION}/stats

	printf "${SIMULATION} ... "
	SECONDS=0

	# Simulate
	./gissumo_fast ${CONFIGFILE} > ${SIMDIR}/${SIMULATION}/gissumo.log 2>&1

	# Remove the copied FCD file
	rm -rf ${FCDFILE}

	# Run a moving average where each new simulation time is 10% of the new average
	SIMULATIONTIME=${SECONDS}
	if [ -z ${PREVSIMTIME} ]; then PREVSIMTIME=${SIMULATIONTIME}; fi
	SIMTIMEAVG=$(expr \( ${PREVSIMTIME} \* 90 + ${SIMULATIONTIME} \* 10 \) / 100)
	SIMSREMAINING=$(expr $SIMSREMAINING - 1)
	ESTTIMEREMAINING=$(expr ${SIMTIMEAVG} \* ${SIMSREMAINING})
	PREVSIMTIME=${SIMTIMEAVG}

	if [ $SIMSREMAINING -eq 0 ]; then printf "okay\n"; exit 0; fi

	printf "okay, time %ds, %d to go, ETA %dh%02dm%02ds\n" "${SIMULATIONTIME}" "${SIMSREMAINING}" $((${ESTTIMEREMAINING}/3600)) $((${ESTTIMEREMAINING}%3600/60)) $((${ESTTIMEREMAINING}%60))
done