#!/usr/bin/env python3
#env python3 -u -OO
#PYTHONUNBUFFERED="YES" PYTHONOPTIMIZE=2
import os, sys, math, random, optparse

optParser = optparse.OptionParser()
optParser.add_option("--seed", type="int", default=31338, help="random number generator seed")
optParser.add_option("--startTime", type="int", default=3*3600, help="start time, in seconds")
optParser.add_option("--stopTime", type="int", default=21*3600, help="stop time, in seconds")
optParser.add_option("--maxPerSecond", type="int", default=1, help="add N vehicles per second at most")
optParser.add_option("--targetActive", type="int", default=55, help="try to maintain N active vehicles")
optParser.add_option("--parkingEvents", type="int", default=4000, help="number of parking events to force")
optParser.add_option("--minDistance", type="int", default=250, help="minimum distance for new trips")
optParser.add_option("--fringeFactor", type="float", default=1.0, help="fringe factor for new trips")
optParser.add_option("--debug", action="store_true", default=False, help="enable debug output")
optParser.add_option("--sumoPort", type="int", default=8813, help="SUMO listening port")
optParser.add_option("--sumoAddress", type="string", default="127.0.0.1", help="SUMO IP address")
optParser.add_option("--netFile", type="string", default="map_clean3.net.xml", help="location of the SUMO network file")

(options, args) = optParser.parse_args()


## Configuration
# Random seed number
random.seed(a = options.seed)

# Minimum distance when generating new trips
# Porto Map #02 -- 1 sq.km. -- (41.1679,-8.6227),(41.1598,-8.6094), BBoxDiameter (maximum trip distance without intermediates) = 2473
minDistance = options.minDistance

# Fringe factor
# On a smaller map, increasing fringe-factor can cause cars to pool up around city edges and cause congestion
fringeFactor = options.fringeFactor

# File locations
netFileLocation=options.netFile
sumoTools="/usr/share/sumo/tools"

# SUMO connection
sumoHost=options.sumoAddress
sumoPort=options.sumoPort

# Load SUMO libs
sys.path.append(sumoTools)
import traci

# Load our own modules
sys.path.append("modules/")
import tripgen
tripgen.setup(netfile=netFileLocation, fringefactor=fringeFactor, mindistance=minDistance, seed=options.seed)
import parkstat

# Open connection to sumo
print("Connecting to {:s}:{:d}... ".format(sumoHost, sumoPort), end='')
traci.init(host=sumoHost, port=sumoPort, numRetries=0)
print("done")

print("Connected to a SUMO instance with:")
print(" {:d} edges".format(traci.edge.getIDCount()) )
print(" {:d} lanes".format(traci.lane.getIDCount()) )
print(" {:d} junctions".format(traci.junction.getIDCount()) )
print(" {:d} trafficlights".format(traci.trafficlights.getIDCount()) )
print(" {:d} routes".format(traci.route.getIDCount()) )
print(" {:d} vehicles".format(traci.vehicle.getIDCount()) )
print(" {:d} persons".format(traci.person.getIDCount()) )
print(" {:d} polygons".format(traci.polygon.getIDCount()) )
print(" {:d} POIs".format(traci.poi.getIDCount()) )


debug = options.debug
startTime = options.startTime
stopTime = options.stopTime
maxNewVehiclesPerSecond = options.maxPerSecond
targetActiveVehicleCount = options.targetActive
numForcedParkingEvents = options.parkingEvents

nextVehicleID = 0
timeMultiplier = 1000 # SUMO tracks milliseconds
timeStep = traci.simulation.getDeltaT()
nowTime = traci.simulation.getCurrentTime() # Should be 0

# Distribute parking events
parkingEvents = parkstat.distributeEvents(numForcedParkingEvents,startTime=startTime,endTime=stopTime)
print("Forcing {:d} parking events from {:d}h{:02d}m to {:d}h{:02d}m".format(
	sum(parkingEvents.values()),
	math.floor( startTime/3600 ),
	math.floor( (startTime % 3600)/60 ),
	math.floor( stopTime/3600 ),
	math.floor( (stopTime % 3600)/60 ) )
	, "({:d} requested)".format(numForcedParkingEvents))



def addNewVehicles(count):
	global nextVehicleID, globalActiveVehicleIDs

	while count > 0:
		count -= 1

		# Get a vehicle ID
		vid = nextVehicleID
		nextVehicleID += 1
		vehicleName = "{:d}".format(vid)
		# Get a trip edge pair
		newTrip = tripgen.makeNewTrip()
		# Create a new route with the just-created trip
		routeName = "trip{:d}".format(vid)
		traci.route.add(routeName, [newTrip[0], newTrip[1]])
		# Add the vehicle
		traci.vehicle.add(vehicleName, routeName)
		# Track the vehicle
		globalActiveVehicleIDs.append(vehicleName)
		# Debug
		if debug: print("{:.1f}\tAdd vehicle {:8s}\tsource {:12s}\tsink {:12s}".format(nowTime/timeMultiplier, vehicleName, newTrip[0], newTrip[1]) )




