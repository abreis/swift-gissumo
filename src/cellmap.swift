/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

// A self-observed coverage map is always paired with an owner ID
struct SelfCoverageMap {
	let ownerID: UInt
	var map: CellMap<Int>
}

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

struct CellMap<T>: CustomStringConvertible where T:InitializableWithString, T:Comparable, T:Equatable {
	var cells: [[T]]
	var flatCells: [T] { return cells.flatMap{ $0 } }
	var size: (x: Int, y: Int)

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
		cells = Array(repeating: Array(repeating: val, count: size.x), count: size.y)
		topLeftCellCoordinate = (x: Int(floor(topLeft.x * 3600)), y: Int(floor(topLeft.y * 3600)))
	}

	/// Initialize with a geographic pair of a coordinate in the middle cell
	init(ofSize mSize:(x: Int, y: Int), withValue val: T, geographicCenter center: (x: Double, y: Double)) {
		guard (mSize.x % 2 != 0) && (mSize.y % 2 != 0) else {
			print("Error: Tried to initialize an even-sized cell map with center coordinates.")
			exit(EXIT_FAILURE)
		}

		size = mSize
		cells = Array(repeating: Array(repeating: val, count: size.x), count: size.y)

		let centerCellCoordinate = (x: Int(floor(center.x * 3600)), y: Int(floor(center.y * 3600)) )
		topLeftCellCoordinate = (x: centerCellCoordinate.x - (size.x-1)/2, y: centerCellCoordinate.y + (size.y-1)/2)
	}

	/// Initialize with a cell coordinate for the top-left cell (useful for duplicating maps)
	init(ofSize mSize:(x: Int, y: Int), withValue val: T, topLeftCellCoordinate topLeft: (x: Int, y: Int)) {
		size = mSize
		cells = Array(repeating: Array(repeating: val, count: size.x), count: size.y)
		topLeftCellCoordinate = topLeft
	}

	/// Initialize with a set of other maps, creating an empty map with appropriate dimensions to contain them
	init(toContainMaps mapList: [CellMap<T>], withValue val: T) {
		// Get the topleft cell (lowest xx, highest yy) and bottomright cell
		guard let firstMap = mapList.first else { print("Error: Empty list of maps provided."); exit(EXIT_FAILURE); }
		var topLeft = firstMap.topLeftCellCoordinate
		var bottomRight = (x: topLeft.x + firstMap.size.x, y: topLeft.y - firstMap.size.y)
		for map in mapList {
			if map.topLeftCellCoordinate.x < topLeft.x { topLeft.x = map.topLeftCellCoordinate.x }
			if map.topLeftCellCoordinate.y > topLeft.y { topLeft.y = map.topLeftCellCoordinate.y }
			if map.topLeftCellCoordinate.x + map.size.x > bottomRight.x { bottomRight.x = map.topLeftCellCoordinate.x + map.size.x }
			if map.topLeftCellCoordinate.y - map.size.y < bottomRight.y { bottomRight.y = map.topLeftCellCoordinate.y - map.size.y }
		}

		topLeftCellCoordinate = topLeft
		size = (bottomRight.x-topLeft.x, topLeft.y-bottomRight.y)
		cells = Array(repeating: Array(repeating: val, count: size.x), count: size.y)
	}

	// Computed property implementing CustomStringConvertible
	var description: String {
		var description = String()

		// Print top-left coordinate on the first line
		// 'tlc': top-left-cell
		description += "tlc" + String(topLeftCellCoordinate.x) + ";" + String(topLeftCellCoordinate.y) + "\n"
		for row in cells {
			for element in row {
				let stringElement = String(describing: element)
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

	// Crop the map to a smaller dimension, in place
	mutating func cropInPlace(newTopLeftCell newTopLeft: (x: Int, y: Int), newSize: (x: Int, y: Int)) {
		// 0. If we're asked to crop to the same size we already are, do nothing
		guard newSize != size && newTopLeft != topLeftCellCoordinate else { return }

		// 1. Ensure the requested crop area is valid
		guard	newTopLeft.x >= topLeftCellCoordinate.x &&
				newTopLeft.y <= topLeftCellCoordinate.y &&
				newTopLeft.x + newSize.x <= topLeftCellCoordinate.x + size.x &&
				newTopLeft.y - newSize.y >= topLeftCellCoordinate.y - size.y &&
				newSize.x > 0 && newSize.y > 0
			else {
				print("Error: Attempted to crop a map to an invalid size.")
				exit(EXIT_FAILURE)
		}

		// 2. Create a new map
		var newCells = [[T]]()
		var copyRange: (x: (start: Int, end: Int), y: (start: Int, end: Int))
		copyRange = (x: (start: newTopLeft.x - topLeftCellCoordinate.x,	end: newTopLeft.x - topLeftCellCoordinate.x + newSize.x-1),
		             y: (start: topLeftCellCoordinate.y - newTopLeft.y, end: topLeftCellCoordinate.y - newTopLeft.y + newSize.y-1))

		// 3. Copy the selected cell range to the new map
		for yy in copyRange.y.start ... copyRange.y.end {
			newCells.append([])
			for xx in copyRange.x.start ... copyRange.x.end {
				newCells[newCells.count-1].append(cells[yy][xx])
			}
		}

		// 4. Mutate our cellmap in place
		topLeftCellCoordinate = newTopLeft
		size = newSize
		cells = newCells
	}

	// Return a new cropped map
	func crop(newTopLeftCell newTopLeft: (x: Int, y: Int), newSize: (x: Int, y: Int)) -> CellMap<T> {
		// 0. If we're asked to crop to the same size we already are, return a clean copy of ourselves
		guard newSize != size && newTopLeft != topLeftCellCoordinate else {
			let newCroppedMap: CellMap<T> = self
			return newCroppedMap
		}
		// 1. Clone our map
		var newCroppedMap: CellMap<T> = self
		// 2. Crop the clone in place
		newCroppedMap.cropInPlace(newTopLeftCell: newTopLeft, newSize: newSize)
		// 3. Return the clone
		return newCroppedMap
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
extension CellMap where T:IntegerArithmetic, T:SignedInteger {
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
 * and increment the cells that are covered by that map ( rhs(i,j)>0 ? lhs(i,j)+=1 ).
 */
extension CellMap where T:IntegerArithmetic, T:SignedInteger {
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

/* Extend coverage and saturation maps with the ability to return a Measurement containing
 * all of its non-zero cells. And if a same-size obstruction map is provided, all cells
 * that are not marked as Blocked will be considered. If 'considerNulls' is set to false,
 * it will both ignore cells marked as "B" on the mask, and cells that equal zero.
 */
extension CellMap where T:IntegerArithmetic, T:SignedInteger, T:CustomStringConvertible {
	func getMeasurement(withObstructionMask mask: CellMap<Character>? = nil, includeNulls: Bool = true) -> Measurement {
		if mask != nil { guard mask!.size == self.size else {
			print("Error: Obstruction mask must match map size")
			exit(EXIT_FAILURE)
		}}

		var measure = Measurement()

		for i in 0..<self.size.y {
			for j in 0..<self.size.x {
				// If the obstruction mask is defined, consider only cells that are 'Open'
				if mask != nil {
					if mask!.cells[i][j] == Character("O") {
						// If 'includeNulls' is false, discard '0' cells
						if includeNulls || self.cells[i][j] != 0 {
							measure.add(Double(self.cells[i][j].description)!)
							// (note: this doublecasting is ridiculous, but Swift doesn't seem to infer that Double(T:Integer) is okay
						}
					}
				}
				// If not, consider all cells that are not null
				else if self.cells[i][j] != 0 {
					measure.add(Double(self.cells[i][j].description)!)
				}
			}
		}

		return measure
	}
}

/* Ability to convert a numeric map to an obstruction map. Creates a same-size
 * character map where cells with signal >0 are marked as Open. Elsewhere, they
 * are marked as Blocked.
 */
extension CellMap where T:IntegerArithmetic, T:SignedInteger {
	func expressAsObstructionMask() -> CellMap<Character> {
		var obstructionMap = CellMap<Character>(ofSize: self.size, withValue: Character("B"), topLeftCellCoordinate: self.topLeftCellCoordinate)
		//(ofSize: self.size, withValue: Character("B"), geographicTopLeft: self.topLeftCellCoordinate)

		for i in 0..<self.size.y {
			for j in 0..<self.size.x {
				if self.cells[i][j] > 0 {
					obstructionMap.cells[i][j] = Character("O")
				}
			}
		}

		return obstructionMap
	}
}
