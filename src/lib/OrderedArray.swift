// TODO: Implement Sequence type
public struct OrderedArray<T: Comparable> {
	public var array = [T]()	// TODO Private

	init() { self.array = [] }
	init(array: [T]) { self.array = array.sorted() }

	var isEmpty: Bool { return array.isEmpty }
	var count: Int { return array.count }

	subscript(index: Int) -> T { return array[index] }
	mutating func removeAtIndex(index: Int) -> T { return array.remove(at: index) }
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
}
