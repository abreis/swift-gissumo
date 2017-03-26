/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class Network {
	// A standard message delay for all transmissions, 10ms
	let messageDelay = SimulationTime(milliseconds: 10)

	// Delay between beacon broadcasts (1 sec)
	let beaconingInterval = SimulationTime(seconds: 1)

	// Maximum radio range (for GIS queries)
	// Match with the chosen propagation algorithm
	let maxRange: Double = 155

	// The size, in cells, of a local coverage map
	// Our coverage maps are 13x13, or ~390m wide (enough for a 155m radio range + margin of error)
	lazy var selfCoverageMapSize: Int = 13

	// Propagation algorithm
	let getSignalStrength: (_ distance: Double, _ lineOfSight: Bool) -> Double = portoEmpiricalDataModel

	// Packet ID generator (can also be made to create random IDs)
	var nextPacketID: UInt = 0
	func getNextPacketID() -> UInt {
		defer { nextPacketID += 1 }
		return nextPacketID
	}
}


/*** GEOCAST AREAS ***/

/* ETSI GeoNetworking header
 * Type: Any(0), Beacon(1), GeoUnicast(2), GeoAnycast(3), GeoBroadcast(4), TSB(Topologically Scoped Broadcast: 5) or LS (6)
 * Subtype: Circle(0), Rectangle(1) or Ellipse(2);
 */

protocol AreaType {
	func isPointInside(_ point: (x: Double, y: Double)) -> Bool
}

struct Square: AreaType, CustomStringConvertible {
	var x: (min: Double, max: Double)
	var y: (min: Double, max: Double)

	// Ensure bounds are always correct (min<max)
	init(x xIn: (min: Double, max: Double), y yIn: (min: Double, max: Double)) {
		x = xIn
		y = yIn

		if x.min > x.max {
			x.min = xIn.max
			x.max = xIn.min
		}
		if y.min > y.max {
			y.min = yIn.max
			y.max = yIn.min
		}
	}

	func isPointInside(_ point: (x: Double, y: Double)) -> Bool {
		if point.x > x.min && point.x < x.max && point.y > y.min && point.y < y.max {
			return true
		} else { return false }
	}

	var description: String { return "(\(x.min),\(y.min))(\(x.max),\(y.max))" }
}

struct Circle: AreaType, CustomStringConvertible {
	var center: (x: Double, y: Double)
	var radius: Double

	init(centerIn: (x: Double, y: Double), radiusIn: Double) {
		center = centerIn
		radius = radiusIn
	}

	func isPointInside(_ point: (x: Double, y: Double)) -> Bool {
		// TODO Unimplemented
		exit(EXIT_FAILURE)
	}

	var description: String { return "center (\(center.x),\(center.x)), radius\(radius)" }
}

/*** PACKETS ***/

// A message packet
struct Packet {
	// A unique packet identifier in the simulation
	var id: UInt

	// Time the packet was created in the simulation
	var created: SimulationTime

	// Layer 2 Network
	var l2src: UInt
//	var l2dst	// Unimplemented, all packets are broadcast at the MAC level

	// Layer 3 Network */
	enum Destination {
		case unicast(destinationID: UInt)
		case broadcast(hopLimit: UInt)
		case geocast(targetArea: AreaType)
	}
	var l3src: UInt
	var l3dst: Destination

	// The packet's payload
	var payload: Payload

	// A single-line description of the packet
	var traceDescription: String {
		return "\(id)\t\(created.asSeconds)\t\(l2src)\t\(l3src)\t\(l3dst)\t\(payload.type)\t\(payload.content.replacingOccurrences(of: "\n", with: "\\n"))\n"
	}
}


/*** PAYLOAD TYPE ***/

// List of payload types so a payload can be correctly cast to a message
enum PayloadType: UInt {
	case beacon = 0
	case coverageMapRequest
	case coverageMaps
	case activeTimeRequest
	case activeTime
	case cellMap
	case disableRSU
}

