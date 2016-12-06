#!/bin/bash
# This script runs statistics in decisionCellCoverageEffects. For every decision, the intermediate metrics are weighted by the corresponding coefficients, and we output a stacked bar plot of grouped decisions.

set -e

BINNING=50	# Interval (in seconds) to group decisions
SIMDIR=simulations
STATDIR=stats
VISDIR=plots
VISNAME=binAllDec

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
for SIMULATIONLOG in $(find ${SIMDIR} -depth 3 -type f -name 'decisionCellCoverageEffects.log'); do
	printf "${SIMULATIONLOG}\n" >> statfilelist
done

# Call swift interpreter
swift $(dirname $0)/binAndWeighAllDecisions.swift statfilelist ${BINNING} > ${VISDIR}/${VISNAME}.data
rm -rf statfilelist

# Copy over gnuplot scaffold script
cp $(dirname $0)/${VISNAME}.gnuplot ${VISDIR}/

# Update file name locations ('dir/datafile.name', 'dir/outfile.eps')
sed -i '' 's|dir/datafile.name|'${VISDIR}'/'${VISNAME}'.data|g' ${VISDIR}/${VISNAME}.gnuplot
sed -i '' 's|dir/outfile.eps|'${VISDIR}'/'${VISNAME}'.eps|g' ${VISDIR}/${VISNAME}.gnuplot

# Plot it
gnuplot ${VISDIR}/${VISNAME}.gnuplot
epstopdf ${VISDIR}/${VISNAME}.eps
