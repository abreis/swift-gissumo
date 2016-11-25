/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

/* Build a CellMap that marks [O]pen on every cell where a car is seen,
 * and [B]locked on every other cell.
 * These maps can then be loaded from from file into a Payload.content, and
 * into a CellMap<Character> to serve as a mask for the statistics module
 * to correctly determine averages.
 */
func buildObstructionMask(fromTrips trips: [FCDTimestep]) throws {
	// First find the city bounds. Same as City.determineBounds()

	// Initialize the city bounds with reversed WGS84 extreme bounds
	var bounds = Square(x: (min: 0, max: 0), y: (min: 0, max: 0))
	bounds.x = (min:  180.0, max: -180.0)
	bounds.y = (min:   90.0, max:  -90.0)

	// Locate the min and max coordinate pairs of the vehicles in the supplied Floating Car Data
	// Run through every timestep and find min and max coordinates
	for timestep in trips {
		for vehicle in timestep.vehicles {
			if vehicle.geo.x < bounds.x.min { bounds.x.min = vehicle.geo.x }
			if vehicle.geo.x > bounds.x.max { bounds.x.max = vehicle.geo.x }
			if vehicle.geo.y < bounds.y.min { bounds.y.min = vehicle.geo.y }
			if vehicle.geo.y > bounds.y.max { bounds.y.max = vehicle.geo.y }
		}
	}

	// Now determine the size of the map in cells
	var cells: (x: Int, y: Int)
	cells.x = Int( ceil(bounds.x.max*3600) - floor(bounds.x.min*3600) )
	cells.y = Int( ceil(bounds.y.max*3600) - floor(bounds.y.min*3600) )

	// Create a new Character map to store cell types
	var blockageMap = CellMap<Character>(ofSize: (x: cells.x, y: cells.y), withValue: Character("B"), geographicTopLeft: (x: bounds.x.min, y: bounds.y.max))

	// Every cell where a vehicle is seen can be marked as [O]pen
	for timestep in trips {
		for vehicle in timestep.vehicles {
			blockageMap[vehicle.geo] = Character("O")
		}
	}

	// Write the map as a Payload.content to a file
	let mapURL = URL(fileURLWithPath: "obstructionMask.payload")
	do {
		try blockageMap.toPayload().content.write(to: mapURL, atomically: true, encoding: String.Encoding.utf8)
	} catch {
		throw error
	}
}
