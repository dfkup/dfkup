# DFkup static stdlib bundle for the Node.js addon (napibuild only).
#
# The CLI loads every stdlib except `system`, `json`, `strings`,
# `sequtils` and `regex` from a dylib shard at runtime
# (see `lang/stdlib_loader`): those five live in `lang/lowlibs` and are
# always linked in. The node addon (dfkup-js repo) links the
# remaining `stdkups/lib*` sources statically on top: this file imports
# them all and re-exports them so `lang/stdlib_loader` can serve them
# without dlopen.
#
# Used as a module: `lang/stdlib_loader` imports it under `napibuild`.
# The init procs below are what `loadStaticStdlibModule` calls.

import ./libjson
import ./libstrings
import ./libsequtils
import pkg/stdkups/libyaml
import pkg/stdkups/libhttp
import pkg/stdkups/libcli
import pkg/stdkups/libconfig
import ./libregex
import pkg/stdkups/libbrowser
import pkg/stdkups/libtoml
import pkg/stdkups/libuuid
import pkg/stdkups/libdotenv
import pkg/stdkups/libcsv
import pkg/stdkups/libbson
import pkg/stdkups/libcolors
import pkg/stdkups/libqr
import pkg/stdkups/libnanoid
import pkg/stdkups/libllm
import pkg/stdkups/libhttpclient
import pkg/stdkups/libxml
import pkg/stdkups/libfeed
import pkg/stdkups/libical
import pkg/stdkups/libcss
import pkg/stdkups/libsvg
import pkg/stdkups/libmarkdown
import pkg/stdkups/libstrongpwd
import pkg/stdkups/libtwofa
import pkg/stdkups/libfswatch
import pkg/stdkups/libalgos
import pkg/stdkups/libbench

export libjson
export libyaml
export libstrings
export libsequtils
export libhttp
export libcli
export libconfig
export libregex
export libbrowser
export libtoml
export libuuid
export libdotenv
export libcsv
export libbson
export libcolors
export libqr
export libnanoid
export libllm
export libhttpclient
export libxml
export libfeed
export libical
export libcss
export libsvg
export libmarkdown
export libstrongpwd
export libtwofa
export libfswatch
export libalgos
export libbench
