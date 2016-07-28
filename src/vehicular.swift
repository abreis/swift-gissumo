/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

class Vehicle {
	var id: UInt
	var gid: UInt?
	var geo: (x: Double, y: Double)
	var speed: Double?
	var creationTime: Double?
	var active: Bool = true

	init(id v_id: UInt, gid v_gid: UInt, xgeo v_xgeo: Double, ygeo v_ygeo: Double) {
		id = v_id
		gid = v_gid
		geo.x = v_xgeo
		geo.y = v_ygeo
	}

	init(createFromFCDVehicle fcdv: FCDVehicle, creationTime ctime: Double?) {
		id = fcdv.id
		geo.x = fcdv.geo.x
		geo.y = fcdv.geo.y
		speed = fcdv.speed
		if let time = ctime { creationTime = time }
	}
}

class City {
	// Vehicles in the city
	var vehicles = [Vehicle]()

	// City bounds. Initialize with the WGS84 bounds.
	var bounds = (
		x: (min:  180.0, max: -180.0),
		y: (min:   90.0, max:  -90.0)
	)

	// City size in cells
	var cells = (x: UInt(0), y:UInt(0))

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
			print("DEBUG City.init(fromFCD)".cyan(),":\t", "City bounds are (", bounds.x.min, bounds.y.min, ") (", bounds.x.max, bounds.y.max, ")") }

		// Now determine the size of the map in cells
		cells.x = UInt( ceil(bounds.x.max*3600) - floor(bounds.x.min*3600) )
		cells.y = UInt( ceil(bounds.y.max*3600) - floor(bounds.y.min*3600) )

		if debug.contains("City.init(fromFCD)"){
			print("DEBUG City.init(fromFCD)".cyan(),":\t", "City cell size is ", cells.x, "x", cells.y) }

	} // end init(fromFCD:)
}