--define:vancodeJitNim
--threads:on
--hints:off
--verbosity:0
--define:nimPreviewHashRef
--define:supranimUseGlobalOnRequest
--mm:arc

# OpenSSL library path for powpow/net/tls (`-lssl -lcrypto`, pulled in
# by std/httpclient and the statically-linked lowlibs). Plain `nim c`
# resolves it ambiently on this machine, but denim's cmake backend
# builds under an SDK sysroot where ambient MacPorts/Homebrew locations
# are invisible and the link fails with `library 'ssl' not found`.
# Declared explicitly (first existing layout wins; anything else falls
# through to today's ambient behavior), so the CLI and the addon link
# the same library reproducibly.
when defined(macosx):
  import std/os
  const sslLibDirs = [
    "/opt/local/libexec/openssl3/lib", # MacPorts openssl3
    "/opt/local/lib",                  # MacPorts fallback
    "/opt/homebrew/opt/openssl@3/lib", # Homebrew openssl@3
    "/opt/homebrew/opt/openssl/lib",   # Homebrew openssl
  ]
  for sslDir in sslLibDirs:
    if dirExists(sslDir):
      switch("passL", "-L" & sslDir)
      break

when defined dfkupDebug:
  --define:checkBounds
  --define:assertions
  --define:useMalloc
  --passC:"-fsanitize=address -fno-omit-frame-pointer"
  --passL:"-fsanitize=address"
