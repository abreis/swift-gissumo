/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

// Auxiliary mathematical functions
func normalCDF(value: Double) -> Double { return 0.5 * erfc(-value * M_SQRT1_2) }
func inverseNormalCDF(value: Double) -> Double {
	// Abramowitz and Stegun formula 26.2.23.
	// The absolute value of the error should be less than 4.5 e-4.
	func RationalApproximation(t: Double) -> Double {
		let c = [2.515517, 0.802853, 0.010328]
		let d = [1.432788, 0.189269, 0.001308]
		return t - ((c[2]*t + c[1])*t + c[0]) /
			(((d[2]*t + d[1])*t + d[0])*t + 1.0);
	}
	if value < 0.5 { return -RationalApproximation( sqrt(-2.0*log(value)) ) }
	else { return RationalApproximation( sqrt(-2.0*log(1-value)) ) }
}


// A measurement object: load data into 'samples' and all metrics are obtained as computed properties
struct Measurement {
	var samples = [Double]()
	mutating func add(point: Double) { samples.append(point) }

	var count: Double { return Double(samples.count) }
	var sum: Double { return samples.reduce(0, combine:+) }
	var mean: Double { return sum/count	}

	// This returns the maximum likelihood estimator(over N), not the minimum variance unbiased estimator (over N-1)
	var variance: Double { return samples.reduce(0, combine: {$0 + pow($1-mean,2)} )/count }
	var stdev: Double { return sqrt(variance) }

	// Specify the desired confidence level (1-significance) before requesting the intervals
//	func confidenceIntervals(confidence: Double) -> Double {}
	//var confidence: Double = 0.90
	//var confidenceInterval: Double { return 0.0 }
}
