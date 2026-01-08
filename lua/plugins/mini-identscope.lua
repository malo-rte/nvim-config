-- plugins/mini-indentscope.lua
local opts = {
    draw = {
        delay = 0,
        animation = nil,                    -- set in config
        -- predicate = function() return true end, -- ALWAYS draw
        predicate = function(_, _, scope)
            return (scope == nil) or (scope.body and not scope.body.is_incomplete)
        end,
        priority = 0,                       -- low, but visible
    },

    mappings = {
        object_scope = "ii",
        object_scope_with_border = "ai",
        goto_top = "[i",
        goto_bottom = "]i",
    },

    options = {
        border = "both",
        indent_at_cursor = true,
        try_as_border = true,
        n_lines = 300,
    },

    symbol = "▏",
}

return {
    "nvim-mini/mini.indentscope",
    version = false,
    opts = opts,

    config = function(_, o)
        local M = require("mini.indentscope")

        o.draw.animation = M.gen_animation.none()
        M.setup(o)

        -- Dim, theme-aware guide color
        local function dim()
            --local fg = (vim.o.background == "dark") and "#3a3a3a" or "#b0b0b0"
            --vim.api.nvim_set_hl(0, "MiniIndentscopeSymbol", { fg = fg, nocombine = true })
            vim.api.nvim_set_hl(0, "MiniIndentscopeSymbol", { link = "NonText" }) -- or "Conceal"
        end
        vim.api.nvim_create_autocmd("ColorScheme", { callback = dim })
        dim()

        -- Optional: disable in sidebars/special buffers
        local grp = vim.api.nvim_create_augroup("MiniIndentscopeDisable", { clear = true })
        vim.api.nvim_create_autocmd("FileType", {
            group = grp,
            pattern = {
                "help","alpha","dashboard","neo-tree","NvimTree","trouble","lazy","mason",
                "notify","fugitive","gitcommit","checkhealth","lspinfo","spectre_panel","toggleterm","oil",
                "make", "markdown", "txt"
            },
            callback = function() vim.b.miniindentscope_disable = true end,
        })

        vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
            group = grp,
            callback = function()
                local bt = vim.bo.buftype
                if bt == "nofile" or bt == "terminal" or bt == "prompt" then
                    vim.b.miniindentscope_disable = true
                end
            end,
        })

        vim.keymap.set("n", "<leader>ui", 
            function()
                vim.b.miniindentscope_disable = not vim.b.miniindentscope_disable
                vim.cmd("redraw")
            end, 
            { desc = "Toggle indent scope" }
        )

        vim.keymap.set("n", "<leader>uI", function()
            vim.g.miniindentscope_disable = not vim.g.miniindentscope_disable
            vim.cmd("redraw")
        end, { desc = "Toggle indent scope (global)" })

    end,


}
