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
		case "NullDecision":
			algorithm = NullDecision()
		case "CellCoverageEffects":
			guard let cellCoverageEffectsConfig = algoConfig["CellCoverageEffects"] as? NSDictionary,
					let kappa = cellCoverageEffectsConfig["kappa"] as? Double,
					let lambda = cellCoverageEffectsConfig["lambda"] as? Double,
					let mu = cellCoverageEffectsConfig["mu"] as? Double,
					let requestReachConfig = cellCoverageEffectsConfig["mapRequestReach"] as? String,
					["1hop","2hop","geocast2r"].contains(requestReachConfig)
			else {
				print("Error: Invalid parameters for CellCoverageEffects algorithm.")
				exit(EXIT_FAILURE)
			}

			let satThresh = cellCoverageEffectsConfig["saturationThreshold"] as? Int
			algorithm = CellCoverageEffects(κ: kappa, λ: lambda, μ: mu, requestReach: requestReachConfig, saturationThreshold: satThresh)
		case "BestNeighborhoodSolution":
			algorithm = BestNeighborhoodSolution()
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

/// NullDecision: a null decision algorithm that simply removes the parked car from the network
class NullDecision: DecisionAlgorithm {
	func trigger(_ pcar: ParkedCar) {
		let removalEvent = SimulationEvent(time: pcar.city.events.now + pcar.city.events.minTimestep, type: .decision, action: {pcar.city.removeEntity(pcar)}, description: "Parked car id \(pcar.id) removed by negative dScore")
		pcar.city.events.add(newEvent: removalEvent)
	}
}

