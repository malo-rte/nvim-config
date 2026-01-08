---@brief
--- https://github.com/tailwindlabs/tailwindcss-intellisense
---
--- Tailwind CSS Language Server can be installed via npm:
---
---   npm install -g @tailwindcss/language-server

---@type vim.lsp.Config

local function read_file_lines(path)
	local ok, data = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	return data
end

local function insert_package_json(root_files, field, fname)
	local pkg = vim.fs.find("package.json", {
		path = fname,
		upward = true,
		type = "file",
		limit = 1,
	})[1]

	if not pkg then
		return root_files
	end

	local lines = read_file_lines(pkg)
	if not lines then
		return root_files
	end

	for _, line in ipairs(lines) do
		if line:find(field, 1, true) then
			table.insert(root_files, "package.json")
			break
		end
	end

	return root_files
end

local function root_markers_with_field(root_files, markers, needle, fname)
	for _, marker in ipairs(markers) do
		local found = vim.fs.find(marker, {
			path = fname,
			upward = true,
			type = "file",
			limit = 1,
		})[1]

		if found then
			local lines = read_file_lines(found)
			if lines then
				for _, line in ipairs(lines) do
					if line:find(needle, 1, true) then
						table.insert(root_files, marker)
						break
					end
				end
			end
		end
	end

	return root_files
end

return {
	cmd = { "tailwindcss-language-server", "--stdio" },

	-- filetypes copied and adjusted from tailwindcss-intellisense
	filetypes = {
		-- html
		"aspnetcorerazor",
		"astro",
		"astro-markdown",
		"blade",
		"clojure",
		"django-html",
		"htmldjango",
		"edge",
		"eelixir", -- vim ft
		"elixir",
		"ejs",
		"erb",
		"eruby", -- vim ft
		"gohtml",
		"gohtmltmpl",
		"haml",
		"handlebars",
		"hbs",
		"html",
		"htmlangular",
		"html-eex",
		"heex",
		"jade",
		"leaf",
		"liquid",
		"markdown",
		"mdx",
		"mustache",
		"njk",
		"nunjucks",
		"php",
		"razor",
		"slim",
		"twig",
		-- css
		"css",
		"less",
		"postcss",
		"sass",
		"scss",
		"stylus",
		"sugarss",
		-- js
		"javascript",
		"javascriptreact",
		"reason",
		"rescript",
		"typescript",
		"typescriptreact",
		-- mixed
		"vue",
		"svelte",
		"templ",
	},

	capabilities = {
		workspace = {
			didChangeWatchedFiles = {
				dynamicRegistration = true,
			},
		},
	},

	settings = {
		tailwindCSS = {
			validate = true,
			lint = {
				cssConflict = "warning",
				invalidApply = "error",
				invalidScreen = "error",
				invalidVariant = "error",
				invalidConfigPath = "error",
				invalidTailwindDirective = "error",
				recommendedVariantOrder = "warning",
			},
			classAttributes = {
				"class",
				"className",
				"class:list",
				"classList",
				"ngClass",
			},
			includeLanguages = {
				eelixir = "html-eex",
				elixir = "phoenix-heex",
				eruby = "erb",
				heex = "phoenix-heex",
				htmlangular = "html",
				templ = "html",
			},
		},
	},

	before_init = function(_, config)
		config.settings = config.settings or {}
		config.settings.editor = config.settings.editor or {}
		if config.settings.editor.tabSize == nil then
			config.settings.editor.tabSize = vim.lsp.util.get_effective_tabstop()
		end
	end,

	workspace_required = true,

	root_dir = function(bufnr, on_dir)
		local root_files = {
			-- Generic
			"tailwind.config.js",
			"tailwind.config.cjs",
			"tailwind.config.mjs",
			"tailwind.config.ts",
			"postcss.config.js",
			"postcss.config.cjs",
			"postcss.config.mjs",
			"postcss.config.ts",
			-- Django
			"theme/static_src/tailwind.config.js",
			"theme/static_src/tailwind.config.cjs",
			"theme/static_src/tailwind.config.mjs",
			"theme/static_src/tailwind.config.ts",
			"theme/static_src/postcss.config.js",
			-- Fallback for tailwind v4, where tailwind.config.* is not required anymore
			".git",
		}

		local fname = vim.api.nvim_buf_get_name(bufnr)

		root_files = insert_package_json(root_files, "tailwindcss", fname)
		root_files = root_markers_with_field(root_files, { "mix.lock", "Gemfile.lock" }, "tailwind", fname)

		local root = vim.fs.find(root_files, {
			path = fname,
			upward = true,
			type = "file",
			limit = 1,
		})[1]

		if not root then
			-- Fallback: current working directory if no root marker found
			on_dir(vim.fn.getcwd())
			return
		end

		on_dir(vim.fs.dirname(root))
	end,
}
