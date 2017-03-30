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

		case "WeightedProductModel":
			guard let weightedProductModelConfig = algoConfig["WeightedProductModel"] as? NSDictionary,
				let wsig = weightedProductModelConfig["wsig"] as? Double,
				let wsat = weightedProductModelConfig["wsat"] as? Double,
				let wcov = weightedProductModelConfig["wcov"] as? Double,
				let wbat = weightedProductModelConfig["wbat"] as? Double,
				let minRedundancy = weightedProductModelConfig["minRedundancy"] as? Double,
				let mapRequestDepth = weightedProductModelConfig["mapRequestDepth"] as? UInt
				else {
					print("Error: Invalid parameters for WeightedProductModel algorithm.")
					exit(EXIT_FAILURE)
			}
			algorithm = WeightedProductModel(weights: (wsig: wsig, wsat: wsat, wcov: wcov, wbat: wbat), minRedundancy: minRedundancy, mapRequestDepth: mapRequestDepth)

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

		let covMapRequestPacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: l3requestType, payload: Payload(type: .coverageMapRequest, content: CoverageMapRequest(depth: 1).toPayload().content) )
		pcar.broadcastPacket(covMapRequestPacket)

		// 2. Schedule an event to process the coverage maps and make the decision
		let decisionEvent = SimulationEvent(time: pcar.city.events.now + mapRequestWaitingTime, type: .decision, action: { self.decide(pcar)}, description: "decide id \(pcar.id)")
		pcar.city.events.add(newEvent: decisionEvent)
	}

	func decide(_ pcar: ParkedCar) {
//		let mapPayloadList = pcar.payloadBuffer.filter( {$0.payload.type == .coverageMap} )

		// Run algorithm if at least 1 coverage map was received
		if pcar.neighborMaps.count > 0 {
			//
			let mapList: [CellMap<Int>] = pcar.neighborMaps.map({ return $1.coverageMap })

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
			if pcar.city.stats.hooks["decisionDetailCCE"] != nil {
				pcar.city.stats.writeToHook("decisionDetailCCE", data: "\n\n\n=== DECISION ON PARKED CAR ID \(pcar.id) ===\n")
				pcar.city.stats.writeToHook("decisionDetailCCE", data: "\n== Received Maps:\n")
				for map in mapList {
					pcar.city.stats.writeToHook("decisionDetailCCE", data: map.description)
				}

				pcar.city.stats.writeToHook("decisionDetailCCE", data: "\n== Self Coverage Map\n")
				pcar.city.stats.writeToHook("decisionDetailCCE", data: pcar.selfCoverageMap.description)

				pcar.city.stats.writeToHook("decisionDetailCCE", data: "\n== Local Map of Coverage\n")
				pcar.city.stats.writeToHook("decisionDetailCCE", data: localMapOfCoverage.description)

				pcar.city.stats.writeToHook("decisionDetailCCE", data: "\n== Local Map of Saturation\n")
				pcar.city.stats.writeToHook("decisionDetailCCE", data: localMapOfSaturation.description)

				pcar.city.stats.writeToHook("decisionDetailCCE", data: "\n== dNew \(dNew) dBoost \(dBoost) dSat \(dSat) dScore \(dScore)\n")
			}

			if pcar.city.stats.hooks["decisionCCE"] != nil {
				let separator = pcar.city.stats.separator
				pcar.city.stats.writeToHook("decisionCCE", data: "\(pcar.city.events.now.asSeconds)\(separator)\(pcar.id)\(separator)\(dNew)\(separator)\(dBoost)\(separator)\(dSat)\(separator)\(dScore)\(separator)\(kappa)\(separator)\(lambda)\(separator)\(mu)\n")
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


/// WeightedProductModel: a multi-criteria decision making approach
class WeightedProductModel: DecisionAlgorithm {
	let mapRequestWaitingTime = SimulationTime(seconds: 1)
	var weights: (wsig: Double, wsat: Double, wcov: Double, wbat: Double) = (1.0, 1.0, 1.0, 1.0)
	var minRedundancy: Double = 2.0
	var mapRequestDepth: UInt = 1

	init(weights: (wsig: Double, wsat: Double, wcov: Double, wbat: Double), minRedundancy: Double, mapRequestDepth: UInt) {
		self.weights = weights
		self.minRedundancy = minRedundancy
		self.mapRequestDepth = mapRequestDepth
	}

	// On trigger, request 1-hop neighborhood coverage maps, and wait 1 second to receive replies before deciding
	func trigger(_ pcar: ParkedCar) {
		// Request neighbors' coverage maps
		let covMapRequestPacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: Packet.Destination.broadcast(hopLimit: 1), payload: CoverageMapRequest(depth: mapRequestDepth).toPayload() )
		pcar.broadcastPacket(covMapRequestPacket)

		// Request neighbors' active times
		let actTimeRequestPacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: Packet.Destination.broadcast(hopLimit: 1), payload: ActiveTimeRequest().toPayload() )
		pcar.broadcastPacket(actTimeRequestPacket)

		// Schedule an event to process the coverage maps and make the decision
		let decisionEvent = SimulationEvent(time: pcar.city.events.now + mapRequestWaitingTime, type: .decision, action: { self.decide(pcar)}, description: "decide id \(pcar.id)")
		pcar.city.events.add(newEvent: decisionEvent)
	}


	/// Weighted Product Model decision
	func decide(_ pcar: ParkedCar) {
		if debug.contains("WeightedProductModel.decide()") {
			print("\(pcar.city.events.now.asSeconds) WeightedProductModel.decide():"
				.padding(toLength: 54, withPad: " ", startingAt: 0).cyan(),
			      "Parked car \(pcar.id) deciding, neighborMaps: (d1: \(pcar.neighborMaps.filter({$1.distance == 1}).count), d2: \(pcar.neighborMaps.filter({$1.distance == 2}).count))") }


		/// 1. Algorithm runs if at least one 1-hop neighbor RSU is present, otherwise the vehicle becomes an RSU straight away
		if pcar.neighborMaps.filter({$1.distance == 1}).count == 0 {
			if debug.contains("WeightedProductModel.decide()") {
				print("\(pcar.city.events.now.asSeconds) WeightedProductModel.decide():"
					.padding(toLength: 54, withPad: " ", startingAt: 0).cyan(),
				      "Parked car \(pcar.id) has no 1-hop neighbors, converting to RSU") }

			pcar.city.convertEntity(pcar, to: .roadsideUnit)
			return
		}


		/// 2. Prepare the coverage maps on the combination pool
		var neighborhoodCoverageMaps: [SelfCoverageMap] = []

		// Self, depth 1, and depth 2 coverage maps
		let selfmap: SelfCoverageMap = SelfCoverageMap(ownerID: pcar.id, cellMap: pcar.selfCoverageMap)
		let depth1maps: [SelfCoverageMap] = pcar.neighborMaps.filter{$1.distance == 1}.map{ return SelfCoverageMap(ownerID: $0, cellMap: $1.coverageMap ) }
		let depth2maps: [SelfCoverageMap] = pcar.neighborMaps.filter{$1.distance == 2}.map{ return SelfCoverageMap(ownerID: $0, cellMap: $1.coverageMap ) }

		// Add ourselves
		neighborhoodCoverageMaps.append( selfmap )

		// Add all distance == 1 neighbor maps
		neighborhoodCoverageMaps += depth1maps

		// Number of elements in each combination
		let setSize = neighborhoodCoverageMaps.count


		/// 3. Combinatorials
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

		if debug.contains("WeightedProductModel.decide()") {
			print("\(pcar.city.events.now.asSeconds) WeightedProductModel.decide():"
				.padding(toLength: 54, withPad: " ", startingAt: 0).cyan(),
			      "Evaluating \(combinations.count) solutions at parked car \(pcar.id)" ) }

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


		/// 4. Routine that analyzes a combination and returns its utility score
		/* We first create an obstruction mask based on the reference coverage (the coverage from the deciding vehicle).
		* This is so that we can compute measurements only on cells that the deciding vehicle can directly reach
		* (it will receive coverage information of cells beyond its reach). This avoids calculating coverage and
		* saturation beyond its range, where coverage from other RSUs might exist but we do not know about it.
		*/
		let baseLocalMap = CellMap<Int>(toContainMaps: ([selfmap] + depth1maps + depth2maps).map{$0.cellMap}, withValue: 0)
		var localMapWithReferenceCoverageOnly = baseLocalMap
		localMapWithReferenceCoverageOnly.keepBestSignal(fromSignalMap: pcar.selfCoverageMap)
		let referenceVehicleObstructionMask = localMapWithReferenceCoverageOnly.expressAsObstructionMask()

		// Count the number of covered cells in the all-on (S0) combination (for the acov attribute)
		var baseCombinationLMC = CellMap<Int>(toContainMaps: ([selfmap] + depth1maps + depth2maps).map{$0.cellMap}, withValue: 0)
		for baseMap in ([selfmap] + depth1maps).map({$0.cellMap}) { baseCombinationLMC.keepBestSignal(fromSignalMap: baseMap) }
		let baseCoveredCellCount: Int = baseCombinationLMC.getMeasurement(withObstructionMask: nil, includeNulls: false).count

		// The scoring routine
		struct CombinationStatistics {
			var asig: Double = 0.0, asat: Double = 0.0, acov: Double = 0.0, abat: Double = 0.0
			var wpmScore: Double = 0.0
			var sigMeasure = Measurement(), satMeasure = Measurement(), covMeasure = Measurement()
		}
		func analyzeCombination(_ combination: Combination) -> CombinationStatistics {
			// Set up a coverage and a saturation map
			var localMapOfCoverage = baseLocalMap
			var localMapOfSaturation = baseLocalMap

			// Apply depth 2 maps (permanent for all combinations)
			if depth2maps.count > 0 {
				for depth2map in depth2maps {
					localMapOfCoverage.keepBestSignal(fromSignalMap: depth2map.cellMap)
					localMapOfSaturation.incrementSaturation(fromSignalMap: depth2map.cellMap)
				}

				if debug.contains("WeightedProductModel.analyzeCombination()") {
					print("\(pcar.city.events.now.asSeconds) WeightedProductModel.analyzeCombination():"
						.padding(toLength: 54, withPad: " ", startingAt: 0).cyan(),
					      "Depth 2 Signal | Saturation | Reference maps\n")
					print(localMapOfCoverage.cleanDescription(replacing: 0).mergeHorizontally(toTheLeftOf: localMapOfSaturation.cleanDescription(replacing: 0)).mergeHorizontally(toTheLeftOf: referenceVehicleObstructionMask.cleanDescription(replacing: Character("B"))) )
				}
			}

			// Apply selected maps (in the combination) to the local maps
			for (combinationIndex, combinationValue) in combination.enumerated() {
				// If an entry in a combination is true, that RSU is to be left active
				if combinationValue == true {
					localMapOfCoverage.keepBestSignal(fromSignalMap: neighborhoodCoverageMaps[combinationIndex].cellMap)
					localMapOfSaturation.incrementSaturation(fromSignalMap: neighborhoodCoverageMaps[combinationIndex].cellMap)
				}
			}

			if debug.contains("WeightedProductModel.analyzeCombination()") {
				print("\(pcar.city.events.now.asSeconds) WeightedProductModel.analyzeCombination():"
					.padding(toLength: 54, withPad: " ", startingAt: 0).cyan(),
				      "Signal | Saturation | Reference map for combination \(combination)")
				print(localMapOfCoverage.cleanDescription(replacing: 0).mergeHorizontally(toTheLeftOf: localMapOfSaturation.cleanDescription(replacing: 0)).mergeHorizontally(toTheLeftOf: referenceVehicleObstructionMask.cleanDescription(replacing: Character("B"))) )
			}


			/// Attribute Scoring Functions
			// Linear asig
			func asig(sigData: Measurement) -> Double {
				return sigData.mean
			}

			// Inverse asat
			func asat(satData: Measurement) -> Double {
				return 1.0/satData.mean
			}

			// Piecewise inverse asat
//			func asat(satData: Measurement) -> Double {
//				let meanSat = satData.mean
//				if meanSat < minRedundancy {
//					return 1.0/minRedundancy
//				} else { return 1.0/meanSat }
//			}

			// Percentage acov
			func acov(covCells: Int, maxCells: Int) -> Double {
				return Double(covCells)/Double(maxCells)
			}

			// Averaging abat
			// This routine assumes the new parked car has an active time of zero, so it isn't considered in the calculation.
			func abat() -> Double {
				// Get the IDs of the RSUs in this combination and matching active times
				var activityInCombination: [UInt:Time] = [:]
				for (combinationIndex, combinationValue) in combination.enumerated() {
					if combinationValue == true {
						let neighInCombinationID = neighborhoodCoverageMaps[combinationIndex].ownerID
						if neighInCombinationID != pcar.id {
							activityInCombination[neighInCombinationID] = pcar.neighborActiveTimes[neighInCombinationID]
						}
					}
				}

				func batteryTransform(_ elapsedTime: Time) -> Double {
					let noImpactTime = 3600.0
					let maxActiveTime = 7200.0

					if elapsedTime.fpSeconds < noImpactTime { return 1.0 }

					let m = -1.0/(maxActiveTime-noImpactTime)
					let b = noImpactTime/(maxActiveTime-noImpactTime)+1

					return m*elapsedTime.fpSeconds + b
				}

				// Sum the transforms and average to get the mean
				return activityInCombination.values.reduce(0, {$0+batteryTransform($1)} ) / Double(activityInCombination.count )
			}

			// Prepare return data struct
			var combinationStats = CombinationStatistics()

			// Get measurements confined to the decision maker's view
			combinationStats.sigMeasure = localMapOfCoverage.getMeasurement(withObstructionMask: referenceVehicleObstructionMask, includeNulls: false)
			combinationStats.satMeasure = localMapOfSaturation.getMeasurement(withObstructionMask: referenceVehicleObstructionMask, includeNulls: false)
			combinationStats.covMeasure = localMapOfCoverage.getMeasurement(withObstructionMask: nil, includeNulls: false)

			// Compute weighted product score
			combinationStats.asig = asig(sigData: combinationStats.sigMeasure)
			combinationStats.asat = asat(satData: combinationStats.satMeasure)
			combinationStats.acov = acov(covCells: combinationStats.covMeasure.count, maxCells: baseCoveredCellCount)
			combinationStats.abat = abat()

			combinationStats.wpmScore = pow(combinationStats.asig, weights.wsig)
									  * pow(combinationStats.asat, weights.wsat)
									  * pow(combinationStats.acov, weights.wcov)
									  * pow(combinationStats.abat, weights.wbat)

			// Possible scoring failures should be scored zero
			if combinationStats.wpmScore.isNaN { combinationStats.wpmScore = 0.0 }

			if debug.contains("WeightedProductModel.analyzeCombination()") {
				print("\(pcar.city.events.now.asSeconds) WeightedProductModel.analyzeCombination():"
					.padding(toLength: 54, withPad: " ", startingAt: 0).cyan(),
				      "Combination \(combination)",
					  "asig", String(format: "%.2f", combinationStats.asig),
					  "asat", String(format: "%.2f", combinationStats.asat),
					  "acov", String(format: "%.2f", combinationStats.acov),
					  "abat", String(format: "%.2f", combinationStats.abat),
					  "wpm",  String(format: "%.2f", combinationStats.wpmScore) ) }

			return combinationStats
		}


		/// 5. Decision: run through each combination, evaluate it, store its score, and decide
		var scoredCombinations = [(combination: Combination, stats: CombinationStatistics)]()
		for combination in combinations {
			let combinationStats = analyzeCombination(combination)
			scoredCombinations.append( (combination: combination, stats: combinationStats ) )
		}

		// Sort score array
		scoredCombinations.sort(by: {$0.stats.wpmScore > $1.stats.wpmScore})

		// Debug print scored combinations
		if debug.contains("WeightedProductModel.decide()") {
			print("\(pcar.city.events.now.asSeconds) WeightedProductModel.decide():"
				.padding(toLength: 54, withPad: " ", startingAt: 0).cyan(),
			      "Combinations ordered by score:" )

			print("".padding(toLength: 54, withPad: " ", startingAt: 0), "score\tcombination")

			for scoredCombination in scoredCombinations {
				print(""
					.padding(toLength: 54, withPad: " ", startingAt: 0),
				      "\(String(format: "%.2f", scoredCombination.stats.wpmScore).lightGray())\t\(scoredCombination.combination)")
			}
		}

		// Pick the best combination and execute it: send 'RSU disable' messages to RSUs disabled in the chosen solution
		let bestCombination = scoredCombinations.first!

		// Don't apply zero-score combinations; this may happen if any of the attributes was null
		if bestCombination.stats.wpmScore > 0 {
			// This flag determines whether the reference vehicle will become an RSU at the end of this process
			var disableSelf: Bool = false
			for (combinationIndex, combinationValue) in bestCombination.combination.enumerated() {
				// Entity will be disabled
				if combinationValue == false {
					let entityID = neighborhoodCoverageMaps[combinationIndex].ownerID

					if entityID == pcar.id {
						disableSelf = true
					} else {
						// Send an RSU disable message
						let disablePayload = DisableRoadsideUnit(disableID: entityID).toPayload()
						let disablePacket = Packet(id: pcar.city.network.getNextPacketID(), created: pcar.city.events.now, l2src: pcar.id, l3src: pcar.id, l3dst: .unicast(destinationID: entityID), payload: disablePayload)
						pcar.broadcastPacket(disablePacket, toFeatureTypes: .roadsideUnit)
					}
				}
				// Entity won't be disabled, do nothing
				else {}
			}

			// Statistics: track top decision metrics
			if pcar.city.stats.hooks["decisionWPM"] != nil {
				let separator = pcar.city.stats.separator
				let terminator = pcar.city.stats.terminator

				let numNeighborsDisabled: Int = bestCombination.combination.filter{ $0 == false }.count

				// Get the score of the null (no-action) decision
				var noActionCombinationID = baseCombination
				noActionCombinationID[0] = false	// The null combination disables the first entity only, ourselves
				let noActionCombination = scoredCombinations.filter( {$0.combination == noActionCombinationID} )
				guard	noActionCombination.count == 1,
						let noAction = noActionCombination.first
					else {
						print("Error: Failed to find the no-action combination.")
						exit(EXIT_FAILURE)
				}

				pcar.city.stats.writeToHook("decisionWPM", data:"\(pcar.city.events.now.asSeconds)\(separator)\(pcar.id)\(separator)\(bestCombination.stats.asig)\(separator)\(bestCombination.stats.asat)\(separator)\(bestCombination.stats.acov)\(separator)\(bestCombination.stats.abat)\(separator)\(bestCombination.stats.wpmScore)\(separator)\(numNeighborsDisabled)\(separator)\(disableSelf)\(separator)\(bestCombination.stats.sigMeasure.mean)\(separator)\(bestCombination.stats.sigMeasure.stdev)\(separator)\(bestCombination.stats.satMeasure.mean)\(separator)\(bestCombination.stats.satMeasure.stdev)\(separator)\(bestCombination.stats.sigMeasure.mean/bestCombination.stats.satMeasure.mean)\(separator)\(noAction.stats.wpmScore)\(terminator)")
			}

			// Statistics: track data for moving average
			if pcar.city.stats.hooks["movingAverageWPM"] != nil {
				if var scoreArray = pcar.city.stats.metrics["movingAverageWPM"] as? (sig: [Double], sat: [Double]) {
					scoreArray.sig.append(bestCombination.stats.sigMeasure.mean)
					scoreArray.sat.append(bestCombination.stats.satMeasure.mean)
					pcar.city.stats.metrics["movingAverageWPM"] = scoreArray
				}
			}

			// Parked car becomes an RSU, or is removed
			if !disableSelf { pcar.city.convertEntity(pcar, to: .roadsideUnit) }
			else { pcar.city.removeEntity(pcar) }
		}
		// If the best combination was zero-score, disable the parked car
		else {
			pcar.city.removeEntity(pcar)
		}
	}
}
