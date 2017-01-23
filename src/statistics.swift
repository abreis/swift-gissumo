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
		}

		// Load obstruction mask if given
		if let maskFileConfig = config["obstructionMaskFile"] as? String {
			let maskFileURL = URL(fileURLWithPath: maskFileConfig)
			do {
				let maskAsString = try String(contentsOf: maskFileURL)
				let maskAsPayload = Payload(type: .coverageMap, content: maskAsString)
				obstructionMask = CellMap<Character>(fromPayload: maskAsPayload)
			} catch {
				obstructionMask = nil
			}
		}

		// Initialize metrics
		initMetrics()

		// Add header lines to enabled hooks
		addHookHeaders()
	}

	// Write all collected statistical data, overwriting existing files
	func writeStatisticsToFiles() {
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

		// Write all collected data
		for (statName, statData) in hooks {
			let hookURL = URL(fileURLWithPath: "\(folder)\(statName).log")
			do {
				try statData.write(to: hookURL, atomically: true, encoding: String.Encoding.utf8)
			} catch {
				print("Error: Failed to write statistical data to", hookURL)
				print(error)
				exit(EXIT_FAILURE)
			}
		}
	}

	// Add data to a specific statistic
	func writeToHook(_ name: String, data: String) {
		guard hooks[name] != nil else {
			print("Error: Tried to write to an undeclared stat hook.")
			exit(EXIT_FAILURE)
		}
		hooks[name]! += data
	}


	// Schedule collection events by startTime & interval until stopTime
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
		// activeVehicleCount
		if hooks["activeVehicleCount"] != nil {
			writeToHook("activeVehicleCount", data: "\(city.events.now.asSeconds)\(separator)\(city.vehicles.count)\(terminator)")
		}

		// activeRoadsideUnitCount
		if hooks["activeRoadsideUnitCount"] != nil {
			writeToHook("activeRoadsideUnitCount", data: "\(city.events.now.asSeconds)\(separator)\(city.roadsideUnits.count)\(terminator)")
		}

		// beaconCounts
		if hooks["beaconCounts"] != nil {
			guard	let beaconsSent = metrics["beaconsSent"] as? UInt,
					let beaconsRecv = metrics["beaconsReceived"] as? UInt
					else {
						print("Error: Metrics unavailable for beaconCounts hook.")
						exit(EXIT_FAILURE)
			}
			writeToHook("beaconCounts", data: "\(city.events.now.asSeconds)\(separator)\(beaconsSent)\(separator)\(beaconsRecv)\(terminator)")
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
				// Get the city coverage map and crop it to the obstruction mask
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
		// activeVehicleCount
		if hooks["activeVehicleCount"] != nil {
			writeToHook("activeVehicleCount", data: "time\(separator)count\(terminator)")
		}

		// activeRoadsideUnitCount
		if hooks["activeRoadsideUnitCount"] != nil {
			writeToHook("activeRoadsideUnitCount", data: "time\(separator)count\(terminator)")
		}

		if hooks["beaconCounts"] != nil {
			writeToHook("beaconCounts", data: "time\(separator)sent\(separator)recv\(terminator)")
		}

		if hooks["cityCoverageEvolution"] != nil {
			writeToHook("cityCoverageEvolution", data: "time\(separator)#covered\(separator)%covered\(separator)meanSig\(separator)stdevSig\(separator)0cells\(separator)1cells\(separator)2cells\(separator)3cells\(separator)4cells\(separator)5cells\(terminator)")
		}

		if hooks["decisionCellCoverageEffects"] != nil {
			writeToHook("decisionCellCoverageEffects", data: "time\(separator)id\(separator)dNew\(separator)dBoost\(separator)dSat\(separator)dScore\(separator)kappa\(separator)lambda\(separator)mu\(terminator)")
		}
	}



	/// Initialize the array of statistical metrics
	func initMetrics() {
		metrics["beaconsSent"] = UInt(0)
		metrics["beaconsReceived"] = UInt(0)
	}
}
