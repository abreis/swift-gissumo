#!/bin/bash

mkdir -p /work/fcddata

while [ 1 ]; do
	printf "\n=== NEW RUN AT $(date "+%Y%m%d%H%M%S") ===\n"
	sumo \
		--remote-port 8813 \
		--net-file /work/map.net.xml \
		--step-length 1.0 \
		--device.rerouting.probability 1 \
		--fcd-output.geo \
		--fcd-output /work/fcddata/fcd.$(date "+%Y%m%d%H%M%S").xml \
		--verbose \
		2>&1
	sleep 1
done
