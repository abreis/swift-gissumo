/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

/* A decision object to enclose the decision process, its algorithms and parameters.
 */
class Decision {
	// The time to wait before running the actual decision process, so cars can build their coverage maps
	var triggerDelay = SimulationTime(seconds:500)

	// The selected algorithm
	var algorithm: DecisionAlgorithm

	// The reach of coverage map requests
	var reqReach: String

	// Load decision configuration from config file entry
	init(config: NSDictionary) {
		// Load general statistics configurations, if defined: folder, interval, startTime
		if let triggerDelayConfig = config["triggerDelay"] as? Int {
			triggerDelay = SimulationTime(seconds: triggerDelayConfig)
		}

		guard let requestReachConfig = config["mapRequestReach"] as? String,
			["1hop","2hop","geocast2r"].contains(requestReachConfig) else {
				print("Error: Please specify a valid reach for coverage map requests.")
				exit(EXIT_FAILURE)
		}
		reqReach = requestReachConfig

		guard	let algoConfig = config["algorithm"] as? NSDictionary,
				let algoInUse = algoConfig["inUse"] as? String else {
					print("Error: Please specify a decision algorithm to use.")
					exit(EXIT_FAILURE)
		}

		switch algoInUse {
		case "CellCoverageEffects":
			guard let cellCoverageEffectsConfig = algoConfig["CellCoverageEffects"] as? NSDictionary,
					let kappa = cellCoverageEffectsConfig["kappa"] as? Double,
					let lambda = cellCoverageEffectsConfig["lambda"] as? Double,
					let mu = cellCoverageEffectsConfig["mu"] as? Double
			else {
				print("Error: Invalid parameters for CellCoverageEffects algorithm.")
				exit(EXIT_FAILURE)
			}

			let satThresh = cellCoverageEffectsConfig["saturationThreshold"] as? Int
			algorithm = CellCoverageEffects(κ: kappa, λ: lambda, μ: mu, requestReach: reqReach, saturationThreshold: satThresh)
		default:
			print("Error: Invalid decision algorithm chosen.")
			exit(EXIT_FAILURE)
		}
	}
}

// A decision algorithm must have a trigger to be called from the vehicle
protocol DecisionAlgorithm {
	func trigger(_ pcar: ParkedCar)
}

class CellCoverageEffects: DecisionAlgorithm {
	let kappa, lambda, mu: Double
	var saturationThreshold: Int = -1
	let mapRequestWaitingTime = SimulationTime(seconds: 1)
	let requestReach: String

	init(κ: Double, λ: Double, μ: Double, requestReach reqReach: String, saturationThreshold: Int? = nil) {
		kappa = κ
		lambda = λ
		mu = μ
		requestReach = reqReach
		if let satThresh = saturationThreshold { self.saturationThreshold = satThresh }
	}

	func trigger(_ pcar: ParkedCar) {
		// 1. Send a request for neighbor coverage maps
		pcar.isRequestingMaps = true

		var l3requestType: Packet.Destination
		switch(requestReach) {
		case "1hop":
			l3requestType = Packet.Destination.broadcast(hopLimit: 1)
		case "2hop":
			l3requestType = Packet.Destination.broadcast(hopLimit: 2)
		case "geocast2r":
			l3requestType = Packet.Destination.geocast(targetArea: Circle(centerIn: pcar.geo, radiusIn: pcar.city.network.maxRange) )
		default:
			print("Error: Coverage map request reach '\(requestReach)' not implemented.")
			exit(EXIT_FAILURE)
		}

		let covMapRequestPacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: l3requestType, payload: Payload(type: .coverageMapRequest, content: CoverageMapRequest().toPayload().content) )
		pcar.broadcastPacket(covMapRequestPacket)

