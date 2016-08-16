/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

struct SimulationEvent {
	enum EventType {
		case Mobility
		case Network
		case Statistics
	}

	var time: SimulationTime
	let type: EventType
	let action: ()->()
	var description: String = ""
}


struct SimulationTime: Equatable, Comparable, Hashable, FloatLiteralConvertible, CustomStringConvertible {
	var nanoseconds: Int
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
	// Conform to Hashable
	var hashValue: Int { return nanoseconds.hashValue }
	// Conform to CustomStringConvertible
	var description: String { return String(nanoseconds) }
	// Print as floating point Seconds with precision=6 (microsecond)
	var asSeconds: String { return String(format: "%6f", Double(nanoseconds)/1000000000.0) }
}

// Conform SimulationTime to Equatable, Comparable
func ==(lhs: SimulationTime, rhs: SimulationTime) -> Bool { return lhs.nanoseconds == rhs.nanoseconds }
func <(lhs: SimulationTime, rhs: SimulationTime) -> Bool { return lhs.nanoseconds < rhs.nanoseconds }
// Overload operatos +, -, +=
func +(left: SimulationTime, right: SimulationTime) -> SimulationTime { return SimulationTime(nanoseconds: left.nanoseconds+right.nanoseconds) }
func -(left: SimulationTime, right: SimulationTime) -> SimulationTime { return SimulationTime(nanoseconds: left.nanoseconds-right.nanoseconds) }
func +=(inout left: SimulationTime, right: SimulationTime) { left = left + right }

class EventList {
	let minTimestep = SimulationTime(microseconds: 1)

	// Current simulation time
	var now = SimulationTime(seconds: -1)

	// Simulation stop time, from config
	var stopTime: SimulationTime

	// Array of simulation events
	var list = [SimulationEvent]()

	// Events to be executed pre-simulation
	var initial = [SimulationEvent]()

	// Events to be executed post-simulation
	var cleanup = [SimulationEvent]()

	// Init with the simulation stop time
	init(stopTime stime: Double) {
		stopTime = SimulationTime(seconds: stime)
	}

	// Add a new event, keeping the event list sorted
	func add(newEvent newEvent: SimulationEvent) {
		orderedBisectAdd(newEvent: newEvent)
	}

	// A bisection-based ordered-insertion algorithm
	func orderedBisectAdd(newEvent newEvent: SimulationEvent) {
		var insertionIndex: Int = 0

		// Make event mutable
		var newEvent = newEvent

		if !list.isEmpty {
			// Quick insertion at the edges
			if newEvent.time > list.last!.time {
				insertionIndex = list.count
			} else if newEvent.time < list.first!.time {
				insertionIndex = 0
			} else if newEvent.time == list.last!.time {
				newEvent.time += minTimestep
				insertionIndex = list.count
			}
			// Locate position through bisection
			else {
				var low = 0
				var high = list.count

				// Bisection, adapted from python's bisect.py
				while low < high {
					let mid = (low+high)/2
					if newEvent.time <= list[mid].time {
						high = mid
					} else {
						low = mid + 1
					}
				}
				insertionIndex = low

				/* Don't let two events have the same time. While events exist
				* with the same time, push our event forward by a small timestep.
				*/
				while insertionIndex != list.count && list[insertionIndex].time == newEvent.time {
					newEvent.time += minTimestep
					insertionIndex += 1
				}
			}
		}

		// Now insert the new event at the correct position
		list.insert(newEvent, atIndex: insertionIndex)

		// Debug
		if debug.contains("EventList.add()") {
			print("\(now.asSeconds) EventList.add():\t".cyan(), "Add new event of type", newEvent.type, "at time", newEvent.time.asSeconds)
		}
	}

