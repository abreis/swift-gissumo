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
enum FloatingCarDataError: Error, CustomStringConvertible{
	case fileError
	case unableToParse
	case invalidTimestamp
	case failedConversion

	var description: String {
		switch self {
		case .fileError: return "Unable to read data file."
		case .unableToParse: return "Unable to parse XML data from file."
		case .invalidTimestamp: return "Invalid timestep entry."
		case .failedConversion:	return "Unable to convert vehicle properties."
		}
	}
}

func loadFloatingCarData(fromFile fcdFile: String, stopTime configStopTime: Double) throws -> [FCDTimestep] {
	// See if the file exists
	let fcdFileURL = URL(fileURLWithPath: fcdFile)
	guard (fcdFileURL as NSURL).checkResourceIsReachableAndReturnError(nil) else {
		throw FloatingCarDataError.fileError
	}

	// Parse XML Floating Car Data
	guard let fcdData = try? Data(contentsOf: fcdFileURL) else {
			throw FloatingCarDataError.unableToParse
	}
	let fcdXML = SWXMLHash.parse(fcdData)

	// Load data onto our Trips array
	var fcdTrips = [FCDTimestep]()
	timestepLoop: for timestep in fcdXML["fcd-export"]["timestep"] {
		guard let timestepElement = timestep.element,
			let s_time = timestepElement.attribute(by: "time")?.text,
			let timestepTime = Double(s_time)
			else {
				throw FloatingCarDataError.invalidTimestamp
		}

		// Don't load timesteps that occur later than the simulation stopTime
		if timestepTime > configStopTime { break timestepLoop }

		var timestepVehicles = [FCDVehicle]()
		for vehicle in timestep["vehicle"] {
			guard let vehicleElement = vehicle.element,
				let s_id = vehicleElement.attribute(by: "id")?.text,
				let s_xgeo = vehicleElement.attribute(by: "x")?.text,
				let s_ygeo = vehicleElement.attribute(by: "y")?.text,
				let s_speed = vehicleElement.attribute(by: "speed")?.text,
				let v_id = UInt(s_id),
				let v_xgeo = Double(s_xgeo),
				let v_ygeo = Double(s_ygeo),
				let v_speed = Double(s_speed)
				else {
					throw FloatingCarDataError.failedConversion
			}
			timestepVehicles.append( FCDVehicle(id: v_id, geo: (x: v_xgeo, y: v_ygeo), speed: v_speed) )
		}
		fcdTrips.append( FCDTimestep(time: timestepTime, vehicles: timestepVehicles) )
	}
	return fcdTrips
}
