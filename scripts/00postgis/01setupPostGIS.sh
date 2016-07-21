#!/bin/bash
# This script setups PostGIS extensions on the postgres database, converts a
# shapefile to SRID4326 (GPS WGS84), and loads it into the database

# Load usernames, passwords, file locations from file 'vars'
. vars
export PGPASSWORD=${SQLPASS}

# Enable PostGIS on the $SQLDB database
PSQLCOMMAND="psql --dbname=${SQLDB} -c "
${PSQLCOMMAND} "CREATE EXTENSION postgis;"
${PSQLCOMMAND} "CREATE EXTENSION postgis_topology;"
${PSQLCOMMAND} "CREATE EXTENSION fuzzystrmatch;"
${PSQLCOMMAND} "CREATE EXTENSION postgis_tiger_geocoder;"

# Convert the shapefile into a set of SQL commands suitable for importing
# into the SQL database
shp2pgsql -d -D -i -s 4326 -I ${SHAPEFILE} ${SQLTABLE} > data/buildings.sql

# Change the geometry field in PostGIS to accept all geometries, otherwise 
# adding POINTs will fail
${PSQLCOMMAND} "ALTER TABLE ${SQLTABLE} ALTER COLUMN geom TYPE geometry(Geometry,4326);"

# Load the shapefile data onto GIS
psql --dbname=${SQLDB} << data/buildings.sql
