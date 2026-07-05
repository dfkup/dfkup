# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

when isMainModule:
  import pkg/kapsis
  import pkg/kapsis/runtime

  import ./commands/[exec_command]
  
  initKapsis do:
    commands:
      -- "Scripting"
      run path(script):
        ## Run a DFkup script file
      ast path(script), ?bool("--dumptree"):
        ## Generate AST from a DFkup script file