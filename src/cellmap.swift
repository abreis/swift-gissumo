/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation


/* A cell map is a 2D map of objects, typically Int for signal strength or Char for visualization.
 * It conforms to CustomStringConvertible, i.e., it can be converted into a String for display.
 * It also conforms to PayloadConvertible, so it can be converted to a Payload. The resulting
 * payload content string is semicolon-separated. It prints a pair with the cell coordinates of
 * the top-left cell, formatted as "tlc$X,$Y".
 */

/* IMPORTANT: Direct subscript access to cells[][] is done as [y][x], not [x][y]
 * To avoid errors access the cells directly with cellmap[x,y] instead of cellmap.cells[][]
 * IMPORTANT: Geographic Y axis is higher->north, lower->south
 */

/* Due to language limitations, we must manually create a protocol for
 * types that can be initialized from a String, and extend those types
 * with the new protocol.
 */
protocol InitializableWithString { init?(string: String) }
extension Int: InitializableWithString {  init?(string: String) { self.init(string) } }
extension Double: InitializableWithString {  init?(string: String) { self.init(string) } }
extension Character: InitializableWithString {  init?(string: String) { self.init(string) } }

struct CellMap<T where T:InitializableWithString, T:Comparable, T:Equatable>: CustomStringConvertible, PayloadConvertible {
	var cells: [[T]]
	let size: (x: Int, y: Int)

	// The cellular coordinates of the top-left cell (lowest latitude, highest longitude)
	var topLeftCellCoordinate: (x: Int, y: Int)

	// The cellular coordinates of the middle cell (computed property)
	var centerCellCoordinate: (x: Int, y: Int)? {
		get {
			guard (size.x % 2 != 0) && (size.y % 2 != 0) else { return nil }
			return (x: topLeftCellCoordinate.x + (size.x-1)/2, y: topLeftCellCoordinate.y - (size.y-1)/2 )
		}
	}

	/// Initialize with a geographic pair of a coordinate in the top-left cell
	init(ofSize mSize:(x: Int, y: Int), withValue val: T, geographicTopLeft topLeft: (x: Double, y: Double)) {
		size = mSize
		cells = Array(count: size.y, repeatedValue: Array(count: size.x, repeatedValue: val))
		topLeftCellCoordinate = (x: Int(floor(topLeft.x * 3600)), y: Int(floor(topLeft.y * 3600)))
	}

	/// Initialize with a geographic pair of a coordinate in the middle cell
	init(ofSize mSize:(x: Int, y: Int), withValue val: T, geographicCenter center: (x: Double, y: Double)) {
		guard (mSize.x % 2 != 0) && (mSize.y % 2 != 0) else {
			print("Error: Tried to initialize an even-sized cell map with center coordinates.")
			exit(EXIT_FAILURE)
		}

		size = mSize
		cells = Array(count: size.y, repeatedValue: Array(count: size.x, repeatedValue: val))

		let centerCellCoordinate = (x: Int(floor(center.x * 3600)), y: Int(floor(center.y * 3600)) )
		topLeftCellCoordinate = (x: centerCellCoordinate.x - (size.x-1)/2, y: centerCellCoordinate.y + (size.y-1)/2)
	}


	// Computed property implementing CustomStringConvertible
	var description: String {
		var description = String()

		// Print top-left coordinate on the first line
		// 'tlc': top-left-cell
		description += "tlc" + String(topLeftCellCoordinate.x) + ";" + String(topLeftCellCoordinate.y) + "\n"
		for row in cells {
			for element in row {
				let stringElement = String(element)
				description += stringElement
			}
			description += "\n"
		}
		return description
	}


	/*** SUBSCRIPT ACCESS TO CELLS ***/

	// Allow correct access to the cells in a (x,y) format
	// Note: this is not the Y->Latitude and X->Longitude, as Y must be reversed for that
	subscript(x: Int, y: Int) -> T {
		get {
			return cells[y][x]
		}
		set {
			cells[y][x] = newValue
		}
	}

	// Allow access to a cell via a coordinate pair
	subscript(geo: (x: Double, y: Double))-> T {
		get {
			let index = (x: Int(floor(geo.x * 3600)) - topLeftCellCoordinate.x, y: Int(floor(geo.y * 3600)) - topLeftCellCoordinate.y)
			return cells[index.y][index.x]
		}
		set {
			let index = (x: Int(floor(geo.x * 3600)) - topLeftCellCoordinate.x, y: topLeftCellCoordinate.y - Int(floor(geo.y * 3600)))
			cells[index.y][index.x] = newValue
		}
	}

	// Allow access to a cell with a cell coordinate pair
	subscript(cellIndex: (x: Int, y: Int)) -> T  {
		get {
			return cells[topLeftCellCoordinate.y - cellIndex.y][cellIndex.x - topLeftCellCoordinate.x]
		}
		set {
			cells[topLeftCellCoordinate.y - cellIndex.y][cellIndex.x - topLeftCellCoordinate.x] = newValue
		}
	}

