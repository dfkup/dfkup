# Package

import std/[os, strutils]

version       = "0.1.0"
author        = "OpenPeeps"
description   = "A tiny scripting language. Enjoyable, easy to learn and work with so you don't f*ck up"
license       = "MIT"
srcDir        = "src"
bin           = @["dfkup"]
binDir        = "bin"


# Dependencies

requires "nim >= 2.2.0"
requires "vancode >= 0.2.14"
requires "datpkgr >= 0.1.9"
requires "dynasm >= 0.1.0"
requires "openparser >= 0.3.10"
requires "voodoo >= 0.2.3"
requires "https://github.com/dfkup/stdkups"

# Shard dylibs are built at workflow level from the separate stdkups repo
# (dfkup/stdlib `tools/build_shards.nim`); the CLI never links stdkups
# (the `stdkups` feature above stays inactive so plain installs never see
# it). The node addon (dfkup-js repo) statically links the same sources
# under `napibuild` instead — see `src/dfkup.nims` and
# `src/lang/lowlibs/liball.nim`.
# See "Build Standard Library" in the README.

# Pinned: flysystem 0.2.1 rewired the local driver onto POSIX-only
# securejoin with no Windows fallback (undeclared `sandboxPassthrough`
# on windows). 0.2.0 was the last version that compiled there, but it is
# gone from the registry (only 0.2.2 is published now), so the floor
# moves to 0.2.2 — re-pin if the Windows fallback regresses again.
requires "flysystem >= 0.2.2"
