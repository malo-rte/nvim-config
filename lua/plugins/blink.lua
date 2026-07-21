-- lua/plugins/blink.lua
local icons = require("utils.icons")

return {
  "Saghen/blink.cmp",
  version = "1.*",
  event = { "InsertEnter", "CmdlineEnter" },
  opts = {
    appearance = {
      nerd_font_variant = "mono",
      kind_icons = icons.lsp_kind,
    },

    keymap = {
      preset = "default",
      ["<Tab>"] = {
        function(cmp)
          cmp.select_next({ auto_insert = false })
        end,
        "snippet_forward",
        "fallback",
      },
      ["<S-Tab>"] = {
        function(cmp)
          cmp.select_prev({ auto_insert = false })
        end,
        "snippet_backward",
        "fallback",
      },
      ["<CR>"] = { "accept", "fallback" },
    },

    completion = {
      menu = {
        border = "rounded",
        winblend = 8,
        winhighlight = "Normal:BlinkCmpMenu,"
          .. "FloatBorder:BlinkCmpMenuBorder,"
          .. "CursorLine:BlinkCmpMenuSelection,"
          .. "Search:None",
      },

      list = {
        selection = {
          preselect = true,
          auto_insert = false,
        },
      },

      ghost_text = { enabled = false },

      documentation = {
        auto_show = true,
        auto_show_delay_ms = 250,
        treesitter_highlighting = true,
        window = {
          border = "rounded",
          winblend = 8,
          winhighlight = "Normal:BlinkCmpDoc,"
            .. "FloatBorder:BlinkCmpDocBorder,"
            .. "EndOfBuffer:BlinkCmpDoc",
        },
      },
    },

    sources = {
      default = {  "lsp", "path", "snippets", "buffer" },
    },

    -- Command-line (`:`) completion uses the same blink menu as insert mode.
    -- auto_show makes it appear as you type (blink only shows it in cmdwin by
    -- default), and <Up>/<Down> are added so it navigates like every other
    -- menu (the cmdline preset only binds <Left>/<Right> + <C-n>/<C-p>).
    cmdline = {
      keymap = {
        preset = "cmdline",
        ["<Up>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
      },
      completion = {
        menu = { auto_show = true },
      },
    },
  },

  config = function(_, opts)
    require("blink.cmp").setup(opts)

    vim.api.nvim_set_hl(0, "BlinkCmpMenu", { link = "Pmenu" })
    vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "FloatBorder" })
    vim.api.nvim_set_hl(0, "BlinkCmpMenuSelection", { link = "PmenuSel" })
    vim.api.nvim_set_hl(0, "BlinkCmpLabel", { link = "Pmenu" })
    vim.api.nvim_set_hl(0, "BlinkCmpLabelDetail", { link = "PmenuExtra" })
    vim.api.nvim_set_hl(0, "BlinkCmpLabelDescription", { link = "PmenuExtra" })
    vim.api.nvim_set_hl(0, "BlinkCmpKind", { link = "Pmenu" })
    vim.api.nvim_set_hl(0, "BlinkCmpDoc", { link = "NormalFloat" })
    vim.api.nvim_set_hl(0, "BlinkCmpDocBorder", { link = "FloatBorder" })
  end,
}