def randomParkVehicles(count):
	global globalActiveVehicleIDs, globalParkedVehicleIDs

	# Draw #count random vehicles (must all be different)
	vehIDsToPark = []
	while True:
		newIndex = random.randrange(0, len(globalActiveVehicleIDs), 1)
		newParkID = globalActiveVehicleIDs[newIndex]
		if newParkID not in vehIDsToPark:
			vehIDsToPark.append(newParkID)
			if len(vehIDsToPark) == count:
				break

	# Park the vehicles
	for parkVehID in vehIDsToPark:
		traci.vehicle.remove(parkVehID)
		globalActiveVehicleIDs.remove(parkVehID)
		globalParkedVehicleIDs.append(parkVehID)

	# Add new active vehicles to compensate
	if len(globalActiveVehicleIDs) < targetActiveVehicleCount:
		addNewVehicles(count)




def updateVehicleLists():
	global globalActiveVehicleIDs, globalParkedVehicleIDs, uncontrolledParkings, reachedStability

	sumoVehicleList = traci.vehicle.getIDList()

	# Check vehicles going from parked to active (SUMO limitation)
	if reachedStability:
		for sumoActiveVeh in sumoVehicleList:
			if sumoActiveVeh in globalParkedVehicleIDs:
				print("{:.1f}\t[info] Assumed parked vehicle {:s} is now active.".format(nowTime/timeMultiplier, sumoActiveVeh))
				globalActiveVehicleIDs.append(sumoActiveVeh)
				globalParkedVehicleIDs.remove(sumoActiveVeh)
				if uncontrolledParkings > 0:
					uncontrolledParkings -= 1

	# Vehicles now missing from the active list are parked
	for gActiveVeh in globalActiveVehicleIDs:
		if gActiveVeh not in sumoVehicleList:
			globalActiveVehicleIDs.remove(gActiveVeh)
			globalParkedVehicleIDs.append(gActiveVeh)
			if reachedStability:
				uncontrolledParkings += 1



## Main loop
reachedStability = False
globalActiveVehicleIDs = []
globalParkedVehicleIDs = []
uncontrolledParkings = 0

while nowTime < ((stopTime-startTime)*timeMultiplier):
	## Update vehicle lists
	updateVehicleLists()

	## Reroute vehicles near their arrival spots to another destination
	for actVID in globalActiveVehicleIDs:
		# Our criteria (not ideal) is finding a vehicle on its third-to-last (or lower) destination edge.
		# Sometimes the vehicle will reach its destination edge and be removed in a single timestep,
		# so we try to reroute it on its third-to-last edge.
		# We thank SUMO devs for making it ridiculously convoluted to change vehicle arrival behavior.
		vehCurrentEdge = traci.vehicle.getRoadID(actVID)
		vehRoute = traci.vehicle.getRoute(actVID)
		if ( vehCurrentEdge == vehRoute[-1] ) or ( vehCurrentEdge == vehRoute[-2] ) or ( vehCurrentEdge == vehRoute[-3] ):
			# Get a new destination, forcing current road as the source
			newTripForcingSource = tripgen.makeNewTripWithSource(vehCurrentEdge)
			# Reroute vehicle
			traci.vehicle.changeTarget(actVID, newTripForcingSource[1])


	## Add new vehicles to near the target number of active vehicles
	if len(globalActiveVehicleIDs) < targetActiveVehicleCount:
		# Find how many vehicles are missing and limit new additions to maxNewVehiclesPerSecond
		numberOfNewVehicles = targetActiveVehicleCount - len(globalActiveVehicleIDs)
		numberOfNewVehicles = maxNewVehiclesPerSecond if numberOfNewVehicles>maxNewVehiclesPerSecond else numberOfNewVehicles
		addNewVehicles(count = numberOfNewVehicles)

	# The first time the above if: is not met, mark stability as reached
	elif not reachedStability:
		reachedStability = True


	# Enforce parking events
	actualTime = (nowTime/timeMultiplier+startTime)
	if actualTime in parkingEvents:
		willPark = parkingEvents[actualTime]
		if willPark > 0:
			print("{:.1f}\t[info] ActualTime {:.1f} will park {:d} uncontrolled {:d} parked {:d}".format(nowTime/timeMultiplier, actualTime, willPark, uncontrolledParkings, len(globalParkedVehicleIDs)))
			# Count any uncontrolled parkings towards the number of parking events we must execute
			if uncontrolledParkings > 0:
				deltaParkings = willPark-uncontrolledParkings
				# The following matches parking event counts:
				# If both willPark and unPark are equal, both get set to 0
				# If more willPark than unPark, willPark is reduced, unPark is zeroed
				# If more unPark than willPark, unPark is reduced, willPark is zeroed
				if deltaParkings == 0:
					willPark = 0
					uncontrolledParkings = 0
				elif deltaParkings > 0:
					willPark = deltaParkings
					uncontrolledParkings = 0
				elif deltaParkings < 0:
					willPark = 0
					uncontrolledParkings = abs(deltaParkings)

			# Now force parking events if willPark > 0
			if willPark > 0:
				randomParkVehicles(count = willPark)


	## Advance simulation
	traci.simulationStep()
	nowTime = traci.simulation.getCurrentTime()

	print("{:.1f}\t{:d} vehicles, {:d} parking events, {:.2f}% done".format(nowTime/timeMultiplier, len(globalActiveVehicleIDs), len(globalParkedVehicleIDs), nowTime/((stopTime-startTime)*timeMultiplier)*100.0 ) )
# Main loop (end)

traci.close()
