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

	// Load decision configuration from config file entry
	init(config: NSDictionary) {
		// Load general statistics configurations, if defined: folder, interval, startTime
		if let triggerDelayConfig = config["triggerDelay"] as? Int {
			triggerDelay = SimulationTime(seconds: triggerDelayConfig)
		}

		guard	let algoConfig = config["algorithm"] as? NSDictionary,
				let algoInUse = algoConfig["inUse"] as? String else {
					print("Error: Please specify a decision algorithm to use.")
					exit(EXIT_FAILURE)
		}

		switch algoInUse {
		case "CellCoverageEffects":
			guard let cellCoverageEffectsConfig = algoConfig["CellCoverageEffects"] as? NSDictionary,
					let kappa = cellCoverageEffectsConfig["kappa"] as? Double,
					let lamda = cellCoverageEffectsConfig["lamda"] as? Double,
					let mu = cellCoverageEffectsConfig["mu"] as? Double
			else {
				print("Error: Invalid parameters for CellCoverageEffects algorithm.")
				exit(EXIT_FAILURE)
			}
			algorithm = CellCoverageEffects(κ: kappa, λ: lamda, μ: mu)
		default:
			print("Error: Invalid decision algorithm chosen.")
			exit(EXIT_FAILURE)
		}
	}
}

// A decision algorithm must have a trigger to be called from the vehicle
protocol DecisionAlgorithm {
	func trigger(pcar: ParkedCar)
}

class CellCoverageEffects: DecisionAlgorithm {
	let kappa, lamda, mu: Double
	let mapRequestWaitingTime = SimulationTime(seconds: 1)

	init(κ: Double, λ: Double, μ: Double) {
		kappa = κ
		lamda = λ
		mu = μ
	}

	func trigger(pcar: ParkedCar) {
		// 1. Send a request for neighbor coverage maps
		pcar.isRequestingMaps = true
		let covMapRequestPacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: .Broadcast(hopLimit: 1), payload: Payload(type: .CoverageMapRequest, content: CoverageMapRequest().toPayload().content) )
		pcar.broadcastPacket(covMapRequestPacket)

		// 2. Schedule an event to process the coverage maps and make the decision
		let decisionEvent = SimulationEvent(time: pcar.city.events.now + mapRequestWaitingTime, type: .Decision, action: { self.decide(pcar)}, description: "decide id \(pcar.id)")
		pcar.city.events.add(newEvent: decisionEvent)
	}

	func decide(pcar: ParkedCar) {
		// 1. Stop receiving maps
		pcar.isRequestingMaps = false

		// 2. Run algorithm if at least 1 coverage map was received
		let mapPayloadList = pcar.payloadBuffer.filter( {$0.type == .CoverageMap} )
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
			               y: (start: pcar.selfCoverageMap.topLeftCellCoordinate.y,
									end: pcar.selfCoverageMap.topLeftCellCoordinate.x + pcar.selfCoverageMap.size.x - 1))

			// Run through actionRange on the SCM, LMC, LMS and update the stats
			for yy in actionRange.y.start ... actionRange.y.end {
				for xx in actionRange.x.start ... actionRange.x.end {
					if pcar.selfCoverageMap[xx,yy] > 0 {
						if localMapOfCoverage[xx,yy] == 0 {
							dNew += pcar.selfCoverageMap[xx,yy]
						} else if localMapOfCoverage[xx,yy] < pcar.selfCoverageMap[xx,yy] {
							dBoost += (pcar.selfCoverageMap[xx,yy]-localMapOfCoverage[xx,yy])
						}
						dSat += localMapOfSaturation[xx,yy]
					}
				}
			}

			// 5. Compute dScore
			let dScore = kappa*Double(dNew) + lamda*Double(dBoost) - mu*Double(dSat)
			if dScore <= 0 { return }
		} else {
			return
		}

		// Parked car becomes an RSU (unless we returned earlier)
		pcar.city.convertEntity(pcar, to: .RoadsideUnit)
	}
}