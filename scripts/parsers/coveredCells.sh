#!/bin/bash
# This script plots the percentage of covered cells from cityCoverageEvolution. 

set -e

if [ -z "$1" ]; then
    echo "Error: Please specify a directory with simulations."
	exit 1
fi

if [ -z "$2" ] || [ "$2" != "full" -a "$2" != "half" ]; then
    echo "Error: Please specify 'half' or 'full' for desired plot width."
	exit 1
fi

if [ "$2" = "full" ]; then
	GNUPLOTWIDTH="1.4"
else
	GNUPLOTWIDTH="0.7"
fi

SIMDIR=$1
STATDIR=stats
VISDIR=plots
VISNAME=covCell

# Ensure we're working with gnuplot version 5
if [[ ! $(gnuplot --version) =~ "gnuplot 5" ]]; then
	echo "Error: gnuplot version 5 is required."
	exit 1
fi

# Plotting directory
VISDIR=${SIMDIR}/${VISDIR}/${VISNAME}
if [ -d ${VISDIR} ]; then
	echo "Folder with previous plots exists, move it before proceeding."
	exit 1
fi
mkdir -p ${VISDIR}

touch statfilelist
for SIMULATIONLOG in $(find ${SIMDIR} -maxdepth 3 -type f -name 'cityCoverageEvolution.log'); do
	printf "${SIMULATIONLOG}\n" >> statfilelist
done

# Call swift interpreter
swift $(dirname $0)/analyzeColumnByTime.swift statfilelist "%covered" > ${VISDIR}/${VISNAME}.data
rm -rf statfilelist

# Copy over gnuplot scaffold script
cp $(dirname $0)/${VISNAME}.gnuplot ${VISDIR}/

# Update file name locations ('dir/datafile.name', 'dir/outfile.eps')
sed -i '' 's|dir/datafile.name|'${VISDIR}'/'${VISNAME}'.data|g' ${VISDIR}/${VISNAME}.gnuplot
sed -i '' 's|dir/outfile.eps|'${VISDIR}'/'${VISNAME}'.eps|g' ${VISDIR}/${VISNAME}.gnuplot

# Plot it
gnuplot -e "argwidth=${GNUPLOTWIDTH}" ${VISDIR}/${VISNAME}.gnuplot
epstopdf ${VISDIR}/${VISNAME}.eps
