/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class Network {
	// A standard message delay for all transmissions, 10ms
	let messageDelay: Double = 0.010

	// Delay between beacon broadcasts (1 sec)
	let beaconingInterval: Double = 1.0

	// Maximum radio range (for GIS queries)
	// Match with the chosen propagation algorithm
	let maxRange: Double = 155

	// The size, in cells, of a local coverage map
	// Our coverage maps are 11x11, or ~330m wide (for an assumed radio range of 155m and average cell size of 30m)
	lazy var selfCoverageMapSize: Int = Int(ceil(self.maxRange*2/30))

	// Propagation algorithm
	let getSignalStrength: (distance: Double, lineOfSight: Bool) -> Double = portoEmpiricalDataModel

	// Packet ID generator - can be made to create random IDs
	var nextPacketID: UInt = 0
	func getNextPacketID() -> UInt {
		defer { nextPacketID += 1 }
		return nextPacketID
	}
}

/*** GEOCAST AREAS ***/

protocol AreaType {
	func isPointInside(point: (x: Double, y: Double)) -> Bool
}

struct Square: AreaType {
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

	func isPointInside(point: (x: Double, y: Double)) -> Bool {
		if point.x > x.min && point.x < x.max && point.y > y.min && point.y < y.max {
			return true
		} else { return false }
	}
}



/*** PACKETS ***/

// List of payload types so a payload can be correctly cast to a message
enum PayloadType {
	case Beacon
	case CoverageMapRequest
	case CoverageMap
}

// A message packet
struct Packet {
	enum Destination {
		case Unicast(destinationID: UInt)
		case Broadcast(hopLimit: UInt)
		case Geocast(targetArea: AreaType)
	}

	var id: UInt
	var src: UInt
	var dst: Destination

	var created: Double

	var payload: Payload
	var payloadType: PayloadType
}

// A payload is a simple text field
struct Payload {
	var content: String
}

// Objects that conform to PayloadConvertible must be able to be completely expressed
// as a Payload type (i.e., a string) and be created from a Payload as well
protocol PayloadConvertible {
	func toPayload() -> Payload
	init? (fromPayload: Payload)
}

// Entitites that implement the PacketReceiver protocol are able to receive packets
protocol PacketReceiver {
	func receive(packet: Packet)
}


// A network beacon
struct Beacon: PayloadConvertible {
	// Our beacons are similar to Cooperative Awareness Messages (CAMs)
	// The payload is simply the sending vehicle's geographic coordinates
	let geo: (x: Double, y: Double)

	init(geo ingeo: (x: Double, y: Double)) { geo = ingeo }

	// Convert coordinates to a Payload string
	func toPayload() -> Payload {
		let payloadContent = String(geo.x) + ";" + String(geo.y)
		return Payload(content: payloadContent)
	}

	// Split a payload's data
	init(fromPayload payload: Payload) {
		let payloadCoords = payload.content.componentsSeparatedByString(";")
		guard	let xgeo = Double(payloadCoords[0]),
				let ygeo = Double(payloadCoords[1])
				else {
					print("Error: Coordinate conversion from Beacon payload failed.")
					exit(EXIT_FAILURE)
		}
		geo = (x: xgeo, y: ygeo)
	}
}



/*** SIGNAL STRENGTH ALGORITHMS ***/

// A discrete propagation model built with empirical data from the city of Porto
func portoEmpiricalDataModel(distance: Double, lineOfSight: Bool) -> Double {
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
	func broadcastPacket(packet: Packet) {
		let neighborGIDarray = city.gis.getFeatureGIDs(inCircleWithRadius: city.network.maxRange, center: geo, featureTypes: .Vehicle, .RoadsideUnit)

		if let neighborGIDs = neighborGIDarray {
			// Fetch vehicles and

			// Send the packet to all neighboring vehicles
			// TODO after Vehicle.receive(packet)
//			let matchingVehicles = city.vehicles.filter( {neighborGIDs.contains($0.gid!)} )
//			for neighborVehicle in matchingVehicles {
//			}

			// Send the packet to all neighboring RSUs
			let matchingRSUs = city.roadsideUnits.filter( {neighborGIDs.contains($0.gid!)} )
			for neighborRSU in matchingRSUs {
				// Schedule a receive(packet) event for time=now+transmissionDelay
				let newReceivePacketEvent = SimulationEvent(time: city.events.now + city.network.messageDelay, type: .Network, action: { neighborRSU.receive(packet) }, description: "RSU \(neighborRSU.id) receive packet \(packet.id) from \(self.id)")
				city.events.add(newEvent: newReceivePacketEvent)
			}
		}
	}
}



