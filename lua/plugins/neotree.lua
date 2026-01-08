local neotree_opts = {
    close_if_last_window = true,

    event_handlers = {
        {
            event = "file_opened",
            handler = function(_)
                -- close all Neo-tree windows (any source)
                require("neo-tree.command").execute({ action = "close" })
                -- If you only want to close the filesystem tree, use:
                -- require("neo-tree.command").execute({ action = "close", source = "filesystem" })
            end,
    },
  },
}

local nlfo_opts = {

}

local nwp_opts = {
    filter_rules = {
        include_current_win = false,
        autoselect_one = true,
        -- filter using buffer options
        bo = {
            -- if the file type is one of following, the window will be ignored
            filetype = { "neo-tree", "neo-tree-popup", "notify" },
            -- if the buffer type is one of following, the window will be ignored
            buftype = { "terminal", "quickfix" },
        },
    },
}

return {
    {
        'nvim-neo-tree/neo-tree.nvim',
        branch = "v3.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "MunifTanjim/nui.nvim",
            "nvim-tree/nvim-web-devicons",
        },
        lazy = false,
        version = '*',
        opts = neotree_opts,

        config = function(_, o)
            local nt = require("neo-tree")

            nt.setup(o)

            -- Open Neo-tree at your project root (uses your config.project module)
            vim.keymap.set("n", "<leader>fe", function()
                local project = require("config.project")
                local root = project.project_root()

                vim.cmd("Neotree position=top toggle dir=" .. vim.fn.fnameescape(root))
            end, { desc = "Explorer: at project root" })
        end,
    },

    {
        "antosha417/nvim-lsp-file-operations",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-neo-tree/neo-tree.nvim", -- makes sure that this loads after Neo-tree.
        },
        opts = nlfo_opts,
        config = function(_, o)
            require("lsp-file-operations").setup(o)
        end,
    },

    {
        "s1n7ax/nvim-window-picker",
        version = "2.*",
        opts = nwp_opts,

        config = function(_, o)
            require("window-picker").setup(o)
        end,
    },
}
