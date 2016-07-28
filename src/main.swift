/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation


/**********************/
/*** INITIALIZATION ***/
/**********************/

/* Process command line options 
 */
guard Process.arguments.count == 2 && Process.arguments[1].hasSuffix(".plist")
 else {
	print("ERROR: Please supply a .plist configuration file.")
	exit(EXIT_FAILURE)
}



/* Load and validate configuration file
 */
print("Reading configuration file...", terminator: "")

let configFileURL = NSURL.fileURLWithPath(Process.arguments[1])
var configFileError : NSError?
guard configFileURL.checkResourceIsReachableAndReturnError(&configFileError)
 else {
	print(" failed\n", configFileError)
	exit(EXIT_FAILURE)
}

// Load plist into a configuration dictionary array
guard let config = NSDictionary(contentsOfURL: configFileURL)
 else {
	print(" failed", "\nError: Invalid configuration file format.")
	exit(EXIT_FAILURE)
}

print(" okay")

// Load debug variable
var debug = false
if let debugFromConfig = config["debug"] as? Bool {
	debug = debugFromConfig
	if debug { print("DEBUG main()".cyan(),":\t","Debug mode is active.") }
}



/* Load floating car data from an XML file
 * - Check for floatingCarDataFile config entry
 * - See if file exists
 * - Parse XML
 */
print("Loading floating car data...", terminator: "")

guard let fcdFile = config["floatingCarDataFile"] as? String
 else {
	print(" failed", "\nError: Please specify a valid SUMO FCD file with 'floatingCarDataFile'.")
	exit(EXIT_FAILURE)
}

// See if the file exists
let fcdFileURL = NSURL.fileURLWithPath(fcdFile)
var fcdFileError : NSError?
guard fcdFileURL.checkResourceIsReachableAndReturnError(&fcdFileError)
 else {
	print(" failed\n", fcdFileError)
	exit(EXIT_FAILURE)
}

// Parse XML Floating Car Data
guard let fcdData = NSData(contentsOfURL: fcdFileURL)
 else {
    print(" failed", "\nError: Unable to parse XML data from file.")
    exit(EXIT_FAILURE)
}

let fcdXML = SWXMLHash.lazy(fcdData)

// Load data onto our Trips array
var trips = [FCDTimestep]()
for timestep in fcdXML["fcd-export"]["timestep"] {
	guard let timestepElement = timestep.element,
			let s_time = timestepElement.attributes["time"],
			let timestepTime = Double(s_time)
	 else {
		print(" failed", "\nError: Invalid timestep entry.")
		exit(EXIT_FAILURE)
	}

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

	trips.append( FCDTimestep(time: timestepTime, vehicles: timestepVehicles) )
}

print(" okay")
print("\tLoaded", trips.count, "timesteps from data file")



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
let gis = GIS(parameters: databaseParams)
let buildingCount = gis.count(featureType: .Building)
print(" okay")
print("\tSaw", buildingCount, "buildings in the database")




/********************/
/*** MAIN ROUTINE ***/
/********************/

// Clear all points from the database
gis.clear(featureType: .Vehicle)

// Initialize a list of events
guard let sTime = config["stopTime"] as? Double
 else {
	print("Error: Please provide a simulation stop time in the configuration.")
	exit(EXIT_FAILURE)
}
var events = EventList(stopTime: sTime)


/*** EVENT LOOP ***/

repeat {
	guard let event = events.list.first
	 else { print("Exhausted event list at time", events.now); exit(EXIT_SUCCESS) }
	
	assert(event.time >= events.now)
	
	print("Executing event at time", event.time)
	event.action()
	events.list.removeFirst()
	
} while events.now < events.stopTime


exit(EXIT_SUCCESS)
