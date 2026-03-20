return {
	"barrettruth/preview.nvim",
	init = function()
		vim.g.preview = { typst = true, latex = true, markdown = true, plantuml = true }
	end,
}
