/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class Statistics {
	// Configuration entries
	var folder: String = "stats/"
	var interval: Double = 1.0
	var startTime: Double = 1.0

	// A dictionary containing (statisticName,statisticData) pairs
	var hooks = [String:String]()

	// A dictionary of metrics for other routines to store data on
	var metrics = [String:Any]()

	// Data separator (e.g. ',' or ';' for CSV (comma not recommended in Europe, prefer semicolon), '\t' for TSV
	let separator = "\t"

	init(config: NSDictionary) {
		// Load general statistics configurations, if defined: folder, interval, startTime
		if let configFolder = config["statsFolder"] as? String {
			folder = configFolder
			if !folder.hasSuffix("/") {	folder.append(Character("/")) }
		}

		if let configInterval = config["collectionInterval"] as? Double {
			interval = configInterval
		}

		if let configStartTime = config["collectionStartTime"] as? Double {
			startTime = configStartTime
		}

		// Load hook list and ready statistics collection point
		if let hookList = config["hooks"] as? NSDictionary {
			for element in hookList {
				if let enabled = element.value as? Bool where enabled == true {
					let hook = String(element.key)
					hooks[hook] = ""
				}
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
		let folderURL = NSURL.fileURLWithPath(folder)
		do {
			if !folderURL.checkResourceIsReachableAndReturnError(nil) {
				try NSFileManager.defaultManager().createDirectoryAtURL(folderURL, withIntermediateDirectories: true, attributes: nil)
			}
		} catch let error as NSError {
			print("Error: Failed to create collection directory", folderURL)
			print(error)
			exit(EXIT_FAILURE)
		}

		// Write all collected data
		for (statName, statData) in hooks {
			let hookURL = NSURL.fileURLWithPath("\(folder)\(statName).log")
			do {
				try statData.writeToURL(hookURL, atomically: true, encoding: NSUTF8StringEncoding)
			} catch {
				print("Error: Failed to write statistical data to", hookURL)
				print(error)
				exit(EXIT_FAILURE)
			}
		}
	}

	// Add data to a specific statistic
	func writeToHook(name: String, data: String) {
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
			let scheduledCollectionEvent = SimulationEvent(time: scheduledCollectionTime, type: .Statistics, action: { city.stats.collectStatistics(fromCity: city)}, description: "scheduledCollectStats")
			city.events.add(newEvent: scheduledCollectionEvent)

			// Jump to next collection time
			scheduledCollectionTime += interval
		} while scheduledCollectionTime < city.events.stopTime

		// Schedule a cleanup-stage event to collect final statistics
		let finalCollectionEvent = SimulationEvent(time: 0, type: .Statistics, action: {city.stats.finalCollection(onCity: city)}, description: "finalCollectStats")
		city.events.add(cleanupEvent: finalCollectionEvent)

		// Schedule a cleanup-stage event to write all statistical data to files
		let statWriteEvent = SimulationEvent(time: 0, type: .Statistics, action: {city.stats.writeStatisticsToFiles()} , description: "writeStatsToFiles")
		city.events.add(cleanupEvent: statWriteEvent)
	}


	// Periodic (intervalled) statistics collection routine
	func collectStatistics(fromCity city: City) {
		// activeVehicleCount
		if hooks["activeVehicleCount"] != nil {
			writeToHook("activeVehicleCount", data: "\(city.events.now.milli)\(separator)\(city.vehicles.count)\n")
		}

		// activeRoadsideUnitCount
		if hooks["activeRoadsideUnitCount"] != nil {
			writeToHook("activeRoadsideUnitCount", data: "\(city.events.now.milli)\(separator)\(city.roadsideUnits.count)\n")
		}

		// beaconCounts
		if hooks["beaconCounts"] != nil {
			guard	let beaconsSent = metrics["beaconsSent"] as? UInt,
					let beaconsRecv = metrics["beaconsReceived"] as? UInt
					else {
						print("Error: Metrics unavailable for beaconCounts hook.")
						exit(EXIT_FAILURE)
			}
			writeToHook("beaconCounts", data: "\(city.events.now.milli)\(separator)\(beaconsSent)\(separator)\(beaconsRecv)\n")
		}
	}

	// Final statistics collection routine
	func finalCollection(onCity city: City) {
		if hooks["finalRoadsideUnitCoverageMaps"] != nil {
			for rsu in city.roadsideUnits {
				writeToHook("finalRoadsideUnitCoverageMaps", data: "\nRSU ID \(rsu.id) type \(rsu.type) created \(rsu.creationTime!.milli)\n")
				writeToHook("finalRoadsideUnitCoverageMaps", data: rsu.localCoverageMap.description)
			}
		}
	}


	// Hook header lines
	func addHookHeaders() {
		// activeVehicleCount
		if hooks["activeVehicleCount"] != nil {
			writeToHook("activeVehicleCount", data: "time\(separator)count\n")
		}

		// activeRoadsideUnitCount
		if hooks["activeRoadsideUnitCount"] != nil {
			writeToHook("activeRoadsideUnitCount", data: "time\(separator)count\n")
		}

		if hooks["beaconCounts"] != nil {
			writeToHook("beaconCounts", data: "time\(separator)sent\(separator)recv\n")
		}
	}

	// Metrics
	func initMetrics() {
		metrics["beaconsSent"] = UInt(0)
		metrics["beaconsReceived"] = UInt(0)
	}
}
