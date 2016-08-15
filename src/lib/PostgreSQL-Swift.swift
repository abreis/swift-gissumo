#if os(Linux)
	import Glibc
#else
	import Darwin
#endif

import libpq



/* ConnectionParameters */

public struct ConnectionParameters {
	public let host: String
	public let port: String
	public let options: String
	public let databaseName: String
	public let user: String
	public let password: String
	
	public init(host: String = String.fromCString(getenv("PGHOST")) ?? "",
	            port: String = String.fromCString(getenv("PGPORT")) ?? "",
	            options: String = String.fromCString(getenv("PGOPTIONS")) ?? "",
	            databaseName: String = String.fromCString(getenv("PGDATABASE")) ?? "",
	            user: String = String.fromCString(getenv("PGUSER")) ?? "",
	            password: String = String.fromCString(getenv("PGPASSWORD")) ?? "") {
		self.host = host
		self.port = port
		self.options = options
		self.databaseName = databaseName
		self.user = user
		self.password = password
	}
}



/* Connection */

/// A database connection is NOT thread safe.
public class Connection {
	let connectionPointer: COpaquePointer
	
	init(pointer: COpaquePointer) {
		self.connectionPointer = pointer
	}
	
	deinit {
		PQfinish(connectionPointer)
	}
	
	/// Executes a passed in query. First parameter is referred to as `$1` in the query.
	public func execute(query: Query, parameters: [Parameter] = []) throws -> QueryResult {
		let values = UnsafeMutablePointer<UnsafePointer<Int8>>.alloc(parameters.count)
		
		defer {
			values.destroy()
			values.dealloc(parameters.count)
		}
		
		var temps = [Array<UInt8>]()
		for (i, value) in parameters.enumerate() {
			temps.append(Array<UInt8>(value.asString.utf8) + [0])
			values[i] = UnsafePointer<Int8>(temps.last!)
		}
		
		let resultPointer = PQexecParams(connectionPointer,
		                                 query.string,
		                                 Int32(parameters.count),
		                                 nil,
		                                 values,
		                                 nil,
		                                 nil,
		                                 query.resultFormat.rawValue)
		
		let status = PQresultStatus(resultPointer)
		
		switch status {
		case PGRES_COMMAND_OK, PGRES_TUPLES_OK: break
		default:
			let message = String.fromCString(PQresultErrorMessage(resultPointer)) ?? ""
			throw QueryError.InvalidQuery(errorMessage: message)
		}
		
		return QueryResult(resultPointer: resultPointer)
	}
}

// TODO: Implement on Connection
public enum ConnectionStatus {
	case Connected
	case Disconnected
}



/* Database */

public enum ConnectionError: ErrorType {
	case ConnectionFailed(message: String)
}

public class Database {
	public static func connect(parameters parameters: ConnectionParameters = ConnectionParameters()) throws -> Connection {
		
		let connectionPointer = PQsetdbLogin(parameters.host,
		                                     parameters.port,
		                                     parameters.options,
		                                     "",
		                                     parameters.databaseName,
		                                     parameters.user,
		                                     parameters.password)
		
		guard PQstatus(connectionPointer) == CONNECTION_OK else {
			let message = String.fromCString(PQerrorMessage(connectionPointer))
			throw ConnectionError.ConnectionFailed(message: message ?? "Unknown error")
		}
		
		return Connection(pointer: connectionPointer)
	}
}



/* Parameter */

public protocol Parameter {
	var asString: String { get }
}

extension String: Parameter {
	public var asString: String {
		return self
	}
}

extension SignedIntegerType {
	public var asString: String {
		return "\(self)"
	}
}

extension FloatingPointType {
	public var asString: String {
		return "\(self)"
	}
}

extension BooleanType {
	public var asString: String {
		return "\(self)"
	}
}

extension Bool: Parameter {}

extension Int: Parameter {}
extension Int16: Parameter {}
extension Int32: Parameter {}
extension Int64: Parameter {}

extension Float: Parameter {}
extension Double: Parameter {}



/* Byteswap */

func floatFromInt32(input: Int32) -> Float {
	let array = byteArrayFrom(input)
	return typeFromByteArray(array, Float.self)
}

func doubleFromInt64(input: Int64) -> Double {
	let array = byteArrayFrom(input)
	return typeFromByteArray(array, Double.self)
}

func byteArrayFrom<T>(value: T) -> [UInt8] {
	var value = value
	return withUnsafePointer(&value) {
		Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: sizeof(T)))
	}
}

func typeFromByteArray<T>(byteArray: [UInt8], _: T.Type) -> T {
	return byteArray.withUnsafeBufferPointer {
		return UnsafePointer<T>($0.baseAddress).memory
	}
}



/* QueryResultRow */

public struct QueryResultRow {
	public let columnValues: [Any?]
	unowned let queryResult: QueryResult
	
