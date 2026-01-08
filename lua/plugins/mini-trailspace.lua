local opts = {
        -- Highlight only in normal buffers (ones with empty 'buftype'). This is
        -- useful to not show trailing whitespace where it usually doesn't matter.
        only_in_normal_buffers = true,
}

return {
    'nvim-mini/mini.trailspace',
    version = '*',
    opts = opts,

    config = function(_, o)
        local plugin = require("mini.trailspace")

        plugin.setup(o)
    end,
}
