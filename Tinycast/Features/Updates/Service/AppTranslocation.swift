import Foundation

/// A quarantined app opened where it was unzipped runs from a read-only mirror Gatekeeper mounts.
enum AppTranslocation {
    private typealias ResolveOriginal =
        @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    static func isTranslocated(_ bundleURL: URL) -> Bool {
        bundleURL.path.contains("/AppTranslocation/")
    }

    /// Where the bundle really lives, so an update replaces that copy instead of the mirror.
    static func originalURL(of bundleURL: URL) -> URL {
        // Security exports the resolver without a public header; Sparkle relies on it the same way.
        guard isTranslocated(bundleURL),
            let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
            let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return bundleURL }
        let resolve = unsafeBitCast(symbol, to: ResolveOriginal.self)
        return resolve(bundleURL as CFURL, nil)?.takeRetainedValue() as URL? ?? bundleURL
    }
}
