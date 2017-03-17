/* This script takes a list of 'cityCoverageEvolution' data files.
 * It then averages and bins every metric in the statistical files.
 */

import Foundation

guard CommandLine.arguments.count == 3 else {
	print("usage: \(CommandLine.arguments[0]) [list of data files] [binning width in seconds]")
	exit(EXIT_FAILURE)
}

guard let binningWidth = UInt(CommandLine.arguments[2])
	else {
		print("ERROR: Invalid binning width.")
		exit(EXIT_FAILURE)
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

// time	#covered	%covered	meanSig	stdevSig	0cells	1cells	2cells	3cells	4cells	5cells
struct CoverageEntry {
	var time: Double
	var cellsCovered: UInt
	var percentCellsCovered: Double
	var meanSignal: Double
	var stdevSignal: Double
	var coverageByStrength: [UInt]
}

// Process statistics files
var coverageData: [CoverageEntry] = []

let statFileArray = statFiles.components(separatedBy: .newlines).filter({!$0.isEmpty})

guard statFileArray.count > 0 else {
	print("Error: No statistics files provided.")
	exit(EXIT_FAILURE)
}

for statFile in statFileArray {
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
	for statFileLine in statFileLines {
		// Split each line by tabs
		let statFileLineColumns = statFileLine.components(separatedBy: "\t").filter({!$0.isEmpty})

		guard	let intime		= Double(statFileLineColumns[0]),
			let inccov 		= UInt(statFileLineColumns[1]),
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
				print("ERROR: Can't interpret input files.")
				exit(EXIT_FAILURE)
		}
		var newCoverage = CoverageEntry(time: intime, cellsCovered: inccov, percentCellsCovered: inpercov, meanSignal: inmeansig, stdevSignal: instdevsig, coverageByStrength: [in0cell,in1cell,in2cell,in3cell,in4cell,in5cell])

		// Push the decision into our array
		coverageData.append(newCoverage)
	}
}

// Sort the array
coverageData.sort { $0.time < $1.time }

// Determine bins
let firstBin = UInt( coverageData.first!.time.subtracting(coverageData.first!.time.truncatingRemainder(dividingBy: Double(binningWidth)) ) )
let lastBin = UInt( coverageData.last!.time.subtracting(coverageData.last!.time.truncatingRemainder(dividingBy: Double(binningWidth)) ) )

var bins: [UInt] = []
var binIterator = firstBin
while(binIterator <= lastBin) {
	bins.append(binIterator)
	binIterator += binningWidth
}

// Output: [bin:data]
var outputDictionary : [UInt:CoverageEntry] = [:]

func sumArray (modify array1: inout [UInt], with array2: [UInt]) {
	guard array1.count == array2.count else {
		print("Error: Incompatible array size for summation.")
		exit(EXIT_FAILURE)
	}
	for index in 0..<array1.count {
		array1[index] += array2[index]
	}
}

var countStart = 0
binLoop: for bin in bins {
	var entries: UInt = 0
	var accumulatedCoverage = CoverageEntry(time: 0, cellsCovered: 0, percentCellsCovered: 0, meanSignal: 0, stdevSignal: 0, coverageByStrength: [0,0,0,0,0,0])

	// Coverage array is sorted, so we brute iterate
	entryLoop: for index in countStart..<Int(coverageData.count) {
		let coverage = coverageData[index]
		if(coverage.time < Double(bin+binningWidth)) {
			accumulatedCoverage.cellsCovered += coverage.cellsCovered
			accumulatedCoverage.percentCellsCovered += coverage.percentCellsCovered
			accumulatedCoverage.meanSignal += coverage.meanSignal
			accumulatedCoverage.stdevSignal += coverage.stdevSignal
			sumArray(modify: &accumulatedCoverage.coverageByStrength, with: coverage.coverageByStrength)
			entries += 1
		} else {
			break entryLoop
		}
		countStart = index
	}

	accumulatedCoverage.cellsCovered		/= UInt(entries)
	accumulatedCoverage.percentCellsCovered /= Double(entries)
	accumulatedCoverage.meanSignal			/= Double(entries)
	accumulatedCoverage.stdevSignal			/= Double(entries)
	for index in 0..<accumulatedCoverage.coverageByStrength.count {
		accumulatedCoverage.coverageByStrength[index] /= entries
	}
	outputDictionary[bin] = accumulatedCoverage
}

let separator = "\t"
print("time\(separator)#covered\(separator)%covered\(separator)meanSig\(separator)stdevSig\(separator)0cells\(separator)1cells\(separator)2cells\(separator)3cells\(separator)4cells\(separator)5cells\n")
for (key, value) in outputDictionary.sorted(by: {$0.key < $1.key}) {
	print(key, value.cellsCovered, value.percentCellsCovered, value.meanSignal, value.stdevSignal,
	      value.coverageByStrength[0],
	      value.coverageByStrength[1],
	      value.coverageByStrength[2],
	      value.coverageByStrength[3],
	      value.coverageByStrength[4],
	      value.coverageByStrength[5],
	      separator: "\t")
}
