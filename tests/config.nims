switch("path", "$projectDir/../src")
switch("path", "/Users/georgelemon/Development/packages/vancode/src")
switch("path", "/Users/georgelemon/Development/packages/voodoo/src")
switch("path", "/Users/georgelemon/Development/packages/openparser/src")
switch("path", "/Users/georgelemon/Development/toys/datpkgr/src")
--define:vancodeJitNim
--define:supranimUseGlobalOnRequest
# Heap contract with the stdlib shard dylibs (see stdkups
# `tools/build_shards.nim` and src/dfkup.nims): every image in the
# process must share these flags. Test binaries that execute scripts through `src/dfkup.exec`
# load arc-built dylibs and pass `Value` refs across; an orc-built
# test binary reads garbage field offsets (and vice versa).
switch("threads", "on")
switch("mm", "arc")
