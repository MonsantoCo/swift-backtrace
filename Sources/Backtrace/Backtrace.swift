import Foundation
//addr2line -e ScoutAPI 0x1dc025 -f 0x558174108025
//addr2line -e /lib/x86_64-linux-gnu/libpthread.so.0 0x10330 -f 0x7fd082e5f330
//SIL Swift Intermediate Language
// Swift -> Swift Intermediate Language -> LLVM Intermediate Representation -> LLVM Bitcode -> ARMv8
//ScoutAPI(+0x28f425) [0x5581741bb425]
@_silgen_name("swift_demangle")
public
func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
    ) -> UnsafeMutablePointer<CChar>?

internal func _stdlib_demangleName(_ mangledName: String) -> String {
    return mangledName.utf8CString.withUnsafeBufferPointer {
        (mangledNameUTF8CStr) in
        
        let demangledNamePtr = _stdlib_demangleImpl(
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

#if os(Linux)
import Glibc // Guarantees <execinfo.h> has a callable implementation for backtrace_print
import CBacktrace

public enum Backtrace {
    private static var traceFilePtr: UnsafeMutablePointer<FILE>? = nil
    private static var traceFileHandle: FileHandle? = nil
    private static var scoutApiPathInCloudFoundryInstance: URL? = nil
    
    public static func install() {
        if let home = URL(string: NSHomeDirectory()) {
            Backtrace.scoutApiPathInCloudFoundryInstance = home.appendingPathComponent("app", isDirectory: true).appendingPathComponent(".swift-bin", isDirectory: true).appendingPathComponent("ScoutAPI", isDirectory: false)
            
            let traceFile = home.appendingPathComponent("stack.trace", isDirectory: false)
            
            if !FileManager.default.fileExists(atPath: traceFile.path) {
                let createdTraceFile = FileManager.default.createFile(atPath: traceFile.path, contents: nil)
                print(createdTraceFile ? "✅ File for stacktrace created." : "❌ Failed to create file for stacktrace.")
            } else {
                print("✅ File for stacktrace already exists. It will be overwritten.")
            }
            
            Backtrace.traceFilePtr = fopen(traceFile.path, "w")
            guard let traceFileHandle = try? FileHandle(forUpdating: traceFile) else { fatalError("❌ Failed to get a handle for printing the trace.") }
            Backtrace.traceFileHandle = traceFileHandle
        } else {
            fatalError("❌ Failed to find the home directory.")
        }
        
        func makeTrace(_ signal: CInt) {
            let state = backtrace_create_state(CommandLine.arguments[0], 1, nil, nil)
            
            guard let traceFilePtr = Backtrace.traceFilePtr else { fatalError("❌ No destination file for the trace.") }
            
            backtrace_print(state, 5, traceFilePtr)

            let stackTraceData = Backtrace.traceFileHandle!.readDataToEndOfFile()
            guard let stackTrace = String(data: stackTraceData, encoding: .utf8) else { fatalError("❌ Failed to decode the trace.") }
            
            let demangledTrace: [String] = stackTrace.split(separator: "\n").flatMap { $0.split(separator: " ") }.map { _stdlib_demangleName(String($0)) }
            demangledTrace.forEach { FileHandle.standardError.write("\($0)\n") }
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

extension String {
    subscript(_ range: CountableRange<Int>) -> String {
        let idx1 = index(startIndex, offsetBy: max(0, range.lowerBound))
        let idx2 = index(startIndex, offsetBy: min(self.count, range.upperBound))
        return String(self[idx1..<idx2])
    }
}

extension FileHandle : TextOutputStream {
    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        self.write(data)
    }
}
