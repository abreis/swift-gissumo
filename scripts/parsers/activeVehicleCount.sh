#!/bin/bash
# This script runs statistics on the 'count' entries in activeVehicleCount, then plots a line chart of the average number of active vehicles on each time step.

set -e

SIMDIR=simulations
STATDIR=stats
VISDIR=plots
VISNAME=actVehCnt

# Ensure we're working with gnuplot version 5
if [[ ! $(gnuplot --version) =~ "gnuplot 5" ]]; then
	echo "Error: gnuplot version 5 is required."
	exit 1
fi

# Plotting directory
VISDIR=${VISDIR}/${VISNAME}
if [ -d ${VISDIR} ]; then
	echo "Folder with previous plots exists, move it before proceeding."
	exit 1
fi
mkdir -p ${VISDIR}

touch statfilelist
for SIMULATION in $(find ${SIMDIR} -maxdepth 1 -type d ! -path ${SIMDIR}); do
	printf "${SIMULATION}/stats/activeVehicleCount.log\n" >> statfilelist
done

# Call swift interpreter
swift $(dirname $0)/analyzeColumnByTime.swift statfilelist count > ${VISDIR}/${VISNAME}.data
rm -rf statfilelist

# Copy over gnuplot scaffold script
cp $(dirname $0)/${VISNAME}.gnuplot ${VISDIR}/

# Update file name locations ('dir/datafile.name', 'dir/outfile.eps')
sed -i '' 's|dir/datafile.name|'${VISDIR}'/'${VISNAME}'.data|g' ${VISDIR}/${VISNAME}.gnuplot
sed -i '' 's|dir/outfile.eps|'${VISDIR}'/'${VISNAME}'.eps|g' ${VISDIR}/${VISNAME}.gnuplot

# Plot it
gnuplot ${VISDIR}/${VISNAME}.gnuplot
epstopdf ${VISDIR}/${VISNAME}.eps
