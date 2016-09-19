#!/bin/bash
# This script concatenates the 'samples' entries in finalCityCoverageStats, then plots a histogram of all the data points (which is effectively the mean distribution -- all simulations with the same obstructionMask will report the same number of cells, and binning will even data out).

set -e

SIMDIR=simulations
STATDIR=stats
VISDIR=plots
SUBVISDIR=sigCovDistHist

# Ensure we're working with gnuplot version 5
if [[ ! $(gnuplot --version) =~ "gnuplot 5" ]]; then
	echo "Error: gnuplot version 5 is required."
	exit 1
fi

# Plotting directory
VISDIR=${VISDIR}/${SUBVISDIR}
if [ -d ${VISDIR} ]; then
	echo "Folder with previous plots exists, move it before proceeding."
	exit 1
fi
mkdir -p ${VISDIR}

# Aggregate data
COMPLETESAMPLES=""
for SIMULATION in $(find ${SIMDIR} -maxdepth 1 -type d ! -path ${SIMDIR}); do
	SAMPLES=$(cat ${SIMULATION}/${STATDIR}/finalCityCoverageStats.log | grep samples)
	SAMPLES=${SAMPLES#"samples	["}	# Remove prefix (there's a \t here)
	SAMPLES=${SAMPLES%"]"}			# Remove suffix
	COMPLETESAMPLES+=${SAMPLES}
	COMPLETESAMPLES+=", "
done
COMPLETESAMPLES=${COMPLETESAMPLES%", "}	# Trim the leading comma
printf "${COMPLETESAMPLES}\n" > ${VISDIR}/sigCovDistHist.col.data

# Row to column
tr -s ", " "\n" < ${VISDIR}/sigCovDistHist.col.data > ${VISDIR}/sigCovDistHist.data

# Copy over gnuplot scaffold script
cp $(dirname $0)/sigCovDistHist.gnuplot ${VISDIR}/

# Update file name locations ('dir/datafile.name', 'dir/outfile.eps')
sed -i '' 's|dir/datafile.name|'${VISDIR}'/sigCovDistHist.data|g' ${VISDIR}/sigCovDistHist.gnuplot
sed -i '' 's|dir/outfile.eps|'${VISDIR}'/sigCovDistHist.eps|g' ${VISDIR}/sigCovDistHist.gnuplot

# Plot it
gnuplot ${VISDIR}/sigCovDistHist.gnuplot
