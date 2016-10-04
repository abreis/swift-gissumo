#!/bin/bash
# This script setups PostGIS extensions on the postgres database, converts a
# shapefile to SRID4326 (GPS WGS84), and loads it into the database
set -e

# Load usernames, passwords, file locations from file 'vars'
. scripts/vars
export PGPASSWORD=${SQLPASS}

# Convert the shapefile into a set of SQL commands suitable for importing
# into the SQL database
shp2pgsql -d -D -i -s 4326 -I ${SHAPEFILE} ${SQLTABLE} > data/buildings.sql

for DBNUM in $(seq 0 7); do
	PSQLCOMMAND="psql --dbname=${SQLDB}${DBNUM} -c "

	# Enable PostGIS on the $SQLDB database
	${PSQLCOMMAND} "CREATE EXTENSION postgis;"
	${PSQLCOMMAND} "CREATE EXTENSION postgis_topology;"
	${PSQLCOMMAND} "CREATE EXTENSION fuzzystrmatch;"
	${PSQLCOMMAND} "CREATE EXTENSION postgis_tiger_geocoder;"

	# Load the shapefile data onto GIS
	psql --dbname=${SQLDB}${DBNUM} < data/buildings.sql

	# Change the geometry field in PostGIS to accept all geometries, otherwise adding POINTs will fail
	${PSQLCOMMAND} "ALTER TABLE ${SQLTABLE} ALTER COLUMN geom TYPE geometry(Geometry,4326);"
done
