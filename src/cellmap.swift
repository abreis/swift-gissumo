/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation


/* A signal map stores signal strength values from 0 to 5.
* It conforms to CustomStringConvertible, i.e., can be converted into a string.
* This lets us transform a map into a string and place it inside a packet's Payload.
* It can also be constructed from a string, and recognizes the presence of a pair of
* center coordinates in the first line, formatted as "c$X,$CY".
*/
struct SignalMap: CustomStringConvertible, PayloadConvertible {
	var cells: [[Int]]
	let size: (x: Int, y: Int)
	var center: (x: Int, y: Int)?

	init(ofSize mSize:(x: Int, y: Int), withValue val: Int, center mCenter: (x: Int, y: Int)?) {
		size = mSize
		center = mCenter
		cells = Array(count: mSize.y, repeatedValue: Array(count: mSize.x, repeatedValue: val))
	}

	// Computed property implementing CustomStringConvertible
	var description: String {
		var desc = String()

		// If we have center coordinates, print them on the first line
		if let ccenter = center {
			desc += "c" + String(ccenter.x) + ";" + String(ccenter.y) + "\n"
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
			let centerCoords = firstLine.stringByReplacingOccurrencesOfString("c", withString: "").componentsSeparatedByString(";")

			guard	let xcenter = Int(centerCoords[0]),
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
	func toPayload() -> Payload {
		let payload = Payload(content: description)
		return payload
	}

	init(fromPayload payload: Payload) {
		self.init(fromString: payload.content)
	}
}
