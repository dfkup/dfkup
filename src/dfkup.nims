--define:vancodeJit
# --define:vancodeJitLog

# --define:vancodeJitLlvm
# switch("passL", "-Wl,-rpath,/opt/local/libexec/llvm-20/lib")

--hints:off
--verbosity:0
--define:nimPreviewHashRef
--define:supranimUseGlobalOnRequest
# --define:release

when defined dfkupDebug:
  --define:checkBounds
  --define:assertions
  --define:useMalloc
  --passC:"-fsanitize=address -fno-omit-frame-pointer"
  --passL:"-fsanitize=address"