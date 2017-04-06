/* This script takes a list of statistical data files containing tab-separated values,
 * and bins the data for presenting as a histogram.
 *
 * If a time, in seconds, is specified in as the third argument, only samples collected
 * after that (simulation) time will be included. This is helpful to exclude impulse stages.
 *
 * The fourth argument specifies the name or number of the column with the time data. 
 * Assumed to be the first column, if not provided.
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


guard 3...5 ~= CommandLine.arguments.count else {
	print("usage: \(CommandLine.arguments[0]) [list of data files] [column name or number] [minimum time] [column name or number of time entry]")
	exit(EXIT_FAILURE)
}


var columnNumber: Int? = nil
var cliColName: String? = nil
if let cliColNum = UInt(CommandLine.arguments[2]) {
	columnNumber = Int(cliColNum)-1
} else {
	cliColName = CommandLine.arguments[2]
}


// Load minimum sample time
var minTime: Double? = nil
if CommandLine.arguments.count > 3 {
	minTime = Double(CommandLine.arguments[3])
}

var timeColumnNumber: Int? = nil
var timeCliColName: String? = nil
if CommandLine.arguments.count > 4 {
	if let timeCliColNum = UInt(CommandLine.arguments[4]) {
		timeColumnNumber = Int(timeCliColNum)-1
	} else {
		timeCliColName = CommandLine.arguments[4]
	}
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
var dataMeasurement = Measurement()
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
	}

	if timeColumnNumber == nil {
		let header = statFileLines.first!
		let colNames = header.components(separatedBy: "\t").filter({!$0.isEmpty})
		if let timeColIndex = colNames.index(where: {$0 == timeCliColName}) {
			timeColumnNumber = timeColIndex
		} else {
			timeColumnNumber = 0
		}
	}

	// 3. Drop the first line (header)
	statFileLines.removeFirst()

	// 4. Run through the statFile lines
	statFileLoop: for statFileLine in statFileLines {
		// Split each line by tabs
		let statFileLineColumns = statFileLine.components(separatedBy: "\t").filter({!$0.isEmpty})
		// 'columnNumber' column is the data we want
		guard	let timeEntry = Double(statFileLineColumns[timeColumnNumber!]),
				let dataEntry = Double(statFileLineColumns[columnNumber!]) else {
					print("ERROR: Can't interpret data.")
					exit(EXIT_FAILURE)
		}

		if minTime != nil && timeEntry < minTime! {
			continue statFileLoop
		}

		// Push the data into the measurement's samples
		dataMeasurement.add(point: dataEntry)
	}
}

// Bin data
let binWidth = 80
let binStart = 0
// binCenter:density
var binDict: [Int:Double] = [:]

var dataPoints = dataMeasurement.samples
dataPoints.sort(by: {$0<$1})

var currentBin = binStart+binWidth/2
for point in dataPoints {
	if point < Double(currentBin+binWidth/2) {
		if binDict[currentBin] != nil {
			binDict[currentBin]! += 1
		} else {
			binDict[currentBin] = 1
		}
	} else {
		currentBin+=binWidth
	}
}


// Normalize
for key in binDict.keys {
	binDict[key] = Double(binDict[key]!)/dataMeasurement.count
}


// Print
print("binCenter", "density", separator: "\t")
for entry in binDict.sorted(by: {$0.key < $1.key}) {
	print(entry.key, entry.value, separator: "\t")
}
