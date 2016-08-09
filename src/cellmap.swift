/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation


/* A cell map is a 2D map of objects, typically Int for signal strength or Char for visualization.
 * It conforms to CustomStringConvertible, i.e., can be converted into a string.
 * This lets us transform a map into a string and place it inside a packet's Payload.
 * It can also be constructed from a string, and recognizes the presence of a pair of
 * center coordinates in the first line, formatted as "c$X,$Y".
 * Note: Its construction will fail if the Object is not representable as a single Character.
 */
/* IMPORTANT: Direct subscript access to cells[][] is done as [y][x], not [x][y]
 * To avoid errors access the cells directly with cellmap[x,y] instead of cellmap.cells[][]
 * IMPORTANT: Geographic Y axis is higher->north, lower->south
 */
struct CellMap: CustomStringConvertible, PayloadConvertible {
	private var cells: [[Any]]
	let size: (x: Int, y: Int)
	var topLeftCoordinate: (x: Int, y: Int) = (0,0)
	var centerCoordinate: (x: Int, y: Int)?

	// Initialize with coordinates of the middle cell (e.g. an RSU)
	init(ofSize mSize:(x: Int, y: Int), withValue val: Any, geographicCenter mCenter: (x: Double, y: Double)) {
		size = mSize
		cells = Array(count: mSize.y, repeatedValue: Array(count: mSize.x, repeatedValue: val))

		// Set the center coordinate in WGS84 seconds
		guard size.x % 2 != 0 && size.y % 2 != 0 else {
			print("Error: Attempted to access a center coordinate in an even-sized map.")
			exit(EXIT_FAILURE)
		}
		centerCoordinate = (x: Int(floor(mCenter.x * 3600)), y: Int(floor(mCenter.y * 3600)) )

		// Set the top left cell coordinate
		topLeftCoordinate = (x: centerCoordinate!.x - (size.x-1)/2, y: centerCoordinate!.y + (size.y-1)/2)
	}

	// Initialize with the coordinates of the top-left-most cell (e.g. a city map)
	init(ofSize mSize:(x: Int, y: Int), withValue val: Any, geographicTopLeft topLeft: (x: Double, y: Double)) {
		size = mSize
		cells = Array(count: mSize.y, repeatedValue: Array(count: mSize.x, repeatedValue: val))

		// Set the top left coordinate in WGS84 seconds
		topLeftCoordinate = ( x: Int(floor(topLeft.x * 3600)), y: Int(floor(topLeft.y * 3600)) )

		// Set the center coordinate if the map size is odd
		if size.x % 2 != 0 && size.y % 2 != 0 {
			centerCoordinate = (x: topLeftCoordinate.x + (size.x-1)/2, y: topLeftCoordinate.y - (size.y-1)/2 )
		}
	}

	// Allow correct access to the cells in a (x,y) format
	// Note: this is not the Y->Latitude and X->Longitude, as Y must be reversed for that
	subscript(x: Int, y: Int) -> Any {
		get {
			return cells[y][x]
		}
		set {
			cells[y][x] = newValue
		}
	}

	// Allow access to a cell via a coordinate pair
	subscript(geo: (x: Double, y: Double))-> Any {
		get {
			let index = (x: Int(floor(geo.x * 3600)) - topLeftCoordinate.x, y: Int(floor(geo.y * 3600)) - topLeftCoordinate.y)
			return cells[index.y][index.x]
		}
		set {
			let index = (x: Int(floor(geo.x * 3600)) - topLeftCoordinate.x, y: topLeftCoordinate.y - Int(floor(geo.y * 3600)))
			cells[index.y][index.x] = newValue
		}
	}

	// Computed property implementing CustomStringConvertible
	var description: String {
		var desc = String()

		// Print top-left coordinate on the first line
		desc += "tl" + String(topLeftCoordinate.x) + ";" + String(topLeftCoordinate.y) + "\n"

		for row in cells {
			for element in row {
				let stringElement = String(element)
				guard stringElement.characters.count == 1 else {
					print("Error: Attempted to retrieve an object not representable by a single Character in a CellMap.")
					exit(EXIT_FAILURE)
				}
				desc += stringElement
			}
			desc += "\n"
		}
		return desc
	}

	// Construct a CellMap from a textual representation
	// This routine will automatically create both numeric and character maps
	init(fromString str: String) {
		// Break string into lines
		var lines: [String] = []
		str.enumerateLines{ lines.append($0.line) }

		if let firstLine = lines.first where firstLine.hasPrefix("tl") {
			lines.removeFirst()
			let topLeftCoords = firstLine.stringByReplacingOccurrencesOfString("tl", withString: "").componentsSeparatedByString(";")

			guard	let xTopLeft = Int(topLeftCoords[0]),
					let yTopLeft = Int(topLeftCoords[1])
					else {
						print("Error: Cell map center coordinate conversion from string failed.")
						exit(EXIT_FAILURE)
			}
			topLeftCoordinate = (x: xTopLeft, y: yTopLeft)
		}

		// Define boundaries
		size.y = lines.count
		size.x = lines.first!.characters.count

		cells = Array(count: size.y, repeatedValue: [])
		var nrow = 0
		for row in lines {
			for cellChar in row.characters {
				if let cellNum = Int(String(cellChar)) {
					cells[nrow].append(cellNum)
				} else {
					cells[nrow].append(cellChar)
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
