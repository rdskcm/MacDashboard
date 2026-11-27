// Engine/ReaderCalls.swift
// READER-STATUS: dlopen/dlsym and sysctl calls that keep the failure detail (first missing symbol, dlerror, errno).
import Foundation

enum SymbolLoader {
    /// dlopen `path`, then dlsym every name in order; the first failure wins. The handle is never dlclose()d: the
    /// resolved pointers must stay valid for the process lifetime (as before READER-STATUS).
    static func load(path: String, mode: Int32, symbols names: [String]) -> Result<[UnsafeMutableRawPointer], ReaderReason> {
        guard let handle = dlopen(path, mode) else {
            return .failure(.libraryNotLoaded(path: path, dlerror: dlerror().map { String(cString: $0) }))
        }
        var out: [UnsafeMutableRawPointer] = []
        out.reserveCapacity(names.count)
        for name in names {
            guard let p = dlsym(handle, name) else { return .failure(.symbolMissing(library: path, symbol: name)) }
            out.append(p)
        }
        return .success(out)
    }
}

enum SysctlRead {
    /// An Int32 sysctl; errno kept on failure, a size other than 4 is a failed check.
    static func int32(_ name: String) -> Result<Int32, ReaderReason> {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return .failure(.errno(call: "sysctlbyname(\(name))", code: errno)) }
        guard size == MemoryLayout<Int32>.size else { return .failure(.validationFailed(what: "sysctl \(name)", check: "size \(size) == 4")) }
        return .success(value)
    }

    /// A string sysctl; errno kept on failure, an empty value is `.empty`.
    static func string(_ name: String) -> Result<String, ReaderReason> {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return .failure(.errno(call: "sysctlbyname(\(name))", code: errno)) }
        guard size > 1 else { return .failure(.empty(what: "sysctl \(name)")) }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return .failure(.errno(call: "sysctlbyname(\(name))", code: errno)) }
        let s = String(nulTerminated: buffer)
        return s.isEmpty ? .failure(.empty(what: "sysctl \(name)")) : .success(s)
    }
}
