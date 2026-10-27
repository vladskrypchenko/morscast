import Foundation
import Security

/// Proves a staged bundle is ours: the Developer ID chain, or the leaf a pre-switch copy pins.
enum BundleSignature {
    /// MorsCast signs with an Apple Development certificate, so only Apple's chain and the team.
    static let developerID = """
        anchor apple generic \
        and certificate leaf[subject.OU] = "BV8636DZJY"
        """

    static func isTrusted(_ bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return false }
        // An unsealed bundle can claim any identity, and a nested helper is where one hides.
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else { return false }
        if satisfiesDeveloperID(staticCode, flags: flags) { return true }
        // A copy installed before the switch knows only the leaf it was itself signed with.
        guard let running = runningLeaf(), let candidate = leaf(of: staticCode) else { return false }
        return running == candidate
    }

    /// No `notarized`: its ticket lookup can hit the network, and the chain already proves ownership.
    private static func satisfiesDeveloperID(_ code: SecStaticCode, flags: SecCSFlags) -> Bool {
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(developerID as CFString, [], &requirement)
                == errSecSuccess, let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func runningLeaf() -> Data? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        return leaf(of: staticCode)
    }

    private static func leaf(of code: SecStaticCode) -> Data? {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
            let dictionary = information as? [String: Any],
            let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }
}