	public subscript(columnName: String) -> Any? {
		get {
			guard let index = queryResult.columnIndexesForNames[columnName] else { return nil }
			return columnValues[index]
		}
	}
}



/* QueryResult */

/// Results are readonly operations and therefore threadsafe.
public final class QueryResult {
	let resultPointer: COpaquePointer
	
	init(resultPointer: COpaquePointer) {
		self.resultPointer = resultPointer
	}
	
	deinit {
		PQclear(resultPointer)
	}
	
	public lazy var columnIndexesForNames: [String: Int] = {
		var columnIndexesForNames = [String: Int]()
		
		for columnNumber in 0..<self.numberOfColumns {
			let name = String.fromCString(PQfname(self.resultPointer, columnNumber))!
			columnIndexesForNames[name] = Int(columnNumber)
		}
		
		return columnIndexesForNames
	}()
	
	public lazy var numberOfRows: Int32 = {
		return PQntuples(self.resultPointer)
	}()
	
	public lazy var numberOfColumns: Int32 = {
		return PQnfields(self.resultPointer)
	}()
	
	lazy var typesForColumnIndexes: [ColumnType?] = {
		var typesForColumns = [ColumnType?]()
		typesForColumns.reserveCapacity(Int(self.numberOfColumns))
		
		for columnNumber in 0..<self.numberOfColumns {
			let typeId = PQftype(self.resultPointer, columnNumber)
			typesForColumns.append(ColumnType(rawValue: typeId))
		}
		
		return typesForColumns
	}()
	
	public lazy var rows: [QueryResultRow] = {
		var rows = [QueryResultRow]()
		rows.reserveCapacity(Int(self.numberOfRows))
		
		for rowIndex in 0..<self.numberOfRows {
			rows.append(self.readResultRowAtIndex(rowIndex))
		}
		
		return rows
	}()
	
	private func readResultRowAtIndex(rowIndex: Int32) -> QueryResultRow {
		var values = [Any?]()
		values.reserveCapacity(Int(self.numberOfColumns))
		
		for columnIndex in 0..<self.numberOfColumns {
			values.append(readColumnValueAtIndex(columnIndex, rowIndex: rowIndex))
		}
		
		return QueryResultRow(columnValues: values, queryResult: self)
	}
	
	private func readColumnValueAtIndex(columnIndex: Int32, rowIndex: Int32) -> Any? {
		guard PQgetisnull(self.resultPointer, rowIndex, columnIndex) == 0 else { return nil }
		
		let startingPointer = PQgetvalue(self.resultPointer, rowIndex, columnIndex)
		
		guard let type = self.typesForColumnIndexes[Int(columnIndex)] else {
			let length = Int(PQgetlength(self.resultPointer, rowIndex, columnIndex))
			// Unsupported column types are returned as [UInt8]
			return byteArrayForPointer(UnsafePointer<UInt8>(startingPointer), length: length)
		}
		
		switch type {
		case .Boolean: return UnsafePointer<Bool>(startingPointer).memory
		case .Int16: return Int16(bigEndian: UnsafePointer<Int16>(startingPointer).memory)
		case .Int32: return Int32(bigEndian: UnsafePointer<Int32>(startingPointer).memory)
		case .Int64: return Int64(bigEndian: UnsafePointer<Int64>(startingPointer).memory)
		case .SingleFloat: return floatFromInt32(Int32(bigEndian: UnsafePointer<Int32>(startingPointer).memory))
		case .DoubleFloat: return doubleFromInt64(Int64(bigEndian: UnsafePointer<Int64>(startingPointer).memory))
		case .Text: return String.fromCString(startingPointer)!
		}
	}
	
	private func byteArrayForPointer(start: UnsafePointer<UInt8>, length: Int) -> [UInt8] {
		return Array(UnsafeBufferPointer(start: start, count: length))
	}
}

public enum ColumnType: UInt32 {
	case Boolean = 16
	case Int64 = 20
	case Int16 = 21
	case Int32 = 23
	case Text = 25
	case SingleFloat = 700
	case DoubleFloat = 701
}



/* Query */

public final class Query: StringLiteralConvertible {
	public let string: String
	
	public typealias StringLiteralType = String
	public typealias ExtendedGraphemeClusterLiteralType = String
	public typealias UnicodeScalarLiteralType = String
	
	public required init(_ string: String) {
		self.string = string
	}
	
	public convenience init(stringLiteral value: String) {
		self.init(value)
	}
	
	public convenience init(unicodeScalarLiteral value: String) {
		self.init(value)
	}
	
	public convenience init(extendedGraphemeClusterLiteral value: String) {
		self.init(value)
	}
	
	var resultFormat: QueryDataFormat {
		return .Binary
	}
}

extension Query: CustomDebugStringConvertible {
	public var debugDescription: String {
		return string
	}
}

public enum QueryError: ErrorType {
	case InvalidQuery(errorMessage: String)
}

enum QueryDataFormat: Int32 {
	case Text = 0
	case Binary = 1
}


