/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class FCDVehicle {
	let id: UInt
	let geo: (x: Double, y: Double)
	let speed: Double

	init(id v_id: UInt, geo v_geo: (x: Double, y: Double), speed v_speed: Double) {
		id = v_id
		geo = v_geo
		speed = v_speed
	}
}

class FCDTimestep {
	let time: Double
	let vehicles: [FCDVehicle]
	init(time intime: Double, vehicles invehicles: [FCDVehicle]) {
		time = intime
		vehicles = invehicles
	}
}

/* Load floating car data from an XML file
 * - Check for floatingCarDataFile config entry
 * - See if file exists
 * - Parse XML
 */
func loadFloatingCarData(fromFile fcdFile: String, stopTime configStopTime: Double) -> [FCDTimestep] {
	// See if the file exists
	let fcdFileURL = NSURL.fileURLWithPath(fcdFile)
	var fcdFileError: NSError?
	guard fcdFileURL.checkResourceIsReachableAndReturnError(&fcdFileError) else {
		print(" failed\n", fcdFileError)
		exit(EXIT_FAILURE)
	}

	// Parse XML Floating Car Data
	guard let fcdData = NSData(contentsOfURL: fcdFileURL)
		else {
			print(" failed", "\nError: Unable to parse XML data from file.")
			exit(EXIT_FAILURE)
	}
	let fcdXML = SWXMLHash.parse(fcdData)

	// Load data onto our Trips array
	var fcdTrips = [FCDTimestep]()
	timestepLoop: for timestep in fcdXML["fcd-export"]["timestep"] {
		guard let timestepElement = timestep.element,
			let s_time = timestepElement.attributes["time"],
			let timestepTime = Double(s_time)
			else {
				print(" failed", "\nError: Invalid timestep entry.")
				exit(EXIT_FAILURE)
		}

		// Don't load timesteps that occur later than the simulation stopTime
		if timestepTime > configStopTime { break timestepLoop }

		var timestepVehicles = [FCDVehicle]()
		for vehicle in timestep["vehicle"] {
			guard let vehicleElement = vehicle.element,
				let s_id = vehicleElement.attributes["id"],
				let s_xgeo = vehicleElement.attributes["x"],
				let s_ygeo = vehicleElement.attributes["y"],
				let s_speed = vehicleElement.attributes["speed"],
				let v_id = UInt(s_id),
				let v_xgeo = Double(s_xgeo),
				let v_ygeo = Double(s_ygeo),
				let v_speed = Double(s_speed)
				else {
					print(" failed", "\nError: Unable to convert vehicle properties.")
					exit(EXIT_FAILURE)
			}
			timestepVehicles.append( FCDVehicle(id: v_id, geo: (x: v_xgeo, y: v_ygeo), speed: v_speed) )
		}
		fcdTrips.append( FCDTimestep(time: timestepTime, vehicles: timestepVehicles) )
	}
	return fcdTrips
}