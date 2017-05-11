/* Andre Braga Reis, 2017
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

// Parking models return a time parked value
protocol ParkDurationModel {
	func getParkingDuration(timeOfParking: Time?) -> Time
}



// A fixed-time parking duration model
class FixedLifetimeModel: ParkDurationModel {
	let maxDuration: Time
	init(lifetime: Int) {
		maxDuration = Time(seconds: lifetime)
	}
	func getParkingDuration(timeOfParking: Time?) -> Time {
		return maxDuration
	}
}



// The dual-Gamma model, returning a random duration based on the time of parking
class DualGammaParkingModel: ParkDurationModel {
	let rng: Random
	var dayTimeDelta: Int = 0

	init() { rng = Random() }
	init(withSeed seed: Int?=nil, dayTimeDelta: Int=0) {
		if seed != nil {
			rng = Random(withSeed: seed!)
		} else {
			rng = Random()
		}
		self.dayTimeDelta = dayTimeDelta
	}

	func getParkingDuration(timeOfParking: Time?) -> Time {
		guard let timeOfParking = timeOfParking else {
			print("Error: Dual gamma model requires a valid time of parking.")
			exit(EXIT_FAILURE)
		}

		// Convert the time of parking to hours and apply day time delta
		let hourOfParking = Int( floor( (timeOfParking.fpSeconds + Double(dayTimeDelta))/3600.0) )

		// Get a random parking duration from the model
		let parkingDurationMinutes = rng.dualGammaParkingRandom(hour: hourOfParking)

		// Note: The model returns a duration in minutes
		return Time(minutes: parkingDurationMinutes)
	}
}



// The Nakagami model, similar to the Gamma model but without hour-to-hour distinction
// UNIMPLEMENTED
class NakagamiParkingModel: ParkDurationModel {
	func getParkingDuration(timeOfParking: Time?) -> Time {
		return Time(seconds: 0)
	}
}
