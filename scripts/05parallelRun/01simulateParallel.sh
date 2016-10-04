#!/bin/bash
set -e

MAXTHREADS=4

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
TOTALSIMS=${FCDCOUNT}


WORKERSTATUS=()
for SUBID in $(seq 0 $(expr ${MAXTHREADS} - 1)); do
	WORKERSTATUS[$SUBID]="none"
done
echo "${WORKERSTATUS[@]}" > /tmp/gissumoworkerstatus



## ROUTINES
findnextfreeid(){
	read -r -a WORKERSTATUS < /tmp/gissumoworkerstatus
	for SUBID in $(seq 0 $(expr ${MAXTHREADS} - 1)); do
		if [ "${WORKERSTATUS[$SUBID]}" != "working" ]; then
			FREEID=$SUBID
			return
		fi
	done
	FREEID=-1
}



subsimulation(){
	SUBSIMID=$FREEID
	#printf "Worker ${SUBSIMID} is starting.\n"

	# Update worker status
	read -r -a WORKERSTATUS < /tmp/gissumoworkerstatus
	WORKERSTATUS[$SUBSIMID]="working"; echo "${WORKERSTATUS[@]}" > /tmp/gissumoworkerstatus

	# Create the base simulation directory
	SIMULATION=$(basename ${GZFCDFILE} .fcd.xml.gz)
	mkdir ${SIMDIR}/${SIMULATION}

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

	# Set 'gis.database' to match the free worker id
	./configPlistEditor ${CONFIGFILE} gis.database gisdb${FREEID}

	# Simulate
	./gissumo_fast ${CONFIGFILE} > ${SIMDIR}/${SIMULATION}/gissumo.log 2>&1

	# Remove the copied FCD file
	rm -rf ${FCDFILE}

	# Update worker status
	read -r -a WORKERSTATUS < /tmp/gissumoworkerstatus
	WORKERSTATUS[$SUBSIMID]="done"; echo "${WORKERSTATUS[@]}" > /tmp/gissumoworkerstatus

	# Update completed simulation count
	read -r -a SIMULATIONS < /tmp/gissumosimulations
	let SIMULATIONS+=1; echo "${SIMULATIONS}" > /tmp/gissumosimulations
}



checkworkercount(){
	WORKERS=0
	read -r -a WORKERSTATUS < /tmp/gissumoworkerstatus
	for SUBID in $(seq 0 $(expr ${MAXTHREADS} - 1)); do
		if [ "${WORKERSTATUS[$SUBID]}" == "working" ]; then let WORKERS+=1; fi
	done
}



## MAIN LOOP
SECONDS=0
SIMULATIONS=0; echo "${SIMULATIONS}" > /tmp/gissumosimulations
for GZFCDFILE in $(find -L ${FCDDIR} -type f -iname '*.fcd.xml.gz'); do
	# Wait for available workers
	sleep 1
	checkworkercount
	while [ $WORKERS -ge $MAXTHREADS ]; do
		sleep 1
		checkworkercount
	done

	# Find a free worker (and database)
	findnextfreeid
	if [ $FREEID -lt 0 ]; then echo "Error, no free workers found."; exit 1; fi

	# Launch a simulation in the background
	subsimulation &

	# Print some statistics
	read -r -a SIMULATIONS < /tmp/gissumosimulations
	if [ $SIMULATIONS -gt 0 ]; then
		SECONDSPERSIM=$(expr $SECONDS / $SIMULATIONS)
		SIMSREMAINING=$(expr $TOTALSIMS - $SIMULATIONS)
		ESTTIMEREMAINING=$(expr $SECONDSPERSIM \* $SIMSREMAINING)
		printf "%d/%d simulations complete, ETA %dh%02dm%02ds\n" "${SIMULATIONS}" "${TOTALSIMS}" $((${ESTTIMEREMAINING}/3600)) $((${ESTTIMEREMAINING}%3600/60)) $((${ESTTIMEREMAINING}%60))
	fi
done

# Clean up
rm -rf gissumo_fast configPlistEditor /tmp/gissumoworkerstatus /tmp/gissumosimulations