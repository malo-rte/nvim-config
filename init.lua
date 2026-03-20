pcall(function()
  require("vim._core.ui2").enable({
    enable = true,
    msg = {
      target = "cmd",
      pager = { height = 0.5 },
      dialog = { height = 0.5 },
      cmd = { height = 0.5 },
      msg = { height = 0.5, timeout = 4500 },
    },
  })
end)

require("config")
local nf = require("utils.nerdfont")
require("utils.nerdfontpicker")

nf.init()
