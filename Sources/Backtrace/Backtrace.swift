#if os(Linux)
import Glibc
import CBacktrace

//SIL Swift Intermediate Language
// Swift -> Swift Intermediate Language -> LLVM Intermediate Representation -> LLVM Bitcode -> ARMv8
//@_silgen_function {
//
//}

public enum Backtrace {
    public static func install() {
        let makeTrace: (CInt) -> Void = { _ in
            let state = backtrace_create_state(CommandLine.arguments[0], 1, nil, nil)
            backtrace_print(state, 5, stderr)
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
