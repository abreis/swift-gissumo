#!/bin/bash
# This script sets up a superuser account and starts the PostgreSQL server.
set -e

# Load usernames, passwords, file locations from file 'vars'
. scripts/vars

# Set up the main user, password
su - postgres -c "${SQLBIN} --single --config-file=${SQLCONF}" <<< "CREATE USER ${SQLUSER} WITH SUPERUSER;"
su - postgres -c "${SQLBIN} --single --config-file=${SQLCONF}" <<< "ALTER USER ${SQLUSER} WITH PASSWORD '${SQLPASS}';"

# Create 8 databases for parallel processing
for DBNUM in $(seq 0 7); do
	su - postgres -c "${SQLBIN} --single --config-file=${SQLCONF}" <<< "CREATE DATABASE ${SQLDB}${DBNUM} OWNER ${SQLUSER} TEMPLATE DEFAULT;"
done

if [ -f scripts/pg_hba.conf ]; then
	# Edit configuration to allow connections on any interface 
	sed -i "s/#listen_addresses.*/listen_addresses = '*'\n&/" ${SQLCONF}

	# Load custom Host-Based Authentication file
	cp scripts/pg_hba.conf ${SQLHBA}
fi

# Start the server in the background
nohup su - postgres -c "${SQLBIN} --config-file=${SQLCONF}" > postgres.log &