// A payload is a simple text field and a header with its type
struct Payload {
	var type: PayloadType
	var content: String
}

// Objects that conform to PayloadConvertible must be able to be completely expressed
// as a Payload type (i.e., a string) and be created from a Payload as well
protocol PayloadConvertible {
	func toPayload() -> Payload
	init? (fromPayload: Payload)
}

// Entitites that implement the PacketReceiver protocol are able to receive packets,
// keep track of seen packets, and process payloads
protocol PacketReceiver {
	var receivedPacketIDs: [UInt] { get set }
	func receive(_ packet: Packet)
}

// Entities that implement PayloadReceiver are able to process payloads
protocol PayloadReceiver {
	func processPayload(withinPacket packet: Packet)
}


/*** PAYLOADS ***/

// A network beacon
struct Beacon: PayloadConvertible {
	// Our beacons are similar to Cooperative Awareness Messages (CAMs)
	// The payload is simply the sending vehicle's geographic coordinates
	let geo: (x: Double, y: Double)
	let src: UInt
	let entityType: RoadEntityType

	init(geo ingeo: (x: Double, y: Double), src insrc: UInt, entityType intype: RoadEntityType) {
		geo = ingeo; src = insrc; entityType = intype;
	}

	// Convert coordinates to a Payload string
	func toPayload() -> Payload {
		let payloadContent = "\(geo.x);\(geo.y);\(src);\(entityType.rawValue)"
		return Payload(type: .beacon, content: payloadContent)
	}

	// Split a payload's data
	init(fromPayload payload: Payload) {
		let payloadCoords = payload.content.components(separatedBy: ";")
		guard	let xgeo = Double(payloadCoords[0]),
				let ygeo = Double(payloadCoords[1]),
				let psrc = UInt(payloadCoords[2]),
				let ptyperaw = UInt(payloadCoords[3]),
				let ptype = RoadEntityType(rawValue: ptyperaw)
				else {
					print("Error: Coordinate conversion from Beacon payload failed.")
					exit(EXIT_FAILURE)
		}
		geo = (x: xgeo, y: ygeo)
		src = psrc
		entityType = ptype
	}
}


// A request for coverage maps
struct CoverageMapRequest: PayloadConvertible {
	let depth: UInt
	func toPayload() -> Payload { return Payload(type: .coverageMapRequest, content: "\(depth)")}
	init? (fromPayload payload: Payload) {
		guard let payloadDepth = UInt(payload.content) else { return nil }
		depth = payloadDepth
	}
	init (depth: UInt) { self.depth = depth }
}

// A payload containing one or more coverage maps
// Add maps to self.maps, then convert everything to a Payload, or viceversa
struct CoverageMaps: PayloadConvertible {
	var maps: [SelfCoverageMap] = []

	init () {}

	func toPayload() -> Payload {
		guard maps.count > 0 else {
			print("Error: attempted to convert an empty coverage map array to a Payload.")
			exit(EXIT_FAILURE)
		}

		var payloadString: String = ""
		for map in maps {
			payloadString += "id" +  String(format: "%08d", map.ownerID)
			payloadString += map.cellMap.toPayload().content
			payloadString += "m"	// split maps with 'm' character; payload contains: "cdilpt-;" plus 0..9
		}

		return Payload(type: .coverageMaps, content: payloadString)
	}

	init? (fromPayload payload: Payload) {
		guard payload.type == .coverageMaps	else { return nil }
		let mapEntries = payload.content.components(separatedBy: "m").filter{!$0.isEmpty}

		guard mapEntries.count > 0 else { return nil }
		for entry in mapEntries {
			guard entry.hasPrefix("id") else { return nil }

			// Index where the map and the ID are split. We reserve 10 chars for the map ID and tag
			let splitIdAndMapIndex = entry.index(entry.startIndex, offsetBy: 10)

			// Substrings
			let idString = entry.substring(to: splitIdAndMapIndex)
			let mapString = entry.substring(from: splitIdAndMapIndex)

			// Obtain cell map and owner ID from substrings
			guard	let mapOwnerID = UInt(idString.substring(from: idString.index(idString.startIndex, offsetBy: 2))),
					let cellMap = CellMap<Int>(fromString: mapString)
				else { return nil }

			// Store the coverage map
			maps.append( SelfCoverageMap(ownerID: mapOwnerID, cellMap: cellMap) )
		}
	}
}


