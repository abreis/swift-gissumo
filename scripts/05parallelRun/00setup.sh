#!/bin/bash
set -e

# Parameters
OSMFILE=/work/map.osm.xml
STOPTIME=1200
PERIOD=2
INITIALSEED=31337
ROUNDS=100

# Delete SETUPCOMPLETE to enable the script and regenerate data
if [ -f SETUPCOMPLETE ]; then exit 0; fi

# OSM map must be provided
if [ ! -f ${OSMFILE} ]; then echo "Missing OSM file."; exit 1; fi

# Copy scripts folder
[ ! -d mobility ] || rm -rf mobility
cp -r ../mobility .

# Set SUMO_HOME
export SUMO_HOME=$( find /root/ -type d -name 'sumo-*' -print -quit )
if [ ! -d "$SUMO_HOME" ]; then echo "SUMO home folder not found." ; exit 1; fi

# Create dir to hold mobility data
[ -d fcddata ] || mkdir -p fcddata

# Generate 100 Floating Car Data files
printf "Generating... "
for COUNT in $(seq 1 ${ROUNDS}); do
	printf "${COUNT} "
	SEED=$(expr $INITIALSEED + $COUNT)
	./mobility/osm5fcd.sh $OSMFILE $STOPTIME $PERIOD $SEED
done
echo "done"

# Compress the FCD
gzip --best mobilitydata/*.fcd.xml
# Store it
mv mobilitydata/*.fcd.xml.gz fcddata/
# Clean up
rm -rf mobilitydata mobility

touch SETUPCOMPLETE