/// CellCoverageEffects: a decision algorithm based on cell coverage: new coverage, improved coverage, excess coverage
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
		let mapPayloadList = pcar.payloadBuffer.filter( {$0.payload.type == .coverageMap} )

		if mapPayloadList.count > 0 {
			// 1. Convert the payloads to actual maps
			var mapList = [CellMap<Int>]()
			for mapPayload in mapPayloadList {
				guard let newMap = CellMap<Int>(fromPayload: mapPayload.payload) else {
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
			var localMapOfSaturation = localMapOfCoverage

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
				print("\(pcar.city.events.now.asSeconds) CellCoverageEffects.decide():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "ParkedCar", pcar.id, "mapCount", mapList.count, "dNew", dNew, "dBoost", dBoost, "dSat", dSat, "dScore", dScore ) }

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

			// If the parked car does not become an RSU, schedule it for removal
			if dScore <= 0 {
				let removalEvent = SimulationEvent(time: pcar.city.events.now + pcar.city.events.minTimestep, type: .decision, action: {pcar.city.removeEntity(pcar)}, description: "Parked car id \(pcar.id) removed by negative dScore")
				pcar.city.events.add(newEvent: removalEvent)
				return
			}
		} else {
			// Debug
			if debug.contains("CellCoverageEffects.decide()"){
				print("\(pcar.city.events.now.asSeconds) CellCoverageEffects.decide():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "ParkedCar", pcar.id, "mapCount", 0 ) }
		}

		// Parked car becomes an RSU (unless we returned earlier)
		pcar.city.convertEntity(pcar, to: .roadsideUnit)
	}
}


/// BestNeighborhoodSolution: a decision algorithm with the ability to shut down nearby RSUs
class BestNeighborhoodSolution: DecisionAlgorithm {
	let mapRequestWaitingTime = SimulationTime(seconds: 1)

	init() {}

	// On trigger, request 1-hop neighborhood coverage maps, and wait 1 second to receive replies before deciding
	func trigger(_ pcar: ParkedCar) {
		// 1. Send a request for neighbor coverage maps
		pcar.isRequestingMaps = true

		let covMapRequestPacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: Packet.Destination.broadcast(hopLimit: 1), payload: Payload(type: .coverageMapRequest, content: CoverageMapRequest().toPayload().content) )
		pcar.broadcastPacket(covMapRequestPacket)

		// 2. Schedule an event to process the coverage maps and make the decision
		let decisionEvent = SimulationEvent(time: pcar.city.events.now + mapRequestWaitingTime, type: .decision, action: { self.decide(pcar)}, description: "decide id \(pcar.id)")
		pcar.city.events.add(newEvent: decisionEvent)
	}

	func decide(_ pcar: ParkedCar) {
		// 1. Stop receiving maps
		pcar.isRequestingMaps = false

		// 2. Prepare neighborhood coverage maps
		// Filter out payloads that do not contain coverage maps from the buffer
		var neighborhoodCoverageMapPayloads = pcar.payloadBuffer.filter( {$0.payload.type == .coverageMap} )

		// Algorithm runs if at least one map was received; else, the vehicle becomes an RSU straight away
		if neighborhoodCoverageMapPayloads.count == 0 {
			pcar.city.convertEntity(pcar, to: .roadsideUnit)
			return
		}


		// 3. Combinatorials
		// Convert the payloads to actual maps
		var neighborhoodCoverageMaps = neighborhoodCoverageMapPayloads.map( { return (id: $0.id, map: CellMap<Int>(fromPayload: $0.payload)!) } )

		// Add our own map to the neighborhood
		neighborhoodCoverageMaps.append( (id: pcar.id, map: pcar.selfCoverageMap) )

		// Number of elements in each combination
		let setSize = neighborhoodCoverageMaps.count

		// A combination is an array of [Bool]
		typealias Combination = [Bool]

		// The array of possible combinations is an array of combinations
		var combinations = [Combination]()

		// Push the first combination (where no neighbors are disabled (nor our parked car)) into the set
		let baseCombination: Combination = Array(repeating: true, count: setSize)
		combinations.append(baseCombination)

		// Build and append (N choose 1) (combinations where a single neighbor is disabled)
		for cIndex in 0..<setSize {
			// Simply disable one entity at a time
			var newCombination = baseCombination
			newCombination[cIndex] = false
			combinations.append(newCombination)
		}

		// Build and append (N choose 2) (combinations where two neighbors are disabled)
		for cIndex in 0..<(setSize-1) {
			// Disable the entity at cIndex and a second entity after it
			var newCombination = baseCombination
			newCombination[cIndex] = false
			for cIndexNext in (cIndex+1)..<setSize {
				var newNewCombination = newCombination
				newNewCombination[cIndexNext] = false
				combinations.append(newNewCombination)
			}
		}

		if debug.contains("BestNeighborhoodSolution.decide()"){
			print("\(pcar.city.events.now.asSeconds) BestNeighborhoodSolution.decide():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Evaluating \(combinations.count) solutions at parked vehicle \(pcar.id)" )
		}

		// Combinatorial generation tested correctly
//		// Ensure the combinations array is of length (n choose 2)+n+1
//		func factorial(_ factorialNumber: Int) -> UInt64 {
//			guard factorialNumber < 21 else { print("Error: Factorial too large."); exit(EXIT_FAILURE) }
//			if factorialNumber == 0 { return 1 }
//			else { return UInt64(factorialNumber) * factorial(factorialNumber - 1) }
//		}
//		let expectedSize = Int(factorial(setSize)/(2*factorial(setSize-2))) + setSize + 1
//		guard combinations.count == expectedSize else {
//			print("Error: Incorrect combination size.");
//			print("\nexpectedSize \(expectedSize) combinations.count \(combinations.count) setSize \(setSize)\n")
//			exit(EXIT_FAILURE)
//		}


		// 4. Routine that analyzes a combination and returns its utility score
		/* We first create an obstruction mask based on the reference coverage (the coverage from the deciding vehicle).
		 * This is so that we can compute measurements only on cells that the deciding vehicle can directly reach
		 * (it will receive coverage information of cells beyond its reach). This avoids calculating coverage and 
		 * saturation beyond its range, where coverage from other RSUs might exist but we do not know about it.
		 */
		var localMapWithReferenceCoverageOnly = CellMap<Int>(toContainMaps: neighborhoodCoverageMaps.map( { return $0.map }), withValue: 0)
		localMapWithReferenceCoverageOnly.keepBestSignal(fromSignalMap: pcar.selfCoverageMap)
		let referenceVehicleObstructionMask = localMapWithReferenceCoverageOnly.expressAsObstructionMask()

		// The analysis routine
		func analyzeCombination(_ combination: Combination) -> Double {
			// Set up a coverage and a saturation map
			var localMapOfCoverage = CellMap<Int>(toContainMaps: neighborhoodCoverageMaps.map( { return $0.map }), withValue: 0)
			var localMapOfSaturation = localMapOfCoverage

			// Apply selected maps (in the combination) to the local maps
			for (combinationIndex, combinationValue) in combination.enumerated() {
				// If an entry in a combination is true, that RSU is to be left active
				if combinationValue == true {
					localMapOfCoverage.keepBestSignal(fromSignalMap: neighborhoodCoverageMaps[combinationIndex].map)
					localMapOfSaturation.incrementSaturation(fromSignalMap: neighborhoodCoverageMaps[combinationIndex].map)
				}
			}

			// Get a measurement confined to the reference vehicle's view
			let coverageData: Measurement = localMapOfCoverage.getMeasurement(withObstructionMask: referenceVehicleObstructionMask, includeNulls: false)
			let saturationData: Measurement = localMapOfSaturation.getMeasurement(withObstructionMask: referenceVehicleObstructionMask, includeNulls: false)

			// TODO
			// Right now, return the coverage-to-saturation ratio as the score
			return coverageData.mean/saturationData.mean
		}


		// 5. Decision: run through each combination, evaluate it, store its score, and decide
		var scoredCombinations = [(combination: Combination, score: Double)]()
		for combination in combinations {
			let score = analyzeCombination(combination)
			scoredCombinations.append( (combination: combination, score: (score.isNaN ? 0.0 : score) ) )
		}

		// Sort score array
		scoredCombinations.sort(by: {$0.score > $1.score})

		if debug.contains("BestNeighborhoodSolution.decide()"){
			print("\(pcar.city.events.now.asSeconds) BestNeighborhoodSolution.decide():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Combinations ordered by score:" )
			print("".padding(toLength: 54, withPad: " ", startingAt: 0), "score\tcombination")
			for scoredCombination in scoredCombinations {
				print("".padding(toLength: 54, withPad: " ", startingAt: 0), "\(String(format: "%.2f", scoredCombination.score).lightGray())\t\(scoredCombination.combination)")
			}
		}

		// Pick the best combination and execute it; send 'RSU disable' messages to RSUs disabled in the chosen solution
		let bestCombination = scoredCombinations.first!.combination

		// This flag determines whether the reference vehicle will become an RSU at the end of this process
		var disableSelf: Bool = false
		for (combinationIndex, combinationValue) in bestCombination.enumerated() {
			if combinationValue == false {
				// Entity will be disabled
				let entityID = neighborhoodCoverageMaps[combinationIndex].id

				if entityID == pcar.id {
					disableSelf = true
				} else {
					// Send an RSU disable message
					let disablePayload = DisableRoadsideUnit(disableID: entityID).toPayload()
					let disablePacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: .unicast(destinationID: entityID), payload: disablePayload)
					pcar.broadcastPacket(disablePacket, toFeatureTypes: .roadsideUnit)
				}
			}
		}

		// Parked car becomes an RSU
		if !disableSelf { pcar.city.convertEntity(pcar, to: .roadsideUnit) }
	}
}
