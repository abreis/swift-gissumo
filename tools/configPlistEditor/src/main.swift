/* Andre Braga Reis, 2016
*/

import Foundation

/* Process command line options
*/
guard CommandLine.arguments.count == 4 && CommandLine.arguments[1].hasSuffix(".plist") else {
	print("ERROR: Please supply a .plist configuration file, an entry to edit, and a new value for the entry.")
	exit(EXIT_FAILURE)
}

let configFileURL = URL(fileURLWithPath: CommandLine.arguments[1])
do {
	guard try configFileURL.checkResourceIsReachable() else {
		print("Error: Configuration file not found.")
		exit(EXIT_FAILURE)
	}
} catch {
	print("Error: Can't open file.", error)
	exit(EXIT_FAILURE)
}

// Load plist into a configuration dictionary array
guard var config = NSMutableDictionary(contentsOf: configFileURL) else {
	print("Error: Invalid configuration file format.")
	exit(EXIT_FAILURE)
}


let newValue = CommandLine.arguments[3]
let key = CommandLine.arguments[2]

// Try to match the input to a specific type supported by the Property List
if newValue.caseInsensitiveCompare("false") == .orderedSame {
	config.setValue(false, forKeyPath: key)
} else if newValue.caseInsensitiveCompare("true") == .orderedSame {
	config.setValue(true, forKeyPath: key)
} else if let integerValue = Int(newValue) {
	config.setValue(integerValue, forKeyPath: key)
} else if let doubleValue = Double(newValue) {
	config.setValue(doubleValue, forKeyPath: key)
} else {
	config.setValue(newValue, forKeyPath: key)
}

// Write back to the same config file
config.write(to: configFileURL, atomically: true)
