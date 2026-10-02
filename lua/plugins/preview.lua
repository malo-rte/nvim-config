-- Document preview (typst / latex / markdown / plantuml), driven entirely by
-- the :Preview command -- nothing attaches on FileType -- so that command is
-- the lazy trigger. `init` still runs at startup because vim.g.preview has to
-- be set before the plugin loads.
--
-- Source note, because this looks like something to "fix" back:
--
-- Upstream moved development off GitHub to Forgejo (:help preview-migration)
-- and calls GitHub a read-only compatibility mirror, so the spec pointed at
-- https://git.barrettruth.com/barrettruth/preview.nvim. That host's `git`
-- subdomain stopped resolving around 2026-10-02 (the apex barrettruth.com
-- still does), which with `checker = { enabled = true }` in config/lazy.lua
-- meant a failed fetch and an error on *every* startup -- lazy probes every
-- remote at launch.
--
-- So: back to the mirror, which is alive, unarchived, and was pushed more
-- recently (2026-09-26) than the commit pinned here. The lockfile stays valid
-- either way -- that commit is fetchable from GitHub too, checked. Move this
-- back to the Forgejo URL if the host returns; the mirror may go stale.
return {
	"barrettruth/preview.nvim",
	cmd = "Preview",
	init = function()
		vim.g.preview = { typst = true, latex = true, markdown = true, plantuml = true }
	end,
}
