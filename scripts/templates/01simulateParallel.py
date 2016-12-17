#!/usr/bin/env python3

import gzip
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time

# Requires Python >3.5
assert sys.version_info >= (3,5), "This requires at least, Python 3.5"


maxThreads = 4
simulationDir = "simulations"
simulationDescription="description.txt"
floatingCarDataDir = "fcddata"


if not os.path.isdir(floatingCarDataDir):
	print("Error: No floating car data directory.")
	sys.exit(1)

if os.path.isdir(simulationDir):
	if "--overwrite" in sys.argv:
		shutil.rmtree(simulationDir)
	else:
		print("Error: Folder with previous simulations exists, move it before proceeding.")
		print("Specify --overwrite on the command line to clear folder.")
		sys.exit(1)

if not os.path.isfile('config.plist'):
	print("Error: Please provide a reference configuration file.")
	sys.exit(1)

if not os.path.isfile('obstructionMask.payload'):
	print("Error: Please generate and provide an obstruction mask file.")
	sys.exit(1)


# Pull the latest binary
shutil.copy('../../build/gissumo_fast','./')

# Create the simulation directory
os.makedirs(simulationDir, exist_ok=True)


# Count the number of floating car data files
fcdFiles = []
for dirpath, dirnames, filenames in os.walk(floatingCarDataDir):
	for file in filenames:
		if file.endswith('fcd.xml.gz'):
			fcdFiles.append( os.path.join(dirpath, file) )


# Worker array: each worker can be 'free' or 'busy'
workers = ['free'] * maxThreads
# Holds Popen handles for each worker
workerHandles = [None] * maxThreads
# Holds the start time of each worker, for statistics
workerStartTimes = [None] * maxThreads
# Total number of simulations
totalSimulations = len(fcdFiles)
# Array to store simulation times, for statistics
simulationTimes = []


# Decompresses akin to 'gzip -d', erasing the original .gz
# Returns the name (and path, if provided) of the decompressed file
def gunzip(fileIn):
	# Like gunzip, default output has the same base name
	fileOut = re.sub('\.gz$', '', fileIn)

	# Handles
	with gzip.open(fileIn, 'rb') as inFileGzipHandle:
		with open(fileOut, 'wb') as outFileGzipHandle:
			outFileGzipHandle.write( inFileGzipHandle.read() ) # Decompress and close

	# Wipe compressed file
	os.remove(fileIn)

	return fileOut


# Routine to create a new simulation
def simulate(fcdFileIn):
	simulationName = re.sub('\.fcd.xml.gz$', '', os.path.basename(fcdFileIn))

	# Find a free worker and mark it busy
	freeWorkerId = workers.index('free')
	workers[freeWorkerId] = 'busy'

	# Create the base simulation directory
	os.makedirs(os.path.join(simulationDir, simulationName), exist_ok=True)

	# Copy the FCD file over
	fcdFile = os.path.join(simulationDir, simulationName, os.path.basename(fcdFileIn))
	shutil.copyfile(fcdFileIn, fcdFile)

	# Uncompress the FCD file
	fcdFile = gunzip(fcdFile)

	# Copy the reference configuration file over
	configFile = os.path.join(simulationDir, simulationName, 'config.plist')
	shutil.copyfile('config.plist', configFile)

	# Prepare to edit the configuration file
	configFileHandle = open(configFile, 'rb')
	configFileDict = plistlib.load(configFileHandle, fmt=plistlib.FMT_XML)

	# Edit 'floatingCarDataFile' and 'statsFolder' on the configuration
	configFileDict['floatingCarDataFile'] = fcdFile
	configFileDict['stats']['statsFolder'] = os.path.join(simulationDir, simulationName, 'stats')

	# Set 'gis.database' to match the free worker id
	configFileDict['gis']['database'] = 'gisdb{:d}'.format(freeWorkerId)

	# Write and close the configuration file
	configFileHandle = open(configFile, 'wb')
	plistlib.dump(configFileDict, configFileHandle, fmt=plistlib.FMT_XML)
	configFileHandle.close()

	# Simulate
	workerStartTimes[freeWorkerId] = time.time()
	runString ="./gissumo_fast {:s} > {:s} 2>&1".format(configFile, os.path.join(simulationDir, simulationName, 'gissumo.log'))
	workerHandles[freeWorkerId] = subprocess.Popen(runString, shell=True)


# Main loop
simulationCount = 0
while True:
	time.sleep(1)

	# Update worker statuses
	for workerId, worker in enumerate(workers):
		if worker == 'busy':
			if workerHandles[workerId].poll() != None:
				# Worker has finished
				workers[workerId] = 'free'
				# Save simulation time
				simulationTimes.append(time.time() - workerStartTimes[workerId])
				# Update simulation count
				simulationCount += 1
				# Print some statistics if a simulation finished
				meanSimulationTime = sum(simulationTimes)/len(simulationTimes)
				remainingTime = meanSimulationTime*len(fcdFiles)
				print("{:d}/{:d} simulations complete, ETA {:d}h{:02d}m{:02d}s".format(simulationCount, totalSimulations, int(remainingTime/3600), int(remainingTime%3600/60), int(remainingTime%60)))

	# Run a simulation if a free worker is available
	if (len(fcdFiles) > 0) and (workers.count('free') > 0):
		# Pull a new simulation file
		newGzFcdFile = fcdFiles.pop(0)

		# Simulate it
		simulate(newGzFcdFile)

	# Iterate until no simulations remain, and no workers still busy
	if (len(fcdFiles) == 0) and (workers.count('busy') == 0):
		break


# Create a file with a description of the simulation set (overwriting)
with open(os.path.join(simulationDir, simulationDescription), 'w') as descriptionFp:
	descriptionFp.write("{:d} simulations\n".format(totalSimulations))

# Simulation over
print("Set complete, ran {:d} simulations.".format(totalSimulations))

# Clean up
os.remove('gissumo_fast')
os.remove('configPlistEditor')

# Remove FCD files
for dirpath, dirnames, filenames in os.walk(simulationDir):
	for file in filenames:
		if file.endswith('fcd.xml'):
			os.remove(os.path.join(dirpath, file))
