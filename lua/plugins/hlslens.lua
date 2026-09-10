-- plugins/hlslens.lua
--
-- Search results at a glance: nvim-hlslens annotates each match with its index
-- and the total ("[3/17]") as virtual text and highlights the nearest one
-- differently, so `n` / `N` stop being a guess about how far through you are.
--
-- Deliberately not lazy on `keys`: hlslens also starts itself from `/` and `?`
-- (auto_enable, with 'incsearch'), and a keys trigger only covers n/N/*/#,
-- which would leave a plain search un-annotated until the first `n`. VeryLazy
-- loads it once the UI is up, well before a search can be typed.
--
-- `:nohlsearch` stops it, so the <Esc> map in config/keymaps.lua already clears
-- the lens along with the search highlight -- nothing extra to bind.
--
-- Keys (normal mode):
--   n / N     next / previous match, centered, lens refreshed
--   * / #     search the word under the cursor forward / backward
--   g* / g#   the same without word boundaries
-- Commands: :HlSearchLensToggle :HlSearchLensEnable :HlSearchLensDisable
return {
	"kevinhwang91/nvim-hlslens",
	event = "VeryLazy",
	cmd = { "HlSearchLensToggle", "HlSearchLensEnable", "HlSearchLensDisable" },

	opts = {
		-- Drop the lens and highlighting once the cursor leaves the matched
		-- range or the text changes, instead of leaving a stale count on
		-- screen. Set false to keep it until :nohlsearch.
		calm_down = true,
	},

	config = function(_, o)
		require("hlslens").setup(o)

		local function nmap(lhs, rhs, desc)
			vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
		end

		-- n/N keep the centering this config has always had (nzzzv), then ask
		-- hlslens to refresh the lens for wherever they landed. v:count1 keeps
		-- counts working (3n).
		nmap(
			"n",
			[[<Cmd>execute('normal! ' . v:count1 . 'nzzzv')<CR><Cmd>lua require('hlslens').start()<CR>]],
			"Next search result centered"
		)
		nmap(
			"N",
			[[<Cmd>execute('normal! ' . v:count1 . 'Nzzzv')<CR><Cmd>lua require('hlslens').start()<CR>]],
			"Previous search result centered"
		)

		-- The rhs is non-recursive, so `*` here is the built-in one.
		for _, lhs in ipairs({ "*", "#", "g*", "g#" }) do
			nmap(lhs, ("%s<Cmd>lua require('hlslens').start()<CR>"):format(lhs), "Search word under cursor: " .. lhs)
		end
	end,
}
