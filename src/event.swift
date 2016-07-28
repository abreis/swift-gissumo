/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

struct SimulationEvent {
	enum EventType {
		case Mobility
		case Network
	}

	var time: Double
	let type: EventType
	let action: ()->()
}

class EventList {
	var stopTime: Double
	var list = [SimulationEvent]()
	let minTimestep = 0.000001 // microsecond

	init(stopTime stime: Double) {
		stopTime = stime
	}

	// Add a new event, performing necessary checks
	func add(newEvent newEvent: SimulationEvent) {
		// Don't let two events have the same time. While events exist with the same time,
		// push our event forward by a small timestep.
		var newEvent = newEvent
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


	// Process mobility events, creating new vehicles and updating existing ones
	func process(mobilityEventsFromTimestep timestep: FCDTimestep, inout vehicleList: [Vehicle], gis: GIS) {
		// Keep track of the vehicles seen in this timestep
		var timestepVehicleIDs = [UInt]()

		for fcdVehicle in timestep.vehicles {
			// See if the vehicle exists in 'vehicleList'
			if let vIndex = vehicleList.indexOf( {$0.id == fcdVehicle.id} ),
				let vGID = vehicleList[vIndex].gid
			{
				// If so, update its coordinates
				vehicleList[vIndex].geo = fcdVehicle.geo

				// And move its point on GIS
				gis.update(pointFromGID: vGID, geo: (x: fcdVehicle.geo.x, y: fcdVehicle.geo.y))

				// Track this vehicle
				timestepVehicleIDs.append(vehicleList[vIndex].id)

				// Debug
				if debug.contains("EventList.process(mobility).update") {
					print(String(format: "%.6f EventList.process(mobility):\t", now).cyan(), "Update vehicle id", vehicleList[vIndex].id, "gid", vGID, "to coordinates", vehicleList[vIndex].geo)
				}
			} else {
				// If not, create the vehicle
				let newVehicle = Vehicle(createFromFCDVehicle: fcdVehicle, creationTime: timestep.time)
				newVehicle.gid = gis.add(pointOfType: .Vehicle, geo: (x:newVehicle.geo.x, y: newVehicle.geo.y), id: newVehicle.id)
				vehicleList.append(newVehicle)

				// Track this vehicle
				timestepVehicleIDs.append(newVehicle.id)

				// Debug
				if debug.contains("EventList.process(mobility).create") {
					print(String(format: "%.6f EventList.process(mobility):\t", now).cyan(), "Create vehicle id", newVehicle.id, "gid", newVehicle.gid!, "at", newVehicle.geo)
				}
			}
		}

		// Now mark any vehicles that disappeared in this timestep as 'inactive'
		for vehicle in vehicleList.filter({ $0.active == true }) {
			if !timestepVehicleIDs.contains(vehicle.id) {
				vehicle.active = false

				if debug.contains("EventList.process(mobility).inactive") {
					print(String(format: "%.6f EventList.process(mobility):\t", now).cyan(), "Mark vehicle id", vehicle.id, "gid", vehicle.gid!, "as inactive")
				}
			}

		}
	}

}

