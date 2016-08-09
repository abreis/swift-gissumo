/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class Statistics {
	var folder: String = "stats/"
	var interval: Double = 1.0
	var startTime: Double = 1.0
	var hooks = [String]()

	init(config: NSDictionary) {
		// Load general statistics configurations, if defined: folder, interval, startTime
		if let configFolder = config["statsFolder"] as? String {
			folder = configFolder
			if !folder.hasSuffix("/") {	folder.append(Character("/")) }
		}

		if let configInterval = config["collectionInterval"] as? Double {
			interval = configInterval
		}

		if let configStartTime = config["collectionStartTime"] as? Double {
			startTime = configStartTime
		}

		// Load hook list
		if let hookList = config["hooks"] as? NSDictionary {
			for element in hookList {
				if let enabled = element.value as? Bool where enabled == true {
					hooks.append(String(element.key))
				}
			}
		}
	}


	func scheduleCollectionEvents(fromCity city: City) {
		
	}

	func collectStatistics(fromCity city: City) {
		
	}
}