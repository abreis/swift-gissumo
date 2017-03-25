/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

enum RoadEntityType: UInt {
	case unspecific = 0
	case vehicle
	case roadsideUnit
	case parkedCar
}


/*** SUPERCLASS ***/

// A basic road entity, with an ID, GIS ID, geographic location, time of creation, and the city it belongs to
class RoadEntity {
	var id: UInt
	var city: City
	var geo: (x: Double, y: Double)
	var type: RoadEntityType { return .unspecific }

	var gid: UInt?
	var creationTime: SimulationTime?

	var receivedPacketIDs = [UInt]()

	init(id v_id: UInt, geo v_geo: (x:Double, y:Double), city v_city: City, creationTime ctime: SimulationTime?) {
		id = v_id; geo = v_geo; city = v_city;
		if let time = ctime { creationTime = time }
	}
}


/*** L1 SUBCLASSES ***/

// Moving entities, e.g. vehicles, motorcycles, pedestrians
// May have a 'speed' entry
class MovingRoadEntity: RoadEntity {
	var speed: Double?
}

// Fixed entities, e.g. parked cars, roadside units, sensors
// Can request coverage maps and build their own from beacons
class FixedRoadEntity: RoadEntity {
	// Initialize the local coverage map
	lazy var selfCoverageMap: CellMap<Int> = CellMap<Int>(ofSize: (x: self.city.network.selfCoverageMapSize, y: self.city.network.selfCoverageMapSize), withValue: 0, geographicCenter: self.geo)

	/* neighborMaps stores the coverage maps received from 1-hop neighbors, and tracks
	 * the last time an update was received to a map, and the distance (hops) to a map's
	 * owner.
	 *
	 * append(coverageMaps:) manages additions to this dictionary, processing coverage map arrays
	 */
	var neighborMaps: [UInt:(coverageMap: CellMap<Int>, lastUpdated: SimulationTime, distance: UInt)] = [:]
	func append(coverageMaps: [SelfCoverageMap], sender: UInt, currentTime: SimulationTime) -> () {
		var coverageMaps = coverageMaps

		// Sanity check: the first map should always belong to the sender
		guard coverageMaps.first!.ownerID == sender else {
			print("Error: First map not owned by map sender.")
			exit(EXIT_FAILURE)
		}

		/// Inferring distances
		/* The first map belongs to the vehicle that sent the message. It is a 1-hop neighbor.
		 * If the sender's map is on our neighbor maps array with a distance==2, reduce it to 1.
		 */
		let senderCoverageMap = coverageMaps.removeFirst()
		neighborMaps[senderCoverageMap.ownerID] = (coverageMap: senderCoverageMap.cellMap, lastUpdated: currentTime, distance: 1)

		/* For the remaining maps, add them to the neighborMaps array with a default distance of 2,
		 * unless we've seen them before, in which case don't change the existing distance.
		 */
		for senderNeighborMap in coverageMaps {
			if neighborMaps[senderNeighborMap.ownerID] != nil {
				neighborMaps[senderNeighborMap.ownerID]!.coverageMap = senderNeighborMap.cellMap
				neighborMaps[senderNeighborMap.ownerID]!.lastUpdated = currentTime
			} else {
				neighborMaps[senderNeighborMap.ownerID] = (coverageMap: senderNeighborMap.cellMap, lastUpdated: currentTime, distance: 2)
			}
		}
	}
}


/*** L2 SUBCLASSES ***/

// A vehicle entity
class Vehicle: MovingRoadEntity {
	override var type: RoadEntityType { return .vehicle }
	var active: Bool = true
}

// A parked car
class ParkedCar: FixedRoadEntity {
	override var type: RoadEntityType { return .parkedCar }
	var neighborActiveTimes: [UInt:Double] = [:]
}

// A roadside unit entity
enum RoadsideUnitType {
	case fixed
	case mobile
	case parkedCar
}

class RoadsideUnit: FixedRoadEntity {
	override var type: RoadEntityType { return .roadsideUnit }
	var rsuType: RoadsideUnitType = .parkedCar

	// Array dictionary to hold coverage maps of neighbor RSUs and their last received update
	// key: neighborID, value: (map, lastUpdated)
}


/* The city is our primary class. It keeps references to:
 * - the list of vehicles
 * - the list of roadside units
 * - the geographic information database
 * - the network layer being used
 * - the list of simulator events
 * - the current simulation time
 *
 * All road entities should keep a pointer to the city they're in, so they may
 * access these features when necessary.
 */
