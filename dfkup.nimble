# Package

version       = "0.1.0"
author        = "OpenPeeps"
description   = "A scripting language with VM + JIT compiler"
license       = "LGPL-3.0-or-later"
srcDir        = "src"
bin           = @["dfkup"]
binDir        = "bin"


# Dependencies

requires "nim >= 2.2.0"
requires "kapsis >= 0.3.4"
requires "vancode >= 0.1.3"

# mostly required for exporting as libraries
requires "openparser >= 0.1.2"
requires "marvdown >= 0.1.0"

requires "mimedb >= 0.1.0"
requires "supranim >= 0.1.2"

requires "blackpaper >= 0.1.0"
requires "e2ee >= 0.1.0"
requires "money >= 0.1.0"