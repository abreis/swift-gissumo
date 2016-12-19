#!/usr/bin/env python3
# This script will run simulation sets modifying the decision.triggerDelay parameter. The number of simulations per set is defined separately in 01simulateParallel.

import os
import plistlib
import shutil
import subprocess
import sys

# Requires Python >3.5
assert sys.version_info >= (3,5)

simulationDir = "simulations"
simulationSetDir = "simulationsets"
simulationDescription="description.txt"

# triggerDelay variables to evaluate
triggerDelays = [50, 100, 150, 200, 250, 300]


if os.path.isdir(simulationSetDir):
	if "--overwrite" in sys.argv:
		shutil.rmtree(simulationSetDir)
	else:
		print("Error: Folder with previous simulation sets exists, move it before proceeding.")
		print("Specify --overwrite on the command line to clear folder.")
		sys.exit(1)

if not os.path.isfile('config.template.plist'):
	print("Error: Please provide a reference configuration file.")
	sys.exit(1)


# Create the simulation set directory
os.makedirs(simulationSetDir, exist_ok=True)


# Iterate
for triggerDelay in triggerDelays:
	displayString = "\nEvaluating triggerDelay = {:d}".format(triggerDelay)
	print(displayString)
	print('-'*len(displayString), flush=True)

	# Erase any previous configuration file and create a new one from the template
	shutil.copyfile('config.template.plist', 'config.plist')

	# Set the triggerDelay in the configuration file
	with open('config.plist', 'rb') as configFileHandle:
		configFileDict = plistlib.load(configFileHandle, fmt=plistlib.FMT_XML)
		configFileDict['decision']['triggerDelay'] = triggerDelay
	with open('config.plist', 'wb') as configFileHandle:
		plistlib.dump(configFileDict, configFileHandle, fmt=plistlib.FMT_XML)

	# Run parallel simulations with 01parallelSimulate
	process = subprocess.Popen(['./01simulateParallel.py', '--overwrite'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
	
	# Show subprocess output
	for line in iter(process.stdout.readline, b''):
		sys.stdout.buffer.write(line)
		sys.stdout.flush()

	# Add details of the simulation set to the description
	descriptionFile = os.path.join(simulationDir, simulationDescription)
	if(os.path.isfile(descriptionFile)):
		descriptionFp = open(descriptionFile, 'a')
	else:
		descriptionFp = open(descriptionFile, 'w')
	descriptionFp.write("triggerDelay: {:d}\n".format(triggerDelay))
	descriptionFp.close()

	# Store simulation set and cleanup
	shutil.move(simulationDir, os.path.join(simulationSetDir, "{:s}_triggerDelay_{:d}".format(simulationDir, triggerDelay)))
	os.remove('config.plist')
