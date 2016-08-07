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
		case Geocast // TODO: implement an Area type to represent geocasts
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
		if distance<70 { return 5 }
		if distance<115 { return 4 }
		if distance<135 { return 3 }
		if distance<155 { return 2 }
	} else {
		if distance<58 { return 5 }
		if distance<65 { return 4 }
		if distance<105 { return 3 }
		if distance<130 { return 2 }
	}
	return 0
}



/*** TRANSPORT ***/

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
		case .Broadcast:
			// TODO: reduce TTL and rebroadcast
			break
		case .Geocast:
			// TODO: see if we're in the destination Area
			exit(EXIT_FAILURE)
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