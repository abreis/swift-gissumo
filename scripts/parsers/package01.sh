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

SIMDIR=simulations
VISBASEDIR=plots
SCRIPTDIR=$(dirname $0)
PACKAGENAME=package01
TEXSUBDIR=tex
PACKAGEDIR=${VISBASEDIR}/${PACKAGENAME}
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


# Plotting directory
if [ -d ${PACKAGEDIR} ]; then
	echo "Folder with previous plots exists, move it before proceeding."
	exit 1
fi
mkdir -p ${PACKAGEDIR}


# Run this package's parsers
printf "Running parsers: "
for PARSER in "${PARSERS[@]}"
do
	printf "${PARSER} "
	printf "\n### Running ${SCRIPTDIR}/${PARSER}.sh\n" >> ${LOGFILE}
	${SCRIPTDIR}/${PARSER}.sh >> ${LOGFILE} 2>&1
done
printf "\n"


printf "Gathering plots..."
# Create TeX dir and figures subdir, 1-shot
mkdir -p ${PACKAGEDIR}/${TEXSUBDIR}/figures

# Gather generated plots
printf "\n### Moving plot PDF files\n" >> ${LOGFILE}
find ${VISBASEDIR} -not \( -path ${PACKAGEDIR} -prune \) -type f -iname '*.pdf' -exec cp {} ${PACKAGEDIR}/${TEXSUBDIR}/figures/ \; >> ${LOGFILE} 2>&1

# Copy TeX scaffold over
cp ${SCRIPTDIR}/${PACKAGENAME}.tex ${PACKAGEDIR}/${TEXSUBDIR}

# Compile TeX
printf "\n### Running pdflatex\n" >> ${LOGFILE}
( cd ${PACKAGEDIR}/${TEXSUBDIR} ; pdflatex -interaction=nonstopmode -file-line-error -recorder ${PACKAGENAME}.tex ) >> ${LOGFILE} 2>&1

printf "\n"

