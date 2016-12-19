#!/bin/bash
# This script will run data parsers on simulation sets. Requires a LaTeX installation.

set -e

if [ -z "$1" ]; then
    echo "Error: Please specify a directory with simulation sets."
	exit 1
fi
SETDIR=$1

if [ -z "$2" ]; then
    echo "Error: Please specify a parser name."
	exit 1
fi
PARSER="$2"

for SIMSET in $(find ${SETDIR} -type d -depth 1); do
	printf "\nRunning parser on $(basename ${SIMSET}):\n"
	../parsers/${PARSER}.sh ${SIMSET} --overwrite
	find ${SIMSET} -type f -name "${PARSER}.pdf" -exec cp {} ${SETDIR}/${PARSER}_$(basename ${SIMSET}).pdf \;
done
