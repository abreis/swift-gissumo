/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class Network {
	// A standard message delay for all transmissions, 10ms
	let messageDelay: Double = 0.010

	// Maximum radio range (for GIS queries)
	// Match with the chosen propagation algorithm
	let maxRange: Double = 155

	// Propagation algorithm
	let getSignalStrength: (distance: Double, lineOfSight: Bool) -> Double = portoEmpiricalDataModel
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
	init (fromPayload: Payload)
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
		let neighborGIDarray = city.gis.get(featuresInCircleWithRadius: city.network.maxRange, center: geo, featureTypes: .Vehicle, .RoadsideUnit)

		if let neighborGIDs = neighborGIDarray {
			// Fetch vehicles and
			let matchingVehicles = city.vehicles.filter( {neighborGIDs.contains($0.gid!)} )
			let matchingRSUs = city.roadsideUnits.filter( {neighborGIDs.contains($0.gid!)} )

			for neighborVehicle in matchingVehicles {
				// TODO after Vehicle.receive(packet)
			}

			for neighborRSU in matchingRSUs {
				let newReceivePacketEvent = SimulationEvent(time: city.events.now + city.network.messageDelay, type: .Network, action: { neighborRSU.receive(packet) }, description: "RSU \(neighborRSU.id) receive packet \(packet.id) from \(self.id)")
				city.events.add(newEvent: newReceivePacketEvent)
			}
		}
	}
}




// Extend Roadside Units with the ability to receive packets
extension RoadsideUnit: PacketReceiver {
	func receive(packet: Packet) {
		// We should never receive packets sent by ourselves
		assert(packet.src != id)

		if debug.contains("RoadsideUnit.receive(packet)"){
			print(String(format: "%.6f RoadsideUnit.receive(packet):\t", city.events.now).cyan(), "RSU", id, "received packet", packet.id, "src", packet.src, "dst", packet.dst, "payloadT", packet.payloadType) }

		// Process destination field
		switch packet.dst {
		case .Unicast(let destinationID):
			// Disregard if we're not the message target
			if destinationID != id { return }
			break
		case .Broadcast:
			// TODO: reduce TTL and rebroadcast
			break
		case .Geocast(let targetArea):
			// Disregard if we're not in the destination area
			// TODO: rebroadcast
			if targetArea.isPointInside(geo) == false { return }
			break
		}

		// Process payload
		switch packet.payloadType {
		case .Beacon:
			// RSUs use beacons to construct their coverage maps
//			addBeacon(toSignalMap: localCoverageMap, beacon: Beacon(fromPayload: packet.payload) )
			break
		case .CoverageMapRequest:
			// TODO: send over the coverage map
			break
		case .CoverageMap:
			// TODO
			break
		}
	}
}
