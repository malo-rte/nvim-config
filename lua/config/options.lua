-- Basic Settings
vim.opt.number = true -- Line numbers
vim.opt.relativenumber = true -- Relative numbers
vim.opt.cursorline = true -- Highlight current line
vim.opt.scrolloff = 10 -- Keep 10 line above / below cursor
vim.opt.sidescrolloff = 8 -- Keep 8 columns left/right of cursor
vim.opt.wrap = false -- Don't wrap lines
vim.opt.cmdheight = 1 -- Command line height
vim.opt.spelllang = { "en", "sv" } -- Set language for spellchecking
vim.opt.spell = true

-- Tabbing / Indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.smartindent = true -- Smart auto indenting
vim.opt.autoindent = true -- Copy indent from current line
vim.g.editorconfig = true -- Use settings in .editorconfig

vim.opt.grepprg = "rg --vimgrep" -- Use ripgrep
vim.opt.grepformat = "%f:%l:%c:%m" -- Filename, line number, column, content

-- Search settings
vim.opt.ignorecase = true -- Case insensitive search
vim.opt.smartcase = true -- Case sensitive if uppercase in search
vim.opt.hlsearch = true -- Highlight search results
vim.opt.incsearch = true -- Show matches as you type

-- Visual settings
vim.opt.termguicolors = true -- Enable 24-bit colors
vim.opt.signcolumn = "yes" -- Always show sign column
vim.opt.colorcolumn = "80" -- Show column
vim.opt.showmatch = true -- Highlight  matching brackets
vim.opt.matchtime = 2 -- How long to show matching bracket
vim.opt.completeopt = "menuone,noinsert,noselect" -- Completion options
vim.opt.showmode = false -- Don't show mode in command line
vim.opt.pumheight = 10 -- Pop-up menu height
vim.opt.pumblend = 10 -- Pop-up menu transparency
vim.opt.winblend = 0 -- Floating window transparency
vim.opt.conceallevel = 0 -- Don't hide markup
vim.opt.lazyredraw = false -- Redraw while executing macros
vim.opt.redrawtime = 10000 -- Timeout for syntax highlighting redraw
vim.opt.maxmempattern = 20000 -- Max memory for pattern matching
vim.opt.synmaxcol = 300 -- Syntax highlighting column limit

-- File handling
vim.opt.backup = false -- Don't create backup files
vim.opt.writebackup = false -- Don't backup before overwriting
vim.opt.swapfile = false -- Don't create swap files
vim.opt.undofile = true -- Persistent undo
vim.opt.updatetime = 300 -- Time in ms to trigger CursorHold
vim.opt.timeoutlen = 500 -- Time in ms to wait for mapped sequence
vim.opt.autoread = true -- Auto reload file if changed outside
vim.opt.autowrite = false -- Don't auto save on some events

-- Diff settings
vim.opt.diffopt:append("vertical") -- Vertical diff splits
vim.opt.diffopt:append("algorithm:patience") -- Better diff algorithm
vim.opt.diffopt:append("linematch:60") -- Better diff highlighting

-- Set undo directory and ensure it exists
local undodir = "~/.local/share/nvim/undodir"
local undodir_path = vim.fn.expand(undodir)
vim.opt.undodir = undodir_path
if vim.fn.isdirectory(undodir_path) == 0 then
	vim.fn.mkdir(undodir_path, "p") -- Create if not exists
end

vim.opt.wildoptions = "pum"


-- Behaviour settings
vim.opt.errorbells = false -- Disable error sounds
vim.opt.backspace = "indent,eol,start"
vim.opt.autochdir = false -- Don't change directory automatically
vim.opt.iskeyword:append("-") -- Tread dash as part of a word
vim.opt.path:append("**") -- Search into subfolders with 'gf'
vim.opt.selection = "inclusive"
vim.opt.mouse = "a" -- Enable mouse support
vim.opt.clipboard:append("unnamedplus") -- Use system clipboard
vim.opt.encoding = "UTF-8"
vim.opt.wildmenu = true -- Enable command line completion menu
vim.opt.wildmode = "longest:full,full" -- Completion mode for the command line
vim.opt.wildignorecase = true -- Case insensitive tab completion in commands

-- Cursor configuration
vim.opt.guicursor = {
	-- Normal
	"n:block",

	-- Visual
	"v:block-blinkwait700-blinkoff250-blinkon250",

	-- Operator pending
	"o:hor50",

	-- Insert
	"i:ver25-blinkwait700-blinkoff250-blinkon250",

	-- Replace
	"r:hor25-blinkwait500-blinkoff100-blinkon100",

	-- Command line normal (append) mode
	"c:ver25-blinkwait700-blinkoff250-blinkon250",

	-- Command line insert mode
	"ci:ver25-blinkwait700-blinkoff250-blinkon250",

	-- Command line replace
	"cr:hor25-blinkwait700-blinkoff250-blinkon250",

	-- Show match in insert mode
	"sm:ver25",

	-- Terminal
	"t:ver25-blinkwait700-blinkoff250-blinkon250",
}

-- Folding settings
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()" -- Use tree sitter for folding
vim.opt.foldlevel = 99 -- Keep all folds open by default

-- Split behaviour
vim.opt.splitbelow = true -- Horizontal splits open below
vim.opt.splitright = true -- Vertical split open to the right
