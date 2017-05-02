/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

struct SimulationEvent {
	enum EventType {
		case mobility		// Events scheduled from the FCD data
		case network		// Network-related events
		case statistics		// Statistics-related events
		case decision		// Decision-related events
		case vehicular		// Vehicular events separate from the FCD data
		case simulation		// Simulator-related events
	}

	var time: SimulationTime
	let type: EventType
	let action: ()->()
	var description: String = ""
}


struct Time: Equatable, Comparable, Hashable, ExpressibleByFloatLiteral, CustomStringConvertible {
	var nanoseconds: Int
	var milliseconds: Int { return nanoseconds/1000 }
	var microseconds: Int { return nanoseconds/1000000 }
	var seconds: Int { return nanoseconds/1000000000 }

	// Floating point returns
	var fpMilliseconds: Double { return Double(nanoseconds)/1000.0 }
	var fpMicroseconds: Double { return Double(nanoseconds)/1000000.0 }
	var fpSeconds: Double { return Double(nanoseconds)/1000000000.0 }

	// Standard init
	init() { nanoseconds = 0 }
	// FloatLiteralConvertible: initialize with a Float (assumes Seconds are provided)
	init(floatLiteral value: Double) { self.init(seconds: Double(value))}
	// Various specific initializers
	init(seconds       sec: Int) { nanoseconds =  sec * 1000000000 }
	init(milliseconds msec: Int) { nanoseconds = msec * 1000000 }
	init(microseconds µsec: Int) { nanoseconds = µsec * 1000 }
	init(nanoseconds  nsec: Int) { nanoseconds = nsec }
	init(seconds       sec: Double) { nanoseconds = Int( sec * 1000000000) }
	init(milliseconds msec: Double) { nanoseconds = Int(msec * 1000000) }
	init(microseconds µsec: Double) { nanoseconds = Int(µsec * 1000) }
	init(nanoseconds  nsec: Double) { nanoseconds = Int(nsec) }
	// Init from equal type
	init(_ ltime: Time) { nanoseconds = ltime.nanoseconds }
	// Conform to Hashable
	var hashValue: Int { return nanoseconds.hashValue }
	// Conform to CustomStringConvertible
	var description: String { return String(nanoseconds) }
	// Print as floating point Seconds with precision=6 (microsecond)
	var asSeconds: String { return String(format: "%6f", Double(nanoseconds)/1000000000.0) }
}

typealias SimulationTime = Time

// Conform Time to Equatable, Comparable
func ==(lhs: Time, rhs: Time) -> Bool { return lhs.nanoseconds == rhs.nanoseconds }
func <(lhs: Time, rhs: Time) -> Bool { return lhs.nanoseconds < rhs.nanoseconds }
// Overload operatos +, -, +=
func +(left: Time, right: Time) -> Time { return Time(nanoseconds: left.nanoseconds+right.nanoseconds) }
func -(left: Time, right: Time) -> Time { return Time(nanoseconds: left.nanoseconds-right.nanoseconds) }
func +=(left: inout Time, right: Time) { left = left + right }
func -=(left: inout Time, right: Time) { left = left - right }


/* An event list specific to this simulator.
 * This is a custom structure that stores events in a dictionary of subarrays,
 * i.e., [Seconds:[SimulationEvent]]. This allows us to partition the eventlist,
 * and to quickly access a subarray by flooring the desired time, e.g.: event
 * at time 140.012345 is stored in eventList[140].
 */
class EventArray: Sequence {
	let minTimestep = SimulationTime(microseconds: 1)

	var eventDictionary: Dictionary<Int,[SimulationEvent]> = [:]

	var sortedKeys = OrderedArray<Int>(array: [])
	var count: Int = 0

