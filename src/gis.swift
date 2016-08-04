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

	// Valid feature types and their 'feattyp' codes.
	enum FeatureType: UInt {
		case Building	= 9790
		case Vehicle	= 2222
	}
	
	// Conversion rate from meters to degrees.
	/* At our location: 1" latitude: 30.89m; 1" longitude: 23.25m.
	 * Ideally we would be using SRID 27492 which would give us equal axis, but that would require
	 * converting the WGS84 coordinates from SUMO, which is nontrivial.
	 * We're defining the conversion between meters and degrees as: 1/(3600*30.89)
	 */
	let degreesPerMeter = 0.0000089925



    /// Returns the number of features with the specified type.
	func count (featureType featureType: FeatureType) -> UInt {
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


    /// Removes all features with the specified type from the database.
    func clear(featureType featureType: FeatureType) {
        let query: String = "DELETE FROM buildings WHERE feattyp='" + String(featureType.rawValue) + "'"
        do {
            try connection.execute(Query(query))
        } catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
        }
    }


	/// Returns the geographic coordinates of a feature identified by its GID. Only works for Point type features.
	func get(coordinatesFromGID gid: UInt) -> (x: Double, y: Double) {
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
	
	
	/// Returns the GIDs of features in a specified circle (center+radius).
	func get(featuresInCircleWithRadius range: Double, center: (x: Double, y: Double), featureType: FeatureType) -> [UInt]? {
		let wgs84range = range*degreesPerMeter
		let query: String = "SELECT gid FROM buildings WHERE ST_DWithin(geom,ST_GeomFromText('POINT(" + String(center.x) + " " + String(center.y) + ")',4326)," + String(wgs84range) + ") and feattyp='" + String(featureType.rawValue) + "'"
		
		do {
			let result = try connection.execute(Query(query))
			
			if result.numberOfRows == 0 {
				return nil
			}
			
			var listOfGIDs = [UInt]()
			for row in result.rows {
				let gid = row["gid"] as! Int32
				listOfGIDs.append(UInt(gid))
			}

			return listOfGIDs

		} catch {
			print("\nDatabase query error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}
	
	
	/// Returns the distance from a specific GID to a geographic location.
	func get(distanceFromPointToGID gid: UInt, geo: (x: Double, y: Double)) -> Double {
		// First find the coordinates of the target point
		let gidCoords: (x: Double, y: Double) = get(coordinatesFromGID: gid)
		
		// Then calculate the distance between the two points
		let query: String = "SELECT ST_Distance('POINT(" + String(geo.x) + " " + String(geo.y) + ")', 'POINT(" + String(gidCoords.x) + " " + String(gidCoords.y) + ")')"

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
	
	
	/// Checks whether there are any buildings in the line-of-sight between two points.
	func checkForLineOfSight(geo1: (x: Double, y: Double), geo2: (x: Double, y: Double)) -> Bool {
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

	
	/// Checks whether there is something at a specified location.
	func checkForObstruction(geo: (x: Double, y: Double)) -> Bool {
		let query: String = "SELECT COUNT(gid) FROM buildings WHERE ST_Intersects(geom, ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326))"
		
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
	

	/// Adds a new point feature of the specified type, and returns its new GID.
	func add(pointOfType type: FeatureType, geo: (x: Double, y: Double), id: UInt) -> UInt {
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

	
	/// Updates the coordinates of a specific point.
	func update(pointFromGID gid: UInt, geo: (x: Double, y: Double)) {
		let query: String = "UPDATE buildings SET geom=ST_GeomFromText('POINT(" + String(geo.x) + " " + String(geo.y) + ")',4326) WHERE gid='" + String(gid) + "'"
		
		do {
			try connection.execute(Query(query))
		} catch {
			print("\nDatabase update error.")
			print("Query: " + query)
			exit(EXIT_FAILURE)
		}
	}

	/// Deletes a point from the database by its ID
	func delete(pointWithGID gid: UInt) {
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