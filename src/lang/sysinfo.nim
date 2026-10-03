# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup
#
# Machine facts shared by parse-time `when` evaluation and the runtime
# `getSystemInfo()` builtin, so both agree on the same numbers.

import std/[os, osproc]

when defined(linux):
  # Only the `/proc/meminfo` reader below needs these, so they are imported
  # conditionally rather than warning as unused on every other platform.
  import std/strutils

type
  SystemInfo* = object
    ## A snapshot of the host machine.
    osName*, arch*, cpuEndian*, executablePath*: string
    cpuCores*: int
    totalMemory*: int64
      ## Physical memory in bytes, or 0 where the platform does not
      ## expose a portable way to read it.

when defined(macosx) or defined(bsd):
  {.emit: "#include <sys/sysctl.h>".}
  {.push nodecl.}
  proc sysctlbyname(name: cstring, oldp: pointer,
                    oldlenp: var csize_t,
                    newp: pointer, newlen: csize_t): cint {.importc.}
  {.pop.}

proc sysctlInt64(name: string): int64 =
  ## Read a 64-bit `sysctl` value by name. Zero when unavailable.
  when defined(macosx) or defined(bsd):
    var
      value: int64
      len = sizeof(value).csize_t
    if sysctlbyname(name.cstring, addr value, len, nil, 0) == 0:
      return value
  discard
  0

proc linuxTotalMemory(): int64 =
  ## `MemTotal` from `/proc/meminfo`, reported in kibibytes.
  when defined(linux):
    try:
      for line in readFile("/proc/meminfo").splitLines():
        if line.startsWith("MemTotal:"):
          let parts = line.splitWhitespace()
          if parts.len >= 2:
            return parseBiggestInt(parts[1]) * 1024
    except IOError, OSError, ValueError:
      discard
  discard
  0

proc windowsTotalMemory(): int64 =
  ## `ullTotalPhys` from `GlobalMemoryStatusEx`.
  when defined(windows):
    type MEMORYSTATUSEX {.importc: "MEMORYSTATUSEX",
      header: "<windows.h>".} = object
      dwLength: uint32
      dwMemoryLoad: uint32
      ullTotalPhys: uint64
      ullAvailPhys: uint64
      ullTotalPageFile: uint64
      ullAvailPageFile: uint64
      ullTotalVirtual: uint64
      ullAvailVirtual: uint64
      ullAvailExtendedVirtual: uint64
    proc GlobalMemoryStatusEx(lpBuffer: ptr MEMORYSTATUSEX): int32
      {.importc, winapi, header: "<windows.h>".}
    var status: MEMORYSTATUSEX
    status.dwLength = uint32(sizeof(status)).uint32
    if GlobalMemoryStatusEx(addr status) != 0:
      return status.ullTotalPhys.int64
  discard
  0

proc totalMemoryBytes*(): int64 =
  ## Physical memory in bytes.
  when defined(macosx):
    result = sysctlInt64("hw.memsize")
  elif defined(bsd):
    result = sysctlInt64("hw.physmem")
  elif defined(linux):
    result = linuxTotalMemory()
  elif defined(windows):
    result = windowsTotalMemory()
  else:
    result = 0
  if result < 0: result = 0

proc collectSystemInfo*(): SystemInfo =
  ## Gather the current machine's facts.
  result.osName = hostOS
  result.arch = hostCPU
  result.cpuCores = osproc.countProcessors()
  result.cpuEndian = $cpuEndian
  result.totalMemory = totalMemoryBytes()
  try:
    result.executablePath = os.getAppFilename()
  except OSError:
    result.executablePath = ""
