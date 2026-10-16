--define:vancodeJitNim
# Threaded runtime: datpkgr (package manager) links into the host binary
# and its install path spawns worker threads, so the host builds with
# threads on. Every image in the process (host + all stdlib dylibs, see
# `clue task stdlibs`) must share these flags: the cross-image heap
# contract is uniform `--threads:on --mm:arc` everywhere (mixed settings
# fault — region-heap mismatch segfaults, useMalloc breaks dylib init).
# Re-verify the dylib boundary matrix (plans/stdlib-dylibs.md) whenever
# either side's flags change.
switch("threads", "on")
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