/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

struct FCDVehicle {
	let id: UInt
	let xgeo: Float
	let ygeo: Float
	let speed: Float
}

struct FCDTimestep {
	let time: Float
	let vehicles: [FCDVehicle]
}