// A request for an RSU's active time
struct ActiveTimeRequest: PayloadConvertible {
	func toPayload() -> Payload { return Payload(type: .activeTimeRequest, content: "")}
	init? (fromPayload payload: Payload) {}
	init () { }
}


// A reply to an RSU active time request
struct ActiveTime: PayloadConvertible {
	let activeTime: Time
	func toPayload() -> Payload { return Payload(type: .activeTime, content: "\(activeTime.nanoseconds)")}
	init? (fromPayload payload: Payload) {
		guard let payloadContentNumeric = Int(payload.content) else { return nil }
		activeTime = Time(nanoseconds: payloadContentNumeric)
	}
	init (activeTime: Time) { self.activeTime = activeTime}
}


// A message to instruct an RSU to disable itself
struct DisableRoadsideUnit: PayloadConvertible {
	let rsuID: UInt

	init (disableID inID: UInt) {
		rsuID = inID
	}

	func toPayload() -> Payload { return Payload(type: .disableRSU, content: "\(rsuID)")}

	init(fromPayload payload: Payload) {
		guard let payloadID = UInt(payload.content) else {
			print("Error: ID conversion from disableRSU payload failed.")
			exit(EXIT_FAILURE)
		}
		rsuID = payloadID
	}
}


// Extend CellMaps to conform with PayloadConvertible
extension CellMap: PayloadConvertible {
	// Write the map to a payload
	func toPayload() -> Payload {
		var description = String()

		// Print top-left coordinate on the first line
		// 'tlc': top-left-cell
		// 'p': line separator; map contains: "clt-;" plus 0..9
		description += "tlc" + String(topLeftCellCoordinate.x) + ";" + String(topLeftCellCoordinate.y) + "p"

		for (cellIndex, row) in cells.enumerated() {
			for (rowIndex, element) in row.enumerated() {
				let stringElement = String(describing: element)
				description += stringElement
				if rowIndex != row.count-1 { description += ";" }
			}
			if cellIndex != cells.count-1 { description += "p" }
		}

		// Note: Cell maps are not necessarily CoverageMaps, this can be generified
		return Payload(type: .cellMap, content: description)
	}

	// Initialize the map from a payload
	init?(fromPayload payload: Payload) {
		self.init(fromString: payload.content)
	}

	// Initialize the map from a string
	init?(fromString content: String) {
		// Break string into lines
		var lines: [String] = content.components(separatedBy: "p").filter{!$0.isEmpty}

		// Extract the coordinates of the top-left cell from the payload header
		guard let firstLine = lines.first, firstLine.hasPrefix("tlc") else { return nil }
		let headerCellCoordinates = firstLine.replacingOccurrences(of: "tlc", with: "").components(separatedBy: ";")
		guard	let xTopLeft = Int(headerCellCoordinates[0]),
				let yTopLeft = Int(headerCellCoordinates[1])
			else { return nil }
		topLeftCellCoordinate = (x: xTopLeft, y: yTopLeft)

		// Remove the header and load the map
		lines.removeFirst()

		// Get the y-size from the number of lines read
		size.y = lines.count

		// Load cell contents
		cells = Array(repeating: [], count: size.y)
		var nrow = 0
		for row in lines {
			let rowItems = row.components(separatedBy: ";")
			for rowItem in rowItems {
				guard let item = T(string: rowItem) else { return nil }
				cells[nrow].append(item)
			}
			nrow += 1
		}

		// Get the x-size from the number of elements read
		size.x = cells.first!.count
	}
}


