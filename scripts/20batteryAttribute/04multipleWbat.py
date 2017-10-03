#!/usr/bin/env python3
# This script will run simulation sets modifying the decision.algorithm.WeightedProductModel.wbat parameter. The number of simulations per set is defined separately in 01simulateParallel.

import os
import plistlib
import shutil
import subprocess
import sys
import datetime

# Requires Python >3.5
assert sys.version_info >= (3,5)

simulationDir="simulations"
simulationSetDir="simulationsets"
simulationDescription="description.txt"
descriptionTemplate="description.template"

# abat values to evaluate
#weightAbats = [0.1, 0.3, 0.5, 1.0]
weightAbats = [1.5]


if os.path.isdir(simulationSetDir):
	if "--overwrite" in sys.argv:
		shutil.rmtree(simulationSetDir)
	elif "--append" in sys.argv:
		pass
	else:
		print("Error: Folder with previous simulation sets exists, move it before proceeding.")
		print("Specify --overwrite on the command line to clear folder.")
		print("Specify --append to use the existing folder.")
		sys.exit(1)

if not os.path.isfile('config.template.plist'):
	print("Error: Please provide a reference configuration file.")
	sys.exit(1)

if not os.path.isfile('01simulateParallel.py'):
	print("Error: Please link '01simulateParallel.py'.")
	sys.exit(1)

# Create the simulation set directory
os.makedirs(simulationSetDir, exist_ok=True)


# Iterate
print(datetime.datetime.now().date())
for weightAbat in weightAbats:
	displayString = "\n{:s}  Evaluating wbat = {:f}".format(str(datetime.datetime.now().time()), weightAbat)
	print(displayString)
	print('-'*len(displayString), flush=True)

	# Erase any previous configuration file and create a new one from the template
	shutil.copyfile('config.template.plist', 'config.plist')

	# Set the triggerDelay in the configuration file
	with open('config.plist', 'rb') as configFileHandle:
		configFileDict = plistlib.load(configFileHandle, fmt=plistlib.FMT_XML)
		configFileDict['decision']['algorithm']['WeightedProductModel']['wbat'] = weightAbat
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
	subprocess.check_output("./descriptionGenerator.py -t {:s} -c config.plist >> {:s} ".format(descriptionTemplate, descriptionFile), shell=True)

	# Store simulation set and cleanup
	shutil.move(simulationDir, os.path.join(simulationSetDir, "{:s}_wbat_{:f}".format(simulationDir, weightAbat)))
	os.remove('config.plist')
