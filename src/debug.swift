/* Andre Braga Reis, 2017
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

class Debug {
	// List of debug hooks enabled via configuration
	var hooks = [String]()

	// Eventlist to draw the current time from
	var events: EventList?

	var isEmpty: Bool { return hooks.isEmpty }

	// Init with the debug configuration entry and fill the array of hooks
	init(config: NSDictionary) {
		for element in config {
			if let enabled = element.value as? Bool, enabled == true {
				hooks.append(String(describing: element.key))
			}
		}
	}

	// Default debug print: checks if the hook is enabled, outputs the current time, and the requested data
	func printToHook(_ hook: String, data: Any...) {
		if debug.hooks.contains(hook) {
			print("\(events?.now.asSeconds) \(hook):".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), data)
		}
	}

	// Debug print with a string instead of time
	func printToHook(_ hook: String, label: String, data: Any...) {
		if debug.hooks.contains(hook) {
			print("\(label) \(hook):".padding(toLength: 54, withPad: " ", startingAt: 0).cyan(), data)
		}
	}
}
