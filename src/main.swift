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
	print(" failed\n", "Error: Invalid configuration file format.")
	exit(EXIT_FAILURE)
}

print(" okay")



/* Load floating car data from an XML file
 * - Check for floatingCarDataFile config entry
 * - See if file exists
 * - Parse XML
 */
print("Loading floating car data...", terminator: "")

guard let fcdFile = config["floatingCarDataFile"] as? String
 else {
	print(" failed\n", "Error: Please specify a valid SUMO FCD file with 'floatingCarDataFile'.")
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
    print(" failed\n", "Error: Unable to parse XML data from file.")
    exit(EXIT_FAILURE)
}

let fcdXML = SWXMLHash.lazy(fcdData)

// Load data onto our Trips array
var Trips = [FCDTimestep]()
for timestep in fcdXML["fcd-export"]["timestep"] {
	guard let timestepElement = timestep.element,
			let s_time = timestepElement.attributes["time"],
			let timestepTime = Double(s_time)
	 else {
		print(" failed\n", "Error: Invalid timestep entry.")
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
			print(" failed\n", "Error: Unable to convert vehicle properties.")
			exit(EXIT_FAILURE)
		}

		timestepVehicles.append( FCDVehicle(id: v_id, xgeo: v_xgeo, ygeo: v_ygeo, speed: v_speed) )
	}

	Trips.append( FCDTimestep(time: timestepTime, vehicles: timestepVehicles) )
}

print(" okay")
print("\tLoaded", Trips.count, "timesteps from data file")



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
	print(" failed\n", "Error: Invalid database configuration.")
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

gis.clear(featureType: .Vehicle)

let pointGID = gis.add(pointOfType: .Vehicle, xgeo: -8.62051, ygeo: 41.16371, id: 1)
print("AddPoint GID:", pointGID)

let coords: (Double, Double) = gis.get(coordinatesFromGID: pointGID)
print("Coordinates:", coords)

let gids = gis.get(featuresInCircleWithRadius: 59, xCenter: -8.6200, yCenter: 41.1636, featureType: .Vehicle)
print("GIDs:", gids)

let distance = gis.get(distanceFromPointToGID: pointGID, xgeo: -8.62, ygeo: 41.1636)
print("Distance:", distance)

let nlos = gis.checkForLineOfSight(-8.620385, ygeo1: 41.164445, xgeo2: -8.62051, ygeo2: 41.16371)
print("NLOS:", nlos)

let los = gis.checkForLineOfSight(-8.620385, ygeo1: 41.164445, xgeo2: -8.619970, ygeo2: 41.164383)
print("LOS:", los)

gis.update(pointFromGID: pointGID, xgeo: -8.62052, ygeo: 41.16372)
let newCoords: (Double, Double) = gis.get(coordinatesFromGID: pointGID)
print("New coords:", newCoords)

exit(EXIT_SUCCESS)
