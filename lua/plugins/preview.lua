-- Document preview (typst / latex / markdown / plantuml), driven entirely by
-- the :Preview command -- nothing attaches on FileType -- so that command is
-- the lazy trigger. `init` still runs at startup because vim.g.preview has to
-- be set before the plugin loads.
--
-- Upstream moved development off GitHub (:help preview-migration), so the
-- source is the Forgejo remote; the GitHub mirror prints a one-time warning
-- and will go stale.
return {
	url = "https://git.barrettruth.com/barrettruth/preview.nvim",
	cmd = "Preview",
	init = function()
		vim.g.preview = { typst = true, latex = true, markdown = true, plantuml = true }
	end,
}
