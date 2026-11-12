// Release signing for NexoLLM updates (Ed25519, CryptoKit).
//
//   swift scripts/release-signing.swift keygen
//       Creates the signing key pair. The private key goes into the login Keychain (service
//       "NexoLLM Release Signing", account "ed25519") and is never written anywhere else; the public key is
//       printed, to be pasted into `Updater.publicKeyBase64`. Refuses to overwrite an existing key.
//
//   swift scripts/release-signing.swift sign <file.dmg> <version>
//       Prints the base64 signature of "NexoLLM-release-v1:<version>:<sha256 of file>" (stdout), using the
//       key in the Keychain. The app verifies exactly this message with the embedded public key.
//
//   swift scripts/release-signing.swift public
//       Prints the public key of the key in the Keychain.
//
// Back up the private key once with scripts/backup-signing-key.sh (encrypted with a password you choose).
import CryptoKit
import Foundation

let service = "NexoLLM Release Signing"
let account = "ed25519"

func fail(_ msg: String) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(1) }

@discardableResult
func security(_ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { fail("cannot run security: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func storedKey() -> Curve25519.Signing.PrivateKey? {
    let r = security(["find-generic-password", "-s", service, "-a", account, "-w"])
    guard r.status == 0, let raw = Data(base64Encoded: r.out) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func sha256Hex(_ url: URL) -> String {
    guard let h = try? FileHandle(forReadingFrom: url) else { fail("cannot read \(url.path)") }
    var hasher = SHA256()
    while let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    if storedKey() != nil { fail("A signing key already exists in the Keychain. Refusing to overwrite it.") }
    let key = Curve25519.Signing.PrivateKey()
    let r = security(["add-generic-password", "-s", service, "-a", account, "-l", service,
                      "-j", "Private Ed25519 key that signs NexoLLM releases. Never share it.",
                      "-w", key.rawRepresentation.base64EncodedString()])
    guard r.status == 0, storedKey() != nil else { fail("Could not store the key in the Keychain.") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    guard let key = storedKey() else { fail("No signing key in the Keychain.") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    let rest = Array(args.dropFirst())
    guard rest.count == 2 else { fail("usage: sign <file> <version>") }
    guard let key = storedKey() else { fail("No signing key in the Keychain (run keygen, or restore the backup).") }
    let message = "NexoLLM-release-v1:\(rest[1]):\(sha256Hex(URL(fileURLWithPath: rest[0])))"
    guard let sig = try? key.signature(for: Data(message.utf8)) else { fail("signing failed") }
    guard key.publicKey.isValidSignature(sig, for: Data(message.utf8)) else { fail("self-check failed") }
    print(sig.base64EncodedString())
default:
    fail("usage: release-signing.swift keygen | public | sign <file> <version>")
}
