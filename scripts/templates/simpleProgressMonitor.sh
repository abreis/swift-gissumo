#!/bin/bash

INTERVAL=1.0
if [ -n "$1" ]; then
	INTERVAL=$1
fi

/usr/local/bin/watch -n ${INTERVAL} -- /usr/bin/find . -type f -name 'simulationTime.log' -exec /usr/bin/tail -n 1 {} +
