/* This script takes a list of statistical data files containing tab-separated values,
 * where the first column is a time entry. It then gathers the data in the column
 * specified in the second argument (counting from 1) and returns statistics.
 */

import Foundation

/*** MEASUREMENT SWIFT3 ***/

// A measurement object: load data into 'samples' and all metrics are obtained as computed properties
struct Measurement {
	var samples = [Double]()
	mutating func add(point: Double) { samples.append(point) }

	var count: Double { return Double(samples.count) }
	var sum: Double { return samples.reduce(0,+) }
	var mean: Double { return sum/count	}
	var min: Double { return samples.min()! }
	var max: Double { return samples.max()! }

	// This returns the maximum likelihood estimator(over N), not the minimum variance unbiased estimator (over N-1)
	var variance: Double { return samples.reduce(0,{$0 + pow($1-mean,2)} )/count }
	var stdev: Double { return sqrt(variance) }

	// Specify the desired confidence level (1-significance) before requesting the intervals
	//	func confidenceIntervals(confidence: Double) -> Double {}
	//var confidence: Double = 0.90
	//var confidenceInterval: Double { return 0.0 }
}

/*** ***/


guard CommandLine.arguments.count == 3 else {
	print("usage: \(CommandLine.arguments[0]) [list of data files] [column name or number]")
	exit(EXIT_FAILURE)
}

var columnNumber: Int? = nil
var cliColName: String? = nil
if let cliColNum = UInt(CommandLine.arguments[2]) {
	columnNumber = Int(cliColNum)-1
} else {
	cliColName = CommandLine.arguments[2]
}

var statFiles: String
do {
	let statFilesURL = NSURL.fileURL(withPath: CommandLine.arguments[1])
	_ = try statFilesURL.checkResourceIsReachable()
	statFiles = try String(contentsOf: statFilesURL, encoding: String.Encoding.utf8)
} catch {
	print(error)
	exit(EXIT_FAILURE)
}

// Process statistics files
var dataDictionary: [Double:Measurement] = [:]
for statFile in statFiles.components(separatedBy: .newlines).filter({!$0.isEmpty}) {
	// 1. Open and read the statFile into a string
	var statFileData: String
	do {
		let statFileURL = NSURL.fileURL(withPath: statFile)
		_ = try statFileURL.checkResourceIsReachable()
		statFileData = try String(contentsOf: statFileURL, encoding: String.Encoding.utf8)
	} catch {
		print(error)
		exit(EXIT_FAILURE)
	}

	// 2. Break the stat file into lines
	var statFileLines: [String] = statFileData.components(separatedBy: .newlines).filter({!$0.isEmpty})

	// [AUX] For the very first file, if a column name was specified instead of a column number, find the column number by name.
	if columnNumber == nil {
		let header = statFileLines.first!
		let colNames = header.components(separatedBy: "\t").filter({!$0.isEmpty})
		guard let colIndex = colNames.index(where: {$0 == cliColName})
			else {
				print("ERROR: Can't match column name to a column number.")
				exit(EXIT_FAILURE)
		}
		columnNumber = colIndex
		print(columnNumber)
	}

	// 3. Drop the first line (header)
	statFileLines.removeFirst()

	// 4. Run through the statFile lines
	for statFileLine in statFileLines {
		// Split each line by tabs
		let statFileLineColumns = statFileLine.components(separatedBy: "\t").filter({!$0.isEmpty})
		// First column is time index for the dictionary
		// 'columnNumber' column is the data we want
		guard	let timeEntry = Double(statFileLineColumns[0]),
				let dataEntry = Double(statFileLineColumns[columnNumber!]) else {
					print("ERROR: Can't interpret time and/or data.")
					exit(EXIT_FAILURE)
		}

		// Push the data into the measurement's samples
		if dataDictionary[timeEntry] == nil { dataDictionary[timeEntry] = Measurement() }
		dataDictionary[timeEntry]?.add(point: dataEntry)
	}
}

// For each sorted entry in the dictionary, print out the mean, median, min, max, std, var, etcetera
print("time", "mean", "stdev", "var", "min", "max", "count", separator: "\t")
for (key, value) in dataDictionary.sorted(by: {$0.0<$1.0}) {
	print(key, value.mean, value.stdev, value.variance, value.min, value.max, value.count, separator: "\t")
}
