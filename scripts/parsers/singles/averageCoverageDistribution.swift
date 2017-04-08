/* This script expects a set of 'cityCoverageEvolution' stat files. 
 * It aggregates all metrics and reports mean values and sample counts
 * for each. Standard deviation is left out due to the computational
 * complexity required when large numbers of samples are present.
 *
 * If a time value is provided as the second argument, only samples that
 * occur after that time are recorded.
 */

import Foundation

/*** MEASUREMENT SWIFT3 ***/

// A measurement object: load data into 'samples' and all metrics are obtained as computed properties
struct Measurement {
	var samples = [Double]()
	mutating func add(_ point: Double) { samples.append(point) }
	
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

guard 2...3 ~= CommandLine.arguments.count else {
	print("usage: \(CommandLine.arguments[0]) [list of data files] [minimum time]")
	exit(EXIT_FAILURE)
}

// Load minimum sample time
var minTime: Double = 0.0
if CommandLine.arguments.count == 3 {
	guard let inMinTime = Double(CommandLine.arguments[2]) else {
		print("Error: Invalid minimum time specified.")
		exit(EXIT_FAILURE)

	}
	minTime = inMinTime
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




/// Process statistics files

struct DataMeasurements {
	var numCovered = Measurement()
	var percentCovered = Measurement()
	var meanSig = Measurement()
	var stdevSig = Measurement()
	var sig0cells = Measurement()
	var sig1cells = Measurement()
	var sig2cells = Measurement()
	var sig3cells = Measurement()
	var sig4cells = Measurement()
	var sig5cells = Measurement()
}
var dataMeasurements = DataMeasurements()


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
	

	// 3. Drop the first line (header)
	statFileLines.removeFirst()
	
	// 4. Run through the statFile lines
	statFileLoop: for statFileLine in statFileLines {
		// Split each line by tabs
		let statFileLineColumns = statFileLine.components(separatedBy: "\t").filter({!$0.isEmpty})

		// 0	1			2			3		4			5		6		7		8		9		10
		// time	#covered	%covered	meanSig	stdevSig	0cells	1cells	2cells	3cells	4cells	5cells

		guard let intime = Double(statFileLineColumns[0]) else {
				print("ERROR: Can't interpret input time.")
				exit(EXIT_FAILURE)
		}

		if(intime > minTime) {
			guard	let inccov 		= UInt(statFileLineColumns[1]),
					let inpercov	= Double(statFileLineColumns[2]),
					let inmeansig	= Double(statFileLineColumns[3]),
					let instdevsig	= Double(statFileLineColumns[4]),
					let in0cell		= UInt(statFileLineColumns[5]),
					let in1cell		= UInt(statFileLineColumns[6]),
					let in2cell		= UInt(statFileLineColumns[7]),
					let in3cell		= UInt(statFileLineColumns[8]),
					let in4cell		= UInt(statFileLineColumns[9]),
					let in5cell		= UInt(statFileLineColumns[10])
					else {
						print("ERROR: Can't interpret input data.")
						exit(EXIT_FAILURE)
			}

			dataMeasurements.numCovered.add(Double(inccov))
			dataMeasurements.percentCovered.add(inpercov)
			dataMeasurements.meanSig.add(inmeansig)
			dataMeasurements.stdevSig.add(instdevsig)
			dataMeasurements.sig0cells.add(Double(in0cell))
			dataMeasurements.sig1cells.add(Double(in1cell))
			dataMeasurements.sig2cells.add(Double(in2cell))
			dataMeasurements.sig3cells.add(Double(in3cell))
			dataMeasurements.sig4cells.add(Double(in4cell))
			dataMeasurements.sig5cells.add(Double(in5cell))
		}
	}
}

print("metric", "numCovered", "percentCovered", "meanSig", "stdevSig", "0cells", "1cells", "2cells", "3cells", "4cells", "5cells", separator: "\t", terminator: "\n")
print("mean", dataMeasurements.numCovered.mean, dataMeasurements.percentCovered.mean, dataMeasurements.meanSig.mean, dataMeasurements.stdevSig.mean, dataMeasurements.sig0cells.mean, dataMeasurements.sig1cells.mean, dataMeasurements.sig2cells.mean, dataMeasurements.sig3cells.mean, dataMeasurements.sig4cells.mean, dataMeasurements.sig5cells.mean, separator: "\t", terminator: "\n")
//print("stdev", dataMeasurements.numCovered.stdev, dataMeasurements.percentCovered.stdev, dataMeasurements.meanSig.stdev, dataMeasurements.stdevSig.stdev, dataMeasurements.sig0cells.stdev, dataMeasurements.sig1cells.stdev, dataMeasurements.sig2cells.stdev, dataMeasurements.sig3cells.stdev, dataMeasurements.sig4cells.stdev, dataMeasurements.sig5cells.stdev, separator: "\t", terminator: "\n")
print("count", dataMeasurements.numCovered.count, dataMeasurements.percentCovered.count, dataMeasurements.meanSig.count, dataMeasurements.stdevSig.count, dataMeasurements.sig0cells.count, dataMeasurements.sig1cells.count, dataMeasurements.sig2cells.count, dataMeasurements.sig3cells.count, dataMeasurements.sig4cells.count, dataMeasurements.sig5cells.count, separator: "\t", terminator: "\n")
