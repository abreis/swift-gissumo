/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

struct SimulationEvent {
	let time: Double
	let action: ()->()
}

class EventList {
	var now: Double = 0.0
	var stopTime: Double

	var list = [SimulationEvent]()

	init(stopTime stime: Double) {
		stopTime = stime
	}

	// Add a new event, performing necessary checks (TODO)
	func add(newEvent newEvent: SimulationEvent) {
		list.append(newEvent)
	}


	// Processes mobility events, creating new vehicles and updating existing ones
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
					print("DEBUG EventList.process(mobility)".cyan(),":\t", "Update vehicle id", vehicleList[vIndex].id, "gid", vGID, "to coordinates", vehicleList[vIndex].geo)
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
					print("DEBUG EventList.process(mobility)".cyan(),":\t", "Create vehicle id", newVehicle.id, "gid", newVehicle.gid!, "at", newVehicle.geo)
				}
			}
		}

		// Now mark any vehicles that disappeared in this timestep as 'inactive'
		for vehicle in vehicleList.filter({ $0.active == true }) {
			if !timestepVehicleIDs.contains(vehicle.id) {
				vehicle.active = false

				if debug.contains("EventList.process(mobility).inactive") {
					print("DEBUG EventList.process(mobility)".cyan(),":\t", "Mark vehicle id", vehicle.id, "gid", vehicle.gid!, "as inactive")
				}
			}

		}
	}

}

