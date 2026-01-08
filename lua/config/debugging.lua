return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"rcarriga/nvim-dap-ui",
			"theHamsta/nvim-dap-virtual-text",
			"nvim-neotest/nvim-nio",
		},

		config = function()
			local dap = require("dap")
			local ui = require("dapui")
			local vt = require("nvim-dap-virtual-text")

			ui.setup()

			vt.setup({
				display_callback = function(variable)
					if #variable.value > 15 then
						return " " .. string.sub(variable.value, 1, 15) .. "... "
					end

					return " " .. variable.value
				end,
			})
		end,
	},
}
