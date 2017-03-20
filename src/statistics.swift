/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class Statistics {
	// Configuration entries
	var folder: String = "stats/"
	var interval = SimulationTime(seconds: 1)
	var startTime = SimulationTime(seconds: 1)

	// A dictionary containing (statisticName,statisticData) pairs
	var hooks = [String:String]()

	// Hooks that output immediately are hardcoded here:
	let hardcodedImmediateHooks: [String] = ["packetTrace", "simulationTime"]
	var immediateHookHandles: [String:FileHandle] = [:]

	// A dictionary of metrics for other routines to store data on
	var metrics = [String:Any]()

	// Data separator (e.g. ',' or ';' for CSV (comma not recommended in Europe, prefer semicolon), '\t' for TSV
	let separator = "\t"
	let terminator = "\n"

	// A map showing open and blocked cells
	// Can be generated with config->tools->buildObstructionMask=true
	var obstructionMask: CellMap<Character>?

	init(config: NSDictionary) {
		// Load general statistics configurations, if defined: folder, interval, startTime
		if let configFolder = config["statsFolder"] as? String {
			folder = configFolder
			if !folder.hasSuffix("/") {	folder.append(Character("/")) }
		}

		if let configInterval = config["collectionInterval"] as? Double {
			interval = SimulationTime(seconds: configInterval)
		}

		if let configStartTime = config["collectionStartTime"] as? Double {
			startTime = SimulationTime(seconds: configStartTime)
		}

		// Load hook list and ready statistics collection point
		if let hookList = config["hooks"] as? NSDictionary {
			for element in hookList {
				if let enabled = element.value as? Bool, enabled == true {
					let hook = String(describing: element.key)
					hooks[hook] = ""
				}
			}

			// Try to create the statistics folder if it doesn't exist
			let folderURL = URL(fileURLWithPath: folder)
			do {
				if !(folderURL as NSURL).checkResourceIsReachableAndReturnError(nil) {
					try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
				}
			} catch let error as NSError {
				print("Error: Failed to create collection directory", folderURL)
				print(error)
				exit(EXIT_FAILURE)
			}

			// Initialize file handles for immediate hooks
			for immediateHook in hardcodedImmediateHooks where hooks.keys.contains(immediateHook) {
				let hookURL = URL(fileURLWithPath: "\(folder)\(immediateHook).log")

				// Overwrite file if it exists
				if FileManager.default.fileExists(atPath: hookURL.path) {
					do {
						try "".write(to: hookURL, atomically: true, encoding: String.Encoding.utf8)
					} catch {
						print("Error: Failed to overwrite existing file for hook", immediateHook)
						exit(EXIT_FAILURE)
					}
				} else {
					FileManager.default.createFile(atPath: hookURL.path, contents: nil)
				}

				// Create handle and store it in the handle dictionary
				do {
					let hookHandle = try FileHandle(forWritingTo: hookURL)
					hookHandle.seekToEndOfFile()
					immediateHookHandles[immediateHook] = hookHandle
				} catch {
					print("Error: Failed to initialize filehandle for", immediateHook)
					print(error)
					exit(EXIT_FAILURE)
				}
			}
		}


		// Load obstruction mask if given
		if let maskFileConfig = config["obstructionMaskFile"] as? String {
			let maskFileURL = URL(fileURLWithPath: maskFileConfig)
			do {
				let maskAsString = try String(contentsOf: maskFileURL)
				obstructionMask = CellMap<Character>(fromString: maskAsString)
			} catch {
				print("\nWarning: Obstruction mask file failed to load.\n".red())
			}
		}
		if obstructionMask == nil {
			print("\nWarning: Obstruction mask not provided or failed to load.\n".red())
		} else {
			print("\tLoaded obstruction mask with size \(obstructionMask!.size), open cells \(obstructionMask!.flatCells.filter{$0=="O"}.count)")
		}

		// Initialize metrics
		initMetrics()

		// Add header lines to enabled hooks
		addHookHeaders()
	}

	/// Write all collected statistical data, overwriting existing files
	func writeStatisticsToFiles() {
		// Write all collected data (except for hardcoded hooks)
		for (statName, statData) in hooks where !hardcodedImmediateHooks.contains(statName) {
			let hookURL = URL(fileURLWithPath: "\(folder)\(statName).log")
			do {
				try statData.write(to: hookURL, atomically: true, encoding: String.Encoding.utf8)
			} catch {
				print("Error: Failed to write statistical data to", hookURL)
				print(error)
				exit(EXIT_FAILURE)
			}
		}

		// Close filehandles of immediate hooks
		for handle in immediateHookHandles.values {
			handle.closeFile()
		}
	}

	/// Add data to a specific statistic
	func writeToHook(_ statName: String, data: String) {
		guard hooks[statName] != nil else {
			print("Error: Tried to write to an undeclared stat hook.")
			exit(EXIT_FAILURE)
		}

		if hardcodedImmediateHooks.contains(statName) {
			// 'Immediate'-type hooks write to disk immediately
			guard immediateHookHandles.keys.contains(statName) else {
				print("Error: Filehandle for immediate hook not found.")
				exit(EXIT_FAILURE)
			}
			immediateHookHandles[statName]!.write( data.data(using: String.Encoding.utf8)! )
		} else {
			// Add data to hook buffer
			hooks[statName]! += data
		}
	}

	/// Schedule collection events by startTime & interval until stopTime
	// Note: If another event is scheduled to time:(stopTime-minTimestep), the collection will never occur
	func scheduleCollectionEvents(onCity city: City) {
		// Schedule collection events on startTime+interval*N, until city.events.stopTime is reached
		var scheduledCollectionTime = startTime
		repeat {
			// Create and schedule an event
			let scheduledCollectionEvent = SimulationEvent(time: scheduledCollectionTime, type: .statistics, action: { city.stats.collectStatistics(fromCity: city)}, description: "scheduledCollectStats")
			city.events.add(newEvent: scheduledCollectionEvent)

			// Jump to next collection time
			scheduledCollectionTime += interval
		} while scheduledCollectionTime < city.events.stopTime

		// Schedule an init-stage event to set up the statistics module
		let statisticsSetupEvent = SimulationEvent(time: SimulationTime(), type: .statistics, action: {city.stats.initialSetup(onCity: city)}, description: "initialStatsSetup")
		city.events.add(initialEvent: statisticsSetupEvent)

		// Schedule a cleanup-stage event to collect final statistics
		let finalCollectionEvent = SimulationEvent(time: SimulationTime(), type: .statistics, action: {city.stats.finalCollection(onCity: city)}, description: "finalCollectStats")
		city.events.add(cleanupEvent: finalCollectionEvent)

		// Schedule a cleanup-stage event to write all statistical data to files
		let statWriteEvent = SimulationEvent(time: SimulationTime(), type: .statistics, action: {city.stats.writeStatisticsToFiles()} , description: "writeStatsToFiles")
		city.events.add(cleanupEvent: statWriteEvent)
	}



	/// Initial statistics module setup
	func initialSetup(onCity city: City) {
		// If inner collection bounds were specified, crop the obstruction mask to them
		if let innerCellSize = city.innerCellSize, let innerTopLeftCell = city.innerTopLeftCell {
			obstructionMask?.cropInPlace(newTopLeftCell: innerTopLeftCell, newSize: innerCellSize)
		}
		else {
			// If not, crop the mask to the city size
			obstructionMask?.cropInPlace(newTopLeftCell: city.topLeftCell, newSize: city.cellSize)
		}
	}


	/// Periodic (intervalled) statistics collection routine
	func collectStatistics(fromCity city: City) {
		// entityCount
		if hooks["entityCount"] != nil {
			writeToHook("entityCount", data: "\(city.events.now.asSeconds)\(separator)\(city.vehicles.count)\(separator)\(city.roadsideUnits.count)\(separator)\(city.parkedCars.count)\(terminator)")
		}

		// beaconCount
		if hooks["beaconCount"] != nil {
			guard	let beaconsSent = metrics["beaconsSent"] as? UInt,
					let beaconsRecv = metrics["beaconsReceived"] as? UInt
					else {
						print("Error: Metrics unavailable for beaconCount hook.")
						exit(EXIT_FAILURE)
			}
			writeToHook("beaconCount", data: "\(city.events.now.asSeconds)\(separator)\(beaconsSent)\(separator)\(beaconsRecv)\(terminator)")
		}

		// cityCoverageEvolution
		if hooks["cityCoverageEvolution"] != nil {
			// Count covered cells
			var coveredCells = Measurement()
			var coverageMap = city.globalMapOfCoverage

			// If an obstruction mask was supplied, crop the coverage map to the mask size
			if let maskMap = obstructionMask {
				coverageMap.cropInPlace(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)
			}

			// Track the number of cells covered at each specific coverage strength
			var coverageByStrength: [UInt] = [0,0,0,0,0,0]

			// Add coverage cells to the Measurement
			for row in coverageMap.cells {
				for cell in row {
					if cell != 0 {
						coveredCells.add(Double(cell))
						coverageByStrength[cell] += 1
					}
				}
			}

			let cellCount = UInt(coveredCells.count)
			var percentCovered: Double = 0.0
			if let totalCells = obstructionMask?.flatCells.filter( {$0 == "O"} ).count {
				percentCovered = Double(cellCount)/Double(totalCells)
			}
			let signalMean = coveredCells.mean.isNaN ? 0.0 : coveredCells.mean
			let signalStdev = coveredCells.stdev.isNaN ? 0.0 : coveredCells.stdev
			writeToHook("cityCoverageEvolution", data: "\(city.events.now.asSeconds)\(separator)\(cellCount)\(separator)\(percentCovered)\(separator)\(signalMean)\(separator)\(signalStdev)\(separator)\(coverageByStrength[0])\(separator)\(coverageByStrength[1])\(separator)\(coverageByStrength[2])\(separator)\(coverageByStrength[3])\(separator)\(coverageByStrength[4])\(separator)\(coverageByStrength[5])\(terminator)")
		}

		// coverageAndSaturationEvolution
		if hooks["signalAndSaturationEvolution"] != nil {
			// Data to write to the hook
			var statData = String()

			// 1. Get the obstruction mask map
			if let maskMap = obstructionMask {
				// Create measurements
				var sigMeasure = Measurement()
				var satMeasure = Measurement()

				// Get the city coverage and saturation maps and crop them to the obstruction mask
				var signalCoverageMap = city.globalMapOfCoverage.crop(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)
				var rsuSaturationMap = city.globalMapOfSaturation.crop(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)

				// 1.1. Push every measurement if the matching obstruction map cell is marked [O]pen
				guard signalCoverageMap.size == rsuSaturationMap.size else {
					print("Error: Signal and saturation maps are not the same size.")
					exit(EXIT_FAILURE)
				}

				for i in 0..<signalCoverageMap.size.y {
					for j in 0..<signalCoverageMap.size.x {
						if maskMap.cells[i][j] == Character("O") {
							// Don't add zero cells, their effect can be extrapolated from %covered if needed
							if signalCoverageMap.cells[i][j] != 0 { sigMeasure.add(Double(signalCoverageMap.cells[i][j])) }
							if rsuSaturationMap.cells[i][j] != 0 { satMeasure.add(Double(rsuSaturationMap.cells[i][j])) }
						}
					}
				}

				// 1.2. Record the desired metrics
				statData = "\(city.events.now.asSeconds)\(separator)\(sigMeasure.mean)\(separator)\(sigMeasure.stdev)\(separator)\(satMeasure.mean)\(separator)\(satMeasure.stdev)\(separator)\(sigMeasure.mean/satMeasure.mean)\(terminator)"
			} else {
				// Print an error message if a mask was not provided
				statData = "Please generate and provide an obstruction mask first."
			}

			// 2. Write data
			writeToHook("signalAndSaturationEvolution", data: statData)
		}

		// movingAverageWPM
		if hooks["movingAverageWPM"] != nil {
			guard var decisionStats = metrics["movingAverageWPM"] as? (sig: [Double], sat: [Double])
				else {
					print("Error: Metrics unavailable for movingAverageWPM hook.")
					exit(EXIT_FAILURE)
			}

			// Exponential moving average settings
			let emaSize = 26
			let emaMultipler = 2.0/(Double(emaSize)+1.0)	// weighting drops by half every time the moving average period doubles

			// No statistics until we have enough decisions
			guard decisionStats.sig.count >= emaSize, decisionStats.sat.count >= emaSize
				else { return }

			// Trim arrays to desired EMA size
			let sigDropCount = decisionStats.sig.count-emaSize
			let satDropCount = decisionStats.sat.count-emaSize
			if sigDropCount > 0 { decisionStats.sig.removeFirst(sigDropCount) }
			if satDropCount > 0 { decisionStats.sat.removeFirst(satDropCount) }

			// Reassign trimmed arrays
			metrics["movingAverageWPM"] = decisionStats

			// Compute EMAs, starting from the SMA
			let sigMean = decisionStats.sig.reduce(0, +)/Double(decisionStats.sig.count)
			let satMean = decisionStats.sat.reduce(0, +)/Double(decisionStats.sat.count)
			let sigEMA = decisionStats.sig.reduce(sigMean, {$0*(1.0-emaMultipler) + $1*emaMultipler} )
			let satEMA = decisionStats.sat.reduce(satMean, {$0*(1.0-emaMultipler) + $1*emaMultipler} )

			writeToHook("movingAverageWPM", data: "\(city.events.now.asSeconds)\(separator)\(sigEMA)\(separator)\(satEMA)\(terminator)")
		}

	}


	/// Final statistics collection routine
	func finalCollection(onCity city: City) {
		if hooks["finalRoadsideUnitCoverageMaps"] != nil {
			for rsu in city.roadsideUnits {
				writeToHook("finalRoadsideUnitCoverageMaps", data: "\(terminator)RSU ID \(rsu.id) type \(rsu.type) created \(rsu.creationTime!.asSeconds)\(terminator)")
				writeToHook("finalRoadsideUnitCoverageMaps", data: rsu.selfCoverageMap.description)
			}
		}

		if hooks["finalCityCoverageMap"] != nil {
			if let maskMap = obstructionMask {
				let croppedMap = city.globalMapOfCoverage.crop(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)
				writeToHook("finalCityCoverageMap", data: croppedMap.description) }
			else { writeToHook("finalCityCoverageMap", data: city.globalMapOfCoverage.description) }
		}

		if hooks["finalCitySaturationMap"] != nil {
			if let maskMap = obstructionMask {
				let croppedMap = city.globalMapOfSaturation.crop(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)
				writeToHook("finalCitySaturationMap", data: croppedMap.description) }
			else { writeToHook("finalCitySaturationMap", data: city.globalMapOfSaturation.description) }
		}

		if hooks["finalCityEntitiesMap"] != nil {
			if let maskMap = obstructionMask {
				let croppedMap = city.globalMapOfEntities.crop(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)
				writeToHook("finalCityEntitiesMap", data: croppedMap.description) }
			else { writeToHook("finalCityEntitiesMap", data: city.globalMapOfEntities.description) }
		}

		if hooks["finalCityCoverageStats"] != nil {
			// Data to write to the hook
			var statData = String()

			// 1. Get the obstruction mask map
			if let maskMap = obstructionMask {
				// Create a measurement
				var sigMeasure = Measurement()
				// Get the city coverage map and crop it to the obstruction mask
				var signalCoverageMap = city.globalMapOfCoverage.crop(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)

				// 1.1. Push every measurement if the matching obstruction map cell is marked [O]pen
				for i in 0..<signalCoverageMap.size.y {
					for j in 0..<signalCoverageMap.size.x {
						if maskMap.cells[i][j] == Character("O") {
							sigMeasure.add(Double(signalCoverageMap.cells[i][j]))
						}
					}
				}

				// 1.2. Record the desired metrics
				statData += "count\(separator)\(sigMeasure.count)\(terminator)"
				statData += "mean\(separator)\(sigMeasure.mean)\(terminator)"
				statData += "var\(separator)\(sigMeasure.variance)\(terminator)"
				statData += "stdev\(separator)\(sigMeasure.stdev)\(terminator)"
				statData += "samples\(separator)\(sigMeasure.samples.description)\(terminator)"
			} else {
				// Print an error message if a mask was not provided
				statData = "Please generate and provide an obstruction mask first."
			}

			// 2. Write data
			writeToHook("finalCityCoverageStats", data: statData)
		}

		if hooks["finalCitySaturationStats"] != nil {
			// Data to write to the hook
			var statData = String()
			
			// 1. Get the obstruction mask map
			if let maskMap = obstructionMask {
				// Create a measurement
				var satMeasure = Measurement()
				// Get the city saturation map and crop it to the obstruction mask
				var rsuSaturationMap = city.globalMapOfSaturation.crop(newTopLeftCell: maskMap.topLeftCellCoordinate, newSize: maskMap.size)

				// 1.1. Push every measurement if the matching obstruction map cell is marked [O]pen
				for i in 0..<rsuSaturationMap.size.y {
					for j in 0..<rsuSaturationMap.size.x {
						if maskMap.cells[i][j] == Character("O") {
							satMeasure.add(Double(rsuSaturationMap.cells[i][j]))
						}
					}
				}

				// 1.2. Record the desired metrics
				statData += "count\(separator)\(satMeasure.count)\(terminator)"
				statData += "mean\(separator)\(satMeasure.mean)\(terminator)"
				statData += "var\(separator)\(satMeasure.variance)\(terminator)"
				statData += "stdev\(separator)\(satMeasure.stdev)\(terminator)"
				statData += "samples\(separator)\(satMeasure.samples.description)\(terminator)"
			} else {
				// Print an error message if a mask was not provided
				statData = "Please generate and provide an obstruction mask first."
			}

			// 2. Write data
			writeToHook("finalCitySaturationStats", data: statData)
		}

		if hooks["obstructionMask"] != nil {
			if let maskMap = city.stats.obstructionMask {
				writeToHook("obstructionMask", data: maskMap.description)
			} else {
				writeToHook("obstructionMask", data: "Please generate and provide an obstruction mask first.")
			}
		}
	}


	/// Add header lines to all registered hooks
	func addHookHeaders() {
		// entityCount
		if hooks["entityCount"] != nil {
			writeToHook("entityCount", data: "time\(separator)vehicles\(separator)roadsideUnits\(separator)parkedCars\(terminator)")
		}

		if hooks["beaconCount"] != nil {
			writeToHook("beaconCount", data: "time\(separator)sent\(separator)recv\(terminator)")
		}

		if hooks["cityCoverageEvolution"] != nil {
			writeToHook("cityCoverageEvolution", data: "time\(separator)#covered\(separator)%covered\(separator)meanSig\(separator)stdevSig\(separator)0cells\(separator)1cells\(separator)2cells\(separator)3cells\(separator)4cells\(separator)5cells\(terminator)")
		}

		if hooks["signalAndSaturationEvolution"] != nil {
			writeToHook("signalAndSaturationEvolution", data: "time\(separator)meanSig\(separator)stdevSig\(separator)meanSat\(separator)stdevSat\(separator)sigToSat\(separator)\(terminator)")
		}

		if hooks["decisionCCE"] != nil {
			writeToHook("decisionCCE", data: "time\(separator)id\(separator)dNew\(separator)dBoost\(separator)dSat\(separator)dScore\(separator)kappa\(separator)lambda\(separator)mu\(terminator)")
		}

		if hooks["decisionWPM"] != nil {
			writeToHook("decisionWPM", data: "time\(separator)id\(separator)asig\(separator)asat\(separator)acov\(separator)abat\(separator)wpm\(separator)disabled\(separator)disableSelf\(separator)meanSig\(separator)stdevSig\(separator)meanSat\(separator)stdevSat\(separator)sigToSat\(terminator)")
		}

		if hooks["movingAverageWPM"] != nil {
			writeToHook("decisionWPM", data: "time\(separator)meanSigEMA\(separator)meanSatEMA\(terminator)")
		}

		if hooks["packetTrace"] != nil {
			writeToHook("packetTrace", data: "id\(separator)created\(separator)l2src\(separator)l3src\(separator)l3dst\(separator)payload\(terminator)")
		}

		if hooks["parkedRoadsideUnitLifetime"] != nil {
			writeToHook("parkedRoadsideUnitLifetime", data: "rsuID\(separator)created\(separator)removed\(separator)lifetime\(terminator)")
		}
	}



	/// Initialize the array of statistical metrics
	func initMetrics() {
		metrics["beaconsSent"] = UInt(0)
		metrics["beaconsReceived"] = UInt(0)
		metrics["movingAverageWPM"] = (sig: [Double](), sat: [Double]())
	}
}
