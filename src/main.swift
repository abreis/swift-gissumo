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

print(" todo")




exit(EXIT_SUCCESS)
