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
            let state = backtrace_create_state(CommandLine.arguments[0], 1, nil, nil)
            
            let buffer: UnsafeRawMutableBufferPointer = .init().allocate()
            defer { buffer.free }
            
            backtrace_print(state, 5, buffer)
            let frames: [[String]] = String(buffer).split("\n").map {
                let trace: (SIGNEDSTACKPOINTER, MODULENAMES) = $0.split(" ")[3...]
            }
            // EXENAME(SIGNEDSTACKPOINTER) [MODULENAMES]
            // -> PPPname1ZZarg1999T
            // -> name(arg1: T)
            
            //call addr2line (or something)
            
            //2019-07-05T10:58:37.38-0500 [APP/PROC/WEB/1] OUT ScoutAPI(+0x1dc025) [0x558174108025]
            // map each frame though a process running addr2line
            // 
            
            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = ["-c", "addr2line -e ~/app/.swift-bin/ScoutAPI \(SIGNEDSTACKPOINTER) -f \(MODULENAMES)"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            process.launch()
            process.waitUntilExit()
            
            run(addr2line "\()")
            
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
