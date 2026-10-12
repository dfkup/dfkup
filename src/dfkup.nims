--define:vancodeJitDynasm
# Single-threaded runtime: tables use the thread-local heap, which is
# safe to share across the stdlib dylib boundary. The shared heap's
# per-image region makes cross-image table frees corrupt the heap
# (dylib-built JObject teardown segfault). Every image in the process
# (host + all dylibs, see `clue task stdlibs`) must use this setting.
switch("threads", "off")
# --define:vancodeJitLog
# switch("passL", "-Wl,-rpath,/opt/local/libexec/llvm-20/lib")

--hints:off
--verbosity:0
--define:nimPreviewHashRef
--define:supranimUseGlobalOnRequest
--mm:arc

when defined dfkupDebug:
  --define:checkBounds
  --define:assertions
  --define:useMalloc
  --passC:"-fsanitize=address -fno-omit-frame-pointer"
  --passL:"-fsanitize=address"