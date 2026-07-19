-- lvim-color-picker.convert: the converter tool — rewrite the color literal under the cursor in the
-- NEXT syntax of `config.convert_cycle` (hex → rgb() → hsl() → …), preserving its alpha. Dot-repeat
-- rides the SAME native operatorfunc seam as lvim-cycle: the trigger arms 'operatorfunc' and returns
-- "g@l", so `.` re-runs the conversion at the new cursor with no repeat.vim.
--
---@module "lvim-color-picker.convert"

local api = vim.api

local config = require("lvim-color-picker.config")
local lib = require("lvim-color-picker.lib")

local M = {}

--- The syntax a matched span is written in, from its leading characters. A `0x…` literal is "hex0x"
--- (distinct from `#…` "hex") so it round-trips when `convert_cycle` includes `hex0x`; when the cycle
--- omits it (the default), `hex0x` is simply "not in the cycle", so next_syntax enters at the first slot.
---@param text string
---@return "hex"|"hex0x"|"rgb"|"hsl"|"cmyk"
local function syntax_of(text)
    if text:match("^0[xX]") then
        return "hex0x"
    elseif text:match("^#") then
        return "hex"
    elseif text:match("^[cC][mM][yY][kK]") then
        return "cmyk"
    elseif text:match("^[hH][sS][lL]") then
        return "hsl"
    end
    return "rgb"
end

--- The next syntax after `cur` in the configured cycle (wraps); falls back to the first entry when
--- `cur` is not in the cycle.
---@param cur string
---@return "hex"|"hex0x"|"rgb"|"hsl"|"cmyk"
local function next_syntax(cur)
    local cyc = config.convert_cycle
    for i, s in ipairs(cyc) do
        if s == cur then
            return cyc[(i % #cyc) + 1]
        end
    end
    return cyc[1] or "hex"
end

--- Convert the color literal under the cursor to the next syntax in the cycle, in place.
---@return boolean  whether a literal was found and rewritten
function M.convert()
    local buf = api.nvim_get_current_buf()
    local cur = api.nvim_win_get_cursor(0)
    local row, col = cur[1] - 1, cur[2]
    local line = api.nvim_get_current_line()
    local hit = lib.parse_at(line, col, true)
    if not hit or col < hit.s or col >= hit.e then
        return false
    end
    local text = line:sub(hit.s + 1, hit.e)
    local target = next_syntax(syntax_of(text))
    local out = lib.format(hit.color, target)
    api.nvim_buf_set_text(buf, row, hit.s, row, hit.e, { out })
    api.nvim_win_set_cursor(0, { row + 1, hit.s })
    return true
end

--- The operatorfunc target for dot-repeat. Public because 'operatorfunc' needs a reachable v:lua
--- name.
---@return nil
function M.opfunc(_)
    M.convert()
end

--- Arm dot-repeat and run one conversion (the normal-mode expr trigger's payload).
---@return string  "g@l" (so `.` replays through operatorfunc)
function M.trigger()
    vim.go.operatorfunc = "v:lua.require'lvim-color-picker.convert'.opfunc"
    return "g@l"
end

return M
