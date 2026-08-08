import Foundation

/// A minimal binary property list (bplist00) reader.
///
/// Written for `CBTaoImporter`, which must walk NSKeyedArchiver object graphs
/// containing UID references. Foundation's `PropertyListSerialization`
/// represents UIDs differently across platforms (and hides them entirely in
/// some bridges), so a tiny self-contained parser is the portable answer —
/// same behavior on macOS and in the Linux test environment.
enum BinaryPlist {

    /// A parsed plist value. Cases mirror the bplist wire types we need.
    indirect enum Value {
        case null
        case bool(Bool)
        case int(Int64)
        case real(Double)
        /// Seconds since 2001-01-01 (Core Data / NSDate reference epoch).
        case date(Double)
        case string(String)
        case data(Data)
        /// NSKeyedArchiver object reference (index into $objects).
        case uid(Int)
        case array([Value])
        case dictionary([(Value, Value)])
    }

    struct ParseError: Error {
        var message: String
    }

    /// Parse a complete bplist00 blob (header at byte 0, trailer at the end).
    static func parse(_ data: Data) throws -> Value {
        let bytes = [UInt8](data)
        guard bytes.count > 40, Array(bytes.prefix(6)) == Array("bplist".utf8) else {
            throw ParseError(message: "not a bplist")
        }
        let trailer = Array(bytes.suffix(32))
        let offsetSize = Int(trailer[6])
        let refSize = Int(trailer[7])
        let numObjects = Int(readBE(trailer, 8, 8))
        let topObject = Int(readBE(trailer, 16, 8))
        let tableOffset = Int(readBE(trailer, 24, 8))
        guard [1, 2, 4, 8].contains(offsetSize), [1, 2, 4, 8].contains(refSize),
              numObjects > 0, topObject < numObjects, tableOffset < bytes.count
        else { throw ParseError(message: "bad trailer") }

        var offsets: [Int] = []
        offsets.reserveCapacity(numObjects)
        for i in 0..<numObjects {
            let start = tableOffset + i * offsetSize
            guard start + offsetSize <= bytes.count else { throw ParseError(message: "offset table overrun") }
            offsets.append(Int(readBE(bytes, start, offsetSize)))
        }

        var cache: [Int: Value] = [:]

        func object(at index: Int, depth: Int = 0) throws -> Value {
            guard depth < 64 else { throw ParseError(message: "nesting too deep") }
            if let cached = cache[index] { return cached }
            guard index < offsets.count else { throw ParseError(message: "object index out of range") }
            var p = offsets[index]
            guard p < bytes.count else { throw ParseError(message: "object offset out of range") }
            let marker = bytes[p]
            p += 1
            let kind = marker >> 4
            var count = Int(marker & 0x0f)

            func readLength() throws -> Int {
                if count != 0x0f { return count }
                // Length is an inline int object.
                let intMarker = bytes[p]; p += 1
                guard intMarker >> 4 == 0x1 else { throw ParseError(message: "bad length int") }
                let size = 1 << Int(intMarker & 0x0f)
                let value = Int(readBE(bytes, p, size)); p += size
                return value
            }

            let result: Value
            switch kind {
            case 0x0:
                switch marker {
                case 0x00: result = .null
                case 0x08: result = .bool(false)
                case 0x09: result = .bool(true)
                default: result = .null
                }
            case 0x1: // int, 2^count bytes
                let size = 1 << count
                result = .int(Int64(bitPattern: readBE(bytes, p, size)))
            case 0x2: // real
                let size = 1 << count
                let raw = readBE(bytes, p, size)
                if size == 8 {
                    result = .real(Double(bitPattern: raw))
                } else if size == 4 {
                    result = .real(Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw))))
                } else {
                    throw ParseError(message: "unsupported real size")
                }
            case 0x3: // date: 8-byte big-endian double
                result = .date(Double(bitPattern: readBE(bytes, p, 8)))
            case 0x4: // data
                count = try readLength()
                result = .data(Data(bytes[p..<(p + count)]))
            case 0x5: // ASCII string
                count = try readLength()
                guard let s = String(bytes: bytes[p..<(p + count)], encoding: .ascii) else {
                    throw ParseError(message: "bad ascii string")
                }
                result = .string(s)
            case 0x6: // UTF-16BE string
                count = try readLength()
                let byteCount = count * 2
                var units: [UInt16] = []
                units.reserveCapacity(count)
                for i in 0..<count {
                    units.append(UInt16(readBE(bytes, p + i * 2, 2)))
                }
                _ = byteCount
                result = .string(String(decoding: units, as: UTF16.self))
            case 0x8: // UID, count+1 bytes
                let size = count + 1
                result = .uid(Int(readBE(bytes, p, size)))
            case 0xa: // array of refs
                count = try readLength()
                var items: [Value] = []
                items.reserveCapacity(count)
                for i in 0..<count {
                    let ref = Int(readBE(bytes, p + i * refSize, refSize))
                    items.append(try object(at: ref, depth: depth + 1))
                }
                result = .array(items)
            case 0xd: // dict: N key refs then N value refs
                count = try readLength()
                var pairs: [(Value, Value)] = []
                pairs.reserveCapacity(count)
                for i in 0..<count {
                    let keyRef = Int(readBE(bytes, p + i * refSize, refSize))
                    let valueRef = Int(readBE(bytes, p + (count + i) * refSize, refSize))
                    pairs.append((try object(at: keyRef, depth: depth + 1),
                                  try object(at: valueRef, depth: depth + 1)))
                }
                result = .dictionary(pairs)
            default:
                throw ParseError(message: "unsupported marker 0x\(String(marker, radix: 16))")
            }
            cache[index] = result
            return result
        }

        return try object(at: topObject)
    }

    /// Find every plausible embedded bplist in a larger blob (e.g. a Core Data
    /// atomic store) and parse it. Trailer position is discovered by scanning
    /// backward for a spot that both looks like a trailer and parses cleanly.
    static func embeddedPlists(in data: Data) -> [Value] {
        let bytes = [UInt8](data)
        let magic = Array("bplist00".utf8)
        var results: [Value] = []
        var searchStart = 0
        while let start = find(magic, in: bytes, from: searchStart) {
            searchStart = start + 1
            var end = bytes.count
            while end - start > 40 {
                let t = Array(bytes[(end - 32)..<end])
                let offsetSize = Int(t[6]), refSize = Int(t[7])
                if [1, 2, 4, 8].contains(offsetSize), [1, 2, 4, 8].contains(refSize) {
                    let numObjects = Int(readBE(t, 8, 8))
                    let topObject = Int(readBE(t, 16, 8))
                    let tableOffset = Int(readBE(t, 24, 8))
                    if numObjects > 0, numObjects < 200_000, topObject < numObjects,
                       tableOffset >= 8, tableOffset < end - start {
                        if let parsed = try? parse(Data(bytes[start..<end])) {
                            results.append(parsed)
                            break
                        }
                    }
                }
                end -= 1
            }
        }
        return results
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        var i = from
        while i <= haystack.count - needle.count {
            if Array(haystack[i..<(i + needle.count)]) == needle { return i }
            i += 1
        }
        return nil
    }

    private static func readBE<C: RandomAccessCollection>(_ bytes: C, _ offset: Int, _ size: Int) -> UInt64
    where C.Element == UInt8, C.Index == Int {
        var value: UInt64 = 0
        for i in 0..<size {
            let index = bytes.startIndex + offset + i
            guard index < bytes.endIndex else { return value }
            value = (value << 8) | UInt64(bytes[index])
        }
        return value
    }
}

// MARK: - Convenience accessors

extension BinaryPlist.Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int64? {
        switch self {
        case .int(let i): return i
        case .real(let r): return Int64(r)
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .real(let r): return r
        case .int(let i): return Double(i)
        default: return nil
        }
    }
    var uidValue: Int? {
        if case .uid(let u) = self { return u }
        return nil
    }
    var arrayValue: [BinaryPlist.Value]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var dictionaryValue: [(BinaryPlist.Value, BinaryPlist.Value)]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }
    subscript(key: String) -> BinaryPlist.Value? {
        guard case .dictionary(let pairs) = self else { return nil }
        for (k, v) in pairs where k.stringValue == key { return v }
        return nil
    }
}