	/*** PAYLOAD CONVERSION ***/

	// Write the map to a payload
	func toPayload() -> Payload {
		var description = String()

		// Print top-left coordinate on the first line
		// 'tlc': top-left-cell
		description += "tlc" + String(topLeftCellCoordinate.x) + ";" + String(topLeftCellCoordinate.y) + "\n"

		for (cellIndex, row) in cells.enumerate() {
			for (rowIndex, element) in row.enumerate() {
				let stringElement = String(element)
				description += stringElement
				if rowIndex != row.count-1 { description += ";" }
			}
			if cellIndex != cells.count-1 { description += "\n" }
		}
		return Payload(content: description)
	}

	// Initialize the map from a payload
	init?(fromPayload payload: Payload) {
		// Break payload into lines
		var lines: [String] = []
		payload.content.enumerateLines{ lines.append($0.line) }

		// Extract the coordinates of the top-left cell from the payload header
		guard let firstLine = lines.first where firstLine.hasPrefix("tlc") else { return nil }
		let headerCellCoordinates = firstLine.stringByReplacingOccurrencesOfString("tlc", withString: "").componentsSeparatedByString(";")
		guard	let xTopLeft = Int(headerCellCoordinates[0]),
			let yTopLeft = Int(headerCellCoordinates[1])
			else { return nil }
		topLeftCellCoordinate = (x: xTopLeft, y: yTopLeft)

		// Remove the header and load the map
		lines.removeFirst()

		// Get the y-size from the number of lines read
		size.y = lines.count

		// Load cell contents
		cells = Array(count: size.y, repeatedValue: [])
		var nrow = 0
		for row in lines {
			let rowItems = row.componentsSeparatedByString(";")
			for rowItem in rowItems {
				guard let item = T(string: rowItem) else {return nil}
				cells[nrow].append(item)
			}
			nrow += 1
		}

		// Get the x-size from the number of elements read
		size.x = cells.first!.count
	}
}



/*** MAP ON MAP ROUTINES ***/

// Extend maps with the ability to compute the bounds of their intersection
extension CellMap {
	func getOverlapBounds(withMap inMap: CellMap) -> (x: (start: Int, end: Int), y: (start: Int, end: Int))? {
		// Determine the overlap bounds between the two maps
		let bounds = (x: (start: max(inMap.topLeftCellCoordinate.x, self.topLeftCellCoordinate.x),
						end: min(inMap.topLeftCellCoordinate.x+inMap.size.x-1, self.topLeftCellCoordinate.x+self.size.x-1)),
		             y:	(start: max(inMap.topLeftCellCoordinate.y-inMap.size.y+1, self.topLeftCellCoordinate.y-self.size.y+1),
						end: min(inMap.topLeftCellCoordinate.y, self.topLeftCellCoordinate.y)))

		// Guard against no overlap between the two maps
		guard bounds.x.end >= bounds.x.start && bounds.y.end >= bounds.y.start
			else { return nil }
		return bounds
	}
}

/* Extend maps of signal coverage (T:Int) with the ability to overlap other maps on them
 * and keep the max(lhs(i,j), rhs(i,j)), i.e., the best signal strength available.
 */
extension CellMap where T:IntegerArithmeticType, T:SignedIntegerType {
	mutating func keepBestSignal(fromSignalMap inMap: CellMap<T>) {
		// Get the intersection range between the two maps
		guard let bounds = self.getOverlapBounds(withMap: inMap) else {
			print("Warning: Attempted to calculate saturation with maps that do not overlap.")
			return
		}

		// Keep the best signal from either map
		for xx in bounds.x.start ... bounds.x.end {
			for yy in bounds.y.start ... bounds.y.end {
				let coords: (x:Int, y:Int) = (xx, yy)
				if inMap[coords] > self[coords] {
					self[coords] = inMap[coords]
				}
			}
		}
	}
}

/* Extend maps of RSU saturation (Int) with the ability to add a signal coverage map
 * and increment the cells that are covered by that map ( rhs(i,j)>0 ? lhs(i,j)+=1 ) .
 */
extension CellMap where T:IntegerArithmeticType, T:SignedIntegerType {
	mutating func incrementSaturation(fromSignalMap inMap: CellMap<T>) {
		// Get the intersection range between the two maps
		guard let bounds = self.getOverlapBounds(withMap: inMap) else {
			print("Warning: Attempted to calculate saturation with maps that do not overlap.")
			return
		}

		// Increment saturation on the computed bounds
		for xx in bounds.x.start ... bounds.x.end {
			for yy in bounds.y.start ... bounds.y.end {
				let coords: (x:Int, y:Int) = (xx, yy)
				if inMap[coords] > 0 {
					self[coords] = self[coords] + 1
				}
			}
		}
	}
}
