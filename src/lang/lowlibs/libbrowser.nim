import std/[json, asyncdispatch, uri]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]
import pkg/chopchop/[types, browser, page, element, context, locator]

proc objField(obj: Object, key: string): Value =
  for i, k in obj.keys:
    if k == key:
      return obj.fields[i].toValue

proc objFieldBool(obj: Object, key: string, default: bool): bool =
  let v = obj.objField(key)
  if v == nil or v.typeId != tyBool: default
  else: v.boolVal

proc objFieldInt(obj: Object, key: string, default: int): int =
  let v = obj.objField(key)
  if v == nil or v.typeId != tyInt: default
  else: v.intVal.int

proc objFieldStr(obj: Object, key: string, default: string): string =
  let v = obj.objField(key)
  if v == nil or v.typeId != tyString: default
  else: v.stringVal[]

proc initBrowser*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)
  discard module.genPtr(tyPointer, "Browser")
  discard module.genPtr(tyPointer, "BrowserPage")
  discard module.genPtr(tyPointer, "BrowserCtx")
  discard module.genPtr(tyPointer, "BrowserElement")
  discard module.genPtr(tyPointer, "BrowserLocator")

  #
  # Browser management
  #
  script.addProc(module, "launchBrowser",
    returnTy = ttyPointer,
    returnTySym = module.sym"Browser",
    impl = proc (args: StackView, argc: int): Value =
      let opts = defaultLaunchOptions()
      let b = waitFor launchBrowser(opts)
      GC_ref(b)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](b),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Browser](data))))
    )

  script.addProc(module, "launchBrowser",
    params = @[paramDef("options", ttyObject)],
    returnTy = ttyPointer,
    returnTySym = module.sym"Browser",
    impl = proc (args: StackView, argc: int): Value =
      let o = args[0].objectVal
      let opts = LaunchOptions(
        headless: o.objFieldBool("headless", true),
        portNo: o.objFieldInt("port", 0)
      )
      let b = waitFor launchBrowser(opts)
      GC_ref(b)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](b),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Browser](data))))
    )

  script.addProc(module, "close",
    params = @[paramDef("browser", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let b = cast[Browser](args[0].objectVal.foreign.data)
      waitFor b.close())

  #
  # Page management
  #
  script.addProc(module, "newPage",
    params = @[paramDef("browser", ttyPointer)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserPage",
    impl = proc (args: StackView, argc: int): Value =
      let b = cast[Browser](args[0].objectVal.foreign.data)
      let p = waitFor b.newPage()
      GC_ref(p)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](p),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Page](data))))
    )

  script.addProc(module, "goto",
    params = @[paramDef("page", ttyPointer), paramDef("url", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      waitFor p.goto(args[1].stringVal[]))

  script.addProc(module, "getTitle",
    params = @[paramDef("page", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      result = initValue(waitFor p.title()))

  script.addProc(module, "getUrl",
    params = @[paramDef("page", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      result = initValue(waitFor p.url()))

  script.addProc(module, "getContent",
    params = @[paramDef("page", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      result = initValue(waitFor p.content()))

  script.addProc(module, "getScreenshot",
    params = @[paramDef("page", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      result = initValue(waitFor p.screenshot()))

  script.addProc(module, "evaluate",
    params = @[paramDef("page", ttyPointer), paramDef("js", ttyString)],
    returnTy = ttyJson,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      result = initValue(waitFor p.evaluate(args[1].stringVal[])))

  script.addProc(module, "setViewport",
    params = @[paramDef("page", ttyPointer), paramDef("width", ttyInt), paramDef("height", ttyInt)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      waitFor p.setViewport(args[1].intVal.int, args[2].intVal.int))

  script.addProc(module, "addInitScript",
    params = @[paramDef("page", ttyPointer), paramDef("script", ttyString)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      result = initValue(waitFor p.addInitScript(args[1].stringVal[])))

  #
  # DOM querying
  #
  script.addProc(module, "querySelector",
    params = @[paramDef("page", ttyPointer), paramDef("selector", ttyString)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserElement",
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      let el = waitFor p.querySelector(args[1].stringVal[])
      if el != nil:
        GC_ref(el)
        result = Value(typeId: tyPointer)
        result.objectVal = Object(isForeign: true,
          foreign: ForeignData(data: cast[pointer](el),
            destructor: proc (data: pointer) {.nimcall.} =
              GC_unref(cast[ElementHandle](data))))
      else:
        result = Value(typeId: tyNil))

  script.addProc(module, "waitForSelector",
    params = @[paramDef("page", ttyPointer), paramDef("selector", ttyString)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserElement",
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      let el = waitFor p.waitForSelector(args[1].stringVal[])
      if el != nil:
        GC_ref(el)
        result = Value(typeId: tyPointer)
        result.objectVal = Object(isForeign: true,
          foreign: ForeignData(data: cast[pointer](el),
            destructor: proc (data: pointer) {.nimcall.} =
              GC_unref(cast[ElementHandle](data))))
      else:
        result = Value(typeId: tyNil))

  #
  # Cookies
  #
  script.addProc(module, "getCookies",
    params = @[paramDef("page", ttyPointer)],
    returnTy = ttyJson,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      let cs = waitFor p.cookies()
      var arr = newJArray()
      for c in cs:
        arr.add(%*{"name": c.name, "value": c.value,
                    "domain": c.domain, "path": c.path,
                    "httpOnly": c.httpOnly, "secure": c.secure})
      result = initValue(arr))

  script.addProc(module, "setCookie",
    params = @[paramDef("page", ttyPointer), paramDef("cookie", ttyObject)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      let o = args[1].objectVal
      var domain = o.objFieldStr("domain", "")
      if domain.len == 0:
        let pageUrl = waitFor p.url()
        if pageUrl.len > 0:
          domain = parseUri(pageUrl).hostname
      let c = Cookie(
        name: o.objFieldStr("name", ""),
        value: o.objFieldStr("value", ""),
        domain: domain,
        path: o.objFieldStr("path", "/"),
        httpOnly: o.objFieldBool("httpOnly", false),
        secure: o.objFieldBool("secure", false)
      )
      waitFor p.setCookie(c))

  script.addProc(module, "deleteCookie",
    params = @[paramDef("page", ttyPointer), paramDef("name", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      waitFor p.deleteCookie(args[1].stringVal[]))

  script.addProc(module, "clearCookies",
    params = @[paramDef("page", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      waitFor p.clearCookies())

  #
  # Storage
  #
  script.addProc(module, "getLocalStorage",
    params = @[paramDef("page", ttyPointer), paramDef("key", ttyString)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      result = initValue(waitFor p.localStorage(args[1].stringVal[])))

  script.addProc(module, "setLocalStorage",
    params = @[paramDef("page", ttyPointer), paramDef("key", ttyString), paramDef("value", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      waitFor p.setLocalStorage(args[1].stringVal[], args[2].stringVal[]))

  #
  # ElementHandle actions
  #
  script.addProc(module, "click",
    params = @[paramDef("el", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.click())

  script.addProc(module, "dblclick",
    params = @[paramDef("el", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.dblclick())

  script.addProc(module, "hover",
    params = @[paramDef("el", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.hover())

  script.addProc(module, "typeText",
    params = @[paramDef("el", ttyPointer), paramDef("text", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.typeText(args[1].stringVal[]))

  script.addProc(module, "press",
    params = @[paramDef("el", ttyPointer), paramDef("key", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.press(args[1].stringVal[]))

  script.addProc(module, "getInnerText",
    params = @[paramDef("el", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      result = initValue(waitFor el.innerText()))

  script.addProc(module, "getInnerHTML",
    params = @[paramDef("el", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      result = initValue(waitFor el.innerHTML()))

  script.addProc(module, "getAttribute",
    params = @[paramDef("el", ttyPointer), paramDef("name", ttyString)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      result = initValue(waitFor el.getAttribute(args[1].stringVal[])))

  script.addProc(module, "isVisible",
    params = @[paramDef("el", ttyPointer)],
    returnTy = ttyBool,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      result = initValue(waitFor el.isVisible()))

  script.addProc(module, "selectByValue",
    params = @[paramDef("el", ttyPointer), paramDef("value", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.selectByValue(args[1].stringVal[]))

  script.addProc(module, "selectByLabel",
    params = @[paramDef("el", ttyPointer), paramDef("label", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.selectByLabel(args[1].stringVal[]))

  script.addProc(module, "selectByIndex",
    params = @[paramDef("el", ttyPointer), paramDef("index", ttyInt)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let el = cast[ElementHandle](args[0].objectVal.foreign.data)
      waitFor el.selectByIndex(args[1].intVal.int))

  #
  # Locator API
  #
  script.addProc(module, "locator",
    params = @[paramDef("page", ttyPointer), paramDef("selector", ttyString)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserLocator",
    impl = proc (args: StackView, argc: int): Value =
      let p = cast[Page](args[0].objectVal.foreign.data)
      let loc = p.locator(args[1].stringVal[])
      GC_ref(loc)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](loc),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Locator](data))))
    )

  script.addProc(module, "locatorFilter",
    params = @[paramDef("loc", ttyPointer), paramDef("text", ttyString)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserLocator",
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      let nloc = loc.filter(args[1].stringVal[])
      GC_ref(nloc)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](nloc),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Locator](data))))
    )

  script.addProc(module, "locatorFirst",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserLocator",
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      let nloc = loc.first()
      GC_ref(nloc)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](nloc),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Locator](data))))
    )

  script.addProc(module, "locatorLast",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserLocator",
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      let nloc = loc.last()
      GC_ref(nloc)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](nloc),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Locator](data))))
    )

  script.addProc(module, "locatorNth",
    params = @[paramDef("loc", ttyPointer), paramDef("index", ttyInt)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserLocator",
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      let nloc = loc.nth(args[1].intVal.int)
      GC_ref(nloc)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](nloc),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Locator](data))))
    )

  #
  # Locator actions
  #
  script.addProc(module, "locatorClick",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      waitFor loc.click())

  script.addProc(module, "locatorHover",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      waitFor loc.hover())

  script.addProc(module, "locatorTypeText",
    params = @[paramDef("loc", ttyPointer), paramDef("text", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      waitFor loc.typeText(args[1].stringVal[]))

  script.addProc(module, "locatorPress",
    params = @[paramDef("loc", ttyPointer), paramDef("key", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      waitFor loc.press(args[1].stringVal[]))

  script.addProc(module, "locatorFill",
    params = @[paramDef("loc", ttyPointer), paramDef("text", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      waitFor loc.fill(args[1].stringVal[]))

  script.addProc(module, "getLocatorInnerText",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      result = initValue(waitFor loc.innerText()))

  script.addProc(module, "getLocatorInnerHTML",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      result = initValue(waitFor loc.innerHTML()))

  script.addProc(module, "locatorGetAttribute",
    params = @[paramDef("loc", ttyPointer), paramDef("name", ttyString)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      result = initValue(waitFor loc.getAttribute(args[1].stringVal[])))

  script.addProc(module, "getLocatorCount",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyInt,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      let cnt = waitFor loc.count()
      result = initValue(cnt.int64))

  script.addProc(module, "locatorIsVisible",
    params = @[paramDef("loc", ttyPointer)],
    returnTy = ttyBool,
    impl = proc (args: StackView, argc: int): Value =
      let loc = cast[Locator](args[0].objectVal.foreign.data)
      result = initValue(waitFor loc.isVisible()))

  #
  # BrowserContext
  #
  script.addProc(module, "newContext",
    params = @[paramDef("browser", ttyPointer)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserCtx",
    impl = proc (args: StackView, argc: int): Value =
      let b = cast[Browser](args[0].objectVal.foreign.data)
      let ctx = waitFor b.newContext()
      GC_ref(ctx)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](ctx),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[BrowserContext](data))))
    )

  script.addProc(module, "contextNewPage",
    params = @[paramDef("ctx", ttyPointer)],
    returnTy = ttyPointer,
    returnTySym = module.sym"BrowserPage",
    impl = proc (args: StackView, argc: int): Value =
      let ctx = cast[BrowserContext](args[0].objectVal.foreign.data)
      let p = waitFor ctx.newPage()
      GC_ref(p)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](p),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[Page](data))))
    )

  script.addProc(module, "contextClose",
    params = @[paramDef("ctx", ttyPointer)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let ctx = cast[BrowserContext](args[0].objectVal.foreign.data)
      waitFor ctx.close())
