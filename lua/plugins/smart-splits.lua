
local opts = {
    -- Ignored buffer types (only while resizing)
    ignored_buftypes = {
        'nofile',
        'quickfix',
        'prompt',
    },
    -- Ignored filetypes (only while resizing)
    ignored_filetypes = { 'NvimTree', "neo-tree" },
    -- the default number of lines/columns to resize by at a time
    default_amount = 2,

    at_edge = 'wrap',
    float_win_behavior = 'previous',
    move_cursor_same_row = false,
    cursor_follows_swapped_bufs = false,

    ignored_events = {
        'BufEnter',
        'WinEnter',
    },

    multiplexer_integration = nil, -- set to "tmux" | "wezterm" | "kitty" | "zellij" if you use one
    disable_multiplexer_nav_when_zoomed = true,
    kitty_password = nil,
    zellij_move_focus_or_tab = false,
    log_level = 'info',
}


return {
    'mrjones2014/smart-splits.nvim',
    opts = opts,

    config = function(_, o) 
        ss = require("smart-splits")

        ss.setup(o)

       -- helper to honor counts: 5<M-S-Right> → resize by 5
        local function bycount(f)
              return function() f(vim.v.count1) end
        end

        -- Resizing splits (Meta+Shift+Arrows)
        vim.keymap.set("n", "<M-S-Left>",  bycount(ss.resize_left),  { silent = true, desc = "Resize left" })
        vim.keymap.set("n", "<M-S-Right>", bycount(ss.resize_right), { silent = true, desc = "Resize right" })
        vim.keymap.set("n", "<M-S-Down>",  bycount(ss.resize_down),  { silent = true, desc = "Resize down" })
        vim.keymap.set("n", "<M-S-Up>",    bycount(ss.resize_up),    { silent = true, desc = "Resize up" })

        -- Moving between splits (Meta+Arrows)
        vim.keymap.set("n", "<M-Left>",  ss.move_cursor_left,  { silent = true, desc = "Focus left window" })
        vim.keymap.set("n", "<M-Right>", ss.move_cursor_right, { silent = true, desc = "Focus right window" })
        vim.keymap.set("n", "<M-Down>",  ss.move_cursor_down,  { silent = true, desc = "Focus below window" })
        vim.keymap.set("n", "<M-Up>",    ss.move_cursor_up,    { silent = true, desc = "Focus above window" })

        -- Swapping buffers between windows (use arrow keys after <leader>w)
        vim.keymap.set("n", "<leader>w<Left>",  ss.swap_buf_left,  { silent = true, desc = "Swap buffer left" })
        vim.keymap.set("n", "<leader>w<Down>",  ss.swap_buf_down,  { silent = true, desc = "Swap buffer down" })
        vim.keymap.set("n", "<leader>w<Up>",    ss.swap_buf_up,    { silent = true, desc = "Swap buffer up" })
        vim.keymap.set("n", "<leader>w<Right>", ss.swap_buf_right, { silent = true, desc = "Swap buffer right" })
    end,
}