	func add(newEvent: SimulationEvent) -> SimulationTime {
		let indexTime = newEvent.time.seconds

		// Make event mutable
		var newEvent = newEvent

		if eventDictionary[indexTime] != nil {
			// This subarray is populated, perform ordered insertion
			var insertionIndex: Int = 0

			// Quick insertion at the edges
			if newEvent.time > eventDictionary[indexTime]!.last!.time {
				insertionIndex = eventDictionary[indexTime]!.count
			} else if newEvent.time < eventDictionary[indexTime]!.first!.time {
				insertionIndex = 0
			} else if newEvent.time == eventDictionary[indexTime]!.last!.time {
				newEvent.time += minTimestep
				insertionIndex = eventDictionary[indexTime]!.count
			} else {
				// Bisect-ordered-add
				var low = 0
				var high = eventDictionary[indexTime]!.count

				// Bisection, adapted from python's bisect.py
				while low < high {
					let mid = (low+high)/2
					if newEvent.time <= eventDictionary[indexTime]![mid].time {
						high = mid
					} else {
						low = mid + 1
					}
				}
				insertionIndex = low

				/* Don't let two events have the same time. While events exist
				* with the same time, push our event forward by a small timestep.
				*/
				while insertionIndex != eventDictionary[indexTime]!.count && eventDictionary[indexTime]![insertionIndex].time == newEvent.time {
					newEvent.time += minTimestep
					insertionIndex += 1
				}
			}

			// Now insert the new event at the correct position
			eventDictionary[indexTime]!.insert(newEvent, at: insertionIndex)

		} else {
			// Subarray not populated, create and insert
			eventDictionary[indexTime] = [newEvent]

			// Keep sortedKeys up to date
			sortedKeys.insert(indexTime)
		}

		// Update count
		count += 1

		return newEvent.time
	}

	// Implement 'last'
	var last: SimulationEvent? {
		if eventDictionary.isEmpty { return nil }
		let lastTimeGroupIndex: Int = Array(eventDictionary.keys).sorted().last!
		return eventDictionary[lastTimeGroupIndex]!.last!
	}

	// Implement endIndex
	var endIndex: Int { return self.count }

	// Implement []
	subscript(requestedIndex: Int) -> SimulationEvent {
		get {
			var requestedIndex = requestedIndex
			for key in sortedKeys {
				if requestedIndex >= eventDictionary[key]!.count {
					requestedIndex -= eventDictionary[key]!.count
				} else {
					return eventDictionary[key]![requestedIndex]
				}
			}
			exit(EXIT_FAILURE)
		}
	}

	// Conform to Sequence and IteratorProtocol
	struct EventArrayIterator: IteratorProtocol {
		let eventArray: EventArray
		var dictionaryPos: Int
		var arrayPos: Int

		init(_ eventArray: EventArray) {
			self.eventArray = eventArray
			self.dictionaryPos = eventArray.sortedKeys.first!
			self.arrayPos = 0
		}

		mutating func next() -> SimulationEvent? {
			// Track current event for returning
			let nextSimulationEvent = eventArray.eventDictionary[dictionaryPos]![arrayPos]

			// Update array positions for the next iteration
			if eventArray.eventDictionary[dictionaryPos]!.index(after: arrayPos) != eventArray.eventDictionary[dictionaryPos]!.endIndex {
				arrayPos = eventArray.eventDictionary[dictionaryPos]!.index(after: arrayPos)
			} else {
				// Return nil if we're at the last time key already
				guard dictionaryPos != eventArray.sortedKeys.last else { return nil }

				// Find the next dictionary key
				guard let currentDictionaryIndex = eventArray.sortedKeys.index(of: dictionaryPos) else { return nil }
				dictionaryPos = eventArray.sortedKeys[eventArray.sortedKeys.index(after: currentDictionaryIndex)]

				// Reset array position
				arrayPos = eventArray.eventDictionary[dictionaryPos]!.startIndex
			}

			// Return the requested event
			return nextSimulationEvent
		}
	}

	func makeIterator() -> EventArrayIterator {
		return EventArrayIterator(self)
	}

	// Dump all events in the dictionary up to a provided iterator's time
	func flushOldEvents(upToTime endTime: SimulationTime) {
		let rangeStart = self.sortedKeys.first!
		let rangeEnd = endTime.seconds
		for keyToRemove in rangeStart..<rangeEnd {
			eventDictionary.removeValue(forKey: keyToRemove)
		}
	}
}


class EventList {
	var minTimestep: SimulationTime { return list.minTimestep }

	// Current simulation time
	var now = SimulationTime(seconds: -1)

	// Simulation stop time, from config
	var stopTime: SimulationTime

	// Array of simulation events
	var list = EventArray()

