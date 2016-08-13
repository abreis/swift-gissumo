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

guard let statisticsConfig = config["stats"] as? NSDictionary else {
	print("Error: Please provide a statistics entry in the configuration.")
	exit(EXIT_FAILURE)
}

print(" okay")



/* Load floating car data from an XML file
 */
print("Loading floating car data...", terminator: "")

guard let fcdFile = config["floatingCarDataFile"] as? String else {
	print(" failed", "\nError: Please specify a valid SUMO FCD file with 'floatingCarDataFile'.")
	exit(EXIT_FAILURE)
}

var fcdTrips: [FCDTimestep]
do {
	try fcdTrips = loadFloatingCarData(fromFile: fcdFile, stopTime: configStopTime)
} catch let error as FloatingCarDataError {
	print(" failed", "\nError:", error.description)
	exit(EXIT_FAILURE)
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
let buildingCount = gisdb.countFeatures(withType: .Building)
print(" okay")
print("\tSaw", buildingCount, "buildings in the database")




/********************/
/*** MAIN ROUTINE ***/
/********************/


/* Initialize a new City, plus a new network, a new eventlist, and a new statistics module
 */
var simCity = City(gis: gisdb, network: Network(), eventList: EventList(stopTime: configStopTime), statistics: Statistics(config: statisticsConfig))

// Load city characteristics, bounds, cell size from the FCD trips
simCity.determineBounds(fromFCD: fcdTrips)

// Store inner city bounds from configuration file
simCity.innerBounds = cityInnerBounds

// Clear all points from the database
print("Clearing old features from GIS...", terminator: "")
simCity.gis.clearFeatures(withType: .Vehicle)
simCity.gis.clearFeatures(withType: .RoadsideUnit)
simCity.gis.clearFeatures(withType: .ParkedCar)
print(" okay")

// Add statistics collection events to the eventlist
print("Scheduling collection events...", terminator: "")
simCity.stats.scheduleCollectionEvents(onCity: simCity)
print(" okay")

// Add mobility timestep events to the eventlist
print("Scheduling mobility events...", terminator: "")
simCity.events.scheduleMobilityEvents(fromFCD: &fcdTrips, city: simCity)
print(" okay")



/*** EVENT LOOP ***/
print("Running simulation events...", terminator: "")
repeat {
	guard let nextEvent = simCity.events.list.first else {
		print("Exhausted event list at time", simCity.events.now.milli)
		exit(EXIT_SUCCESS)
	}

	// Update current time
	assert(nextEvent.time > simCity.events.now)
	simCity.events.now = nextEvent.time

	if debug.contains("main().events"){
		print(String(format: "%.6f main():\t", simCity.events.now.milli).cyan(), "Executing", nextEvent.type, "event\t", nextEvent.description.darkGray())
	}
	nextEvent.action()
	simCity.events.list.removeFirst()

} while simCity.events.now < simCity.events.stopTime
print(" okay")


// Cleanup stage events
print("Running cleanup events...", terminator: "")
for event in simCity.events.cleanup {
	event.action()
	if debug.contains("main().events"){
		print("[cleanup] main():\t".cyan(), "Executing", event.type, "event\t", event.description.darkGray())
	}
}
print(" okay")


// Successful exit
print("Simulation complete.")
exit(EXIT_SUCCESS)
