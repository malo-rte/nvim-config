local M = {}

-- Severity glyphs come from the shared icon table so the sign column, the
-- statusline, and the quickfix all render the same code points (DEV-TOOLS-DES-0004
-- §86 semantic consistency).
local icons = require("utils.icons").diagnostics

M.setup = function ()
    vim.diagnostic.config({
        signs = {
            text = {
                [vim.diagnostic.severity.ERROR] = icons.error,
                [vim.diagnostic.severity.WARN] = icons.warn,
                [vim.diagnostic.severity.INFO] = icons.info,
                [vim.diagnostic.severity.HINT] = icons.hint,
            },
        },
        virtual_text = false,
        virtual_lines = { current_line = true, },
        severity_sort =  true,
        update_in_insert = false,
        float = { source = 'if_many' },
        jump = { float = true },
    })
end

return M;
