#!/bin/bash
set -e

STARTATTIME=0
if [[ "$1" =~ ^[0-9]+$ ]]; then 
	STARTATTIME=$1
else
	printf "\nWarning: No start time provided, assuming zero.\n\n"
fi

for SIMSET in $(find simulationsets -depth 1 -type d -name 'simulations*'); do
	find ${SIMSET} -type f -name 'signalAndSaturationEvolution.log' > statfilelist
	printf "${SIMSET}\n"
	swift $(dirname $0)/averageColumn.swift statfilelist meanSat ${STARTATTIME}
	printf "\n"
done
rm statfilelist