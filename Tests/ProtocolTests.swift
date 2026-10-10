import XCTest

final class ProtocolTests: XCTestCase {
    // Produced independently with Python `cryptography` (AESGCM): key = bytes 0…31, nonce = bytes 100…111.
    // The Android Receiver's unit tests decrypt the same fixture.
    let key = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    let fixture = "ZGVmZ2hpamtsbW5vMzmrFBXLbLxWFiuYqV9F0jutc37+QpEXiLX9P8/UnB/zsSORbj65cJSHFFrfeOiMej1bTgCo3bvYjKdtnx+g0SCar97W+ip4YFo="

    func testDecryptsIndependentFixture() throws {
        let payload = try WireCrypto.decode(fixture, key: key)
        XCTAssertEqual(payload, LinkPayload(url: "https://youtu.be/dQw4w9WgXcQ", title: "Café ✓"))
    }

    func testRoundTripUsesFreshNonce() throws {
        let payload = LinkPayload(url: "geo:0,0?q=Colosseum", title: "Colosseum")
        let a = try WireCrypto.encode(payload, key: key)
        let b = try WireCrypto.encode(payload, key: key)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try WireCrypto.decode(a, key: key), payload)
    }

    func testRejectsTampering() throws {
        var bytes = [UInt8](Data(base64Encoded: fixture)!)
        bytes[20] ^= 1
        XCTAssertThrowsError(try WireCrypto.decode(Data(bytes).base64EncodedString(), key: key))
    }

    func testParsesPairingCode() throws {
        let pairing = try Pairing(code: " https://ntfy.sh|sm-abc_123|\(key)\n")
        XCTAssertEqual(pairing.topic, "sm-abc_123")
        XCTAssertEqual(try pairing.serverURL().absoluteString, "https://ntfy.sh")
        XCTAssertEqual(try Pairing(code: "ntfy.example.com/|t|\(key)").serverURL().absoluteString, "https://ntfy.example.com")
        XCTAssertThrowsError(try Pairing(code: "https://ntfy.sh|bad topic|\(key)"))
        XCTAssertThrowsError(try Pairing(code: "http://example.com|t|\(key)"))
        XCTAssertThrowsError(try Pairing(code: "https://ntfy.sh|t|c2hvcnQ="))
        XCTAssertThrowsError(try Pairing(code: "just text"))
    }

    func testLinkParsing() {
        XCTAssertEqual(LinkParser.payload(from: "https://youtu.be/abc")?.title, "YouTube video")
        XCTAssertEqual(LinkParser.payload(from: "Great video https://youtu.be/abc"),
                       LinkPayload(url: "https://youtu.be/abc", title: "Great video"))
        XCTAssertEqual(LinkParser.payload(from: "https://maps.apple.com/?q=Colosseum&ll=41.89,12.49")?.url,
                       "geo:0,0?q=Colosseum")
        XCTAssertEqual(LinkParser.payload(from: "geo:0,0?q=Piazza%20Navona")?.title, "Piazza Navona")
        XCTAssertNil(LinkParser.payload(from: "  "))
        XCTAssertNil(LinkParser.payload(from: "just some words", requireTarget: true))
        XCTAssertEqual(LinkParser.payload(from: "just some words")?.url, "just some words")
        XCTAssertEqual(LinkParser.payload(from: "x", title: "Mine")?.title, "Mine")
    }
}
