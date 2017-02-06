/* Andre Braga Reis, 2017
*/

import Foundation

/* Process command line options
*/
guard	CommandLine.arguments.count == 2,
		CommandLine.arguments[1].hasSuffix(".fcd.xml")
	else {
		print("ERROR: Please supply a .fcd.xml floating car data file.")
		exit(EXIT_FAILURE)
}



/* Load floating car data from an XML file
*/
print("Loading floating car data... ", terminator: ""); fflush(stdout)

// See if the file exists
let fcdFile: String = CommandLine.arguments[1]
let fcdFileURL = URL(fileURLWithPath: fcdFile)
guard (fcdFileURL as NSURL).checkResourceIsReachableAndReturnError(nil) else {
	print("\n","Error: Unable to open floating car data file.")
	exit(EXIT_FAILURE)
}

// Parse XML Floating Car Data
guard let fcdData = try? Data(contentsOf: fcdFileURL, options: [.mappedIfSafe, .uncached] ) else {
	print("\n","Error: Unable to memmap floating car data file.")
	exit(EXIT_FAILURE)
}

// Create an XML indexer for the FCD data
let fcdXML = SWXMLHash.config {
	config in
	config.shouldProcessLazily = true
	}.parse(fcdData)

print("okay")



// Extension to write strings to OutputStream
// Credit: stackoverflow rob & aleksey-timoshchenko
extension OutputStream {
	/// Write `String` to `OutputStream`
	///
	/// - parameter string:                The `String` to write.
	/// - parameter encoding:              The `String.Encoding` to use when writing the string. This will default to `.utf8`.
	/// - parameter allowLossyConversion:  Whether to permit lossy conversion when writing the string. Defaults to `false`.
	///
	/// - returns:                         Return total number of bytes written upon success. Return `-1` upon failure.
	
	func write(_ string: String, encoding: String.Encoding = .utf8, allowLossyConversion: Bool = false) -> Int {
		if let data = string.data(using: encoding, allowLossyConversion: allowLossyConversion) {
			return data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Int in
				var pointer = bytes
				var bytesRemaining = data.count
				var totalBytesWritten = 0
				
				while bytesRemaining > 0 {
					let bytesWritten = self.write(pointer, maxLength: bytesRemaining)
					if bytesWritten < 0 {
						return -1
					}
					
					bytesRemaining -= bytesWritten
					pointer += bytesWritten
					totalBytesWritten += bytesWritten
				}
				
				return totalBytesWritten
			}
		}
		return -1
	}
	
}


// Prepare output file
let tsvURL = URL(fileURLWithPath: fcdFile.replacingOccurrences(of: ".xml", with: ".tsv"))
guard let tsvStream = OutputStream(url: tsvURL, append: true) else {
	print("Error: Unable to open output file")
	exit(EXIT_FAILURE)
}
tsvStream.open()

// Print header
_ = tsvStream.write("time\tid\txgeo\tygeo\n")



// Auxiliary variable to ensure we get time-sorted data
var lastTimestepTime: Double = -Double.greatestFiniteMagnitude

// Iterate through every timestep and vehicle, outputting TSV-formatted data
for xmlTimestep in fcdXML["fcd-export"]["timestep"] {
	// 1. Get this timestep's time
	guard	let timestepElement = xmlTimestep.element,
		let s_time = timestepElement.attribute(by: "time")?.text,
		let timestepTime = Double(s_time)
		else {
			print("Error: Invalid timestep entry.")
			exit(EXIT_FAILURE)
	}
	
	// 2. We assume the FCD data is provided to us sorted; if not, fail
	if lastTimestepTime >= timestepTime {
		print("Error: Floating car data not sorted in time.")
		exit(EXIT_FAILURE)
	} else { lastTimestepTime = timestepTime }

	// 3. Iterate through the vehicles on this timestep
	for vehicle in xmlTimestep["vehicle"] {
		// Load the vehicle's ID and geographic position
		guard let vehicleElement = vehicle.element,
			let s_id = vehicleElement.attribute(by: "id")?.text,
			let v_id = UInt(s_id),
			let s_xgeo = vehicleElement.attribute(by: "x")?.text,
			let v_xgeo = Double(s_xgeo),
			let s_ygeo = vehicleElement.attribute(by: "y")?.text,
			let v_ygeo = Double(s_ygeo)
			//let s_speed = vehicleElement.attribute(by: "speed")?.text,
			//let v_speed = Double(s_speed)
			else {
				print("Error: Unable to convert vehicle properties.")
				exit(EXIT_FAILURE)
		}
		// Write data to tsv file
		_ = tsvStream.write("\(timestepTime)\t\(v_id)\t\(v_xgeo)\t\(v_ygeo)\n")
	}
}

// Close stream
tsvStream.close()
