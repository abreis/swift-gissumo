/* Andre Braga Reis, 2016
 * Licensing information can be found in the accompanying LICENSE file.
 */

import Foundation

class GIS {
	let connection: PGConnection
	let srid: UInt
	let useHaversine: Bool

	init(parameters: String, srid insrid: UInt, inUseHaversine: Bool = false) {
		connection = PGConnection()

		guard connection.connectdb(parameters) == PGConnection.StatusType.ok else {
			print("\nDatabase connection error.")
			exit(EXIT_FAILURE)
		}

		srid = insrid
		useHaversine = inUseHaversine
	}

	// Valid feature types and their 'feattyp' codes.
	enum FeatureType: UInt {
		case building	= 9790
		case vehicle	= 2222
		case roadsideUnit = 2223
		case parkedCar = 2224
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

	/* Possible query results from libpq:
	 * Bad:
	 * .emptyQuery		The string sent to the server was empty.
	 * .badResponse		The server's response was not understood.
	 * .nonFatalError	A nonfatal error (a notice or warning) occurred.
	 * .fatalError		A fatal error occurred.
	 *
	 * Good:
	 * .commandOK		Successful completion of a command returning no data.
	 * .tuplesOK		Successful completion of a command returning data (such as a SELECT or SHOW).
	 * .singleTuple		For libpq in single-row mode only.
	 *
	 */


