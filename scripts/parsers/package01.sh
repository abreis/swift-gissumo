#!/bin/bash

## PARSER PACKAGE 01 ##
#
# This package will grab the following plots from the data:
#
# - activeVehicleCount
# - activeRoadsideUnitCount
# - signalCoverageDistributionHistogram
# - rsuRedundancyDistributionHistogram
# - coverageOverTime
# - binAllDecisions
# - binPositiveDecisions
# - binAndCountDecisions
#
# Run from the location where the 'simulations' folder is present.

set -e

if [ -z "$1" ]; then
    echo "Error: Please specify a directory with simulations."
	exit 1
fi
SIMDIR=$1
VISDIR=plots
SIMDESCR=description.txt
SCRIPTDIR=$(dirname $0)
PACKAGENAME=package01
TEXSUBDIR=tex
PACKAGEDIR=${SIMDIR}/${VISDIR}/${PACKAGENAME}
LOGFILE=${PACKAGEDIR}/${PACKAGENAME}.log

declare -a PARSERS=(
"activeVehicleCount"
"activeRoadsideUnitCount"
"signalCoverageDistributionHistogram"
"rsuRedundancyDistributionHistogram"
"coverageOverTime"
"binAllDecisions"
"binPositiveDecisions"
"binAndCountDecisions"
)

# Check for the presence of a simulation folder
if [ ! -d ${SIMDIR} ]; then
	echo "Error: Simulations folder not present."
	exit 1
fi

# Ensure we're working with pdflatex version 3
if [[ ! $(pdflatex --version) =~ "pdfTeX 3" ]]; then
	echo "Error: pdflatex version 3 is required."
	exit 1
fi

# Check for previous plotfolders and offer to wipe them
PLOTFOLDERS=$(find ${SIMDIR} -type d -name ${VISDIR} | wc -l | tr -d ' ')
if [ ${PLOTFOLDERS} -ne 0 ]; then
	if [ "$2" = "--overwrite" ]; then
		echo "Erasing existing visualization folders..."
		find ${SIMDIR} -type d -name ${VISDIR} -exec rm -rf {} +
	else
		echo "Error: A folder with previous plots exists."
		echo "Add '--overwrite' as the second argument to erase it."
		exit 1
	fi
fi

# Plotting directory
if [ -d ${PACKAGEDIR} ]; then
	echo "Folder with previous plots exists, move it before proceeding."
	exit 1
fi
mkdir -p ${PACKAGEDIR}


# Run this package's parsers
printf "Running parsers..."
for PARSER in "${PARSERS[@]}"
do
	printf "\n\t* ${PARSER} "
	printf "\n### Running ${SCRIPTDIR}/${PARSER}.sh\n" >> ${LOGFILE}
	${SCRIPTDIR}/${PARSER}.sh ${SIMDIR} >> ${LOGFILE} 2>&1
done
printf "\n"


printf "Gathering plots..."
# Create TeX dir and figures subdir, 1-shot
mkdir -p ${PACKAGEDIR}/${TEXSUBDIR}/figures

# Gather generated plots
printf "\n### Moving plot PDF files\n" >> ${LOGFILE}
find ${SIMDIR}/${VISDIR} -not \( -path ${PACKAGEDIR} -prune \) -type f -iname '*.pdf' -exec cp {} ${PACKAGEDIR}/${TEXSUBDIR}/figures/ \; >> ${LOGFILE} 2>&1

# Copy TeX scaffold over
cp ${SCRIPTDIR}/${PACKAGENAME}.tex ${PACKAGEDIR}/${TEXSUBDIR}

# Copy simulation description, if present
if [ -f ${SIMDIR}/${SIMDESCR} ]; then
	cp -f ${SIMDIR}/${SIMDESCR} ${PACKAGEDIR}/${TEXSUBDIR}
fi

# Compile TeX
printf "\n### Running pdflatex\n" >> ${LOGFILE}
( cd ${PACKAGEDIR}/${TEXSUBDIR} ; pdflatex -interaction=nonstopmode -file-line-error -recorder ${PACKAGENAME}.tex ) >> ${LOGFILE} 2>&1

printf "\nDone.\n"

