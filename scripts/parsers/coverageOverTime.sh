#!/bin/bash
# This script plots the metrics on cityCoverageEvolution. The number of cells covered at each specific coverage strength is binned and then plotted in stacked column bars.

set -e

BINNING=50	# Interval (in seconds) to group decisions
SIMDIR=simulations
STATDIR=stats
VISDIR=plots
VISNAME=covOverTime

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
for SIMULATIONLOG in $(find ${SIMDIR} -depth 3 -type f -name 'cityCoverageEvolution.log'); do
	printf "${SIMULATIONLOG}\n" >> statfilelist
done

# Call swift interpreter
swift $(dirname $0)/binCoverageEvolution.swift statfilelist ${BINNING} > ${VISDIR}/${VISNAME}.data
rm -rf statfilelist

# Copy over gnuplot scaffold script
cp $(dirname $0)/${VISNAME}.gnuplot ${VISDIR}/

# Update file name locations ('dir/datafile.name', 'dir/outfile.eps')
sed -i '' 's|dir/datafile.name|'${VISDIR}'/'${VISNAME}'.data|g' ${VISDIR}/${VISNAME}.gnuplot
sed -i '' 's|dir/outfile.eps|'${VISDIR}'/'${VISNAME}'.eps|g' ${VISDIR}/${VISNAME}.gnuplot

# Plot it
gnuplot ${VISDIR}/${VISNAME}.gnuplot
epstopdf ${VISDIR}/${VISNAME}.eps
