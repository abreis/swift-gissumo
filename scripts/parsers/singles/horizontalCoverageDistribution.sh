#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Error: Please specify a directory with simulations."
	exit 1
fi

STARTATTIME=0
if [[ "$2" =~ ^[0-9]+$ ]]; then 
	STARTATTIME=$2
else
	printf "\nWarning: No start time provided, assuming zero.\n\n"
fi

SIMDIR=$1
STATDIR=stats
VISDIR=plots
VISNAME=horizCovDist

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

find ${SIMDIR} -maxdepth 3 -type f -name 'cityCoverageEvolution.log' > statfilelist

# Call swift interpreter
swift $(dirname $0)/averageCoverageDistribution.swift statfilelist ${STARTATTIME} > ${VISDIR}/${VISNAME}.data
rm -rf statfilelist


# Copy over gnuplot scaffold script
cp $(dirname $0)/${VISNAME}.gnuplot ${VISDIR}/

# Update file name locations ('dir/datafile.name', 'dir/outfile.eps')
sed -i '' 's|dir/datafile.name|'${VISDIR}'/'${VISNAME}'.data|g' ${VISDIR}/${VISNAME}.gnuplot
sed -i '' 's|dir/outfile.eps|'${VISDIR}'/'${VISNAME}'.eps|g' ${VISDIR}/${VISNAME}.gnuplot

# Plot it
gnuplot ${VISDIR}/${VISNAME}.gnuplot
epstopdf ${VISDIR}/${VISNAME}.eps
pdfjam ${VISDIR}/${VISNAME}.pdf --quiet --angle '-90' --fitpaper 'true' --rotateoversize 'true' --outfile ${VISDIR}/${VISNAME}_horiz.pdf