class City {
	// Arrays for vehicles, roadside units and parked cars in the city
	var vehicles = [Vehicle]()
	var roadsideUnits = [RoadsideUnit]()
	var parkedCars = [ParkedCar]()

	// Our GIS database
	var gis: GIS

	// Our network layer
	var network: Network

	// Our list of events
	var events: EventList

	// Our statistics module
	let stats: Statistics

	// Our decision module
	let decision: Decision

	// Maximum roadside unit lifetime
	var rsuLifetime: Int? = nil {
		didSet {
			let initialExpireEvent = SimulationEvent(time: self.decision.triggerDelay, type: .mobility, action: { self.recurringExpireRoadsideUnits() }, description: "expire roadside units")
			self.events.add(newEvent: initialExpireEvent)
		}
	}

	// City bounds
	var bounds = Square(x: (min: 0, max: 0), y: (min: 0, max: 0))
	var topLeftCell: (x: Int, y: Int) {
		return (x: Int(floor(bounds.x.min*3600)), y: Int(floor(bounds.y.max*3600)) )
	}
	var cellSize: (x: Int, y: Int) {
		return (x: Int( ceil(bounds.x.max*3600) - floor(bounds.x.min*3600) ),
		        y: Int( ceil(bounds.y.max*3600) - floor(bounds.y.min*3600) ))
	}

