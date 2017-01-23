/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation


/**********************/
/*** INITIALIZATION ***/
/**********************/


/* Process command line options
 */
guard CommandLine.arguments.count == 2 && CommandLine.arguments[1].hasSuffix(".plist") else {
	print("ERROR: Please supply a .plist configuration file.")
	exit(EXIT_FAILURE)
}



/* Load and validate configuration file
 */
print("Reading configuration file... ", terminator: ""); fflush(stdout)
let configFileURL = URL(fileURLWithPath: CommandLine.arguments[1])
do {
	guard try configFileURL.checkResourceIsReachable() else {
		print("failed\n", "\nError: Configuration file not found.")
		exit(EXIT_FAILURE)
	}
} catch {
	print("failed\n", error)
	exit(EXIT_FAILURE)
}


// Load plist into a configuration dictionary array
guard let config = NSDictionary(contentsOf: configFileURL) else {
	print("failed", "\nError: Invalid configuration file format.")
	exit(EXIT_FAILURE)
}

// Load stop time
guard let configStopTime = config["stopTime"] as? Double else {
	print("failed", "\nError: Please provide a valid simulation stop time in the configuration.")
	exit(EXIT_FAILURE)
}

// Load debug variable
var debug = [String]()
if let debugConfig = config["debug"] as? NSDictionary {
	for element in debugConfig {
		if let enabled = element.value as? Bool, enabled == true {
			debug.append(String(describing: element.key))
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

// Load statistics configuration point
guard let statisticsConfig = config["stats"] as? NSDictionary else {
	print("failed", "\nError: Please provide a statistics entry in the configuration.")
	exit(EXIT_FAILURE)
}

// Load decision configuration point
guard let decisionConfig = config["decision"] as? NSDictionary else {
	print("failed", "\nError: Please provide a decision entry in the configuration.")
	exit(EXIT_FAILURE)
}

print("okay")



/* Initialize PostgreSQL connection
*/
print("Initializing GIS connection... ", terminator: ""); fflush(stdout)

guard	let gisConfig = config["gis"] as? NSDictionary,
		let gisHost = gisConfig["host"] as? String,
		let gisPort = gisConfig["port"] as? Int,
		let gisDB = gisConfig["database"] as? String,
		let gisUser = gisConfig["user"] as? String,
		let gisPass = gisConfig["password"] as? String,
		let sridConfig = config["locationSRID"] as? UInt,
		let useHaversineConfig = config["useHaversine"] as? Bool
	else {
		print("failed", "\nError: Invalid database configuration.")
		exit(EXIT_FAILURE)
}

let databaseParams = "host=\(gisHost) port=\(String(gisPort)) dbname=\(gisDB) user=\(gisUser) password=\(gisPass)"
let gisdb = GIS(parameters: databaseParams, srid: sridConfig, inUseHaversine: useHaversineConfig )
let buildingCount = gisdb.countFeatures(withType: .building)
print("okay")
print("\tSaw", buildingCount, "buildings in the database")



/* Load floating car data from an XML file
 */
print("Loading floating car data... ", terminator: ""); fflush(stdout)

guard let fcdFile = config["floatingCarDataFile"] as? String else {
	print("failed", "\nError: Please specify a valid SUMO FCD file with 'floatingCarDataFile'.")
	exit(EXIT_FAILURE)
}

var fcdTrips: [FCDTimestep]
do {
	try fcdTrips = loadFloatingCarData(fromFile: fcdFile, stopTime: configStopTime)
} catch let error as FloatingCarDataError {
	print("failed", "\nError:", error.description)
	exit(EXIT_FAILURE)
}

print("okay")
print("\tLoaded", fcdTrips.count, "timesteps from data file")


/* To build an obstruction cell mask, jump here.
 */
if	let toolsConfig = config["tools"] as? NSDictionary,
	let buildMask = toolsConfig["buildObstructionMask"] as? Bool, buildMask == true
{
	print("Building obstruction mask... ", terminator: ""); fflush(stdout)
	do {
		try buildObstructionMask(fromTrips: fcdTrips)
	} catch {
		print("failed", "\nError:", error)
		exit(EXIT_FAILURE)
	}
	print("okay")
	print("\tBuilt a map of obstructions from \(fcdTrips.count) steps.")
	exit(EXIT_SUCCESS)
}



/********************/
/*** MAIN ROUTINE ***/
/********************/


/* Initialize a new City, plus a new network, a new eventlist, a new statistics module, and a new decision module
 */
var simCity = City(gis: gisdb, network: Network(), eventList: EventList(stopTime: configStopTime), statistics: Statistics(config: statisticsConfig), decision: Decision(config: decisionConfig))

// Load city characteristics, bounds, cell size from the FCD trips
simCity.determineBounds(fromFCD: fcdTrips)

// Store inner city bounds from configuration file
simCity.innerBounds = cityInnerBounds

// Clear all points from the database
print("Clearing old features from GIS... ", terminator: ""); fflush(stdout)
simCity.gis.clearFeatures(withType: .vehicle)
simCity.gis.clearFeatures(withType: .roadsideUnit)
simCity.gis.clearFeatures(withType: .parkedCar)
print("okay")

// Add statistics collection events to the eventlist
print("Scheduling collection events... ", terminator: ""); fflush(stdout)
simCity.stats.scheduleCollectionEvents(onCity: simCity)
print("okay")

// Add mobility timestep events to the eventlist
print("Scheduling mobility events... ", terminator: ""); fflush(stdout)
simCity.events.scheduleMobilityEvents(fromFCD: &fcdTrips, city: simCity)
print("okay")


/*** EVENT LOOP ***/

// Initial stage events
print("Running initial events... ", terminator: "");
if !debug.isEmpty { print("") }
fflush(stdout)
for event in simCity.events.initial {
	event.action()
	if debug.contains("main().events"){
		print("[initial] main():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Executing", event.type, "event\t", event.description.darkGray())
	}
}
print("okay")


// Main simulation events
print("Running simulation events... ", terminator: "");
if !debug.isEmpty { print("") }
fflush(stdout)

// Implement a simple progress bar
let maxRunTime = simCity.events.list.last!.time.nanoseconds
let progressIncrement: Int = 10
var nextTargetPercent: Int = 0 + progressIncrement
var nextTarget: Int { return nextTargetPercent*maxRunTime/100 }

mainEventLoop: repeat {
	guard let nextEvent = simCity.events.list.first else {
		print("Exhausted event list at time", simCity.events.now.asSeconds)
		break mainEventLoop
	}

	// Remove the event from the eventlist
	simCity.events.list.removeFirst()

	// Update current time
	assert(nextEvent.time > simCity.events.now)
	simCity.events.now = nextEvent.time

	// Print progress bar
	if simCity.events.now.nanoseconds > nextTarget {
		print(nextTargetPercent, terminator: "% ")
		// If debug is being printed, don't single-line the progress bar
		if !debug.isEmpty { print("") }
		fflush(stdout)
		nextTargetPercent += progressIncrement
	}

	if debug.contains("main().events"){
		print("\(simCity.events.now.asSeconds) main():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Executing", nextEvent.type, "event\t", nextEvent.description.darkGray())
	}

	// Execute the event
	nextEvent.action()

} while simCity.events.now < simCity.events.stopTime
print("done")


// Cleanup stage events
print("Running cleanup events... ", terminator: "");
if !debug.isEmpty { print("") }
fflush(stdout)
for event in simCity.events.cleanup {
	event.action()
	if debug.contains("main().events"){
		print("[cleanup] main():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Executing", event.type, "event\t", event.description.darkGray())
	}
}
print("okay")


// Successful exit
print("Simulation complete.")
exit(EXIT_SUCCESS)
