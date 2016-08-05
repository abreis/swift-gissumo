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


// A payload is a simple text field
struct Payload {
	var content: String
}

// Objects that conform to PayloadConvertible must be able to be completely expressed
// as a Payload type (i.e., a string) and be created from a Payload as well
protocol PayloadConvertible {
	func toPayload () -> Payload
	init (fromPayload: Payload)
}



/*** PACKETS ***/

// List of payload types so a payload can be correctly cast to a message
enum PayloadType {
	case Beacon
	case RequestCoverageMap
	case CoverageMap
}

// A message packet
// TODO: methods for geocasting, TTL, controlled propagation
struct Packet {
	var id: Int
	var src, dst: Int

	var created: Double

	var payload: Payload
	var payloadType: PayloadType
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
