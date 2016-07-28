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
}
