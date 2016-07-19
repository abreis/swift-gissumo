/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation



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
	let timestepTime = Float(timestep.element!.attributes["time"]!)
	var timestepVehicles = [FCDVehicle]()

	for vehicle in timestep["vehicle"] {
		let v_id = UInt(vehicle.element!.attributes["id"]!)
		let v_xgeo = Float(vehicle.element!.attributes["x"]!)
		let v_ygeo = Float(vehicle.element!.attributes["y"]!)
		let v_speed = Float(vehicle.element!.attributes["speed"]!)

		timestepVehicles.append( FCDVehicle(id: v_id!, xgeo: v_xgeo!, ygeo: v_ygeo!, speed: v_speed!) )
	}

	Trips.append( FCDTimestep(time: timestepTime!, vehicles: timestepVehicles) )
}

print(" okay")
print("Loaded", Trips.count, "timesteps.")

exit(EXIT_SUCCESS)
