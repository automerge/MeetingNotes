import Foundation

// https://stackoverflow.com/a/56870030/19477
// Licensed: CC BY-SA 4.0 for [itMaxence](https://stackoverflow.com/users/3328736/itmaxence)
extension String {
    enum ExtendedEncoding {
        case hexadecimal
    }

    func data(using _: ExtendedEncoding) -> Data? {
        let hexStr = self.dropFirst(self.hasPrefix("0x") ? 2 : 0)

        guard hexStr.count % 2 == 0 else { return nil }

        var newData = Data(capacity: hexStr.count / 2)

        var indexIsEven = true
        for i in hexStr.indices {
            if indexIsEven {
                let byteRange = i ... hexStr.index(after: i)
                guard let byte = UInt8(hexStr[byteRange], radix: 16) else { return nil }
                newData.append(byte)
            }
            indexIsEven.toggle()
        }
        return newData
    }
}

// usage:
//   "5413".data(using: .hexadecimal)
//   "0x1234FF".data(using: .hexadecimal)

// extension Data {
// Could make a more optimized one~
//    func hexa(prefixed isPrefixed: Bool = true) -> String {
//        self.bytes.reduce(isPrefixed ? "0x" : "") { $0 + String(format: "%02X", $1) }
//    }
// print("000204ff5400".data(using: .hexadecimal)?.hexa() ?? "failed") // OK
// print("0x000204ff5400".data(using: .hexadecimal)?.hexa() ?? "failed") // OK
// print("541".data(using: .hexadecimal)?.hexa() ?? "failed") // fails
// print("5413".data(using: .hexadecimal)?.hexa() ?? "failed") // OK
// }

// https://stackoverflow.com/a/73731660/19477
// Licensed: CC BY-SA 4.0 for [Nick](https://stackoverflow.com/users/392986/nick)
extension Data {
    init(hexString: String) {
        self = hexString
            .dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
            .compactMap { $0.hexDigitValue.map { UInt8($0) } }
            .reduce(into: (data: Data(capacity: hexString.count / 2), byte: nil as UInt8?)) { partialResult, nibble in
                if let p = partialResult.byte {
                    partialResult.data.append(p + nibble)
                    partialResult.byte = nil
                } else {
                    partialResult.byte = nibble << 4
                }
            }.data
    }
}
