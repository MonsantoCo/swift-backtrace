import Foundation

#if os(Linux)
import Glibc
import CBacktrace

public enum Backtrace {
    private static var traceFilePtr: UnsafeMutablePointer<FILE>? = nil
    private static var traceFileHandle: FileHandle? = nil
    
    public static func install() {
        let home = URL(string: NSHomeDirectory())!
        let traceFile = home.appendingPathComponent("stack.trace", isDirectory: false)
        FileManager.default.createFile(atPath: traceFile.path, contents: nil)
        
        guard let traceFileHandle = try? FileHandle(forUpdating: traceFile) else { fatalError("❌ Failed to get a handle for printing the trace.") }
        // We only need a file-pointer for redirecting libbacktrace's output. FileHandle is otherwise more convenient.
        Backtrace.traceFileHandle = traceFileHandle
        Backtrace.traceFilePtr = fopen(traceFile.path, "w")
        
        // Our signal-handler which will be called when the specified POSIX signals are sent.
        func makeTrace(_ signal: CInt) {
            FileHandle.standardError.write("💔: ScoutAPI crashed. Preparing trace...\n".data(using: .utf8)!)
            guard let traceFilePtr = Backtrace.traceFilePtr else { fatalError("❌ No destination file for the trace.") }
            
            let state = backtrace_create_state(CommandLine.arguments[0], 1, nil, nil)
            backtrace_print(state, 3, traceFilePtr)
            
            let stackTraceData = Backtrace.traceFileHandle!.readDataToEndOfFile()
            guard let stackTrace = String(data: stackTraceData, encoding: .utf8) else { fatalError("❌ Failed to decode the trace.") }
            
            // Searches for occurrences of names mangled by swiftc (which start with $s) or paths to source-files.
            let demangledTrace = #"\$s[_$a-zA-Z0-9]+|[\/][^\s]+"#.regex.matchesFound(in: stackTrace).map { match in
                Range(match.range(at: 0), in: stackTrace).flatMap { Backtrace._stdlib_demangleName(String(stackTrace[$0])) }!
                }.joined(separator: "\n")
            
            FileHandle.standardError.write(demangledTrace.data(using: .utf8) ?? "❌ The stacktrace could not be UTF8 encoded.\n".data(using: .utf8)!)
        }
        
        setupHandler(signal: SIGSEGV, handler: makeTrace)
        setupHandler(signal: SIGILL, handler: makeTrace)
    }
    
    private static func setupHandler(signal: Int32, handler: @escaping @convention(c) (CInt) -> Void) {
        typealias sigaction_t = sigaction
        let sa_flags = CInt(SA_NODEFER) | CInt(bitPattern: CUnsignedInt(SA_RESETHAND))
        var sa = sigaction_t(__sigaction_handler: unsafeBitCast(handler, to: sigaction.__Unnamed_union___sigaction_handler.self),
                             sa_mask: sigset_t(),
                             sa_flags: sa_flags,
                             sa_restorer: nil)
        withUnsafePointer(to: &sa) { ptr -> Void in
            sigaction(signal, ptr, nil)
        }
    }
}

#else
public enum Backtrace {
    public static func install() {
    }
}
#endif

internal extension Backtrace {
    @_silgen_name("swift_demangle") static func _stdlib_demangleImpl(mangledName: UnsafePointer<CChar>?,mangledNameLength: UInt,outputBuffer: UnsafeMutablePointer<CChar>?,outputBufferSize: UnsafeMutablePointer<UInt>?,flags: UInt32) -> UnsafeMutablePointer<CChar>?
    
    static func _stdlib_demangleName(_ mangledName: String) -> String {
        return mangledName.utf8CString.withUnsafeBufferPointer {
            (mangledNameUTF8CStr) in
            
            let demangledNamePtr = Backtrace._stdlib_demangleImpl(
                mangledName: mangledNameUTF8CStr.baseAddress,
                mangledNameLength: UInt(mangledNameUTF8CStr.count - 1),
                outputBuffer: nil,
                outputBufferSize: nil,
                flags: 0)
            
            if let demangledNamePtr = demangledNamePtr {
                let demangledName = String(cString: demangledNamePtr)
                free(demangledNamePtr)
                return demangledName
            }
            return mangledName
        }
    }
}

extension String {
    var regex: NSRegularExpression! {
        return try! NSRegularExpression(pattern: self, options: [])
    }
}

extension NSRegularExpression {
    func matchesFound(in stringToSearch: String) -> [NSTextCheckingResult] {
        let fullRange = NSRange(stringToSearch.startIndex..<stringToSearch.endIndex, in: stringToSearch)
        
        return matches(in: stringToSearch, options: [], range: fullRange)
    }
}