/*** SIGNAL STRENGTH ALGORITHMS ***/

// A discrete propagation model built with empirical data from the city of Porto
func portoEmpiricalDataModel(_ distance: Double, lineOfSight: Bool) -> Double {
	if lineOfSight {
		switch distance {
		case   0..<70	: return 5
		case  70..<115	: return 4
		case 115..<135	: return 3
		case 135..<155	: return 2
		default			: return 0
		}
	} else {
		switch distance {
		case   0..<58	: return 5
		case  58..<65	: return 4
		case  65..<105	: return 3
		case 105..<130	: return 2
		default			: return 0
		}
	}
}



/*** TRANSPORT ***/

// Extend RoadEntity types with the ability to broadcast messages
extension RoadEntity {
	func broadcastPacket(_ packet: Packet, toFeatureTypes features: GIS.FeatureType...) {
		// If no destination is specified, assume ALL
		var features = features
		if features.count == 0 {
			features = [.vehicle, .roadsideUnit, .parkedCar]
		}

		// Output packet trace, if enabled
		if city.stats.hooks["packetTrace"] != nil {
			city.stats.writeToHook("packetTrace", data: packet.traceDescription)
		}

		// Locate matching neighbor GIDs
		var neighborGIDs: [UInt]

		// If we're using the Haversine formula, skip the GIS query and locate neighbors right in the simulator
		if city.gis.useHaversine {
			neighborGIDs = city.getFeatureGIDs(inCircleWithRadius: city.network.maxRange, center: geo, featureTypes: features)
		} else {
			neighborGIDs = city.gis.getFeatureGIDs(inCircleWithRadius: city.network.maxRange, center: geo, featureTypes: features)
		}

		if neighborGIDs.count > 0 {
			// Remove ourselves from the list
			if let selfGID = self.gid,
				let selfIndex = neighborGIDs.index(of: selfGID) {
					neighborGIDs.remove(at: selfIndex)
			}

			// TODO: Broadcast packets to other Vehicles
			// Necessary for >1 hop transmissions, forwarding geocasts

			// Send the packet to all neighboring RSUs
			let matchingRSUs = city.roadsideUnits.filter( {neighborGIDs.contains($0.gid!)} )
			for neighborRSU in matchingRSUs {
				// Schedule a receive(packet) event for time=now+transmissionDelay
				let newReceivePacketEvent = SimulationEvent(time: city.events.now + city.network.messageDelay, type: .network, action: { neighborRSU.receive(packet) }, description: "RSU \(neighborRSU.id) receive packet \(packet.id) from \(self.id)")
				city.events.add(newEvent: newReceivePacketEvent)
			}

			// Send the packet to all neighboring parked cars
			let matchingParkedCars = city.parkedCars.filter( {neighborGIDs.contains($0.gid!)} )
			for neighborParkedCar in matchingParkedCars {
				// Schedule a receive(packet) event for time=now+transmissionDelay
				let newReceivePacketEvent = SimulationEvent(time: city.events.now + city.network.messageDelay, type: .network, action: { neighborParkedCar.receive(packet) }, description: "ParkedCar \(neighborParkedCar.id) receive packet \(packet.id) from \(self.id)")
				city.events.add(newEvent: newReceivePacketEvent)
			}
		}
	}
}


