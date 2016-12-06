/* This script takes a list of 'decisionCellCoverageEffects' data files.
* It then averages all post-coefficient decisions, binning by a specified
* bin width, and outputs the resulting calculations
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

struct DecisionEntry {
	var time: Double
	var id: UInt
	var dNew: Int
	var dBoost: Int
	var dSat: Int
	var dScore: Double
	var kappa: Double
	var lambda: Double
	var mu: Double
}

// Process statistics files
var decisionData: [DecisionEntry] = []

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

		guard	let intime	= Double(statFileLineColumns[0]),
				let inid		= UInt(statFileLineColumns[1]),
				let indNew	= Int(statFileLineColumns[2]),
				let indBoost	= Int(statFileLineColumns[3]),
				let indSat	= Int(statFileLineColumns[4]),
				let indScore	= Double(statFileLineColumns[5]),
				let inkappa	= Double(statFileLineColumns[6]),
				let inlambda	= Double(statFileLineColumns[7]),
				let inmu		= Double(statFileLineColumns[8])
			else {
				print("ERROR: Can't interpret input files.")
				exit(EXIT_FAILURE)
		}
		var newDecision = DecisionEntry(time: intime, id: inid, dNew: indNew, dBoost: indBoost, dSat: indSat, dScore: indScore, kappa: inkappa, lambda: inlambda, mu: inmu)

		// Push the decision into our array
		decisionData.append(newDecision)
	}
}

// Sort the array
decisionData.sort { $0.time < $1.time }

// Determine bins
let firstBin = UInt( decisionData.first!.time.subtracting(decisionData.first!.time.truncatingRemainder(dividingBy: Double(binningWidth)) ) )
let lastBin = UInt( decisionData.last!.time.subtracting(decisionData.last!.time.truncatingRemainder(dividingBy: Double(binningWidth)) ) )

var bins: [UInt] = []
var binIterator = firstBin
while(binIterator <= lastBin) {
	bins.append(binIterator)
	binIterator += binningWidth
}

struct SubDecisionEntry {
	var positive: Double = 0
	var negative: Double = 0
}

var outputDictionary : [UInt:SubDecisionEntry] = [:]

let numberOfSimulations = statFileArray.count

var countStart = 0
binLoop: for bin in bins {
	var accumulatedDecision = SubDecisionEntry()

	// Decision array is sorted, so we brute iterate
	decisionLoop: for index in countStart..<Int(decisionData.count) {
		let decision = decisionData[index]
		if(decision.time < Double(bin+binningWidth)) {
			if(decision.dScore > 0) {
				accumulatedDecision.positive += 1
			} else {
				accumulatedDecision.negative += 1
			}
		} else {
			break decisionLoop
		}
		countStart = index
	}

	accumulatedDecision.positive /= Double(numberOfSimulations)
	accumulatedDecision.negative /= Double(numberOfSimulations)
	outputDictionary[bin] = accumulatedDecision
}

print("bin", "positive", "negative", separator: "\t")
for (key, value) in outputDictionary.sorted(by: {$0.key < $1.key}) {
	print(key, value.positive, value.negative, separator: "\t")
}
