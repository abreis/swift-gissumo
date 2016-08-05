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

	// City bounds (initialized with the WGS84 extreme bounds)
	var bounds = (
		x: (min:  180.0, max: -180.0),
		y: (min:   90.0, max:  -90.0)
	)

	// City size in cells
	var cells = (x: UInt(0), y:UInt(0))

	/// Standard init, provide a database, network and eventlist
	init(gis ingis: GIS, network innet: Network, eventlist inevents: EventList) {
		network = innet
		gis = ingis
		events = inevents
	}

	/// Automatically determine bounds and cell map sizes from FCD data
	func determine(boundsfromFCD trips: [FCDTimestep]) {
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

		if debug.contains("City.init(fromFCD)"){
			print(String(format: "%.6f City.init(fromFCD):\t", events.now).cyan(), "City bounds are (", bounds.x.min, bounds.y.min, ") (", bounds.x.max, bounds.y.max, ")") }

		// Now determine the size of the map in cells
		cells.x = UInt( ceil(bounds.x.max*3600) - floor(bounds.x.min*3600) )
		cells.y = UInt( ceil(bounds.y.max*3600) - floor(bounds.y.min*3600) )

		if debug.contains("City.init(fromFCD)"){
			print(String(format: "%.6f City.init(fromFCD):\t", events.now).cyan(), "City cell size is ", cells.x, "x", cells.y) }
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
}
