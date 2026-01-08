local opts = {
    delay = 100,
}

return {
    'nvim-mini/mini.cursorword', 
    version = '*',
    opts = opts,
    
    config = function(_, o)
        local plugin = require("mini.cursorword")
        
        plugin.setup(o)
    end,
}
