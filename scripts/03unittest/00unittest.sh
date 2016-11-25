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


for GZFCDFILE in $(find -L ${FCDDIR} -type f -iname '*.fcd.xml.gz'); do
	SIMULATION=$(basename ${GZFCDFILE} .fcd.xml.gz)
	mkdir ${SIMDIR}/${SIMULATION}

	printf "* Simulation %s\n" "${SIMULATION}"

	# Gunzip and copy the FCD file over
	FCDFILE=${SIMDIR}/${SIMULATION}/${SIMULATION}.fcd.xml
	cp -f ${GZFCDFILE} ${SIMDIR}/${SIMULATION}/
	gzip -d ${SIMDIR}/${SIMULATION}/${SIMULATION}.fcd.xml.gz

	# Copy the reference configuration file over
	CONFIGFILE=${SIMDIR}/${SIMULATION}/config.plist
	cp config.plist ${CONFIGFILE}

	# Edit 'floatingCarDataFile' and 'statsFolder' on the .plist
	./configPlistEditor ${CONFIGFILE} floatingCarDataFile ${FCDFILE}
	./configPlistEditor ${CONFIGFILE} stats.statsFolder ${SIMDIR}/${SIMULATION}/stats

	# Set 'gis.database' to the first database
	./configPlistEditor ${CONFIGFILE} gis.database gisdb1 #gisdb${FREEID}

	# Simulate
	./gissumo_fast ${CONFIGFILE} > ${SIMDIR}/${SIMULATION}/gissumo.log 2>&1

	# Remove the copied FCD file
	rm -rf ${FCDFILE}
done

# Clean up
rm -rf gissumo_fast configPlistEditor