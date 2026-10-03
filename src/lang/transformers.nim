# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup
#
# dfkup extends VanCode at compile time through Voodoo macros. Everything here
# is a language feature VanCode does not implement on its own: `enum`
# declarations, and the qualified field access `EnumName.field`.
#
# Fields are always reached through their enum's identifier, so two enums may
# declare the same field name without ever colliding, and a bare `field` stays
# an undefined reference.

import pkg/voodoo/extensibles

const
  CodegenModule* = "vancode/interpreter/codegen.nim"

block extendvancodeAstAndCodeGen:

  extendEnum NodeKind:
    # `type Name = enum` declaration, and one of its fields.
    nkEnumDef
    nkEnumField

  extendObject do:
    type Ast = ref object        # required by `extendCase`
      forwardDecl*: seq[Node]

  extendCase do:
    type Node = ref object        # required by `extendCase`
      case kind: NodeKind
      of nkEnumDef:
        enumName*: Node
          ## the enum's identifier; fields hang off this
        enumFields*: seq[Node]
      of nkEnumField:
        fieldName*: string
          ## the field's identifier, as written
        fieldValue*: string
          ## the explicit `= "value"` when given, else the field name itself

  extendCaseStmt "astHashCase":
    case node.kind
    of nkEnumDef:
      h = h !& hash(node.enumName)
      for field in node.enumFields:
        h = h !& hash(field)
    of nkEnumField:
      h = h !& hash(node.fieldName)
      h = h !& hash(node.fieldValue)

  # `genTypeDef` only knows `nkObject`, so an enum registers itself as its own
  # type here.
  extendCaseStmt "codeGenTypeDef":
    case defNode.kind:
    of nkEnumDef:
      discard gen.genEnumDef(defNode)

  # `Fruits.apple`. An enum is a `ttyObject` type carrying an `nkEnumDef`
  # implementation node, and nothing else registers a type that way. The
  # receiver here is the enum *type*, not a value, so this has to run before
  # `genGetField` evaluates the receiver -- otherwise `Fruits` in value
  # position compiles into an object construction, emitting an `opcConstrObj`
  # that is never consumed.
  #
  # The body is inlined rather than delegated to `extendModule`: this branch
  # sits above codegen's `injectExtendedModule()` site, so injected procs are
  # not in scope yet at this point in the file.
  extendCaseStmt "codegenGetField":
    case node.kind:
    of nkDot:
      # The receiver is either a bare enum name (`Fruits.apple`) or a qualified
      # one from an aliased import (`veggie.Veg.carrot`). Anything else
      # (`"str".method`, `a[i].method`) is not an enum, and the kind checks keep
      # `lookup` from rejecting a non-ident receiver.
      var enumTy: Sym = nil
      if node[0].kind == nkIdent:
        # `gen.lookup` is the single place that knows how a name resolves, so
        # this reaches the same symbol a type annotation in this file would.
        # Resolving it any other way here is what let a file's own `Fruits`
        # silently pick up another file's enum when both were imported.
        enumTy = gen.lookup(node[0], quiet = true)
      elif node[0].kind == nkDot:
        enumTy = gen.lookupQualifiedType(node[0])
      if node[1].kind == nkIdent and enumTy != nil and enumTy.kind == skType and
         enumTy.tyKind == ttyObject and enumTy.impl != nil and
         enumTy.impl.kind == nkEnumDef:
        # Field names go through `normName` for the same reason type names do,
        # so `Fruits.APPLE` resolves the way `BadFruits` does.
        let fieldName = gen.normName(node[1].ident)
        if not enumTy.objectFields.hasKey(fieldName):
          node[1].error(ErrNonExistentField % [fieldName, $enumTy])
        var fieldValue = ""
        for field in enumTy.impl.enumFields:
          if gen.normName(field.fieldName) == fieldName:
            fieldValue = field.fieldValue
            break
        # The value is known at compile time, so it is emitted as a string
        # constant while the static type stays the enum's own. That is what
        # keeps `Fruits.apple` and `BadFruits.apple` distinct types, so `==`
        # refuses to compare values coming from two different enums.
        gen.chunk.emit(opcPushS)
        gen.chunk.emit(gen.chunk.getString(fieldValue))
        return enumTy

  injectCodeHandler "CodeGenForwardDecl":
    proc genEnumDef*(node: Node): Sym {.codegen.}

  extendModule CodegenModule:
  
    proc addEnumProc*(gen: CodeGen, name: string, paramTys: seq[Sym],
          returnTy: Sym, impl: ForeignProc) =
      ## Register a builtin whose parameters are a specific enum's own type.
      ##
      ## `addProc` resolves parameter types from a `TypeKind` name, which cannot
      ## express "this enum and only this enum". Building the proc here lets each
      ## enum register its own `echo`/`==`/`!=`, which is what makes comparing a
      ## `Fruits` value against a `BadFruits` value a compile error rather than a
      ## silent true.
      var params: seq[ProcParam]
      for i, ty in paramTys:
        params.add((ast.newIdent("a" & $i), ty, nil, false, false))
      let (sym, theProc) = gen.script.newProc(
        ast.newIdent(name),
        impl = nil,
        params,
        returnTy,
        pkForeign,
        exported = true
      )
      theProc.foreign = impl
      discard gen.module.addCallable(sym, sym.name)
      gen.script.procs.add(theProc)

    proc genEnumDef*(node: Node): Sym {.codegen.} =
      ## Register a `type Name = enum` declaration as its own type.
      ##
      ## Each field becomes a compile-time constant typed as the enum itself,
      ## so `Fruits.apple` produces a value only `Fruits`'s own fields can.
      result = newType(ttyObject, name = node.enumName, impl = node,
                       src = some(gen.chunk.file))
      # `type Veg* = enum` marks the enum exported, matching `func f*()`, so an
      # importing file can name it. The marker arrives as a postfix wrapper
      # around the name, the same shape `newProc` reads.
      var nameNode = node.enumName
      if nameNode.kind == nkPostfix:
        result.typeExport = nameNode[0].kind == nkIdent and
                            nameNode[0].ident == "*"
        nameNode = nameNode[1]
        result.name = Node(kind: nkIdent, ident: nameNode.ident,
                           ln: nameNode.ln, col: nameNode.col)
      # objectId is the VM's runtime type tag. 0 belongs to the built-in
      # `object` type, so an enum handed 0 would be indistinguishable from it
      # at runtime and generic overloads such as `echo(object)` would match enum
      # values first. `stamp` (set by `newType`) carries the compile-time
      # identity, so two same-named enums in different files stay distinct.
      if globalTypeCounter == 0: inc(globalTypeCounter)
      result.objectId = globalTypeCounter
      inc(globalTypeCounter)
      for field in node.enumFields:
        result.objectFields[gen.normName(field.fieldName)] = (
          id: result.objectFields.len,
          name: ast.newIdent(field.fieldName),
          ty: result,
          implVal: nil
        )
      gen.addSym(result)

      # An enum field is emitted as a plain string, but its static type is the
      # enum. So `echo`/`==`/`!=` need enum-typed overloads: without them these
      # resolve to the generic `object` overloads and print `"Apple"` with
      # quotes.
      let enumSyms = @[result]
      gen.addEnumProc("echo", enumSyms, gen.module.sym"void",
        proc (args: StackView, argc: int): Value =
          if likely(args[0].typeId == tyString): echo args[0].stringVal[]
          else: echo $args[0])

      let sameEnum = proc (args: StackView, argc: int): Value =
        if args[0].typeId != tyString or args[1].typeId != tyString:
          return initValue(false)
        result = initValue(args[0].stringVal[] == args[1].stringVal[])

      let notSameEnum = proc (args: StackView, argc: int): Value =
        result = sameEnum(args, argc)
        result.boolVal = not result.boolVal

      gen.addEnumProc("==", enumSyms & enumSyms, gen.module.sym"bool", sameEnum)
      gen.addEnumProc("!=", enumSyms & enumSyms, gen.module.sym"bool", notSameEnum)