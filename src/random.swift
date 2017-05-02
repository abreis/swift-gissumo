/* Andre Braga Reis, 2017
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

// From SwiftStats@github
class Random {
	init() { self.seed() }
	init(withSeed seed: Int) { self.seed(seed) }

	func seed() { srand48(Int(Date().timeIntervalSinceReferenceDate)) }
	func seed(_ s: Int) { srand48(s) }

	func erfinv(_ y: Double) -> Double {
		let center = 0.7
		let a = [ 0.886226899, -1.645349621,  0.914624893, -0.140543331]
		let b = [-2.118377725,  1.442710462, -0.329097515,  0.012229801]
		let c = [-1.970840454, -1.624906493,  3.429567803,  1.641345311]
		let d = [ 3.543889200,  1.637067800]
		if abs(y) <= center {
			let z = pow(y,2)
			let num = (((a[3]*z + a[2])*z + a[1])*z) + a[0]
			let den = ((((b[3]*z + b[2])*z + b[1])*z + b[0])*z + 1.0)
			var x = y*num/den
			x = x - (erf(x) - y)/(2.0/sqrt(M_PI)*exp(-x*x))
			x = x - (erf(x) - y)/(2.0/sqrt(M_PI)*exp(-x*x))
			return x
		}

		else if abs(y) > center && abs(y) < 1.0 {
			let z = pow(-log((1.0-abs(y))/2),0.5)
			let num = ((c[3]*z + c[2])*z + c[1])*z + c[0]
			let den = (d[1]*z + d[0])*z + 1
			// should use the sign public static function instead of pow(pow(y,2),0.5)
			var x = y/pow(pow(y,2),0.5)*num/den
			x = x - (erf(x) - y)/(2.0/sqrt(M_PI)*exp(-x*x))
			x = x - (erf(x) - y)/(2.0/sqrt(M_PI)*exp(-x*x))
			return x
		}

		else if abs(y) == 1 {
			return y*Double(Int.max)
		}

		else {
			// this should throw an error instead
			return Double.nan
		}
	}

	func normrnd(mean: Double, variance: Double) -> Double {
		let p = Double(drand48())
		return mean + pow(variance*2, 0.5) * erfinv(2*p-1)
	}

	func unifrnd(a: Double, b: Double) -> Double {
		let p = Double(drand48())
		if p>=0 && p<=1{
			return p*(b-a)+a
		}
		return Double.nan
	}

	func gamrnd(shape: Double, scale: Double) -> Double {
		if shape < 1 {
			let u = unifrnd(a: 0, b: 1)
			return gamrnd(shape: 1.0 + shape, scale: scale) * pow(u, 1.0/shape)
		}

		let d = shape - 1.0 / 3.0
		let c = (1.0/3.0)/sqrt(d)

		var v: Double = 0, x: Double
		while true {
			repeat {
				x = normrnd(mean: 0, variance: 1)
				v = 1.0 + c*x
			} while v < 0

			v = v * v * v
			let u = unifrnd(a: 0, b: 1)

			if u < 1 - 0.0331 * x * x * x * x {
				break
			}

			if log(u) < 0.5 * x * x + d * (1 - v + log (v)) {
				break
			}
		}

		return scale * d * v
	}
}