	// Events to be executed pre-simulation
	var initial = [SimulationEvent]()

	// Events to be executed post-simulation
	var cleanup = [SimulationEvent]()

	// Init with the simulation stop time
	init(stopTime stime: Double) {
		stopTime = SimulationTime(seconds: stime)
	}

	// Add a new event, keeping the event list sorted
	func add(newEvent: SimulationEvent) {
		let insertedAtTime = list.add(newEvent: newEvent)

		if debug.contains("EventList.add()") {
			print("\(now.asSeconds) EventList.add():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Add new event of type", newEvent.type, "at time", insertedAtTime.asSeconds)
		}
	}

	// Add events to the pre-simulation (initial) stage
	func add(initialEvent event: SimulationEvent) {
		initial.append(event)
	}

	// Add events to the post-simulation (cleanup) stage
	func add(cleanupEvent event: SimulationEvent) {
		cleanup.append(event)
	}

	// Process mobility timesteps, adding events to create, update and remove vehicles (DEPRECATED)
	func scheduleMobilityEvents(fromFCD fcdTimesteps: inout [FCDTimestep], city: City) {
		// A temporary array to store vehicles that will be active
		var cityVehicleIDs = Set<UInt>()

		// The array of timesteps is assumed sorted
		for timestep in fcdTimesteps {
			/* Create a set of vehicle IDs in this timestep
			 * This is done by mapping the timestep's array of FCDVehicles into an array of
			 * the vehicle's IDs, and then initializing the Set<UInt> with that array.
			 */
			let fcdVehicleIDs = Set<UInt>( timestep.vehicles.map({$0.id}) )

			// Through set relations we can now get the IDs of all new, existing and removed vehicles
			let newVehicleIDs = fcdVehicleIDs.subtracting(cityVehicleIDs)
			let existingVehicleIDs = fcdVehicleIDs.intersection(cityVehicleIDs)
			let missingVehicleIDs = cityVehicleIDs.subtracting(fcdVehicleIDs)

			// Debug
			if debug.contains("EventList.scheduleMobilityEvents()"){
				print("\(now.asSeconds) EventList.scheduleMobilityEvents():".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), "Timestep", timestep.time, "sees:" )
				print("\t\tFCD vehicles:", fcdVehicleIDs)
				print("\t\tCity vehicles:", cityVehicleIDs)
				print("\t\tNew vehicles:", newVehicleIDs)
				print("\t\tExisting vehicles:", existingVehicleIDs)
				print("\t\tMissing vehicles:", missingVehicleIDs)
			}

			// Insert and remove vehicles into our temporary array
			cityVehicleIDs.formUnion(newVehicleIDs)
			cityVehicleIDs.subtract(missingVehicleIDs)

			// Schedule events to create new vehicles
			for newFCDvehicleID in newVehicleIDs {
				let newFCDvehicle = timestep.vehicles[ timestep.vehicles.index( where: {$0.id == newFCDvehicleID} )! ]
				// (note: the IDs came from timestep.vehicles, so an .indexOf on the array can be force-unwrapped safely)

				let newVehicleEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .mobility, action: {_ = city.addNew(vehicleWithID: newFCDvehicle.id, geo: newFCDvehicle.geo)}, description: "newVehicle id \(newFCDvehicle.id)")

				add(newEvent: newVehicleEvent)
			}

			// Schedule events to update existing vehicles
			for existingFDCvehicleID in existingVehicleIDs {
				let existingFCDvehicle = timestep.vehicles[ timestep.vehicles.index( where: {$0.id == existingFDCvehicleID} )! ]

				let updateVehicleEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .mobility, action: {city.updateLocation(entityType: .vehicle, id: existingFDCvehicleID, geo: existingFCDvehicle.geo)}, description: "updateVehicle id \(existingFCDvehicle.id)")

				add(newEvent: updateVehicleEvent)
			}

			// Schedule events to act on vehicles ending their trips
			for missingFDCvehicleID in missingVehicleIDs {
				let endTripEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .mobility, action: {city.endTripConvertToParkedCar(vehicleID: missingFDCvehicleID)}, description: "endTripConvertToParkedCar vehicle \(missingFDCvehicleID)")

				add(newEvent: endTripEvent)
			}
		}
	}
}
