/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class GIS {
	let connection: Connection
	let srid: UInt
	let useHaversine: Bool

	init(parameters: ConnectionParameters, srid insrid: UInt, inUseHaversine: Bool = false) {
		do {
			connection = try Database.connect(parameters: parameters)
		} catch {
			print("\nDatabase connection error.")
			exit(EXIT_FAILURE)
		}
		srid = insrid
		useHaversine = inUseHaversine
	}

	// Valid feature types and their 'feattyp' codes.
	enum FeatureType: UInt {
		case Building	= 9790
		case Vehicle	= 2222
		case RoadsideUnit = 2223
		case ParkedCar = 2224
	}

	// Conversion rate from meters to degrees.
	/* At our location: 1" latitude: 30.89m; 1" longitude: 23.25m.
	 * Ideally we would be using SRID 27492 which would give us equal axis, but that would require
	 * converting the WGS84 coordinates from SUMO, which is nontrivial.
	 * We're defining the conversion between meters and degrees as: 1/(3600*30.89)
	 */
	let degreesPerMeter = 0.0000089925



	/*****************************/
	/*** Database Interactions ***/
	/*****************************/

	/// Returns the number of features with the specified type
	func countFeatures(withType featureType: FeatureType) -> UInt {
		let query: String = "SELECT COUNT(gid) FROM buildings WHERE feattyp='" + String(featureType.rawValue) + "'"
		do {
			let result = try connection.execute(Query(query))
			guard	let resultRow = result.rows.first,
					let countRow = resultRow["count"] as? Int64
					else {
						print("\nInvalid feature count returned.")
						print("Query: " + query)
						exit(EXIT_FAILURE)
			}
			return UInt(countRow)
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}

	/// Removes all features with the specified type from the database
	func clearFeatures(withType featureType: FeatureType) {
		let query: String = "DELETE FROM buildings WHERE feattyp='" + String(featureType.rawValue) + "'"
		do {
			try connection.execute(Query(query))
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}


	/// Returns the geographic coordinates of a feature identified by its GID (only works for Point type features)
	func getCoordinates(fromGID gid: UInt) -> (x: Double, y: Double) {
		let query: String = "SELECT ST_X(geom),ST_Y(geom) FROM buildings WHERE gid='" + String(gid) + "'"
		do {
			let result = try connection.execute(Query(query))
			if result.numberOfRows != 1 {
				print("\nNo matching GID in database.")
				print("Query: " + query)
				exit(EXIT_FAILURE)
			}
			guard	let resultRow = result.rows.first,
					let xgeo = resultRow["st_x"] as? Double,
					let ygeo = resultRow["st_y"] as? Double
					else {
						print("\nInvalid coordinate pair returned.")
						print("Query: " + query)
						exit(EXIT_FAILURE)
			}
			return (xgeo, ygeo)
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}


	/// Returns the GIDs of features in a specified circle (center+radius)
	func getFeatureGIDs(inCircleWithRadius range: Double, center: (x: Double, y: Double), featureTypes: [FeatureType]) -> [UInt] {
		let wgs84range = range*degreesPerMeter
		var query: String = "SELECT gid FROM buildings WHERE ST_DWithin(geom,ST_GeomFromText('POINT(" + String(center.x) + " " + String(center.y) + ")',4326)," + String(wgs84range) + ")"

		// Should always have at least one featureType
		guard let firstType = featureTypes.first else {
			print("\nError: At least one feature type must be specified.")
			exit(EXIT_FAILURE)
		}

		// Append first feature type to request
		query += " AND (feattyp='" + String(firstType.rawValue) + "'"

		// Append additional feature types to the query using OR clauses
		let additionalFeatureTypes = featureTypes.dropFirst()
		for type in additionalFeatureTypes {
			query += " OR feattyp='" + String(type.rawValue) + "'"
		}
		query += ")"

		do {
			var listOfGIDs = [UInt]()

			let result = try connection.execute(Query(query))
			if result.numberOfRows > 0 {
				for row in result.rows {
					let gid = row["gid"] as! Int32
					listOfGIDs.append(UInt(gid))
				}
			}
			return listOfGIDs
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}

	// Temporary convenience counterpart until splattering is implemented in Swift
	// Tracked as SR-128 (https://bugs.swift.org/browse/SR-128)
	func getFeatureGIDs(inCircleWithRadius range: Double, center: (x: Double, y: Double), featureTypes: FeatureType...) -> [UInt]? {
		return getFeatureGIDs(inCircleWithRadius: range, center: center, featureTypes: featureTypes)
	}


	/// Returns the distance from a specified GID to a geographic location
	func getDistance(fromGID gid: UInt, toPoint geo: (x: Double, y: Double)) -> Double {
		let gidCoords: (x: Double, y: Double) = getCoordinates(fromGID: gid)
		return getDistance(fromPoint: gidCoords, toPoint: geo)
	}


	/// Returns the distance between two geographic locations
	func getDistance(fromPoint geo1: (x: Double, y: Double), toPoint geo2: (x: Double, y: Double)) -> Double {
		if useHaversine {
			return getHaversineDistance(fromPoint: geo1, toPoint: geo2)
		} else {
			return getGISDistance(fromPoint: geo1, toPoint: geo2)
		}
	}


	/// Queries the database for the distance between two geographic locations
	func getGISDistance(fromPoint geo1: (x: Double, y: Double), toPoint geo2: (x: Double, y: Double)) -> Double {
		// Then calculate the distance between the two points
		let query: String = "SELECT ST_Distance(ST_Transform(ST_GeomFromText('POINT(\(geo1.x) \(geo1.y))',4326),\(srid)),ST_Transform(ST_GeomFromText('POINT(\(geo2.x) \(geo2.y))',4326),\(srid)));"

		do {
			let result = try connection.execute(Query(query))
			guard	let resultRow = result.rows.first,
				let distance = resultRow["st_distance"] as? Double
				else {
					print("\nInvalid distance returned.")
					print("Query: " + query)
					exit(EXIT_FAILURE)
			}
			return distance/degreesPerMeter
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}


	/// Returns the distance between two geographic locations with the Haversine approximation (no database query)
	func getHaversineDistance(fromPoint geo1: (x: Double, y: Double), toPoint geo2: (x: Double, y: Double)) -> Double {
		// Credits to rosettacode.org
		let lat1rad = geo1.y * M_PI/180
		let lon1rad = geo1.x * M_PI/180
		let lat2rad = geo2.y * M_PI/180
		let lon2rad = geo2.x * M_PI/180

		let dLat = lat2rad - lat1rad
		let dLon = lon2rad - lon1rad
		let a = sin(dLat/2) * sin(dLat/2) + sin(dLon/2) * sin(dLon/2) * cos(lat1rad) * cos(lat2rad)
		let c = 2 * asin(sqrt(a))
		let R = 6372.8

		return R * c / degreesPerMeter / 100
	}


	/// Checks whether there are any buildings in the line-of-sight between two points
	func checkForLineOfSight(fromPoint geo1: (x: Double, y: Double), toPoint geo2: (x: Double, y: Double)) -> Bool {
		let query: String = "SELECT COUNT(id) FROM buildings WHERE ST_Intersects(geom, ST_GeomFromText('LINESTRING(" + String(geo1.x) + " "	+ String(geo1.y) + "," + String(geo2.x) + " " + String(geo2.y) + ")',4326)) and feattyp='" + String(FeatureType.Building.rawValue) + "'"
		do {
			let result = try connection.execute(Query(query))
			guard	let resultRow = result.rows.first,
					let countRow = resultRow["count"] as? Int64
					else {
						print("\nInvalid feature count returned.")
						print("Query: " + query)
						exit(EXIT_FAILURE)
			}
			// If any buildings matched, return false
			return countRow > 0 ? false	: true
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}


	/// Checks whether there is a building at a specified location
	func checkForObstruction(atPoint geo: (x: Double, y: Double)) -> Bool {
		let query: String = "SELECT COUNT(gid) FROM buildings WHERE ST_Intersects(geom, ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326)) AND feattyp='" + String(FeatureType.Building.rawValue) + "'"
		do {
			let result = try connection.execute(Query(query))
			guard	let resultRow = result.rows.first,
					let countRow = resultRow["count"] as? Int64
					else {
						print("\nInvalid feature count returned.")
						print("Query: " + query)
						exit(EXIT_FAILURE)
			}
			// If anything matched, return true
			return countRow > 0 ? true : false
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}


	/// Adds a new point feature of the specified type, and returns its new GID
	func addPoint(ofType type: FeatureType, geo: (x: Double, y: Double), id: UInt) -> UInt {
		let query: String = "INSERT INTO buildings(id, geom, feattyp) VALUES (" + String(id) + ", ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326)," + String(type.rawValue) + ") RETURNING gid"
		do {
			let result = try connection.execute(Query(query))
			guard	let resultRow = result.rows.first,
					let gid = resultRow["gid"] as? Int32
					else {
						print("\nInvalid GID value returned.")
						print("Query: " + query)
						exit(EXIT_FAILURE)
			}
			return UInt(gid)
		} catch {
			print("\nDatabase insertion error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}


	/// Updates the coordinates of a specific point
	func updatePoint(withGID gid: UInt, geo: (x: Double, y: Double)) {
		let query: String = "UPDATE buildings SET geom=ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326) WHERE gid='" + String(gid) + "'"
		do {
			try connection.execute(Query(query))
		} catch {
			print("\nDatabase update error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}


	/// Deletes a point from the database by its GID
	func deletePoint(withGID gid: UInt) {
		let query: String = "DELETE FROM buildings WHERE gid='" + String(gid) + "'"
		do {
			try connection.execute(Query(query))
		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}
}
