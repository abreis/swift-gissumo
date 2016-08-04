/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class RoadEntity {
	var id: UInt
	var gid: UInt?
	var geo: (x: Double, y: Double)
	var creationTime: Double?

	init(id v_id: UInt, gid v_gid: UInt?, geo v_geo:(x:Double, y:Double), creationTime ctime: Double?) {
		id = v_id
		gid = v_gid
		geo.x = v_geo.x
		geo.y = v_geo.y
		if let time = ctime { creationTime = time }
	}
}

// A vehicle entity
// Has a speed entry and an active tag
class Vehicle: RoadEntity {
	var speed: Double?
	var active: Bool = true

	// Standard init
	init(id v_id: UInt, gid v_gid: UInt?, v_geo:(x:Double, y:Double), creationTime ctime: Double?, speed v_speed: Double?) {
		super.init(id: v_id, gid: v_gid, geo: v_geo, creationTime: ctime)
		if let sspeed = v_speed { speed = sspeed }
	}

	// Initialize from an FCD vehicle entry
	init(createFromFCDVehicle fcdv: FCDVehicle, creationTime ctime: Double?) {
		super.init(id: fcdv.id, gid: nil, geo: fcdv.geo, creationTime: ctime)
		speed = fcdv.speed
	}
}

// A roadside unit entity
class RoadsideUnit: RoadEntity {
	enum RoadsideUnitType {
		case Fixed
		case Mobile
		case ParkedCar
	}

	var type: RoadsideUnitType = .ParkedCar
}

class City {
	// Vehicles in the city
	var vehicles = [Vehicle]()
	var roadsideUnits = [RoadsideUnit]()

	// City bounds (initialized with the WGS84 extreme bounds)
	var bounds = (
		x: (min:  180.0, max: -180.0),
		y: (min:   90.0, max:  -90.0)
	)

	// City size in cells
	var cells = (x: UInt(0), y:UInt(0))

	// Initialize a City from a list of timesteps, automatically determining bounds and cell map sizes
	init(inout fromFCD trips: [FCDTimestep]) {
		// Locate the min and max coordinate pairs of the vehicles in the supplied Floating Car Data. Run through every timestep and find min and max coordinates.
		for timestep in trips {
			for vehicle in timestep.vehicles {
				if vehicle.geo.x < bounds.x.min { bounds.x.min = vehicle.geo.x }
				if vehicle.geo.x > bounds.x.max { bounds.x.max = vehicle.geo.x }
				if vehicle.geo.y < bounds.y.min { bounds.y.min = vehicle.geo.y }
				if vehicle.geo.y > bounds.y.max { bounds.y.max = vehicle.geo.y }
			}
		}

		if debug.contains("City.init(fromFCD)"){
			print(String(format: "%.6f City.init(fromFCD):\t", now).cyan(), "City bounds are (", bounds.x.min, bounds.y.min, ") (", bounds.x.max, bounds.y.max, ")") }

		// Now determine the size of the map in cells
		cells.x = UInt( ceil(bounds.x.max*3600) - floor(bounds.x.min*3600) )
		cells.y = UInt( ceil(bounds.y.max*3600) - floor(bounds.y.min*3600) )

		if debug.contains("City.init(fromFCD)"){
			print(String(format: "%.6f City.init(fromFCD):\t", now).cyan(), "City cell size is ", cells.x, "x", cells.y) }

	} // end init(fromFCD:)

	// Match a vehicle ID to a Vehicle entity
	func get(vehicleFromID vid: UInt) -> Vehicle? {
		if let vIndex = vehicles.indexOf( { $0.id == vid } ) {
			return vehicles[vIndex]
		} else {
			return nil
		}
	}
}