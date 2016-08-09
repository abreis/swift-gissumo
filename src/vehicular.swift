/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

// A basic road entity, with an ID, GIS ID, geographic location, time of creation, and the city it belongs to
class RoadEntity {
	var id: UInt
	var city: City
	var geo: (x: Double, y: Double)

	var gid: UInt?
	var creationTime: Double?

	init(id v_id: UInt, geo v_geo:(x:Double, y:Double), city v_city: City, creationTime ctime: Double?) {
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

// A roadside unit entity
enum RoadsideUnitType {
	case Fixed
	case Mobile
	case ParkedCar
}

class RoadsideUnit: RoadEntity {
	var type: RoadsideUnitType = .ParkedCar

	// The size, in cells, of a local coverage map
	// Our coverage maps are 11x11, or ~330m wide (for an assumed radio range of 155m and average cell size of 30m)
	lazy var localCoverageMapSize: Int = Int(ceil(self.city.network.maxRange*2/30))

	// Initialize the local coverage map
	lazy var localCoverageMap: CellMap = CellMap(ofSize: (x: self.localCoverageMapSize, y: self.localCoverageMapSize), withValue: UInt(0), geographicCenter: self.geo)
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
	// Arrays for vehicles and roadside units in the city
	var vehicles = [Vehicle]()
	var roadsideUnits = [RoadsideUnit]()

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

	// Inner bounds for data analysis (supplied in configuration file)
	var innerBounds: Square?

	// City size in cells
	var cells = (x: UInt(0), y:UInt(0))

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

		if debug.contains("City.determineBounds(fromFCD)"){
			print(String(format: "%.6f City.determineBounds(fromFCD):\t", events.now).cyan(), "City bounds are (", bounds.x.min, bounds.y.min, ") (", bounds.x.max, bounds.y.max, ")") }

		// Now determine the size of the map in cells
		cells.x = UInt( ceil(bounds.x.max*3600) - floor(bounds.x.min*3600) )
		cells.y = UInt( ceil(bounds.y.max*3600) - floor(bounds.y.min*3600) )

		if debug.contains("City.determineBounds(fromFCD)"){
			print(String(format: "%.6f City.determineBounds(fromFCD):\t", events.now).cyan(), "City cell size is", cells.x, "x", cells.y) }
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
			print(String(format: "%.6f City.addNewVehicle():\t", events.now).cyan(), "Create vehicle id", newVehicle.id, "gid", newVehicle.gid!, "at", newVehicle.geo)
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
			print(String(format: "%.6f City.addNewRSU():\t", events.now).cyan(), "Create RSU id", newRSU.id, "gid", newRSU.gid!, "at", newRSU.geo)
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
			print(String(format: "%.6f City.updateVehicleLocation():\t", events.now).cyan(), "Update vehicle id", vehicles[vIndex].id, "gid", vGID, "to coordinates", vehicles[vIndex].geo)
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
			print(String(format: "%.6f City.removeVehicle():\t", events.now).cyan(), "Removed vehicle id", v_id, "gid", vGID)
		}
	}


	/// Removes a vehicle from the City and creates a parked car RSU in its place
	func convertVehicleToParkedCarRSU(id v_id: UInt) {
		guard	let vIndex = vehicles.indexOf( {$0.id == v_id} ),
				let vGID = vehicles[vIndex].gid
				else {
					print("Error: Trying to convert a non-existent vehicle to an RSU.")
					exit(EXIT_FAILURE)
		}

		// Mark the vehicle as inactive
		vehicles[vIndex].active = false

		// Remove the vehicle from GIS to avoid potential ID collisions
		gis.deletePoint(withGID: vGID)

		// Create a new RoadsideUnit from the Vehicle
		let newRSUgid = addNewRSU(id: vehicles[vIndex].id, geo: vehicles[vIndex].geo, type: .ParkedCar)

		// Remove the vehicle from the City
		vehicles.removeAtIndex(vIndex)

		// Debug
		if debug.contains("City.convertVehicleToParkedCarRSU()") {
			print(String(format: "%.6f City.convertVehicleToParkedCarRSU():\t", events.now).cyan(), "Converted vehicle id", v_id, "gid", vGID, "to an RSU gid", newRSUgid)
		}
	}
}
