import Foundation
//addr2line -e ScoutAPI 0x1dc025 -f 0x558174108025
//addr2line -e /lib/x86_64-linux-gnu/libpthread.so.0 0x10330 -f 0x7fd082e5f330
    
//ScoutAPI(+0x28f425) [0x5581741bb425]
private func addr2lineInvocations(from swiftBacktrace: String) -> [String] {
    let pattern = #######"(.*)\((.*)\)\s\[(.*)\]"#######
    let regex = try! NSRegularExpression(pattern: pattern, options: [])
    
    return regex.matches(in: swiftBacktrace, options: [], range: NSRange(location: 0, length: swiftBacktrace.count)).map { line in
        let captureGroup: (Int) -> String = { captureGroup in
            swiftBacktrace[Range(line.range(at: captureGroup))!]
        }
        
        return "addr2line -e \(captureGroup(1)) \(captureGroup(2)) -f \(captureGroup(3))"
    }
}

#if os(Linux)
import Glibc // Guarantees <execinfo.h> has a callable implementation for backtrace_print
import CBacktrace

//SIL Swift Intermediate Language
// Swift -> Swift Intermediate Language -> LLVM Intermediate Representation -> LLVM Bitcode -> ARMv8
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

public enum Backtrace {
    public static func install() {
        let makeTrace: (CInt) -> Void = { _ in
            let scoutApiPathInCloudFoundryInstance: String = "~/app/.swift-bin"
            let state = backtrace_create_state(CommandLine.arguments[0], 1, nil, nil)
            
            var buffer: UnsafeMutablePointer<String> = .allocate(capacity: 2048)
            buffer.initialize(to: "")
            defer {buffer.deallocate()}
            
            backtrace_print(state, 5, &buffer)
            
            let trace: String = addr2lineInvocations(from: buffer.pointee).map {
                let process = Process()
                process.launchPath = "/bin/bash"
                process.arguments = ["-c", "cd \(scoutApiPathInCloudFoundryInstance) && \($0)"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.launch()
                process.waitUntilExit()
                let addr2lineOutput = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Failed to Encode"
                
                return _stdlib_demangleName(addr2lineOutput)
            }
            
            var stderr = FileHandle.standardError
            if let data = trace.data(using: .utf8) {
                stderr.write(data)
            } else {
                print("You suck")
            }
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
    // EXENAME(SIGNEDSTACKPOINTER) [MODULENAMES]
    // -> PPPname1ZZarg1999T
    // -> name(arg1: T)
    
    //call addr2line (or something)
    
    //2019-07-05T10:58:37.38-0500 [APP/PROC/WEB/1] OUT ScoutAPI(+0x1dc025) [0x558174108025]
    //map each frame though a process running addr2line
    //
extension String {
    subscript(_ range: CountableRange<Int>) -> String {
        let idx1 = index(startIndex, offsetBy: max(0, range.lowerBound))
        let idx2 = index(startIndex, offsetBy: min(self.count, range.upperBound))
        return String(self[idx1..<idx2])
    }
}