	// A safe version of ordered event insertion
	// Test new ordered insertion routines against this one
	func reverseIteratorAdd(newEvent newEvent: SimulationEvent) {
		var insertionIndex: Int = 0

		// Make event mutable
		var newEvent = newEvent

		// Don't run any code for the first event
		if !list.isEmpty {
			/* Find the position to insert our event in. As new events are more
			* likely to be scheduled for the end of the simulation, we run
			* through the eventlist in reverse order.
			*/
			forevent: for (pos, iteratorEvent) in list.enumerate().reverse() {
				insertionIndex = pos
				if iteratorEvent.time < newEvent.time {
					insertionIndex += 1
					break forevent
				}
			}

			/* Don't let two events have the same time. While events exist
			* with the same time, push our event forward by a small timestep.
			*/
			while insertionIndex != list.count && list[insertionIndex].time == newEvent.time {
				newEvent.time += minTimestep
				insertionIndex += 1
			}
		}

		// Now insert the new event at the correct position
		list.insert(newEvent, atIndex: insertionIndex)

		// Debug
		if debug.contains("EventList.add()") {
			print("\(now.asSeconds) EventList.add():\t".cyan(), "Add new event of type", newEvent.type, "at time", newEvent.time)
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

	// Process mobility timesteps, adding events to create, update and remove vehicles
	func scheduleMobilityEvents(inout fromFCD fcdTimesteps: [FCDTimestep], city: City) {
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
			let newVehicleIDs = fcdVehicleIDs.subtract(cityVehicleIDs)
			let existingVehicleIDs = fcdVehicleIDs.intersect(cityVehicleIDs)
			let missingVehicleIDs = cityVehicleIDs.subtract(fcdVehicleIDs)

			// Debug
			if debug.contains("EventList.scheduleMobilityEvents()"){
				print("\(now.asSeconds) EventList.scheduleMobilityEvents():\t".cyan(), "Timestep", timestep.time, "sees:" )
				print("\t\tFCD vehicles:", fcdVehicleIDs)
				print("\t\tCity vehicles:", cityVehicleIDs)
				print("\t\tNew vehicles:", newVehicleIDs)
				print("\t\tExisting vehicles:", existingVehicleIDs)
				print("\t\tMissing vehicles:", missingVehicleIDs)
			}

			// Insert and remove vehicles into our temporary array
			cityVehicleIDs.unionInPlace(newVehicleIDs)
			cityVehicleIDs.subtractInPlace(missingVehicleIDs)

			// Schedule events to create new vehicles
			for newFCDvehicleID in newVehicleIDs {
				let newFCDvehicle = timestep.vehicles[ timestep.vehicles.indexOf( {$0.id == newFCDvehicleID} )! ]
				// (note: the IDs came from timestep.vehicles, so an .indexOf on the array can be force-unwrapped safely)

				let newVehicleEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .Mobility, action: {city.addNewVehicle(id: newFCDvehicle.id, geo: newFCDvehicle.geo)}, description: "newVehicle id \(newFCDvehicle.id)")

				add(newEvent: newVehicleEvent)
			}

			// Schedule events to update existing vehicles
			for existingFDCvehicleID in existingVehicleIDs {
				let existingFCDvehicle = timestep.vehicles[ timestep.vehicles.indexOf( {$0.id == existingFDCvehicleID} )! ]

				let updateVehicleEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .Mobility, action: {city.updateVehicleLocation(id: existingFDCvehicleID, geo: existingFCDvehicle.geo)}, description: "updateVehicle id \(existingFCDvehicle.id)")

				add(newEvent: updateVehicleEvent)
			}

			// Schedule events to act on vehicles ending their trips
			for missingFDCvehicleID in missingVehicleIDs {
				let endTripEvent = SimulationEvent(time: SimulationTime(seconds: timestep.time), type: .Mobility, action: {city.endTripHook(vehicleID: missingFDCvehicleID)}, description: "endTripHook vehicle \(missingFDCvehicleID)")

				add(newEvent: endTripEvent)
			}
		}
	}
}
