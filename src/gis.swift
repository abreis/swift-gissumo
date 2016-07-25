/* Andre Braga Reis, 2016
* Licensing information can be found in the accompanying LICENSE file.
*/

import Foundation

class GIS {
	let connection: Connection
	
	init(parameters: ConnectionParameters) {
		do {
			connection = try Database.connect(parameters: parameters)
		} catch {
			print("\nDatabase connection error.")
			exit(EXIT_FAILURE)
		}
	}

	enum FeatureType: UInt {
		case Building	= 9790
		case Vehicle	= 2222
	}

	func count (featureType feat: FeatureType) -> UInt {
		let query: String = "SELECT COUNT(gid) FROM buildings WHERE feattyp='" + String(feat.rawValue) + "';"

		do {
			let result = try connection.execute(Query(query))
			let resultRow = result.rows[0]
			let countRow = resultRow["count"] as! Int64
			return UInt(countRow)
		} catch {
			print("\nDatabase query error.")
			exit(EXIT_FAILURE)
		}
	}
}