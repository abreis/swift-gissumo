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

	var time: Double
	let type: EventType
	let action: ()->()
	var description: String = ""
}

class EventList {
	let minTimestep = 0.000001 // microsecond

	// Current simulation time
	var now: Double = -1.0

	// Simulation stop time, from config
	var stopTime: Double

	// Array of simulation events
	var list = [SimulationEvent]()

	// Events to be executed post-simulation
	var cleanup = [SimulationEvent]()

	// Init with the simulation stop time
	init(stopTime stime: Double) {
		stopTime = stime
	}


	// Add a new event, performing necessary checks
	func add(newEvent event: SimulationEvent) {
		// Don't let two events have the same time. While events exist with the same time,
		// push our event forward by a small timestep.
		var newEvent = event
		while list.filter( {$0.time == newEvent.time} ).count > 0 {
			newEvent.time += minTimestep
		}

		/* Add the new event and trigger a sort to place it in the right location
		 * Built-in sort algorithms are likely faster than us running through the
		 * array to find the correct insertion index.
		 */
		list.append(newEvent)
		list.sortInPlace( {$0.time < $1.time} )

		// Debug
		if debug.contains("EventList.add(newEvent)") {
			print(String(format: "%.6f EventList.add(newEvent):\t", now).cyan(), "Add new event of type", newEvent.type, "at time", newEvent.time)
		}
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
			if debug.contains("EventList.scheduleMobilityEvents(fromFCD)"){
				print(String(format: "%.6f EventList.scheduleMobilityEvents(fromFCD):\t", now).cyan(), "Timestep", timestep.time, "sees:" )
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

				let newVehicleEvent = SimulationEvent(time: timestep.time, type: .Mobility, action: {city.addNewVehicle(id: newFCDvehicle.id, geo: newFCDvehicle.geo)}, description: "newVehicle id \(newFCDvehicle.id)")

				add(newEvent: newVehicleEvent)
			}

			// Schedule events to update existing vehicles
			for existingFDCvehicleID in existingVehicleIDs {
				let existingFCDvehicle = timestep.vehicles[ timestep.vehicles.indexOf( {$0.id == existingFDCvehicleID} )! ]

				let updateVehicleEvent = SimulationEvent(time: timestep.time, type: .Mobility, action: {city.updateVehicleLocation(id: existingFDCvehicleID, geo: existingFCDvehicle.geo)}, description: "updateVehicle id \(existingFCDvehicle.id)")

				add(newEvent: updateVehicleEvent)
			}

			// Schedule events to remove missing vehicles
			for missingFDCvehicleID in missingVehicleIDs {
				let removeVehicleEvent = SimulationEvent(time: timestep.time, type: .Mobility, action: {city.removeVehicle(id: missingFDCvehicleID)}, description: "removeVehicle id \(missingFDCvehicleID)")

				add(newEvent: removeVehicleEvent)
			}
		}
	}
}
