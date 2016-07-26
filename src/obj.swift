/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

struct FCDVehicle {
	let id: UInt
	let xgeo: Double
	let ygeo: Double
	let speed: Double
}

struct FCDTimestep {
	let time: Double
	let vehicles: [FCDVehicle]
}
