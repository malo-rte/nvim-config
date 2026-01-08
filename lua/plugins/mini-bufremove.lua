local opts = {
    silent = false,
}

return {
    'nvim-mini/mini.bufremove',
    version = '*',
    opts = opts,

    config = function(_, o)
        local plugin = require("mini.bufremove")

        plugin.setup(o)
    end,
}
