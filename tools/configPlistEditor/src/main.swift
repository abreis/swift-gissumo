/* Andre Braga Reis, 2016
*/

import Foundation

/* Process command line options
*/
guard Process.arguments.count == 4 && Process.arguments[1].hasSuffix(".plist") else {
	print("ERROR: Please supply a .plist configuration file, an entry to edit, and a new value for the entry.")
	exit(EXIT_FAILURE)
}

let configFileURL = NSURL.fileURLWithPath(Process.arguments[1])
var configFileError : NSError?
guard configFileURL.checkResourceIsReachableAndReturnError(&configFileError) else {
	print("Error: Can't open file.\n", configFileError)
	exit(EXIT_FAILURE)
}

// Load plist into a configuration dictionary array
guard var config = NSMutableDictionary(contentsOfURL: configFileURL) else {
	print("failed", "\nError: Invalid configuration file format.")
	exit(EXIT_FAILURE)
}


let newValue = Process.arguments[3]
let key = Process.arguments[2]

// Try to match the input to a specific type supported by the Property List
if newValue.caseInsensitiveCompare("false") == .OrderedSame {
	config.setValue(false, forKeyPath: key)
} else if newValue.caseInsensitiveCompare("true") == .OrderedSame {
	config.setValue(true, forKeyPath: key)
} else if let integerValue = Int(newValue) {
	config.setValue(integerValue, forKeyPath: key)
} else if let doubleValue = Double(newValue) {
	config.setValue(doubleValue, forKeyPath: key)
} else {
	config.setValue(newValue, forKeyPath: key)
}

// Write back to the same config file
config.writeToURL(configFileURL, atomically: true)
