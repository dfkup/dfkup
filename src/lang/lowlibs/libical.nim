# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, options]
import pkg/openparser/ical
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc getCal(v: Value): IcalCalendar =
  cast[IcalCalendar](v.objectVal.foreign.data)

proc optStr(o: Option[string]): JsonNode =
  if o.isSome: %(o.get()) else: newJNull()

proc optDt(o: Option[IcalDt]): JsonNode =
  if o.isSome: %(writeIcalDt(o.get())) else: newJNull()

proc eventToJson(e: IcalEvent): JsonNode =
  result = newJObject()
  result["uid"] = %(e.uid)
  result["summary"] = optStr(e.summary)
  result["description"] = optStr(e.description)
  result["location"] = optStr(e.location)
  result["status"] = optStr(e.status)
  result["url"] = optStr(e.url)
  result["rrule"] = optStr(e.rrule)
  result["dtstart"] = optDt(e.dtStart)
  result["dtend"] = optDt(e.dtEnd)
  var cats = newJArray()
  for c in e.categories: cats.add(%c)
  result["categories"] = cats

proc eventsOf(cal: IcalCalendar): seq[IcalEvent] =
  for comp in cal.components:
    if comp.kind == cckEvent:
      result.add(comp.event)

proc initIcal*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseIcal", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, parseIcal(args[0].stringVal[]))
      result.objectVal.foreign.tag = "ICalCalendar")

  script.addProc(module, "parseIcalFile", @[paramDef("path", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, parseIcal(readFile(args[0].stringVal[])))
      result.objectVal.foreign.tag = "ICalCalendar")

  script.addProc(module, "calendarInfo", @[paramDef("cal", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let cal = getCal(args[0])
      var info = newJObject()
      info["prodId"] = optStr(cal.prodId)
      info["version"] = optStr(cal.version)
      info["eventCount"] = %(eventsOf(cal).len)
      result = initValue(info))

  script.addProc(module, "events", @[paramDef("cal", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var arr = newJArray()
      for e in eventsOf(getCal(args[0])):
        arr.add(eventToJson(e))
      result = initValue(arr))

  script.addProc(module, "eventCount", @[paramDef("cal", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(eventsOf(getCal(args[0])).len.int64))

  script.addProc(module, "toIcal", @[paramDef("cal", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toIcal(getCal(args[0]))))
