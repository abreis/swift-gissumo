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

// Load stop time, and set it to DBL_MAX if it equals 0 (meaning, no stop time)
guard var configStopTime = config["stopTime"] as? Double else {
	print("failed", "\nError: Please provide a valid simulation stop time in the configuration.")
	exit(EXIT_FAILURE)
}
if configStopTime.isLessThanOrEqualTo(0) { configStopTime = Double.greatestFiniteMagnitude }

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

// Load RSU lifetime
let configRsuLifetime = config["rsuLifetime"] as? Int

// Load data flush interval
var configDataFlushInterval = config["dataFlushInterval"] as? Int
if configDataFlushInterval == 0 { configDataFlushInterval = nil }

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



/* Load floating car data from a TSV file
 */
print("Loading floating car data... ", terminator: ""); fflush(stdout)

guard	let fcdFile = config["floatingCarDataFile"] as? String,
		fcdFile.hasSuffix(".fcd.tsv")
else {
	print("failed", "\nError: Please specify a valid .fcd.tsv file with 'floatingCarDataFile'.")
	exit(EXIT_FAILURE)
}

let fcdFileURL = URL(fileURLWithPath: fcdFile)
guard (fcdFileURL as NSURL).checkResourceIsReachableAndReturnError(nil) else {
	print("failed", "\nError: FCD file is not reachable.")
	exit(EXIT_FAILURE)
}

var fcdTSV: [String]
do {
	fcdTSV = try String(contentsOf: fcdFileURL, encoding: .utf8).components(separatedBy: .newlines).filter{!$0.isEmpty}
} catch {
	print("failed", "\nError: Unable to parse FCD file.", "\n", error)
	exit(EXIT_FAILURE)
}

// Drop the header file
fcdTSV.removeFirst()

print("okay")



/* To build an obstruction cell mask, jump here.
 */
// TODO: Rewrite buildObstructionMask to work with TSV data
//if	let toolsConfig = config["tools"] as? NSDictionary,
//	let buildMask = toolsConfig["buildObstructionMask"] as? Bool, buildMask == true
//{
//	print("Parsing floating car data... ", terminator: ""); fflush(stdout)
//
//	let fcdTrips: [FCDTimestep]
//	do {
//		try fcdTrips = parseFloatingCarData(fromXML: fcdXML, stopTime: configStopTime)
//	} catch let error as FloatingCarDataError {
//		print("failed", "\nError:", error.description)
//		exit(EXIT_FAILURE)
//	}
//
//	print("Building obstruction mask... ", terminator: ""); fflush(stdout)
//	do {
//		try buildObstructionMask(fromTrips: fcdTrips)
//	} catch {
//		print("failed", "\nError:", error)
//		exit(EXIT_FAILURE)
//	}
//	print("okay")
//	print("\tBuilt a map of obstructions from \(fcdTrips.count) steps.")
//	exit(EXIT_SUCCESS)
//}



/********************/
/*** MAIN ROUTINE ***/
/********************/


/* Initialize a new City, plus a new network, a new eventlist, a new statistics module, and a new decision module
 */
var simCity = City(gis: gisdb, network: Network(), eventList: EventList(stopTime: configStopTime), statistics: Statistics(config: statisticsConfig), decision: Decision(config: decisionConfig))

// Set RSU lifetime
if configRsuLifetime != nil { simCity.rsuLifetime = configRsuLifetime }

// Set periodic data flush
if configDataFlushInterval != nil { simCity.dataFlushInterval = configDataFlushInterval }

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
/* One-shot:
 * - Add mobility timestep events to the eventlist
 * - Load city bounds from the FCD trips
 *
 * Previously, we parsed all the floating car data onto an array of our own, 
 * and then iterated on that array for these two tasks. For larger datasets
 * this is very inneficient.
 */
print("Scheduling mobility events... ", terminator: ""); fflush(stdout)
simCity.scheduleMobilityAndDetermineBounds(fromTSV: &fcdTSV, stopTime: configStopTime)
print("done")

// Store inner city bounds from configuration file
simCity.innerBounds = cityInnerBounds


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

// Trap SIGINT (Ctrl-C)
var sigInt: Bool = false
Signals.trap(signal: .int) { signal in sigInt = true }

// Implement a simple progress bar
let maxRunTime = simCity.events.list.last!.time.nanoseconds
let progressIncrement: Int = 10
var nextTargetPercent: Int = 0 + progressIncrement
var nextTarget: Int { return nextTargetPercent*maxRunTime/100 }

// Go through the events
for nextEvent in simCity.events.list where nextEvent.time <= simCity.events.stopTime && !sigInt {
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

	// Output simulation time, if enabled
	if simCity.stats.hooks["simulationTime"] != nil {
		simCity.stats.writeToHook("simulationTime", data: "\(simCity.events.now.asSeconds)\n")
	}
}
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
print("Simulation complete at time \(simCity.events.now.asSeconds).")
exit(EXIT_SUCCESS)
