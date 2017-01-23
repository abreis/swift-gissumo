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
	// Payload buffer to store coverage map request replies
	var payloadBuffer = [Payload]()

	// Flag to mark whether we are requesting coverage maps
	var isRequestingMaps: Bool = false

	// Initialize the local coverage map
	lazy var selfCoverageMap: CellMap<Int> = CellMap<Int>(ofSize: (x: self.city.network.selfCoverageMapSize, y: self.city.network.selfCoverageMapSize), withValue: 0, geographicCenter: self.geo)
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

	/// Automatically determine bounds and cell map sizes from FCD data
	func determineBounds(fromFCD trips: [FCDTimestep]) {
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


	/// Match a vehicle ID to a Vehicle entity
	func get(vehicleFromID vid: UInt) -> Vehicle? {
		if let vIndex = vehicles.index( where: { $0.id == vid } ) {
			return vehicles[vIndex]
		} else { return nil }
	}


	/// Match a vehicle GID to a Vehicle entity
	func get(vehicleFromGID vgid: UInt) -> Vehicle? {
		if let vIndex = vehicles.index( where: { $0.gid == vgid } ) {
			return vehicles[vIndex]
		} else { return nil }
	}

	/// Match a vehicle GID to a Vehicle entity
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

		// NOTE: Removed the decision process
//		// Schedule a decision trigger event
//		let decisionTriggerEvent = SimulationEvent(time: events.now + decision.triggerDelay, type: .decision, action: { self.decision.algorithm.trigger(newParkedCar) }, description: "decisionTrigger id\(newParkedCar.id)")
//		events.add(newEvent: decisionTriggerEvent)

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
						print("Error: Trying to remove a non-existent vehicle.")
						exit(EXIT_FAILURE)
			}
			eGID = rGID
			// Remove the roadside unit from the City
			roadsideUnits.remove(at: rIndex)
		case .parkedCar:
			guard	let pIndex = parkedCars.index( where: {$0.id == e_id} ),
					let pGID = parkedCars[pIndex].gid else {
						print("Error: Trying to remove a non-existent vehicle.")
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

	/// Action to perform on vehicles that end their FCD trips
	func endTripHook(vehicleID v_id: UInt) {
		// Pick the routine to be ran whenever a vehicle ends its trip here
		let endTripRoutineForVehicle: (UInt)->() = endTripConvertToParkedCar
		let routineName = "endTripConvertToParkedCar" // For debugging, match the name in the previous line

		// Schedule an event right away for the end trip action
		let endTripEvent = SimulationEvent(time: events.now + events.minTimestep, type: .mobility, action: { endTripRoutineForVehicle(v_id) }, description: "\(routineName) id \(v_id)")
		events.add(newEvent: endTripEvent)
	}

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
	var targetNumberOfParkedCarsReached = false
	func endTripConvertToParkedCar(vehicleID v_id: UInt) {
		// NOTE: Static configuration of simulation parameters:
		let targetNumberOfParkedCars = 100
		let timeToBuildCoverageMaps = 350

		// Limit the number of parked cars to a predefined value
		if parkedCars.count < targetNumberOfParkedCars {
			convertEntity(v_id, to: .parkedCar)
		} else {
			// One-time code, the first time the above if condition is false
			if !targetNumberOfParkedCarsReached {
				targetNumberOfParkedCarsReached = true

				// When that value is reached, allow time for parked cars to build their coverage maps, and then run the coverage analysis
				let analysisEvent = SimulationEvent(time: events.now + SimulationTime(seconds: timeToBuildCoverageMaps), type: .statistics, action: { self.analyzeParkedCarCombinations() }, description: "analyzeParkedCarCombinations")
				events.add(newEvent: analysisEvent)
			}
		}
	}

	// NOTE: Routine to analyze combinations of parked cars
	func analyzeParkedCarCombinations() {
		// Output statistics
		if debug.contains("City.analyzeCombinations()"){
			print("\(events.now.asSeconds) City.analyzeCombinations():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Analyzing combinations, \(parkedCars.count) parked cars in the city.") }

		// Run through every parked car, performing the analysis
		for (pcIndex,parkedCar) in parkedCars.enumerated() {
			/// 1. Create an array with the selected parked car and its neighbors
			var parkedCarArray: [ParkedCar] = []
			parkedCarArray.append(parkedCar)

			// Get its neighbors
			var neighborGIDs: [UInt]
			if gis.useHaversine {
				neighborGIDs = getFeatureGIDs(inCircleWithRadius: network.maxRange, center: parkedCar.geo, featureTypes: [.parkedCar] )
			} else {
				neighborGIDs = gis.getFeatureGIDs(inCircleWithRadius: network.maxRange, center: parkedCar.geo, featureTypes: [.parkedCar])
			}

			// Pull parked cars from the GIDs that were found
			for pGID in neighborGIDs {
				guard let neighborParkedCar = get(parkedCarFromGID: pGID)
					else { print("Error: Couldn't match a GID to a parked car.\n"); exit(EXIT_FAILURE) }
				parkedCarArray.append(neighborParkedCar)
			}

			/// 2. From the parkedCarArray, evaluate combinations with parkedCar as a reference

			// Array with the coverage maps of every parked car
			let coverageMapArray = parkedCarArray.map({$0.selfCoverageMap})
			// An empty map large enough for all of the neighbors' maps, that can be cloned easily
			let emptyMap = CellMap<Int>(toContainMaps: coverageMapArray, withValue: 0)
			// Number of possible combinations to evaluate
			let numberOfCombinations = Int(pow(2.0,Double(coverageMapArray.count)))
			// Our reference map is a large map with the selected parked car applied to it
			var referenceMap = emptyMap
			referenceMap.incrementSaturation(fromSignalMap: parkedCar.selfCoverageMap)

			// Debug
			if debug.contains("City.analyzeCombinations()"){
				print("\(events.now.asSeconds) City.analyzeCombinations():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Parked car \(pcIndex+1) has:\tGID \(parkedCar.gid!)\tneighborhood: \(neighborGIDs.count)\tcombinations: \(numberOfCombinations)") }

			// Run through every possible combination
			for combination in 0..<numberOfCombinations {
				// Make this combination into a binary string
				let combinationBinary = String(String(combination, radix: 2).characters.reversed()).padding(toLength: coverageMapArray.count, withPad: "0", startingAt: 0)

				// Clone the empty map
				var combinationMapOfCoverage = emptyMap
				var combinationMapOfSaturation = emptyMap

				// Run through the bits
				for (combinationIndex,combinationBit) in combinationBinary.characters.enumerated() where combinationBit=="1" {
					// Apply the maps where the combination bit is positive
					combinationMapOfCoverage.keepBestSignal(fromSignalMap: coverageMapArray[combinationIndex])
					combinationMapOfSaturation.incrementSaturation(fromSignalMap: coverageMapArray[combinationIndex])
				}

				// Create two measurement entries
				var coverageMeasurement = Measurement()
				var saturationMeasurement = Measurement()

				// Now run through every cell in the reference map; if it's not '0', then pull the same cell in the combination maps into the measurements
				for i in 0..<referenceMap.size.y {
					for j in 0..<referenceMap.size.x {
						if referenceMap.cells[i][j] != 0 {
							coverageMeasurement.add(Double(combinationMapOfCoverage.cells[i][j]))
							saturationMeasurement.add(Double(combinationMapOfSaturation.cells[i][j]))
						}
					}
				}

				// Report on the measurements
				stats.writeToHook("combinationAnalysis", data: "\(parkedCar.id)\(stats.separator)\(combinationBinary)\(stats.separator)\(combinationBinary.characters.reduce(0, { if $1 == "1" {return $0+1} else {return $0} }))\(stats.separator)\(coverageMeasurement.mean)\(stats.separator)\(coverageMeasurement.stdev)\(stats.separator)\(saturationMeasurement.mean)\(stats.separator)\(saturationMeasurement.stdev)\(stats.terminator)")
			}

			/// Force end simulation
			// Dump all events from the main event list except the first (ourselves)
			// We only need the final (cleanup stage) events to write statistics to files
			events.list.removeAll()
		}
	}
}
