# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A fast scripting language for cool kids!"
license       = "MIT"
srcDir        = "src"
bin           = @["dfkup"]
binDir        = "bin"


# Dependencies

requires "nim >= 2.2.0"
requires "kapsis >= 0.3.4"
requires "vancode >= 0.1.3"

requires "openparser >= 0.1.2"
requires "marvdown >= 0.1.0"

requires "mimedb >= 0.1.0"
requires "supranim >= 0.1.1"

requires "blackpaper >= 0.1.0"
requires "e2ee >= 0.1.0"
requires "money >= 0.1.0"