	/// Returns the number of features with the specified type
	func countFeatures(withType featureType: FeatureType) -> UInt {
		let query: String = "SELECT COUNT(gid) FROM buildings WHERE feattyp='" + String(featureType.rawValue) + "'"
		let result = connection.exec(statement: query)
		guard result.status() == .tuplesOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard let count = result.getFieldInt(tupleIndex: 0, fieldIndex: 0) else {
			print("\nInvalid feature count returned.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		return UInt(count)
	}

	/// Removes all features with the specified type from the database
	func clearFeatures(withType featureType: FeatureType) {
		let query: String = "DELETE FROM buildings WHERE feattyp='" + String(featureType.rawValue) + "'"
		let result = connection.exec(statement: query)
		guard result.status() == .commandOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
	}


	/// Returns the geographic coordinates of a feature identified by its GID (only works for Point type features)
	func getCoordinates(fromGID gid: UInt) -> (x: Double, y: Double) {
		let query: String = "SELECT ST_X(geom),ST_Y(geom) FROM buildings WHERE gid='" + String(gid) + "'"
		let result = connection.exec(statement: query)
		// If no GIDs are found, this might return .commandOK instead, and should fail
		guard result.status() == .tuplesOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard result.numTuples() > 0 else {
			print("\nNo matching GID in database.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard	result.numFields() > 1,
				result.fieldName(index: 0) == "st_x",
				result.fieldName(index: 0) == "st_y",
				let xgeo = result.getFieldDouble(tupleIndex: 0, fieldIndex: 0),
				let ygeo = result.getFieldDouble(tupleIndex: 0, fieldIndex: 1)
				else {
					print("\nInvalid coordinate pair returned.", "Query: ", query)
					exit(EXIT_FAILURE)
		}
		return (xgeo, ygeo)
	}


	/// Returns the GIDs of features in a specified circle (center+radius)
	func getFeatureGIDs(inCircleWithRadius range: Double, center: (x: Double, y: Double), featureTypes: [FeatureType]) -> [UInt] {
		let wgs84range = range*degreesPerMeter

		// Assemble query
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

		// Execute query
		let result = connection.exec(statement: query)
		// If no GIDs are found, this might return .commandOK instead -> and should succeed and return an empty array
		var listOfGIDs = [UInt]()
		if result.status() == .commandOK {
			print("TODO: Got a .commandOK, need to address it.\n")
			return listOfGIDs
		}
		guard result.status() == .tuplesOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard result.fieldName(index: 0) == "gid" else {
			print("\nUnexpected reply structure.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		if result.numFields() > 0 {
			for tupleNum in 0..<result.numTuples() {
				let gid = result.getFieldInt(tupleIndex: tupleNum, fieldIndex: 0)
				listOfGIDs.append(UInt(gid!))
			}
		}
		return listOfGIDs
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
		let query: String = "SELECT ST_Distance(ST_Transform(ST_GeomFromText('POINT(\(geo1.x) \(geo1.y))',4326),\(srid)),ST_Transform(ST_GeomFromText('POINT(\(geo2.x) \(geo2.y))',4326),\(srid)));"
		let result = connection.exec(statement: query)
		guard result.status() == .tuplesOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard	result.numTuples() > 0,
				result.numFields() > 0,
				result.fieldName(index: 0) == "st_distance",
				let distance = result.getFieldDouble(tupleIndex: 0, fieldIndex: 0)
				else {
					print("\nInvalid distance returned, ", "Query: ", query)
					exit(EXIT_FAILURE)
		}

		/* NOTE: For some unknown reason PostGIS might be returning st_distance in meters or degrees,
		 * so this routine may need to be adjusted accordingly. We're not solving this bug now, as 
		 * we'll be using the faster Haversine distance routine (below).
		 */
//		return distance/degreesPerMeter
		return distance
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
		var a = sin(dLat/2) * sin(dLat/2)
			a += sin(dLon/2) * sin(dLon/2) * cos(lat1rad) * cos(lat2rad)
		let c = 2 * asin(sqrt(a))
		let R = 6372.8

		return R * c / degreesPerMeter / 100
	}


	/// Checks whether there are any buildings in the line-of-sight between two points
	func checkForLineOfSight(fromPoint geo1: (x: Double, y: Double), toPoint geo2: (x: Double, y: Double)) -> Bool {
		let query: String = "SELECT COUNT(id) FROM buildings WHERE ST_Intersects(geom, ST_GeomFromText('LINESTRING(" + String(geo1.x) + " "	+ String(geo1.y) + "," + String(geo2.x) + " " + String(geo2.y) + ")',4326)) and feattyp='" + String(FeatureType.building.rawValue) + "'"
		let result = connection.exec(statement: query)
		guard result.status() == .tuplesOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard	result.numTuples() > 0,
				result.numFields() > 0,
				result.fieldName(index: 0) == "count",
				let count = result.getFieldInt(tupleIndex: 0, fieldIndex: 0)
			else {
				print("\nInvalid feature count returned, ", "Query: ", query)
				exit(EXIT_FAILURE)
		}
		// If any buildings matched, return false
		return count > 0 ? false : true
	}


	/// Checks whether there is a building at a specified location
	func checkForObstruction(atPoint geo: (x: Double, y: Double)) -> Bool {
		let query: String = "SELECT COUNT(gid) FROM buildings WHERE ST_Intersects(geom, ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326)) AND feattyp='" + String(FeatureType.building.rawValue) + "'"
		let result = connection.exec(statement: query)
		guard result.status() == .tuplesOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard	result.numTuples() > 0,
			result.numFields() > 0,
			result.fieldName(index: 0) == "count",
			let count = result.getFieldInt(tupleIndex: 0, fieldIndex: 0)
			else {
				print("\nInvalid feature count returned, ", "Query: ", query)
				exit(EXIT_FAILURE)
		}
		// If anything matched, return true
		return count > 0 ? true : false
	}


	/// Adds a new point feature of the specified type, and returns its new GID
	func addPoint(ofType type: FeatureType, geo: (x: Double, y: Double), id: UInt) -> UInt {
		let query: String = "INSERT INTO buildings(id, geom, feattyp) VALUES (" + String(id) + ", ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326)," + String(type.rawValue) + ") RETURNING gid"
		let result = connection.exec(statement: query)
		guard result.status() == .tuplesOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
		guard	result.numTuples() > 0,
				result.numFields() > 0,
				result.fieldName(index: 0) == "gid",
				let gid = result.getFieldInt(tupleIndex: 0, fieldIndex: 0)
				else {
					print("\nInvalid GID value returned, ", "Query: ", query)
					exit(EXIT_FAILURE)
		}
		return UInt(gid)
	}


	/// Updates the coordinates of a specific point
	func updatePoint(withGID gid: UInt, geo: (x: Double, y: Double)) {
		let query: String = "UPDATE buildings SET geom=ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326) WHERE gid='" + String(gid) + "'"
		let result = connection.exec(statement: query)
		guard result.status() == .commandOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
	}


	/// Deletes a point from the database by its GID
	func deletePoint(withGID gid: UInt) {
		let query: String = "DELETE FROM buildings WHERE gid='" + String(gid) + "'"
		let result = connection.exec(statement: query)
		guard result.status() == .commandOK else {
			print("\nDatabase query error.", "Query: ", query)
			exit(EXIT_FAILURE)
		}
	}
}
