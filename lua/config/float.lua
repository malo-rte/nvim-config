-- lua/config/float.lua
--
-- Style LSP hover / signature floats to match the blink.cmp doc window.
-- The border comes from the global 'winborder' (see options.lua); this
-- override only adds what winborder can't: transparency, size caps, and
-- the BlinkCmpDoc winhighlight.
do
	local orig = vim.lsp.util.open_floating_preview
	function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
		opts = opts or {}
		opts.winblend = opts.winblend or 8
		opts.max_width = opts.max_width or math.floor(vim.o.columns * 0.45)
		opts.max_height = opts.max_height or math.floor(vim.o.lines * 0.30)

		local bufnr, winnr = orig(contents, syntax, opts, ...)
		pcall(
			vim.api.nvim_set_option_value,
			"winhighlight",
			"Normal:BlinkCmpDoc,FloatBorder:BlinkCmpDocBorder,EndOfBuffer:BlinkCmpDoc",
			{ win = winnr }
		)
		return bufnr, winnr
	end
end