// Extend Vehicles with the ability to send beacons
extension Vehicle {
	func broadcastBeacon() {
		// Construct the beacon payload with the sender's coordinates (Cooperative Awareness Message)
		let beaconPayload: Payload = Beacon(geo: self.geo).toPayload()

		// Construct the beacon packet, a broadcast with hoplimit = 1
		let beaconPacket = Packet(id: city.network.getNextPacketID(), src: self.id, dst: .Broadcast(hopLimit: 1), created: city.events.now, payload: beaconPayload, payloadType: .Beacon)

		// Send the beacon to our neighbors
		self.broadcastPacket(beaconPacket)

		// Track number of beacons sent
		if city.stats.hooks["beaconCounts"] != nil {
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
		// Ensure this vehicle is still active -- a beaconing event can be scheduled for after the vehicle is removed
		guard self.active else { return }

		// A safer, but slower way to do this, is to check whether the vehicle in question is still in the City
//		guard city.vehicles.contains( {$0 === self} ) else { return }

		// Send a beacon right away
		self.broadcastBeacon()

		// Schedule a new beacon to be sent in now+beaconingInterval
		let newBeaconEvent = SimulationEvent(time: city.events.now + city.network.beaconingInterval, type: .Network, action: {self.recurrentBeaconing()}, description: "broadcastBeacon vehicle \(self.id)")
		city.events.add(newEvent: newBeaconEvent)
	}
}



// Extend Roadside Units with the ability to receive packets
extension RoadsideUnit: PacketReceiver {
	func receive(packet: Packet) {
		// We should never receive packets sent by ourselves
		assert(packet.src != id)

		if debug.contains("RoadsideUnit.receive()"){
			print(String(format: "%.6f RoadsideUnit.receive():\t", city.events.now.milli).cyan(), "RSU", id, "received packet", packet.id, "src", packet.src, "dst", packet.dst, "payload", packet.payloadType) }

		// Process destination field
		switch packet.dst {
		case .Unicast(let destinationID):
			// Disregard if we're not the message target
			if destinationID != id { return }
		case .Broadcast:
			// TODO: reduce TTL and rebroadcast
			break
		case .Geocast(let targetArea):
			// Disregard if we're not in the destination area
			if targetArea.isPointInside(geo) == false { return }
			// TODO: rebroadcast
		}

		// Process payload
		switch packet.payloadType {
		case .Beacon:
			// RSUs use beacons to construct their coverage maps
			let receivedBeacon = Beacon(fromPayload: packet.payload)
			trackSignalStrength(fromBeacon: receivedBeacon)

			// Track number of beacons received
			if city.stats.hooks["beaconCounts"] != nil {
				if var recvBeacons = city.stats.metrics["beaconsReceived"] as? UInt {
					recvBeacons += 1
					city.stats.metrics["beaconsReceived"] = recvBeacons
				}
			}
		case .CoverageMapRequest:
			// TODO: send over the coverage map
			break
		case .CoverageMap:
			// TODO
			break
		}
	}
}



/*** SIGNAL STRENGTH MAPS ***/

// Extend RoadsideUnits with the ability to receive a Beacon payload and register a signal coverage metric
extension RoadsideUnit {
	func trackSignalStrength(fromBeacon beacon: Beacon) {
		// Get the signal strength we see to the beacon's geographic coordinates
		let beaconDistance = city.gis.getDistance(fromPoint: self.geo, toPoint: beacon.geo)
		let beaconLOS = city.gis.checkForLineOfSight(fromPoint: self.geo, toPoint: beacon.geo)
		let beaconSignalStrength = city.network.getSignalStrength(distance: beaconDistance, lineOfSight: beaconLOS)

		// Store the signal strength seen at the beacon location
		selfCoverageMap[(beacon.geo)] = Int(beaconSignalStrength)

		// Debug
		if debug.contains("RoadsideUnit.trackSignalStrength()"){
			print(String(format: "%.6f RoadsideUnit.trackSignalStrength():\t", city.events.now.milli).cyan(), "RSU", id, "sees signal", beaconSignalStrength, "at geo", beacon.geo, "distance", beaconDistance, "los", beaconLOS) }
	}
}
