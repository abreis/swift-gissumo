#!/bin/bash
# This script sets up a superuser account and starts the PostgreSQL server.

# Load usernames, passwords, file locations from file 'vars'
. vars

# Set up the main user, password and database
su - postgres -c "${SQLBIN} --single --config-file=${SQLCONF}" <<< "CREATE USER ${SQLUSER} WITH SUPERUSER;"
su - postgres -c "${SQLBIN} --single --config-file=${SQLCONF}" <<< "ALTER USER ${SQLUSER} WITH PASSWORD '${SQLPASS}';"
su - postgres -c "${SQLBIN} --single --config-file=${SQLCONF}" <<< "CREATE DATABASE ${SQLDB} OWNER ${SQLUSER} TEMPLATE DEFAULT;"

# Edit configuration to allow connections on any interface 
sed -i "s/#listen_addresses.*/listen_addresses = '*'\n&/" postgresql.conf

# Start the server in the background
nohup su - postgres -c "${SQLBIN} --config-file=${SQLCONF}" > postgres.log &
