-- plugins/debugging.lua
--
-- Debugging via GDB's native DAP interface (gdb --interpreter=dap, gdb >= 14).
-- No external adapter to install. Two ways to start, picked from the
-- dap.continue() list:
--   * Launch (local gdb)        -- run a local executable under gdb
--   * Attach to QEMU / gdbstub  -- `target remote host:port` (QEMU -s -S, gdbserver, ...)
--
-- The per-config `gdb` field swaps the binary: rust-gdb for Rust (loads the
-- Rust pretty-printers), or a multiarch/cross gdb for foreign-arch targets.
--
-- Keymaps (<leader>d = Debug; add `{ "<leader>d", group = "Debug" }` to which-key):
--   <F5> start/continue · <F10> over · <F11> into · <F12> out
--   <leader>db breakpoint · dB conditional · dl logpoint
--   <leader>dc continue · dr REPL · dL run-last · dt terminate
--   <leader>du toggle UI · de eval (n/v)

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

			--------------------------------------------------------------
			-- Adapter: gdb's native DAP. `config.gdb` chooses the binary.
			--------------------------------------------------------------
			dap.adapters.gdb = function(cb, config)
				cb({
					type = "executable",
					command = config.gdb or "gdb",
					args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
				})
			end

			--------------------------------------------------------------
			-- Interactive prompts
			--------------------------------------------------------------
			local function pick_exe()
				return function()
					local path = vim.fn.input({
						prompt = "Path to executable: ",
						default = vim.fn.getcwd() .. "/",
						completion = "file",
					})
					return (path ~= "" and path) or dap.ABORT
				end
			end

			local function pick_target()
				local t = vim.fn.input({ prompt = "Remote target (host:port): ", default = "localhost:1234" })
				return (t ~= "" and t) or dap.ABORT
			end

			--------------------------------------------------------------
			-- Configurations (dap.continue() lists these to choose from).
			--------------------------------------------------------------
			local function configs_for(gdb)
				return {
					{
						name = "Launch (local gdb)",
						type = "gdb",
						request = "launch",
						program = pick_exe(),
						cwd = "${workspaceFolder}",
						stopAtBeginningOfMainSubprogram = false,
						gdb = gdb,
					},
					{
						name = "Launch with args (local gdb)",
						type = "gdb",
						request = "launch",
						program = pick_exe(),
						cwd = "${workspaceFolder}",
						args = function()
							return vim.split(vim.fn.input("Args: "), " ", { trimempty = true })
						end,
						gdb = gdb,
					},
					{
						-- QEMU: start it with `-s -S` (listens on :1234, halted),
						-- then pick this and point `program` at the ELF with symbols.
						name = "Attach to QEMU / gdbstub",
						type = "gdb",
						request = "attach",
						target = pick_target, -- -> `target remote host:port`
						program = pick_exe(), -- unstripped ELF for symbols
						cwd = "${workspaceFolder}",
						gdb = gdb, -- set to a multiarch/cross gdb for foreign arch
					},
				}
			end

			dap.configurations.c = configs_for(nil)
			dap.configurations.cpp = configs_for(nil)
			dap.configurations.rust = configs_for("rust-gdb")

			--------------------------------------------------------------
			-- dap-ui auto open/close
			--------------------------------------------------------------
			dap.listeners.after.event_initialized["dapui"] = function()
				ui.open()
			end
			dap.listeners.before.event_terminated["dapui"] = function()
				ui.close()
			end
			dap.listeners.before.event_exited["dapui"] = function()
				ui.close()
			end

			--------------------------------------------------------------
			-- Keymaps
			--------------------------------------------------------------
			local map = vim.keymap.set
			map("n", "<F5>", dap.continue, { desc = "Debug: start/continue" })
			map("n", "<F10>", dap.step_over, { desc = "Debug: step over" })
			map("n", "<F11>", dap.step_into, { desc = "Debug: step into" })
			map("n", "<F12>", dap.step_out, { desc = "Debug: step out" })
			map("n", "<leader>dc", dap.continue, { desc = "Continue / start" })
			map("n", "<leader>db", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
			map("n", "<leader>dB", function()
				dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
			end, { desc = "Conditional breakpoint" })
			map("n", "<leader>dl", function()
				dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
			end, { desc = "Log point" })
			map("n", "<leader>dr", dap.repl.toggle, { desc = "Toggle REPL" })
			map("n", "<leader>dL", dap.run_last, { desc = "Run last" })
			map("n", "<leader>dt", dap.terminate, { desc = "Terminate" })
			map("n", "<leader>du", ui.toggle, { desc = "Toggle DAP UI" })
			map({ "n", "v" }, "<leader>de", function()
				ui.eval()
			end, { desc = "Eval expression" })
		end,
	},
}
