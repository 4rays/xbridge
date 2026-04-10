import Foundation

/// A type-safe, Sendable representation of any JSON value.
public enum JSONValue: Sendable, Hashable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null; return }
    if let v = try? c.decode(Bool.self) { self = .bool(v); return }
    if let v = try? c.decode(Int.self) { self = .int(v); return }
    if let v = try? c.decode(Double.self) { self = .double(v); return }
    if let v = try? c.decode(String.self) { self = .string(v); return }
    if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
    if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
    throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON value")
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .int(let v): try c.encode(v)
    case .double(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}

// MARK: - Convenience accessors

extension JSONValue {
  public var stringValue: String? {
    guard case .string(let s) = self else { return nil }
    return s
  }

  public var intValue: Int? {
    guard case .int(let i) = self else { return nil }
    return i
  }

  public var doubleValue: Double? {
    guard case .double(let d) = self else { return nil }
    return d
  }

  public var boolValue: Bool? {
    guard case .bool(let b) = self else { return nil }
    return b
  }

  public var arrayValue: [JSONValue]? {
    guard case .array(let a) = self else { return nil }
    return a
  }

  public var objectValue: [String: JSONValue]? {
    guard case .object(let o) = self else { return nil }
    return o
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  public subscript(key: String) -> JSONValue? { objectValue?[key] }

  public subscript(index: Int) -> JSONValue? {
    guard let arr = arrayValue, index < arr.count else { return nil }
    return arr[index]
  }
}

// MARK: - Literal conformances

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) { self = .null }
}
extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self = .int(value) }
}
extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) { self = .double(value) }
}
extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}
