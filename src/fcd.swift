/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class FCDVehicle {
	let id: UInt
	let geo: (x: Double, y: Double)

	init(id v_id: UInt, geo v_geo: (x: Double, y: Double)) {
		id = v_id
		geo = v_geo
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

/* Load Floating Car Data onto an XMLIndexer object (DEPRECATED)
 * Datasets can be of considerable size and are usually only iterated on once,
 * so we memmap the file and process the XML lazily. This routine should be
 * near-instantaneous.
 */
func loadFloatingCarData(fromFile fcdFile: String) throws -> XMLIndexer {
	// See if the file exists
	let fcdFileURL = URL(fileURLWithPath: fcdFile)
	guard (fcdFileURL as NSURL).checkResourceIsReachableAndReturnError(nil) else {
		throw FloatingCarDataError.fileError
	}

	// Parse XML Floating Car Data
	guard let fcdData = try? Data(contentsOf: fcdFileURL, options: [.mappedIfSafe, .uncached] ) else {
		throw FloatingCarDataError.unableToParse
	}

	// Create an XML indexer for the FCD data
	let fcdXML = SWXMLHash.config {
		config in
		config.shouldProcessLazily = true
		}.parse(fcdData)

	return fcdXML
}

// Parse the Floating Car Data into an FCDTimestep array (DEPRECATED)
func parseFloatingCarData(fromXML fcdXML: XMLIndexer, stopTime configStopTime: Double) throws -> [FCDTimestep] {
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
				let v_id = UInt(s_id),
				let v_xgeo = Double(s_xgeo),
				let v_ygeo = Double(s_ygeo)
				else {
					throw FloatingCarDataError.failedConversion
			}
			timestepVehicles.append( FCDVehicle(id: v_id, geo: (x: v_xgeo, y: v_ygeo)) )
		}
		fcdTrips.append( FCDTimestep(time: timestepTime, vehicles: timestepVehicles) )
	}
	return fcdTrips
}
