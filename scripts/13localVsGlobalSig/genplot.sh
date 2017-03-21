#!/bin/bash
set -e

# Ensure we're working with gnuplot version 5
if [[ ! $(gnuplot --version) =~ "gnuplot 5" ]]; then
	echo "Error: gnuplot version 5 is required."
	exit 1
fi

printf "Processing local decision data... "
find simulations* -iname 'movingAverageWPM.log' > filelistLocalSig
swift ../parsers/analyzeColumnByTime.swift filelistLocalSig meanSigEMA > sigLocalEMA.data
printf "done\n"

printf "Processing citywide data... "
find simulations* -iname 'signalAndSaturationEvolution.log' > filelistGlobalSig
swift ../parsers/analyzeColumnByTime.swift filelistGlobalSig meanSig > sigGlobal.data
printf "done\n"


printf "Generating plot... "
gnuplot localSigVsGlobalSig.gnuplot
epstopdf localSigVsGlobalSig.eps
printf "done\n"

rm -rf localSigVsGlobalSig.eps filelistLocalSig filelistGlobalSig sigLocalEMA.data sigGlobal.data
