-- lua/config/float.lua
do
	local orig = vim.lsp.util.open_floating_preview
	function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
		opts = opts or {}
		opts.border = opts.border or "rounded"
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
