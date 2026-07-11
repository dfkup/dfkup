import pkg/voodoo/extensibles

extendObject do:
  type Ast = ref object        # required by `extendCase`
    forwardDecl*: seq[Node]