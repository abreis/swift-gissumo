#!/bin/bash

set -e

DESTDIR="/Users/abreis/Desktop/20170224-workingDocument/plots/H0_lifetimeHistograms"

for SIMDIR in simulationsets/simulations_wbat_*; do
	cd ${SIMDIR}/plots/rsuLife
	rm rsuLifeCompact.*
	gnuplot ../../../../../parsers/singles/rsuLifeCompact.gnuplot
	epstopdf rsuLifeCompact.eps
	DESTNAME=$(basename ${SIMDIR})
	DESTNAME=${DESTNAME//.}
	DESTNAME=${DESTNAME//_}
	DESTNAME=${DESTNAME::${#DESTNAME}-4}
	DESTNAME=${DESTNAME:11}
	cp rsuLifeCompact.pdf ${DESTDIR}/${DESTNAME}.pdf
	cd -
done

