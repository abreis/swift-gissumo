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
					let gamma = cellCoverageEffectsConfig["gamma"] as? Double,
					let mu = cellCoverageEffectsConfig["mu"] as? Double
			else {
				print("Error: Invalid parameters for CellCoverageEffects algorithm.")
				exit(EXIT_FAILURE)
			}
			algorithm = CellCoverageEffects(κ: kappa, ɣ: gamma, μ: mu)
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
	let kappa, gamma, mu: Double
	let mapRequestWaitingTime = SimulationTime(seconds: 1)

	init(κ: Double, ɣ: Double, μ: Double) {
		kappa = κ
		gamma = ɣ
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
		if pcar.payloadBuffer.filter( {$0.type == .CoverageMap} ).count > 0 {
//			let localMapOfCoverage = 
//			let localMapOfSaturation = 
		}

		// Parked car becomes an RSU
		pcar.city.convertEntity(pcar, to: .RoadsideUnit)
	}
}