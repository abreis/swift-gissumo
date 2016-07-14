#!/bin/bash
WORKDIR=/data

# This script pulls a square map from OpenStreetMap,
# and converts it into a SUMO-compatible format.
export SUMO_HOME=$( find /root/ -type d -name 'sumo-*' -print -quit )
if [ ! -d "$SUMO_HOME" ]; then echo "SUMO home folder not found."; exit 1; fi

TYPEMAPS=$SUMO_HOME/data/typemap
if [ ! -d "$TYPEMAPS" ]; then echo "SUMO typemaps folder not found."; exit 1; fi

# Porto Map #02 -- 1 sq.km. -- (41.1679,-8.6227),(41.1598,-8.6094)
LONMIN='-8.6227'
LONMAX='-8.6094'
LATMIN='41.1598'
LATMAX='41.1679'

# Fetch a map from OSM
curl -L -o ${WORKDIR}/map.osm.xml "http://overpass-api.de/api/map?bbox=${LONMIN},${LATMIN},${LONMAX},${LATMAX}"

# Assert XML validity
xmllint --noout ${WORKDIR}/map.osm.xml || { echo "Got an invalid XML file from OSM."; exit 1; }

# Convert the OSM map to a SUMO road network map
netconvert --osm-files ${WORKDIR}/map.osm.xml -o ${WORKDIR}/map.net.xml \
	--type-files ${TYPEMAPS}/osmNetconvert.typ.xml,${TYPEMAPS}/osmNetconvertUrbanDe.typ.xml \
	--geometry.remove \
	--remove-edges.isolated \
	--roundabouts.guess \
	--ramps.guess \
	--junctions.join \
	--tls.guess-signals \
	--tls.discard-simple \
	--tls.join

if [ $? -ne 0 ]; then echo "Map conversion failed."; exit 1; fi

