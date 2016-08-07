/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation


/**********************/
/*** INITIALIZATION ***/
/**********************/



/* Process command line options
 */
guard Process.arguments.count == 2 && Process.arguments[1].hasSuffix(".plist") else {
	print("ERROR: Please supply a .plist configuration file.")
	exit(EXIT_FAILURE)
}



/* Load and validate configuration file
 */
print("Reading configuration file...", terminator: "")

let configFileURL = NSURL.fileURLWithPath(Process.arguments[1])
var configFileError : NSError?
guard configFileURL.checkResourceIsReachableAndReturnError(&configFileError) else {
	print(" failed\n", configFileError)
	exit(EXIT_FAILURE)
}

// Load plist into a configuration dictionary array
guard let config = NSDictionary(contentsOfURL: configFileURL) else {
	print(" failed", "\nError: Invalid configuration file format.")
	exit(EXIT_FAILURE)
}

// Load stop time
guard let configStopTime = config["stopTime"] as? Double else {
	print("Error: Please provide a valid simulation stop time in the configuration.")
	exit(EXIT_FAILURE)
}

// Load debug variable
var debug = [String]()
if let debugConfig = config["debug"] as? NSDictionary {
	for element in debugConfig {
		if let enabled = element.value as? Bool where enabled == true {
			debug.append(String(element.key))
		}
	}
}

// Load inner bounds
var cityInnerBounds: Square?
if	let innerBoundsConfig = config["innerBounds"] as? NSDictionary,
	let innerX = innerBoundsConfig["x"] as? NSDictionary,
	let innerXmin = innerX["min"] as? Double,
	let innerXmax = innerX["max"] as? Double,
	let innerY = innerBoundsConfig["y"] as? NSDictionary,
	let innerYmin = innerY["min"] as? Double,
	let innerYmax = innerY["max"] as? Double {
		cityInnerBounds = Square(x: (min: innerXmin, max: innerXmax), y: (min: innerYmin, max: innerYmax))
}

print(" okay")



/* Load floating car data from an XML file
 * - Check for floatingCarDataFile config entry
 * - See if file exists
 * - Parse XML
 */
print("Loading floating car data...", terminator: "")

guard let fcdFile = config["floatingCarDataFile"] as? String else {
	print(" failed", "\nError: Please specify a valid SUMO FCD file with 'floatingCarDataFile'.")
	exit(EXIT_FAILURE)
}

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

print(" okay")
print("\tLoaded", fcdTrips.count, "timesteps from data file")



/* Initialize PostgreSQL connection
 */
print("Initializing GIS connection...", terminator: "")

guard	let gisConfig = config["gis"],
		let gisHost = gisConfig["host"] as? String,
		let gisPort = gisConfig["port"] as? Int,
		let gisDB = gisConfig["database"] as? String,
		let gisUser = gisConfig["user"] as? String,
		let gisPass = gisConfig["password"] as? String
		else {
			print(" failed", "\nError: Invalid database configuration.")
			exit(EXIT_FAILURE)
}

let databaseParams = ConnectionParameters(host: gisHost, port: String(gisPort), databaseName: gisDB, user: gisUser, password: gisPass)
let gisdb = GIS(parameters: databaseParams)
let buildingCount = gisdb.count(featureType: .Building)
print(" okay")
print("\tSaw", buildingCount, "buildings in the database")




/********************/
/*** MAIN ROUTINE ***/
/********************/


/* Initialize a new City, plus a new network, and a new eventlist
 */
var simCity = City(gis: gisdb, network: Network(), eventlist: EventList(stopTime: configStopTime))

// Load city characteristics, bounds, cell size from the FCD trips
simCity.determineBounds(fromFCD: fcdTrips)

// Store inner city bounds from configuration file
simCity.innerBounds = cityInnerBounds

// Clear all points from the database
simCity.gis.clear(featureType: .Vehicle)


// Add mobility timestep events to the eventlist
simCity.events.scheduleMobilityEvents(fromFCD: fcdTrips, city: simCity)


/*** EVENT LOOP ***/
repeat {
	guard let nextEvent = simCity.events.list.first else {
		print("Exhausted event list at time", simCity.events.now)
		exit(EXIT_SUCCESS)
	}

	// Update current time
	assert(nextEvent.time > simCity.events.now)
	simCity.events.now = nextEvent.time

	if debug.contains("main().events"){
		print(String(format: "%.6f main():\t", simCity.events.now).cyan(), "Executing", nextEvent.type, "event", nextEvent.description.darkGray())
	}
	nextEvent.action()
	simCity.events.list.removeFirst()

} while simCity.events.now < simCity.events.stopTime

print("Simulation completed")
exit(EXIT_SUCCESS)
