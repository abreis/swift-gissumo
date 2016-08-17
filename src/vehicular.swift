/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

enum RoadEntityType {
	case Vehicle
	case RoadsideUnit
	case ParkedCar
}

// A basic road entity, with an ID, GIS ID, geographic location, time of creation, and the city it belongs to
class RoadEntity {
	var id: UInt
	var city: City
	var geo: (x: Double, y: Double)

	var gid: UInt?
	var creationTime: SimulationTime?

	init(id v_id: UInt, geo v_geo:(x:Double, y:Double), city v_city: City, creationTime ctime: SimulationTime?) {
		id = v_id
		geo.x = v_geo.x
		geo.y = v_geo.y
		city = v_city
		if let time = ctime { creationTime = time }
	}
}

// A vehicle entity
// Has a speed entry and an active tag
class Vehicle: RoadEntity {
	var speed: Double?
	var active: Bool = true
}

// A parked car
class ParkedCar: Vehicle {

}

// A roadside unit entity
enum RoadsideUnitType {
	case Fixed
	case Mobile
	case ParkedCar
}

class RoadsideUnit: RoadEntity {
	var type: RoadsideUnitType = .ParkedCar

	// Initialize the local coverage map
	lazy var selfCoverageMap: CellMap<Int> = CellMap<Int>(ofSize: (x: self.city.network.selfCoverageMapSize, y: self.city.network.selfCoverageMapSize), withValue: 0, geographicCenter: self.geo)
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
			if debug.contains("City.determineBounds()"){
				print("\(events.now.asSeconds) City.determineBounds():\t".cyan(), "City inner bounds", innerBounds!, "cell size", innerCellSize!, "top left cell", innerTopLeftCell!) }
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
	init(gis ingis: GIS, network innet: Network, eventList inevents: EventList, statistics instats: Statistics) {
		network = innet
		gis = ingis
		events = inevents
		stats = instats
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
			print("\(events.now.asSeconds) City.determineBounds():\t".cyan(), "City bounds", bounds, "cell size", cellSize, "top left cell", topLeftCell) }
	}


	/// Match a vehicle ID to a Vehicle entity
	func get(vehicleFromID vid: UInt) -> Vehicle? {
		if let vIndex = vehicles.indexOf( { $0.id == vid } ) {
			return vehicles[vIndex]
		} else { return nil }
	}


	/// Match a vehicle GID to a Vehicle entity
	func get(vehicleFromGID vgid: UInt) -> Vehicle? {
		if let vIndex = vehicles.indexOf( { $0.gid == vgid } ) {
			return vehicles[vIndex]
		} else { return nil }
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

	/// Add a new vehicle to the City and to GIS
	func addNewVehicle(id v_id: UInt, geo v_geo: (x: Double, y: Double)) -> UInt {
		let newVehicle = Vehicle(id: v_id, geo: v_geo, city: self, creationTime: events.now)

		// Add the new vehicle to GIS and record its GIS ID
		newVehicle.gid = gis.addPoint(ofType: .Vehicle, geo: newVehicle.geo, id: newVehicle.id)

		// Append the new vehicle to the city's vehicle list
		vehicles.append(newVehicle)

		// Schedule an initial recurrent beaconing
		let newBeaconEvent = SimulationEvent(time: events.now + network.beaconingInterval, type: .Network, action: {newVehicle.recurrentBeaconing()}, description: "firstBroadcastBeacon vehicle \(newVehicle.id)")
		events.add(newEvent: newBeaconEvent)

		// Debug
		if debug.contains("City.addNewVehicle()") {
			print("\(events.now.asSeconds) City.addNewVehicle():\t".cyan(), "Create vehicle id", newVehicle.id, "gid", newVehicle.gid!, "at", newVehicle.geo)
		}

		return newVehicle.gid!
	}


	/// Add a new RoadsideUnit to the City and to GIS, returning its GID
	func addNewRSU(id r_id: UInt, geo r_geo: (x: Double, y: Double), type r_type: RoadsideUnitType) -> UInt {
		let newRSU = RoadsideUnit(id: r_id, geo: r_geo, city: self, creationTime: events.now)
		newRSU.type = r_type

		// Add the new RSU to GIS and record its GIS ID
		newRSU.gid = gis.addPoint(ofType: .RoadsideUnit, geo: newRSU.geo, id: newRSU.id)

		// Append the new vehicle to the city's vehicle list
		roadsideUnits.append(newRSU)

		// Debug
		if debug.contains("City.addNewRSU()") {
			print("\(events.now.asSeconds) City.addNewRSU():\t".cyan(), "Create RSU id", newRSU.id, "gid", newRSU.gid!, "at", newRSU.geo)
		}

		return newRSU.gid!
	}


	/// Update the location of a vehicle in this City and on GIS
	func updateVehicleLocation(id v_id: UInt, geo new_geo: (x: Double, y: Double)) {
		guard	let vIndex = vehicles.indexOf( {$0.id == v_id} ),
				let vGID = vehicles[vIndex].gid
				else {
					print("Error: Trying to update a non-existent vehicle.")
					exit(EXIT_FAILURE)
		}

		// Update the vehicle coordinates
		vehicles[vIndex].geo = new_geo

		// Move the corresponding point in GIS
		gis.updatePoint(withGID: vGID, geo: new_geo)

		// Debug
		if debug.contains("City.updateVehicleLocation()") {
			print("\(events.now.asSeconds) City.updateVehicleLocation():\t".cyan(), "Update vehicle id", vehicles[vIndex].id, "gid", vGID, "to coordinates", vehicles[vIndex].geo)
		}
	}


	/// Remove a vehicle from the City and from GIS
	func removeVehicle(id v_id: UInt) {
		guard	let vIndex = vehicles.indexOf( {$0.id == v_id} ),
				let vGID = vehicles[vIndex].gid
				else {
					print("Error: Trying to remove a non-existent vehicle.")
					exit(EXIT_FAILURE)
		}

		// Mark the vehicle as inactive
		vehicles[vIndex].active = false

		// Remove the vehicle from the City
		vehicles.removeAtIndex(vIndex)

		// Clear the corresponding point from GIS
		gis.deletePoint(withGID: vGID)

		// Debug
		if debug.contains("City.removeVehicle()") {
			print("\(events.now.asSeconds) City.removeVehicle():\t".cyan(), "Removed vehicle id", v_id, "gid", vGID)
		}
	}

	/// Generic conversion routine to create parked cars from vehicles, RSUs from parked cars, etcetera
	func convertEntity(entity: RoadEntity, to targetType: RoadEntityType) {
		guard let vGID = entity.gid else {
			print("Error: Tried to convert a RoadEntity with no GID.")
			exit(EXIT_FAILURE)
		}

		// GID of the new entity
		var newEntityGID: UInt?

		// From vehicle to...
		if let vehicle = entity as? Vehicle {
			// Ensure we're converting a vehicle that's part of the city
			guard let vIndex = vehicles.indexOf( {$0 === entity} )	else {
						print("Error: Trying to convert a vehicle not in the city.")
						exit(EXIT_FAILURE)
			}

			// Perform the requested conversion
			switch targetType {
			case .RoadsideUnit:
				// Mark the vehicle as inactive
				vehicle.active = false
				// Remove the vehicle from GIS to avoid potential ID collisions
				gis.deletePoint(withGID: vGID)
				// Create a new parked car RoadsideUnit from the Vehicle
				newEntityGID = addNewRSU(id: entity.id, geo: entity.geo, type: .ParkedCar)
				// Remove the vehicle from the City
				vehicles.removeAtIndex(vIndex)
			case .ParkedCar:
				// TODO
				break
			case .Vehicle:
				print("Error: Attempted to convert a Vehicle to a Vehicle again.")
				exit(EXIT_FAILURE)
			}
		}

		// From parked car to...
		// TODO

		// From RSU to...
		// TODO

		// Debug
		if debug.contains("City.convertEntity()") {
			print("\(events.now.asSeconds) City.convertEntity():\t".cyan(), "Converted a", entity.dynamicType , "id", entity.id, "gid", vGID, "to a", targetType, "gid", newEntityGID!)
		}
	}

	// Convenience function that first tries to locate the entity in the city's entity lists
	func convertEntity(entityID: UInt, to targetType: RoadEntityType) {
		// Try to match to a vehicle
		if let vIndex = vehicles.indexOf( {$0.id == entityID} ) {
			convertEntity(vehicles[vIndex], to: targetType)
			return
		}

		// Try to match to a roadside unit
		if let rIndex = roadsideUnits.indexOf( {$0.id == entityID} ) {
			convertEntity(roadsideUnits[rIndex], to: targetType)
			return
		}

		// Try to match to a parked car
		if let pIndex = parkedCars.indexOf( {$0.id == entityID} ) {
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
		let endTripRoutine = endTripConvertToRSU
		let routineName = "endTripConvertToRSU" // For debugging, match the name in the previous line

		// Schedule an event right away for the end trip action
		let endTripEvent = SimulationEvent(time: events.now + events.minTimestep, type: .Mobility, action: { endTripRoutine(vehicleID: v_id) }, description: "\(routineName) id \(v_id)")
		events.add(newEvent: endTripEvent)
	}

	/* One of these routines can be executed when a vehicle ends its trip in the FDC data.
	* The routines can, e.g., simply remove the vehicle, park the vehicle, park and convert the
	* vehicle to an RSU immediately, park the first N vehicles and remove the rest, etcetera.
	* Pick a routine and assign it to 'endTripRoutine' inside endTripHook() above.
	*/
	// Remove vehicles that end their trips
	func endTripRemoveVehicle(vehicleID v_id: UInt) {
		removeVehicle(id: v_id)
	}

	// Convert all vehicles that end their trips to RoadsideUnits
	func endTripConvertToRSU(vehicleID v_id: UInt) {
		convertEntity(v_id, to: .RoadsideUnit)
	}

	// Convert all vehicles that end their trips to parked cars
	func endTripConvertToParkedCar(vehicleID v_id: UInt) {
		convertEntity(v_id, to: .ParkedCar)
	}
}
