public final class Domain: NSObject {
    public private(set) var domain: String
    public private(set) var spkis: [[String: DomainSpkisAlgorithm]]
    public private(set) var matchMode: DomainMatchMode
    public private(set) var reportUris: [String]?

    init(
        _ domain: String,
        spkis: [[String: DomainSpkisAlgorithm]],
        matchMode: DomainMatchMode,
        reportUris: [String]? = nil
    ) {
        self.domain = domain
        self.spkis = spkis
        self.matchMode = matchMode
        self.reportUris = reportUris
    }
}

public enum DomainMatchMode: String {
    case unsupported, exact, includeSubdomains

    static func matchMode(string: String) -> DomainMatchMode {
        if string == "exact" {
            .exact
        }
        else if string == "include-subdomains" {
            .includeSubdomains
        }
        else {
            .unsupported
        }
    }
}

public enum DomainSpkisAlgorithm {
    case unsupported, sha256

    static func spskisAlgorithm(string: String) -> DomainSpkisAlgorithm {
        string == "sha256" ? .sha256 : .unsupported
    }
}

extension Domain {
    static var defaultConfig: [Domain] {
        [
            Domain(
                "threema.ch",
                spkis: [
                    ["vGQZ8hm2h+km+q7rnJ7kF9S17BwSY0rbhwjz6nIupf0=": .sha256],
                    ["3L0bKTNfTwVUCjYqqhZXJIO03qC00bSnuxZFsb09OUo=": .sha256],
                    ["NN6Lb+2AE7CN3HWZKoWOe6mmHROOnywWoKZYWL1oHIU=": .sha256],
                    ["efJCZofFPR3oV/bBk0wmehqnhy3Vv+s9P+3sjhHem/E=": .sha256],
                    ["2Vpy8qUQCqc2+Lg6BgRO8G6e6vh7NmvVHTljfwP/Pfk=": .sha256],
                    ["KKBJHJn1PQSdNTmoAfhxqWTO61r8O8bPi/JeGtP/6gg=": .sha256],
                ],
                matchMode: .includeSubdomains,
                reportUris: ["https://3ma.ch/pinreport"]
            ),
            Domain(
                "threema.com",
                spkis: [
                    ["saKwtUPx8bCj9CW+c55nU2jb4aOpr0vBD8XMJveXq34=": .sha256],
                    ["nZWRY8rNSEqxjQDQjaunWlUL+YBOTK1xN5Bb0wMq/K0=": .sha256],
                    ["5AfgU7xFqhx5AS69cQZlAGv6JpmLm0A+Z6yBrLPOCP8=": .sha256],
                    ["GGSYKwkV3h6SRIY16Ixsh8LEKuGuhx3B4CamRde4xgY=": .sha256],
                    ["oD0JGdy32wZtoUT4n9ac3HLOgEosnx2kq+qaJnmtsQk=": .sha256],
                    ["j4n4RTr0MLfQ3gBmONIFreXDq5/Kkb2oquVTmq0n5pI=": .sha256],
                ],
                matchMode: .includeSubdomains,
                reportUris: ["https://3ma.ch/pinreport"]
            ),
            Domain(
                "sfu.threema.ch",
                spkis: [
                    ["useMPV2qPBEgxVucMPuqexG27L64zFAksHh9BehZpY0=": .sha256],
                    ["88JttF0tDWrGT6g8H9uEZ0T8xosvZtZwWlsZuD4NvHA=": .sha256],
                    ["F82gDLif130AsVx454ZsMxPGl9EpzB5LqY39CzVKWDQ=": .sha256],
                    ["Jo4Re5X+mksn/Ankgrnov07caZwkkT8NezJMQf1i8cI=": .sha256],
                ],
                matchMode: .includeSubdomains,
                reportUris: ["https://3ma.ch/pinreport"]
            ),
            
        ]
    }
}
