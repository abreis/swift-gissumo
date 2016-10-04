#!/bin/bash
# This script goes through every directory in scripts/, runs the scripts 
# inside, and shows each script's error code.

SCRIPTDIR='scripts'

unset REPLY
echo ''
for SCRIPTGROUP in $( find ${SCRIPTDIR} -maxdepth 1 -type d ! -path ${SCRIPTDIR} | sed 's!.*/!!' | sort ); do

	while [ -z $REPLY ]; do
		read -p "Run ${SCRIPTGROUP}? [y/N] " 
	done

	if [[ $REPLY =~ ^[Yy]$ ]]; then
		for SCRIPT in $( find ${SCRIPTDIR}/${SCRIPTGROUP} -type f -iname '*.sh' | sed 's!.*/!!' | sort ); do
			echo -e -n "\t $(basename ${SCRIPT} .sh ) ... \t"
			echo -e "\n### Script ${SCRIPTDIR}/${SCRIPTGROUP}/${SCRIPT} at $(date) ###" >> main.log
			${SCRIPTDIR}/${SCRIPTGROUP}/${SCRIPT} >> main.log 2>&1
			if [ $? -eq 0 ]; then echo "[ok]"; else echo "[!!]"; fi
			sleep 1
		done
		echo ''
	fi

	unset REPLY
done
