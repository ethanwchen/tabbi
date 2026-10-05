import Foundation

/// Finds where a translocated app really lives.
///
/// Gatekeeper runs a quarantined app opened in place (from Downloads or a
/// disk image) from a random read-only mirror under `/AppTranslocation/`.
/// Security.framework can map the mirror back to the original, but only
/// through `SecTranslocateCreateOriginalPathForURL`, which has no public
/// header, so it is looked up at run time (as LetsMove does). When it is
/// missing the move still works; only the tidy-up of the original is skipped.
enum Translocation {
    private typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    static func originalURL(of url: URL) -> URL? {
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return nil }
        defer { dlclose(security) }
        guard let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let originalPath = unsafeBitCast(symbol, to: OriginalPath.self)
        return originalPath(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
