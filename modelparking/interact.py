#!/usr/bin/env python3 -i
import os, sys, math, random

## Configuration

# Random seed number
randomSeed = 31338
random.seed(a = randomSeed)

# Minimum distance when generating new trips
# Porto Map #02 -- 1 sq.km. -- (41.1679,-8.6227),(41.1598,-8.6094), BBoxDiameter (maximum trip distance without intermediates) = 2473
minDistance = 250

# Fringe factor
# On a smaller map, increasing fringe-factor can cause cars to pool up around city edges and cause congestion
fringeFactor = 1.0

# File locations
netFileLocation="map_clean3.net.xml"
sumoTools="/Users/abreis/Development/SUMO/sumo-0.28.0/tools"

# SUMO connection
sumoHost="192.168.99.100"
sumoPort=8813

# Load SUMO libs
sys.path.append(sumoTools)
import traci

# Load our own modules
sys.path.append("modules/")
import tripgen
tripgen.setup(netfile=netFileLocation, fringefactor=fringeFactor, mindistance=minDistance, seed=randomSeed)
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


debug = False
startTime = 3*3600
stopTime = 21*3600
# startTime = 8*3600
# stopTime = 9*3600
maxNewVehiclesPerSecond = 4
targetActiveVehicleCount = 55
nextVehicleID = 0
numForcedParkingEvents = 4000

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



## Main loop
reachedStability = False
uncontrolledParkings=0
parkedVehicleCounter=0
while nowTime < ((stopTime-startTime)*timeMultiplier):

	## Reroute vehicles near their arrival spots to another destination
	for actVID in traci.vehicle.getIDList():
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
	if targetActiveVehicleCount > traci.vehicle.getIDCount():
		# Find how many vehicles are missing and limit new additions to maxNewVehiclesPerSecond
		numberOfNewVehicles = targetActiveVehicleCount-traci.vehicle.getIDCount()
		numberOfNewVehicles = maxNewVehiclesPerSecond if numberOfNewVehicles>maxNewVehiclesPerSecond else numberOfNewVehicles

		# If the target number of vehicles was reached earlier, then 
		# some vehicles have not been rerouted in time and parked outside
		# our control
		if reachedStability:
			uncontrolledParkings+=numberOfNewVehicles
			parkedVehicleCounter+=numberOfNewVehicles
		for nullVar in range(0, numberOfNewVehicles):
			## Add a new Vehicle
			# Get a vehicle ID
			vid = nextVehicleID
			nextVehicleID+=1
			vehicleName = "veh{:d}".format(vid)
			# Get a trip edge pair
			newTrip = tripgen.makeNewTrip()
			# Create a new route with the just-created trip
			routeName = "trip{:d}".format(vid)
			traci.route.add(routeName, [newTrip[0], newTrip[1]])
			# Add the vehicle
			traci.vehicle.add(vehicleName, routeName)
			# Debug
			if debug: print("{:.1f}\tAdd vehicle {:8s}\tsource {:12s}\tsink {:12s}".format(nowTime/timeMultiplier, vehicleName, newTrip[0], newTrip[1]) )
	# The first time the above if: is met, mark stability as reached
	elif not reachedStability:
		reachedStability = True


	# Enforce parking events
	actualTime = (nowTime/timeMultiplier+startTime)
	if actualTime in parkingEvents:
		willPark = parkingEvents[actualTime]
		if willPark > 0:
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
				activeVehicles = traci.vehicle.getIDList()
				activeVehicleCount = len(activeVehicles)

				vehIDsToPark = []

				# Draw #willPark random vehicles (must all be different)
				while True:
					newIndex = random.randrange(0, activeVehicleCount, 1)
					newParkID = activeVehicles[newIndex]
					if newParkID not in vehIDsToPark:
						vehIDsToPark.append(newParkID)
						if len(vehIDsToPark)==willPark:
							break

				# Park the vehicles
				for parkVehID in vehIDsToPark:
					traci.vehicle.remove(parkVehID)
					parkedVehicleCounter += 1


	## Advance simulation
	traci.simulationStep()
	nowTime = traci.simulation.getCurrentTime()

	print("{:.1f}\t{:d} vehicles, {:d} parking events".format(nowTime/timeMultiplier, traci.vehicle.getIDCount(), parkedVehicleCounter) )
# Main loop (end)

traci.close()