	// Inner bounds for data analysis (supplied in configuration file)
	var innerBounds: Square? {
		didSet {
			guard let inBounds = innerBounds, let inCellSize = innerCellSize, let inTopLeft = innerTopLeftCell else { return }
			// When inner bounds are set, ensure the city (outer) bounds are larger than what's requested
			guard	inBounds.x.min >= bounds.x.min &&
					inBounds.x.max <= bounds.x.max &&
					inBounds.y.min >= bounds.y.min &&
					inBounds.y.max <= bounds.y.max
			else {
				print("Error: The specified inner city bounds are larger than the outer bounds.")
				exit(EXIT_FAILURE)
			}
			// Debug
			if debug.contains("City.determineBounds()"){
				print("\(events.now.asSeconds) City.determineBounds():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "City inner bounds", inBounds, "cell size", inCellSize, "top left cell", inTopLeft) }
		}
	}
	var innerTopLeftCell: (x: Int, y: Int)? {
		if let iBounds = innerBounds {
			return (x: Int(floor(iBounds.x.min*3600)), y: Int(floor(iBounds.y.max*3600)) )
		} else { return nil }
	}
	var innerCellSize: (x: Int, y: Int)? {
		if let iBounds = innerBounds {
			return (x: Int( ceil(iBounds.x.max*3600) - floor(iBounds.x.min*3600) ),
			        y: Int( ceil(iBounds.y.max*3600) - floor(iBounds.y.min*3600) ))
		} else { return nil }
	}

	/// Standard init, provide a database, network and eventlist
	init(gis ingis: GIS, network innet: Network, eventList inevents: EventList, statistics instats: Statistics, decision indecision: Decision) {
		network = innet
		gis = ingis
		events = inevents
		stats = instats
		decision = indecision
	}

	/// Automatically determine bounds and cell map sizes from FCD data (DEPRECATED)
	func determineBounds(fromFCD trips: inout [FCDTimestep]) {
		// Initialize the city bounds with reversed WGS84 extreme bounds
		bounds.x = (min:  180.0, max: -180.0)
		bounds.y = (min:   90.0, max:  -90.0)

		// Locate the min and max coordinate pairs of the vehicles in the supplied Floating Car Data
		// Run through every timestep and find min and max coordinates
		for timestep in trips {
			for vehicle in timestep.vehicles {
				if vehicle.geo.x < bounds.x.min { bounds.x.min = vehicle.geo.x }
				if vehicle.geo.x > bounds.x.max { bounds.x.max = vehicle.geo.x }
				if vehicle.geo.y < bounds.y.min { bounds.y.min = vehicle.geo.y }
				if vehicle.geo.y > bounds.y.max { bounds.y.max = vehicle.geo.y }
			}
		}

		if debug.contains("City.determineBounds()"){
			print("\(events.now.asSeconds) City.determineBounds():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "City bounds", bounds, "cell size", cellSize, "top left cell", topLeftCell) }
	}

	/// Schedule mobility events and determine bounds from the FCD data
	func scheduleMobilityAndDetermineBounds(fromTSV fcdTSV: inout [String], stopTime configStopTime: Double = 0.0) {
		// Auxiliary variable to ensure we get time-sorted data
		var lastTimestepTime: Double = -Double.greatestFiniteMagnitude

		// Implement a simple progress bar
		let maxRunTime = events.stopTime.seconds
		let progressIncrement: Int = 10
		var nextTargetPercent: Int = 0 + progressIncrement
		var nextTarget: Int { return nextTargetPercent*maxRunTime/100 }

		// [bounds]
		// Initialize the city bounds with reversed WGS84 extreme bounds
		bounds.x = (min:  180.0, max: -180.0)
		bounds.y = (min:   90.0, max:  -90.0)

		// [mobility]
		// A temporary array to store vehicles that will be active
		var cityVehicleIDs = Set<UInt>()

		// Index for iterating the TSV file
		var entryPosition: Int = 0

		// Iterate over the TSV file, pulling a timestep set at a time
		tsvLoop: repeat {
			// Pull a complete timestep
			// This timestep's time is the time on the current position
			guard let timestepTime = Double(fcdTSV[entryPosition].components(separatedBy: "\t").first!) else {
				print("Error: Failed to grab the time on a timestep.")
				exit(EXIT_FAILURE)
			}

			// Don't load timesteps that occur later than the simulation stopTime
			if configStopTime > 0, timestepTime > configStopTime { break tsvLoop }

			// Create an array for storing FCDVehicles
			var timestepVehicles = [FCDVehicle]()
			timestepLoop: repeat {
				// Pull an entry
				let fcdEntry = fcdTSV[entryPosition].components(separatedBy: "\t")

				// Get the entry's timestep time, and continue if it belongs to the next timestep
				guard	let v_time = Double(fcdEntry[0]),
						v_time == timestepTime
				else {
					break timestepLoop
				}

				// Process the entry
				guard	let v_id = UInt(fcdEntry[1]),
						let v_xgeo = Double(fcdEntry[2]),
						let v_ygeo = Double(fcdEntry[3])
				else {
						print("Error: Unable to convert vehicle properties.")
						exit(EXIT_FAILURE)
				}

				// Append a new FCDVehicle entry
				timestepVehicles.append( FCDVehicle(id: v_id, geo: (x: v_xgeo, y: v_ygeo)) )

				// Increment our position on the TSV array
				entryPosition += 1
			} while entryPosition < fcdTSV.count

			// Create an FCDTimestep object
			let timestep = FCDTimestep(time: timestepTime, vehicles: timestepVehicles)


			// Schedule mobility and determine bounds
			// [bounds]
			for vehicle in timestep.vehicles {
				if vehicle.geo.x < bounds.x.min { bounds.x.min = vehicle.geo.x }
				if vehicle.geo.x > bounds.x.max { bounds.x.max = vehicle.geo.x }
				if vehicle.geo.y < bounds.y.min { bounds.y.min = vehicle.geo.y }
				if vehicle.geo.y > bounds.y.max { bounds.y.max = vehicle.geo.y }
			}

			// [mobility]
			/* Create a set of vehicle IDs in this timestep
			* This is done by mapping the timestep's array of FCDVehicles into an array of
			* the vehicle's IDs, and then initializing the Set<UInt> with that array.
			*/
			let fcdVehicleIDs = Set<UInt>( timestep.vehicles.map({$0.id}) )

			// Through set relations we can now get the IDs of all new, existing and removed vehicles
			let newVehicleIDs = fcdVehicleIDs.subtracting(cityVehicleIDs)
			let existingVehicleIDs = fcdVehicleIDs.intersection(cityVehicleIDs)
			let missingVehicleIDs = cityVehicleIDs.subtracting(fcdVehicleIDs)

			// Debug
			if debug.contains("EventList.scheduleMobilityEvents()"){
				print("\(events.now.asSeconds) EventList.scheduleMobilityEvents():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Timestep", timestep.time, "sees:" )
				print("\t\tFCD vehicles:", fcdVehicleIDs)
				print("\t\tCity vehicles:", cityVehicleIDs)
				print("\t\tNew vehicles:", newVehicleIDs)
				print("\t\tExisting vehicles:", existingVehicleIDs)
				print("\t\tMissing vehicles:", missingVehicleIDs)
			}

			// Insert and remove vehicles into our temporary array
			cityVehicleIDs.formUnion(newVehicleIDs)
			cityVehicleIDs.subtract(missingVehicleIDs)

			// Schedule events to create new vehicles
			for newFCDvehicleID in newVehicleIDs {
				let newFCDvehicle = timestep.vehicles[ timestep.vehicles.index( where: {$0.id == newFCDvehicleID} )! ]
				// (note: the IDs came from timestep.vehicles, so an .indexOf on the array can be force-unwrapped safely)

				let newVehicleEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .mobility, action: {_ = self.addNew(vehicleWithID: newFCDvehicle.id, geo: newFCDvehicle.geo)}, description: "newVehicle id \(newFCDvehicle.id)")

				events.add(newEvent: newVehicleEvent)
			}

			// Schedule events to update existing vehicles
			for existingFDCvehicleID in existingVehicleIDs {
				let existingFCDvehicle = timestep.vehicles[ timestep.vehicles.index( where: {$0.id == existingFDCvehicleID} )! ]

				let updateVehicleEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .mobility, action: {self.updateLocation(entityType: .vehicle, id: existingFDCvehicleID, geo: existingFCDvehicle.geo)}, description: "updateVehicle id \(existingFCDvehicle.id)")

				events.add(newEvent: updateVehicleEvent)
			}

			// Schedule events to act on vehicles ending their trips
			for missingFDCvehicleID in missingVehicleIDs {
				let endTripEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .mobility, action: {self.endTripConvertToParkedCar(vehicleID: missingFDCvehicleID)}, description: "endTripConvertToParkedCar vehicle \(missingFDCvehicleID)")

				events.add(newEvent: endTripEvent)
			}


			// Print progress bar
			if Int(timestep.time) > nextTarget {
				print(nextTargetPercent, terminator: "% ")
				fflush(stdout)
				nextTargetPercent += progressIncrement
			}

		} while entryPosition < fcdTSV.count
	}

	/// Remove Roadside Units in the network whose expiry time is elapsed
	func recurringExpireRoadsideUnits() -> () {
		if rsuLifetime != nil {
			let currentTime = events.now
			for rsu in roadsideUnits {
				if (currentTime.seconds - rsu.creationTime!.seconds) >= rsuLifetime! {
					removeEntity(rsu)
				}
			}
		}

		// Schedule next expiry
		let nextEventTime = self.events.now + SimulationTime(seconds: 1.0)
		if nextEventTime < self.events.stopTime {
			let nextExpireEvent = SimulationEvent(time: nextEventTime, type: .mobility, action: { self.recurringExpireRoadsideUnits() }, description: "expire roadside units")
			self.events.add(newEvent: nextExpireEvent)
		}
	}

	/// Match a vehicle ID to a Vehicle entity
	func get(vehicleFromID vid: UInt) -> Vehicle? {
		if let vIndex = vehicles.index( where: { $0.id == vid } ) {
			return vehicles[vIndex]
		} else { return nil }
	}

	/// Match a RoadEntity GID to a Vehicle entity
	func get(vehicleFromGID vgid: UInt) -> Vehicle? {
		if let vIndex = vehicles.index( where: { $0.gid == vgid } ) {
			return vehicles[vIndex]
		} else { return nil }
	}

	/// Match a RoadEntity GID to a Parked entity
	func get(parkedCarFromGID pgid: UInt) -> ParkedCar? {
		if let pIndex = parkedCars.index( where: { $0.gid == pgid } ) {
			return parkedCars[pIndex]
		} else { return nil }
	}


	/// Returns the GIDs of features in a specified circle (no database query)
	func getFeatureGIDs(inCircleWithRadius range: Double, center: (x: Double, y: Double), featureTypes: [GIS.FeatureType]) -> [UInt] {
		var listOfGIDs = [UInt]()

		if featureTypes.contains(.vehicle) {
			for vehicle in vehicles {
				if gis.getHaversineDistance(fromPoint: center, toPoint: vehicle.geo) < range {
					listOfGIDs.append(vehicle.gid!)
				}
			}
		}

		if featureTypes.contains(.roadsideUnit) {
			for rsu in roadsideUnits {
				if gis.getHaversineDistance(fromPoint: center, toPoint: rsu.geo) < range {
					listOfGIDs.append(rsu.gid!)
				}
			}
		}

		if featureTypes.contains(.parkedCar) {
			for pcar in parkedCars {
				if gis.getHaversineDistance(fromPoint: center, toPoint: pcar.geo) < range {
					listOfGIDs.append(pcar.gid!)
				}
			}
		}

		return listOfGIDs
	}


	/*** GLOBAL CELL MAPS ***/
	// Get the global map of best signal strength (Global Map of Coverage)
	var globalMapOfCoverage: CellMap<Int> {
		var GMC = CellMap<Int>(ofSize: cellSize, withValue: 0, geographicTopLeft: (x: bounds.x.min, y: bounds.y.max))
		for rsu in roadsideUnits {
			GMC.keepBestSignal(fromSignalMap: rsu.selfCoverageMap)
		}
		return GMC
	}

	// Get the global map of RSU saturation (Global Map of Saturation)
	var globalMapOfSaturation: CellMap<Int> {
		var GMS = CellMap<Int>(ofSize: cellSize, withValue: 0, geographicTopLeft: (x: bounds.x.min, y: bounds.y.max))
		for rsu in roadsideUnits {
			GMS.incrementSaturation(fromSignalMap: rsu.selfCoverageMap)
		}
		return GMS
	}

	// Get a global map with the location of all entities marked on it
	var globalMapOfEntities: CellMap<Character> {
		var GME = CellMap<Character>(ofSize: cellSize, withValue: "·", geographicTopLeft: (x: bounds.x.min, y: bounds.y.max))
		for vehicle in vehicles { GME[vehicle.geo] = "V" }
		for parkedCar in parkedCars { GME[parkedCar.geo] = "P" }
		for roadsideUnit in roadsideUnits { GME[roadsideUnit.geo] = "R" }
		return GME
	}

	/*** ROAD ENTITY ACTIONS ***/

	/// Add a new Vehicle to the City and to GIS,  returning its GID
	func addNew(vehicleWithID v_id: UInt, geo v_geo: (x: Double, y: Double)) -> Vehicle {
		let newVehicle = Vehicle(id: v_id, geo: v_geo, city: self, creationTime: events.now)

		// Add the new vehicle to GIS and record its GIS ID
		newVehicle.gid = gis.addPoint(ofType: .vehicle, geo: newVehicle.geo, id: newVehicle.id)

		// Append the new vehicle to the city's vehicle list
		vehicles.append(newVehicle)

		// Schedule an initial recurrent beaconing
		let newBeaconEvent = SimulationEvent(time: events.now + network.beaconingInterval, type: .network, action: {newVehicle.recurrentBeaconing()}, description: "firstBroadcastBeacon vehicle \(newVehicle.id)")
		events.add(newEvent: newBeaconEvent)

		// Debug
		if debug.contains("City.addNew(vehicle)") {
			print("\(events.now.asSeconds) City.addNew(vehicle):".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Create vehicle id", newVehicle.id, "gid", newVehicle.gid!, "at", newVehicle.geo)
		}

		return newVehicle
	}


	/// Add a new RoadsideUnit to the City and to GIS, returning its GID
	func addNew(roadsideUnitWithID r_id: UInt, geo r_geo: (x: Double, y: Double), type r_type: RoadsideUnitType) -> RoadsideUnit {
		let newRSU = RoadsideUnit(id: r_id, geo: r_geo, city: self, creationTime: events.now)
		newRSU.rsuType = r_type

		// Add the new RSU to GIS and record its GIS ID
		newRSU.gid = gis.addPoint(ofType: .roadsideUnit, geo: newRSU.geo, id: newRSU.id)

		// Append the new vehicle to the city's vehicle list
		roadsideUnits.append(newRSU)

		// Debug
		if debug.contains("City.addNew(roadsideUnit)") {
			print("\(events.now.asSeconds) City.addNew(roadsideUnit):".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Create RSU id", newRSU.id, "gid", newRSU.gid!, "at", newRSU.geo)
		}

		return newRSU
	}


	/// Add a new ParkedCar to the City and to GIS, returning its GID
	func addNew(parkedCarWithID p_id: UInt, geo p_geo: (x: Double, y: Double)) -> ParkedCar {
		let newParkedCar = ParkedCar(id: p_id, geo: p_geo, city: self, creationTime: events.now)

		// Add the new Parked Car to GIS and record its GIS ID
		newParkedCar.gid = gis.addPoint(ofType: .parkedCar, geo: newParkedCar.geo, id: newParkedCar.id)

		// Append the new vehicle to the city's vehicle list
		parkedCars.append(newParkedCar)

		// Schedule a decision trigger event
		let decisionTriggerEvent = SimulationEvent(time: events.now + decision.triggerDelay, type: .decision, action: { self.decision.algorithm.trigger(newParkedCar) }, description: "decisionTrigger for id \(newParkedCar.id)")
		events.add(newEvent: decisionTriggerEvent)

		// Debug
		if debug.contains("City.addNew(parkedCar)") {
			print("\(events.now.asSeconds) City.addNew(parkedCar):".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Create ParkedCar id", newParkedCar.id, "gid", newParkedCar.gid!, "at", newParkedCar.geo)
		}

		return newParkedCar
	}


	/// Update the location of a vehicle in this City and on GIS
	func updateLocation(entityType type: RoadEntityType, id e_id: UInt, geo new_geo: (x: Double, y: Double)) {
		// Entity GID
		var eGID: UInt

		switch type {
		case .vehicle:
			guard	let vIndex = vehicles.index( where: {$0.id == e_id} ),
					let vGID = vehicles[vIndex].gid else {
						print("Error: Trying to update a non-existent vehicle.")
						exit(EXIT_FAILURE)
			}
			eGID = vGID
			// Update the vehicle coordinates
			vehicles[vIndex].geo = new_geo
		case .roadsideUnit:
			guard	let rIndex = roadsideUnits.index( where: {$0.id == e_id} ),
					let rGID = roadsideUnits[rIndex].gid else {
						print("Error: Trying to update a non-existent roadside unit.")
						exit(EXIT_FAILURE)
			}
			eGID = rGID
			// Update the vehicle coordinates
			roadsideUnits[rIndex].geo = new_geo
		case .parkedCar:
			guard	let pIndex = parkedCars.index( where: {$0.id == e_id} ),
					let pGID = parkedCars[pIndex].gid else {
						print("Error: Trying to update a non-existent parked car.")
						exit(EXIT_FAILURE)
			}
			eGID = pGID
			// Update the vehicle coordinates
			parkedCars[pIndex].geo = new_geo
		default:
			print("Error: Attempted to update the location of an unknown type of RoadEntity.")
			exit(EXIT_FAILURE)
		}

		// Move the corresponding point in GIS
		gis.updatePoint(withGID: eGID, geo: new_geo)

		// Debug
		if debug.contains("City.updateLocation()") {
			print("\(events.now.asSeconds) City.updateVehicleLocation():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Update", type, "id", e_id, "gid", eGID, "to coordinates", new_geo)
		}
	}


	/// Remove a vehicle from the City and from GIS
	func removeEntity(entityType type: RoadEntityType, id e_id: UInt) {
		// Entity GID
		var eGID: UInt

		switch type {
		case .vehicle:
			guard	let vIndex = vehicles.index( where: {$0.id == e_id} ),
					let vGID = vehicles[vIndex].gid else {
						print("Error: Trying to remove a non-existent vehicle.")
						exit(EXIT_FAILURE)
			}
			eGID = vGID
			// Mark the vehicle as inactive
			vehicles[vIndex].active = false
			// Remove the vehicle from the City
			vehicles.remove(at: vIndex)
		case .roadsideUnit:
			guard	let rIndex = roadsideUnits.index( where: {$0.id == e_id} ),
					let rGID = roadsideUnits[rIndex].gid else {
						if !debug.isEmpty { print("Warning: Trying to remove a non-existent roadside unit.") }
						return
			}
			eGID = rGID

			// Track RSU lifetime for statistics
			if stats.hooks["parkedRoadsideUnitLifetime"] != nil, roadsideUnits[rIndex].creationTime != nil {
				stats.writeToHook("parkedRoadsideUnitLifetime", data: "\(roadsideUnits[rIndex].id)\t\(roadsideUnits[rIndex].creationTime!.asSeconds)\t\(events.now.asSeconds)\t\(events.now.seconds-roadsideUnits[rIndex].creationTime!.seconds)\n")
			}

			// Remove the roadside unit from the City
			roadsideUnits.remove(at: rIndex)
		case .parkedCar:
			guard	let pIndex = parkedCars.index( where: {$0.id == e_id} ),
					let pGID = parkedCars[pIndex].gid else {
						print("Error: Trying to remove a non-existent parked car.")
						exit(EXIT_FAILURE)
			}
			eGID = pGID
			// Remove the parked car from the City
			parkedCars.remove(at: pIndex)
		default:
			print("Error: Attempted to remove an unknown type of RoadEntity.")
			exit(EXIT_FAILURE)
		}

		// Clear the corresponding point from GIS
		gis.deletePoint(withGID: eGID)

		// Debug
		if debug.contains("City.removeEntity()") {
			print("\(events.now.asSeconds) City.removeEntity():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Remove", type, "id", e_id, "gid", eGID)
		}
	}

	// Convenience remove() pulls the type and ID from the entity itself
	func removeEntity(_ entity: RoadEntity) {
		removeEntity(entityType: entity.type, id: entity.id)
	}


	/// Generic conversion routine to create parked cars from vehicles, RSUs from parked cars, etcetera
	func convertEntity(_ entity: RoadEntity, to targetType: RoadEntityType) {
		guard let eGID = entity.gid else {
			print("Error: Tried to convert a RoadEntity with no GID.")
			exit(EXIT_FAILURE)
		}

		// GID of the new entity
		var newEntity: RoadEntity? = nil

		// From vehicle to...
		if entity is Vehicle {
			switch targetType {
			case .roadsideUnit:
				removeEntity(entity)
				newEntity = addNew(roadsideUnitWithID: entity.id, geo: entity.geo, type: .parkedCar)
			case .parkedCar:
				removeEntity(entity)
				newEntity = addNew(parkedCarWithID: entity.id, geo: entity.geo)
			default:
				print("Error: Invalid entity conversion.")
				exit(EXIT_FAILURE)
			}
		}
		// From parked car to...
		else if entity is ParkedCar {
			switch targetType {
			case .roadsideUnit:
				removeEntity(entity)
				newEntity = addNew(roadsideUnitWithID: entity.id, geo: entity.geo, type: .parkedCar)
				// Copy the coverage map over to the new RSU
				(newEntity as! RoadsideUnit).selfCoverageMap = (entity as! ParkedCar).selfCoverageMap
			default:
				print("Error: Invalid entity conversion.")
				exit(EXIT_FAILURE)
			}
		}

		// From RSU to...
		// else if entity is RoadsideUnit {}

		// Debug
		if debug.contains("City.convertEntity()") {
			print("\(events.now.asSeconds) City.convertEntity():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Converted a", type(of: entity) , "id", entity.id, "gid", eGID, "to a", targetType, "gid", newEntity!.gid!)
		}
	}


	// Convenience function that first tries to locate the entity in the city's entity lists
	func convertEntity(_ entityID: UInt, to targetType: RoadEntityType) {
		// Try to match to a vehicle
		if let vIndex = vehicles.index( where: {$0.id == entityID} ) {
			convertEntity(vehicles[vIndex], to: targetType)
			return
		}

		// Try to match to a roadside unit
		if let rIndex = roadsideUnits.index( where: {$0.id == entityID} ) {
			convertEntity(roadsideUnits[rIndex], to: targetType)
			return
		}

		// Try to match to a parked car
		if let pIndex = parkedCars.index( where: {$0.id == entityID} ) {
			convertEntity(parkedCars[pIndex], to: targetType)
			return
		}

		// If nothing is matched, abort
		print("Error: Tried to convert entity not in present in the city.")
		exit(EXIT_FAILURE)
	}



	/*** END TRIP ACTIONS ***/

	/* One of these routines can be executed when a vehicle ends its trip in the FDC data.
	* The routines can, e.g., simply remove the vehicle, park the vehicle, park and convert the
	* vehicle to an RSU immediately, park the first N vehicles and remove the rest, etcetera.
	* Pick a routine and assign it to 'endTripRoutine' inside endTripHook() above.
	*/
	// Remove vehicles that end their trips
	func endTripRemoveVehicle(vehicleID v_id: UInt) {
		removeEntity(entityType: .vehicle, id: v_id)
	}

	// Convert all vehicles that end their trips to RoadsideUnits
	func endTripConvertToRSU(vehicleID v_id: UInt) {
		convertEntity(v_id, to: .roadsideUnit)
	}

	// Convert all vehicles that end their trips to parked cars
	func endTripConvertToParkedCar(vehicleID v_id: UInt) {
		convertEntity(v_id, to: .parkedCar)
	}
}