		// 2. Schedule an event to process the coverage maps and make the decision
		let decisionEvent = SimulationEvent(time: pcar.city.events.now + mapRequestWaitingTime, type: .decision, action: { self.decide(pcar)}, description: "decide id \(pcar.id)")
		pcar.city.events.add(newEvent: decisionEvent)
	}

	func decide(_ pcar: ParkedCar) {
		// 1. Stop receiving maps
		pcar.isRequestingMaps = false

		// 2. Run algorithm if at least 1 coverage map was received
		let mapPayloadList = pcar.payloadBuffer.filter( {$0.type == .coverageMap} )

		if mapPayloadList.count > 0 {
			// 1. Convert the payloads to actual maps
			var mapList = [CellMap<Int>]()
			for mapPayload in mapPayloadList {
				guard let newMap = CellMap<Int>(fromPayload: mapPayload) else {
					print("Error: Failed to convert coverage map payload to an actual map.")
					exit(EXIT_FAILURE)
				}
				mapList.append(newMap)
			}

			// 2. Set up empty maps for neighborhood coverage and saturation
			// Consider the vehicle's map as well, so these maps can encompass it
			var extendedMapList = mapList
			extendedMapList.append(pcar.selfCoverageMap)
			var localMapOfCoverage = CellMap<Int>(toContainMaps: extendedMapList, withValue: 0)
			var localMapOfSaturation = CellMap<Int>(toContainMaps: extendedMapList, withValue: 0)

			// 3. Populate maps
			for map in mapList {
				localMapOfCoverage.keepBestSignal(fromSignalMap: map)
				localMapOfSaturation.incrementSaturation(fromSignalMap: map)
			}

			// 4. Run the algorithm
			var dNew:	Int = 0
			var dBoost: Int = 0
			var dSat:	Int = 0

			// actionRange goes through each cell in the car's self coverage map
			// These are the only cells where overlap occurs with the neighbors' maps
			let actionRange = (x: (start: pcar.selfCoverageMap.topLeftCellCoordinate.x,
									end: pcar.selfCoverageMap.topLeftCellCoordinate.x + pcar.selfCoverageMap.size.x - 1),
			               y: (start: pcar.selfCoverageMap.topLeftCellCoordinate.y - pcar.selfCoverageMap.size.y + 1,
									end: pcar.selfCoverageMap.topLeftCellCoordinate.y))

			// Run through actionRange on the SCM, LMC, LMS and compute the stats
			for yy in actionRange.y.start ... actionRange.y.end {
				for xx in actionRange.x.start ... actionRange.x.end {
					let cellLocation = (x: xx, y: yy)

					// If we cover this cell
					if pcar.selfCoverageMap[cellLocation] > 0 {
						if localMapOfCoverage[cellLocation] == 0 {
							// If no-one else covers the cell, add to dNew
							dNew += pcar.selfCoverageMap[cellLocation]
						} else if localMapOfCoverage[cellLocation] < pcar.selfCoverageMap[cellLocation] {
							// If we boost the signal on this cell, add to dBoost
							dBoost += (pcar.selfCoverageMap[cellLocation]-localMapOfCoverage[cellLocation])
						}
						// Add to dSat as a function of how much the cell is already saturated, over a specified threshold
						if localMapOfSaturation[cellLocation] >= saturationThreshold {
							dSat += localMapOfSaturation[cellLocation] - saturationThreshold + 1
							// Alternative algorithms:
							//dSat += 1
						}
					}
				}
			}

			// 5. Compute dScore
			let dScore = kappa*Double(dNew) + lambda*Double(dBoost) - mu*Double(dSat)

			// Debug
			if debug.contains("CellCoverageEffects.decide()"){
				print("\(pcar.city.events.now.asSeconds) CellCoverageEffects.decide():\t".cyan(), "ParkedCar", pcar.id, "mapCount", mapList.count, "dNew", dNew, "dBoost", dBoost, "dSat", dSat, "dScore", dScore ) }

			// Statistics
			if pcar.city.stats.hooks["detailedDecisions"] != nil {
				pcar.city.stats.writeToHook("detailedDecisions", data: "\n\n\n=== DECISION ON PARKED CAR ID \(pcar.id) ===\n")
				pcar.city.stats.writeToHook("detailedDecisions", data: "\n== Received Maps:\n")
				for map in mapList {
					pcar.city.stats.writeToHook("detailedDecisions", data: map.description)
				}

				pcar.city.stats.writeToHook("detailedDecisions", data: "\n== Self Coverage Map\n")
				pcar.city.stats.writeToHook("detailedDecisions", data: pcar.selfCoverageMap.description)

				pcar.city.stats.writeToHook("detailedDecisions", data: "\n== Local Map of Coverage\n")
				pcar.city.stats.writeToHook("detailedDecisions", data: localMapOfCoverage.description)

				pcar.city.stats.writeToHook("detailedDecisions", data: "\n== Local Map of Saturation\n")
				pcar.city.stats.writeToHook("detailedDecisions", data: localMapOfSaturation.description)

				pcar.city.stats.writeToHook("detailedDecisions", data: "\n== dNew \(dNew) dBoost \(dBoost) dSat \(dSat) dScore \(dScore)\n")
			}

			if pcar.city.stats.hooks["decisionCellCoverageEffects"] != nil {
				let separator = pcar.city.stats.separator
				pcar.city.stats.writeToHook("decisionCellCoverageEffects", data: "\(pcar.city.events.now.asSeconds)\(separator)\(pcar.id)\(separator)\(dNew)\(separator)\(dBoost)\(separator)\(dSat)\(separator)\(dScore)\(separator)\(kappa)\(separator)\(lambda)\(separator)\(mu)\n")
			}

			if dScore <= 0 { return }
		} else {
			// Debug
			if debug.contains("CellCoverageEffects.decide()"){
				print("\(pcar.city.events.now.asSeconds) CellCoverageEffects.decide():\t".cyan(), "ParkedCar", pcar.id, "mapCount", 0 ) }
		}

		// Parked car becomes an RSU (unless we returned earlier)
		pcar.city.convertEntity(pcar, to: .roadsideUnit)
	}
}