// Extend Roadside Units with the ability to receive packets
extension RoadEntity: PacketReceiver {
	func receive(_ packet: Packet) {
		// We should never receive packets sent by ourselves on layer2
		assert(packet.l2src != id)

		// Ignore retransmissions of packets originally sent by ourselves
		guard packet.l3src != id else { return }

		// Ignore packets we've already seen
		// Note: Packet IDs must not change during retransmissions
		guard !receivedPacketIDs.contains(packet.id) else { return }

		// Store the packet ID
		receivedPacketIDs.append(packet.id)

		// Debug
		if debug.contains("RoadEntity.receive()"){
			print("\(city.events.now.asSeconds) \(type(of: self)).receive():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "RSU", id, "received packet", packet.id, "l2src", packet.l2src, "l3src", packet.l3src,  "l3dst", packet.l3dst, "payload", packet.payload.type) }

		// Process destination field
		switch packet.l3dst {
		case .unicast(let destinationID):
			// Disregard if we're not the message target
			if destinationID != id { return }

		case .broadcast(let hopsRemaining):
			// Disregard if the hop limit is reached
			if hopsRemaining <= 1 { break }

			// 1. Clone the packet
			var rebroadcastPacket = packet
			// 2. Reduce TTL
			rebroadcastPacket.l3dst = .broadcast(hopLimit: hopsRemaining - 1)
			// 3. Refresh l2src
			rebroadcastPacket.l2src = self.id
			// 4. Rebroadcast
			self.broadcastPacket(rebroadcastPacket)

			// Debug
			if debug.contains("RoadEntity.receive()"){
				print("\(city.events.now.asSeconds) \(type(of: self)).receive():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "RSU", id, "rebroadcasting packet", rebroadcastPacket.id, "l2src", rebroadcastPacket.l2src, "l3src", rebroadcastPacket.l3src,  "l3dst", rebroadcastPacket.l3dst, "payload", rebroadcastPacket.payload.type) }

		case .geocast(let targetArea):
			// Disregard if we're not in the destination area
			if targetArea.isPointInside(geo) == false { return }

			// 1. Clone the packet
			var rebroadcastPacket = packet
			// 2. Refresh l2src
			rebroadcastPacket.l2src = self.id
			// 2. Rebroadcast
			self.broadcastPacket(rebroadcastPacket)

			// Debug
			if debug.contains("RoadEntity.receive()"){
				print("\(city.events.now.asSeconds) \(type(of: self)).receive():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "RSU", id, "rebroadcasting packet", rebroadcastPacket.id, "l2src", rebroadcastPacket.l2src, "l3src", rebroadcastPacket.l3src,  "l3dst", rebroadcastPacket.l3dst, "payload", rebroadcastPacket.payload.type) }
		}

		// Entity-independent payload processing
		// Code that all RoadEntities should run on payloads goes here
		// Process payload
		switch packet.payload.type {
		case .beacon:
			// Track number of beacons received
			if city.stats.hooks["beaconCount"] != nil {
				if var recvBeacons = city.stats.metrics["beaconsReceived"] as? UInt {
					recvBeacons += 1
					city.stats.metrics["beaconsReceived"] = recvBeacons
				}
			}
		default: break
		}

		// Entity-specific payload processing
		// Call the entity's specific payload processing routine
		if self is PayloadReceiver {
			(self as! PayloadReceiver).processPayload(withinPacket: packet)
		}
	}
}


// Extend Vehicles with the ability to send beacons
extension Vehicle {
	func broadcastBeacon() {
		// Construct the beacon payload with the sender's coordinates (Cooperative Awareness Message)
		let beaconPayload: Payload = Beacon(geo: self.geo, src: self.id, entityType: self.type).toPayload()

		// Construct the beacon packet, a broadcast with hoplimit = 1
		let beaconPacket = Packet(id: city.network.getNextPacketID(), created: city.events.now, l2src: self.id, l3src: self.id, l3dst: .broadcast(hopLimit: 1), payload: beaconPayload)

		// Send the beacon to our neighbors
		self.broadcastPacket(beaconPacket)

		// Track number of beacons sent
		if city.stats.hooks["beaconCount"] != nil {
			if var sentBeacons = city.stats.metrics["beaconsSent"] as? UInt {
				sentBeacons += 1
				city.stats.metrics["beaconsSent"] = sentBeacons
			}
		}
	}
}


// Extend Vehicles with a recurrent beaconing routine
// This must be initiated when the vehicle is created
extension Vehicle {
	func recurrentBeaconing() {
		// Ensure this vehicle is still active -- a beaconing event may have been scheduled for after the vehicle is removed
		// This requires tagging vehicles with active=false when they are removed
		guard self.active else { return }

		// A safer, but slower way to do this, is to check whether the vehicle in question is still in the City
//		guard city.vehicles.contains( {$0 === self} ) else { return }

		// Send a beacon right away
		self.broadcastBeacon()

		// Schedule a new beacon to be sent in now+beaconingInterval
		let newBeaconEvent = SimulationEvent(time: city.events.now + city.network.beaconingInterval, type: .network, action: {self.recurrentBeaconing()}, description: "broadcastBeacon vehicle \(self.id)")
		city.events.add(newEvent: newBeaconEvent)
	}
}


// Extend Fixed Road Entities (e.g. roadside units) with the ability to process payloads
extension FixedRoadEntity: PayloadReceiver {
	func processPayload(withinPacket packet: Packet) {
		switch packet.payload.type {
		case .beacon:
			// RSUs use beacons to construct their coverage maps
			let receivedBeacon = Beacon(fromPayload: packet.payload)
			trackSignalStrength(fromBeacon: receivedBeacon)


		case .coverageMapRequest:
			// Only RSUs reply to requests for coverage maps
			if self is RoadsideUnit {
				guard let coverageRequest = CoverageMapRequest(fromPayload: packet.payload) else {
					print("Error: Failed to convert a CoverageMapRequest payload.")
					exit(EXIT_FAILURE)
				}


				switch coverageRequest.depth {
				/* DEPTH == 1 */
				case 1:
					// depth 1 -> only send our own map, already appended earlier
					// Array to store the maps for the payload
					var coverageMapArray = CoverageMaps()

					// Append our own map
					coverageMapArray.maps.append( SelfCoverageMap(ownerID: self.id, cellMap: self.selfCoverageMap) )

					let coverageMapReplyPacket = Packet(id: self.city.network.getNextPacketID(), created: self.city.events.now, l2src: self.id, l3src: self.id, l3dst: .unicast(destinationID: packet.l3src), payload: coverageMapArray.toPayload())

					// We're sending coverage map replies to parked cars and roadside units, for the depth request to work
					self.broadcastPacket(coverageMapReplyPacket, toFeatureTypes: .parkedCar, .roadsideUnit)

				/* DEPTH == 2 */
				case 2:
					/* depth 2:
					 * -> broadcast a depth==1 request, wait for replies (0.5s)
					 * -> send our map and our 1-hop neighbors' maps
					 */
					let onDemandCoverageMapRequestPacket = Packet(id: self.city.network.getNextPacketID(), created: self.city.events.now, l2src: self.id, l3src: self.id, l3dst: .broadcast(hopLimit: 1), payload: CoverageMapRequest(depth: 1).toPayload())

					// We're only interested in maps from active roadside units here
					self.broadcastPacket(onDemandCoverageMapRequestPacket, toFeatureTypes: .roadsideUnit)

					// Create and schedule a reply to the original requester with the received maps
					let coverageBroadcastClosure = {
						// Array to store the maps for the payload
						var coverageMapArray = CoverageMaps()

						// Append our own map
						coverageMapArray.maps.append( SelfCoverageMap(ownerID: self.id, cellMap: self.selfCoverageMap) )

						// Append 1-hop neighbor maps (distance == 1)
						// Don't send maps that are not new, as they may belong to RSUs that don't exist anymore
						// We're arbitrarily choosing 1 second since replies should have arrived in the last .5 seconds
						coverageMapArray.maps +=
							self.neighborMaps
								.filter{ $1.distance == 1 }
								.filter{ $1.lastUpdated > self.city.events.now - SimulationTime(seconds: 1) }
								.map{ return SelfCoverageMap(ownerID: $0, cellMap: $1.coverageMap) }

						let coverageMapReplyPacket = Packet(id: self.city.network.getNextPacketID(), created: self.city.events.now, l2src: self.id, l3src: self.id, l3dst: .unicast(destinationID: packet.l3src), payload: coverageMapArray.toPayload())

						// We're only sending coverage map replies to parked cars
						self.broadcastPacket(coverageMapReplyPacket, toFeatureTypes: .parkedCar)
					}

					let coverageMapReplyEvent = SimulationEvent(time: self.city.events.now + SimulationTime(milliseconds: 500), type: .network, action: coverageBroadcastClosure, description: "deferred coverage map reply src \(self.id) dst \(packet.l3src)")

					self.city.events.add(newEvent: coverageMapReplyEvent)

				default:
					print("Error: Invalid depth on coverage map request.")
					exit(EXIT_FAILURE)
				}

			}


		case .coverageMaps:
			// Pull coverage maps from the payload
			guard let coverageMapPayload = CoverageMaps(fromPayload: packet.payload)
				else {
					print("Error: failed to convert a CoverageMaps payload.")
					exit(EXIT_FAILURE)
			}
			// Call the neighbor map managing routine in FixedRoadEntity
			self.append(coverageMaps: coverageMapPayload.maps, sender: packet.l3src, currentTime: self.city.events.now)


		case .activeTimeRequest:
			// Only RSUs reply to requests for active time
			if self is RoadsideUnit {
				guard let creationTime = self.creationTime else {
					print("Error: Creation time not set for RSU.")
					exit(EXIT_FAILURE)
				}

				// Prepare a packet
				let activeTime = ActiveTime(activeTime: Time(self.city.events.now - creationTime))
				let activeTimePacket = Packet(id: self.city.network.getNextPacketID(), created: self.city.events.now, l2src: self.id, l3src: self.id, l3dst: .unicast(destinationID: packet.l3src), payload: activeTime.toPayload())

				// Unicast the packet to the requester
				self.broadcastPacket(activeTimePacket, toFeatureTypes: .parkedCar)
			}


		case .activeTime:
			// Only parked cars in decision mode keep active times of neighbors
			if self is ParkedCar {
				// Track the neighbor's active time
				(self as! ParkedCar).neighborActiveTimes[packet.l3src] = ActiveTime(fromPayload: packet.payload)!.activeTime
			}


		case .disableRSU:
			// Only RSUs can be disabled by a message
			if self is RoadsideUnit {
				// Pull the targed GID from the payload
				let disableMessage = DisableRoadsideUnit(fromPayload: packet.payload)
				// If the disable command was directed to us, schedule an event to remove us from the network
				if disableMessage.rsuID == self.id {
					let removalEvent = SimulationEvent(time: self.city.events.now + self.city.events.minTimestep, type: .vehicular, action: {self.city.removeEntity(self)}, description: "Remove RSU id \(self.id) by disableRSU packet \(packet.id)")
					self.city.events.add(newEvent: removalEvent)
				}
			}


		default:
			print("Error: Received an unknown payload.")
			exit(EXIT_FAILURE)
		}
	}
}




/*** SIGNAL STRENGTH MAPS ***/

// Extend Fixed Road Entities with the ability to receive a Beacon payload and register a signal coverage metric
extension FixedRoadEntity {
	func trackSignalStrength(fromBeacon beacon: Beacon) {
		// Get the signal strength we see to the beacon's geographic coordinates
		let beaconDistance = city.gis.getDistance(fromPoint: self.geo, toPoint: beacon.geo)
		let beaconLOS = city.gis.checkForLineOfSight(fromPoint: self.geo, toPoint: beacon.geo)
		let beaconSignalStrength = city.network.getSignalStrength(beaconDistance, beaconLOS)

		// Store the signal strength seen at the beacon location
		selfCoverageMap[(beacon.geo)] = Int(beaconSignalStrength)

		// Debug
		if debug.contains("FixedRoadEntity.trackSignalStrength()"){
			print("\(city.events.now.asSeconds) FixedRoadEntity.trackSignalStrength():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "RSU", id, "sees signal", beaconSignalStrength, "at geo", beacon.geo, "distance", beaconDistance, "los", beaconLOS) }
	}
}
