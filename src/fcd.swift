/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

struct FCDVehicle {
	let id: UInt
	let geo: (x: Double, y: Double)
	let speed: Double
}

struct FCDTimestep {
	let time: Double
	let vehicles: [FCDVehicle]
}
