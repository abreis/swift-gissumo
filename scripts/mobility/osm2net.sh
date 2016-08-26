#!/bin/bash
set -e

if [ "$#" -ne 2 ]; then 
	echo "Usage: $0 <osm file> <output net file>"
	exit 1
fi

OSMFILE=$1
NETFILE=$2

if [ -z "$SUMO_HOME" ]; then 
	echo "Error: Please set and export SUMO_HOME."
	exit 1
fi

TYPEMAPS=$SUMO_HOME/data/typemap
if [ ! -d "$TYPEMAPS" ]; then 
	echo "Error: SUMO typemaps folder not found."
	exit 1
fi

BASETYPEMAP=${TYPEMAPS}/osmNetconvert.typ.xml
URBANTYPEMAP=${TYPEMAPS}/osmNetconvertUrbanDe.typ.xml

# Convert the OSM map to a SUMO road network map
netconvert --osm-files ${OSMFILE} \
 --output-file ${NETFILE} \
 --type-files ${BASETYPEMAP},${URBANTYPEMAP} \
 --geometry.remove \
 --remove-edges.isolated \
 --roundabouts.guess \
 --ramps.guess \
 --junctions.join \
 --tls.guess-signals \
 --tls.discard-simple \
 --tls.join \
 --keep-edges.by-vclass passenger
