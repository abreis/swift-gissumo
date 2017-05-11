/* Andre Braga Reis, 2017
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation
import libgsl

class Random {
	init() { self.seed() }
	init(withSeed seed: Int) { self.seed(seed) }

	func seed() { srand48(Int(Date().timeIntervalSinceReferenceDate)) }
	func seed(_ s: Int) { srand48(s) }

	func gammaCDF(x: Double, shape: Double, scale: Double) -> Double {
		let probability: Double = gsl_cdf_gamma_P(x, shape, scale)
		return probability
	}

	let gammaCoefficientTable: [Int:(d1: Double, d2: Double, ks: Double, ts: Double, kl: Double, tl: Double)] = [
		 3 : (0.5642, 0.4358,  1.272, 298.7, 15.00, 43.73),
		 4 : (0.4984, 0.5016,  1.059, 338.4, 15.95, 40.14),
		 5 : (0.4854, 0.5146,  1.252, 156.1, 20.09, 30.06),
		 6 : (0.4317, 0.5683,  1.195, 127.5, 22.50, 25.24),
		 7 : (0.3972, 0.6028,  1.057, 111.6, 23.27, 21.96),
		 8 : (0.5482, 0.4518,  1.079, 137.8, 22.36, 21.46),
		 9 : (0.8206, 0.1794, 0.9479, 106.0, 22.90, 20.08),
		10 : (0.9543, 0.0457, 0.8640, 85.58, 19.39, 20.07),
		11 : (0.8755, 0.1245, 0.9315, 56.75, 9.388, 30.38),
		12 : (0.8000, 0.2000,  1.153, 44.69, 8.545, 28.69),
		13 : (0.7631, 0.2369,  1.224, 39.52, 9.682, 24.23),
		14 : (0.7523, 0.2477,  1.233, 30.55, 6.246, 29.97),
		15 : (0.7061, 0.2939,  1.252, 27.84, 5.831, 27.02),
		16 : (0.6995, 0.3005,  1.224, 23.82, 5.335, 23.06),
		17 : (0.6407, 0.3593,  1.129, 22.34, 4.384, 23.73),
		18 : (0.5669, 0.4331,  1.229, 24.59, 4.244, 27.27),
		19 : (0.5071, 0.4929,  1.309, 21.23, 3.849, 29.47),
		20 : (0.6390, 0.3611,  1.451, 11.93, 3.031, 30.10),
		21 : (0.6277, 0.3723,  1.454, 9.482, 2.966, 30.41)
	]

	func dualGammaParkingCDF(duration: Double, hour: Int) -> Double {
		guard 3...21 ~= hour else {
			print("Error: Invalid hour provided in the dual gamma parking model.")
			exit(EXIT_FAILURE)
		}

		let coeff = gammaCoefficientTable[hour]!

		let probability = coeff.d1 * gammaCDF(x: duration, shape: coeff.ks , scale: coeff.ts)
						+ coeff.d2 * gammaCDF(x: duration, shape: coeff.kl , scale: coeff.tl)

		return probability
	}

	func dualGammaParkingRandom(hour: Int, precision: Int = 3) -> Double {
		let randomUniformValue = drand48()

		var low: Double = 0.0
		var high: Double = 1500.0
		// Handle (rare) randoms above 1500
		while randomUniformValue > dualGammaParkingCDF(duration: high, hour: hour) {
			high += high
		}

		// Bisection, adapted from python's bisect.py
		let precisionMultiplier: Double = pow(10.0, Double(precision))
		while low < high {
			// Floor the mid to 'precision' decimal points
			let mid: Double = floor( ((low+high)/2.0) * precisionMultiplier) / precisionMultiplier

			// Bisect, adding the correct increment for the requested precision (0->1, 1->0.1, 2->0.01, ...)
			if randomUniformValue <= dualGammaParkingCDF(duration: mid, hour: hour) {
				high = mid
			} else {
				low = mid + 1.0/precisionMultiplier
			}

			// Safeguard floating point errors
			if (high-low) < 1.0/precisionMultiplier { break }
		}
		return low
	}
}
