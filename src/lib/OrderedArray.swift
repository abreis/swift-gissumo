/* Andre Braga Reis, 2017
 * Adapted from Ray Wenderlich's swift-algorithm-club.
 * Licensing information can be found in the accompanying LICENSE file.
 */

public struct OrderedArrayIterator<T: Comparable>: IteratorProtocol {
	let orderedArray: OrderedArray<T>
	var position: Int = 0

	init(_ orderedArray: OrderedArray<T>) {
		self.orderedArray = orderedArray
	}

	mutating public func next() -> T? {
		let nextElement: T? = orderedArray[position]
		position += 1
		return nextElement
	}
}

public struct OrderedArray<T: Comparable>: Collection {
	private var array = [T]()

	init() { self.array = [] }
	init(array: [T]) { self.array = array.sorted() }

	// Replicate Array properties and methods
	public var isEmpty: Bool { return array.isEmpty }
	public var count: Int { return array.count }
	public var first: T? { return array.first }
	public var last: T? { return array.last }
	mutating func remove(at index: Int) -> T { return array.remove(at: index) }
	mutating func removeAll() { array.removeAll() }

	mutating func insert(_ newElement: T) {
		array.insert(newElement, at: findInsertionPoint(newElement))
	}

	private func findInsertionPoint(_ newElement: T) -> Int {
		var range = (startIndex:0, endIndex: array.count)
		while range.startIndex < range.endIndex {
			let midIndex = range.startIndex + (range.endIndex - range.startIndex) / 2
			if array[midIndex] == newElement {
				return midIndex
			} else if array[midIndex] < newElement {
				range.startIndex = midIndex + 1
			} else {
				range.endIndex = midIndex
			}
		}
		return range.startIndex
	}

	// Conform to Sequence
	public func makeIterator() -> OrderedArrayIterator<T> {
		return OrderedArrayIterator<T>(self)
	}

	// Conform to Collection
	public var startIndex: Int { return array.startIndex }
	public var endIndex: Int { return array.endIndex }
	public func index(after i: Int) -> Int { return array.index(after: i) }
	public subscript(position: Int) -> T { return array[position] }
}
