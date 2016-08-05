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



/*** SIGNAL MAPS ***/

/* A signal map stores signal strength values from 0 to 5.
 * It conforms to CustomStringConvertible, i.e., can be converted into a string.
 * This lets us transform a map into a string and place it inside a packet's Payload.
 * It can also be constructed from a string, and recognizes the presence of a pair of
 * center coordinates in the first line, formatted as "c$X,$CY".
 */
struct SignalMap : CustomStringConvertible, PayloadConvertible {
	var cells: [[Int]]
	let size: (x: Int, y: Int)
	var center: (x: Int, y: Int)?

	init(ofSize mSize:(x: Int, y: Int), withValue val: Int, center mCenter: (x: Int, y: Int)?) {
		size = mSize
		center = mCenter
		cells = Array(count: mSize.y, repeatedValue: Array(count: mSize.x, repeatedValue: val))
	}

	// Implement CustomStringConvertible
	var description: String {
		var desc = String()

		// If we have center coordinates, print them on the first line
		if let ccenter = center {
			desc += "c" + String(ccenter.x) + "," + String(ccenter.y) + "\n"
		}

		for row in cells {
			for element in row {
				desc += String(element)
			}
			desc += "\n"
		}
		return desc
	}

	// Construct a new SignalMap from a textual representation
	init(fromString str: String) {
		// Break string into lines
		var lines: [String] = []
		str.enumerateLines{ lines.append($0.line) }

		if let firstLine = lines.first where firstLine.hasPrefix("c") {
			lines.removeFirst()
			let centerCoords = firstLine.stringByReplacingOccurrencesOfString("c", withString: "").componentsSeparatedByString(",")
			
			guard let xcenter = Int(centerCoords[0]),
				let ycenter = Int(centerCoords[1])
				else {
					print("Error: Signal map center coordinate conversion from string failed.")
					exit(EXIT_FAILURE)
			}
			center = (x: xcenter, y: ycenter)
		}

		// Define boundaries
		size.y = lines.count
		size.x = lines.first!.characters.count

		cells = Array(count: size.y, repeatedValue: [])
		var nrow = 0
		for row in lines {
			for signalChar in row.characters {
				if let signalNum = Int(String(signalChar)) {
					cells[nrow].append(signalNum)
				}
			}
			nrow += 1
		}
	}

	// Implement PayloadConvertible protocol
	func toPayload () -> Payload {
		let payload = Payload(content: description)
		return payload
	}

	init(fromPayload payload: Payload) {
		self.init(fromString: payload.content)
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
