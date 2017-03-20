#!/bin/bash
set -e

# Parameters
OSMFILE=/work/map.osm.xml
FCDDATADIR=fcddata
STOPTIME=1200
PERIOD=2
INITIALSEED=31337
ROUNDS=100

# Check for previous plotfolders and offer to wipe them
if [ -d ${FCDDATADIR} ]; then
	if [ "$1" = "--overwrite" ]; then
		echo "Erasing existing Floating Car Data..."
		rm -rf ${FCDDATADIR}
	else
		echo "Error: A folder with Floating Car Data exists."
		echo "Add '--overwrite' to erase it."
		exit 1
	fi
fi

# OSM map must be provided
if [ ! -f ${OSMFILE} ]; then echo "Missing OSM file."; exit 1; fi

# Copy scripts folder
[ ! -d mobility ] || rm -rf mobility
cp -r ../mobility .

# Set SUMO_HOME
export SUMO_HOME=$( find /root/ -type d -name 'sumo-*' -print -quit )
if [ ! -d "$SUMO_HOME" ]; then echo "SUMO home folder not found." ; exit 1; fi

# Create dir to hold mobility data
[ -d ${FCDDATADIR} ] || mkdir -p ${FCDDATADIR}

# Generate Floating Car Data files
printf "Generating... "
for COUNT in $(seq 1 ${ROUNDS}); do
	printf "${COUNT} "
	SEED=$(expr $INITIALSEED + $COUNT)
	./mobility/osm5fcd.sh $OSMFILE $STOPTIME $PERIOD $SEED
done
echo "done"

printf "Compressing... "
# Compress the FCD
gzip --best mobilitydata/*.fcd.xml
# Store it
mv mobilitydata/*.fcd.xml.gz ${FCDDATADIR}/
# Clean up
rm -rf mobilitydata mobility
echo "done"
