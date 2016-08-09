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
enum FloatingCarDataError: ErrorType, CustomStringConvertible{
	case FileError
	case UnableToParse
	case InvalidTimestamp
	case FailedConversion

	var description: String {
		switch self {
		case .FileError: return "Unable to read data file."
		case .UnableToParse: return "Unable to parse XML data from file."
		case .InvalidTimestamp: return "Invalid timestep entry."
		case .FailedConversion:	return "Unable to convert vehicle properties."
		}
	}
}

func loadFloatingCarData(fromFile fcdFile: String, stopTime configStopTime: Double) throws -> [FCDTimestep] {
	// See if the file exists
	let fcdFileURL = NSURL.fileURLWithPath(fcdFile)
	guard fcdFileURL.checkResourceIsReachableAndReturnError(nil) else {
		throw FloatingCarDataError.FileError
	}

	// Parse XML Floating Car Data
	guard let fcdData = NSData(contentsOfURL: fcdFileURL) else {
			throw FloatingCarDataError.UnableToParse
	}
	let fcdXML = SWXMLHash.parse(fcdData)

	// Load data onto our Trips array
	var fcdTrips = [FCDTimestep]()
	timestepLoop: for timestep in fcdXML["fcd-export"]["timestep"] {
		guard let timestepElement = timestep.element,
			let s_time = timestepElement.attributes["time"],
			let timestepTime = Double(s_time)
			else {
				throw FloatingCarDataError.InvalidTimestamp
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
					throw FloatingCarDataError.FailedConversion
			}
			timestepVehicles.append( FCDVehicle(id: v_id, geo: (x: v_xgeo, y: v_ygeo), speed: v_speed) )
		}
		fcdTrips.append( FCDTimestep(time: timestepTime, vehicles: timestepVehicles) )
	}
	return fcdTrips
}