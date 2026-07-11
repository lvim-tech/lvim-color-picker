-- lvim-color-picker.highlighter: the inline highlighter — paint color literals in the buffer. Driven
-- by per-buffer autocmds (not a decoration provider) so the lazy per-color highlight groups are
-- created OUTSIDE redraw, where nvim_set_hl is safe; only the VISIBLE line range of each window is
-- scanned, so a large file never pays for its off-screen lines. Groups (LvimColorPickerSwatch_<hex>)
-- are cached and flushed on ColorScheme (they hold literal `bg`/`fg` values a theme swap would
-- otherwise strand), then the visible range repaints.
--
---@module "lvim-color-picker.highlighter"

local api = vim.api

local config = require("lvim-color-picker.config")
local lib = require("lvim-color-picker.lib")

local M = {}

local ns = api.nvim_create_namespace("lvim-color-picker-highlight")
---@type table<integer, boolean>  buffers with the highlighter on
local enabled = {}
---@type table<string, string>  "#rrggbb" → cached group name
local groups = {}
---@type table<integer, uv.uv_timer_t>  per-buffer refresh debounce
local timers = {}
local REFRESH_MS = 30

--- The (cached) highlight group painting `color` per the configured style: `bg` tints the background
--- with a contrast-picked fg, `fg`/`virtual` color the foreground. Created lazily on first sighting.
---@param color LvimColor
---@return string
local function group_for(color)
    local hex = lib.format({ r = color.r, g = color.g, b = color.b }, "hex")
    local cached = groups[hex]
    if cached then
        return cached
    end
    local name = "LvimColorPickerSwatch_" .. hex:sub(2)
    local style = config.highlighter.style
    if style == "bg" then
        local fg = lib.luminance(color) > 0.5 and "#000000" or "#ffffff"
        api.nvim_set_hl(0, name, { bg = hex, fg = fg })
    else
        api.nvim_set_hl(0, name, { fg = hex })
    end
    groups[hex] = name
    return name
end

--- Repaint the visible line range of every window showing `buf`.
---@param buf integer
---@return nil
local function refresh(buf)
    if not enabled[buf] or not api.nvim_buf_is_valid(buf) then
        return
    end
    local style = config.highlighter.style
    local named = config.highlighter.named
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        local top = api.nvim_win_call(win, function()
            return vim.fn.line("w0") - 1
        end)
        local bot = api.nvim_win_call(win, function()
            return vim.fn.line("w$")
        end)
        api.nvim_buf_clear_namespace(buf, ns, top, bot)
        local lines = api.nvim_buf_get_lines(buf, top, bot, false)
        for i, line in ipairs(lines) do
            local row = top + i - 1
            for _, h in ipairs(lib.parse_all(line, named)) do
                local grp = group_for(h.color)
                if style == "virtual" then
                    pcall(api.nvim_buf_set_extmark, buf, ns, row, h.s, {
                        virt_text = { { config.highlighter.chip_icon, grp } },
                        virt_text_pos = "inline",
                    })
                else
                    pcall(api.nvim_buf_set_extmark, buf, ns, row, h.s, { end_col = h.e, hl_group = grp })
                end
            end
        end
    end
end

--- Debounced refresh (coalesces a burst of edits / scrolls into one repaint).
---@param buf integer
---@return nil
local function schedule(buf)
    if not timers[buf] then
        timers[buf] = assert(vim.uv.new_timer())
    end
    timers[buf]:stop()
    timers[buf]:start(
        REFRESH_MS,
        0,
        vim.schedule_wrap(function()
            refresh(buf)
        end)
    )
end

--- Turn the highlighter ON for a buffer: attach the repaint autocmds and paint once. Idempotent.
---@param buf integer
---@return nil
function M.enable(buf)
    buf = buf or api.nvim_get_current_buf()
    if enabled[buf] then
        return
    end
    enabled[buf] = true
    local group = api.nvim_create_augroup("lvim-color-picker-hl-" .. buf, { clear = true })
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "WinScrolled", "BufWinEnter" }, {
        group = group,
        buffer = buf,
        callback = function()
            schedule(buf)
        end,
    })
    api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = buf,
        callback = function()
            M.disable(buf)
        end,
    })
    refresh(buf)
end

--- Turn the highlighter OFF for a buffer: clear its marks, autocmds and timer.
---@param buf integer
---@return nil
function M.disable(buf)
    buf = buf or api.nvim_get_current_buf()
    enabled[buf] = nil
    if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        pcall(api.nvim_del_augroup_by_name, "lvim-color-picker-hl-" .. buf)
    end
    local t = timers[buf]
    if t then
        t:stop()
        t:close()
        timers[buf] = nil
    end
end

--- Toggle the highlighter for a buffer.
---@param buf integer
---@return nil
function M.toggle(buf)
    buf = buf or api.nvim_get_current_buf()
    if enabled[buf] then
        M.disable(buf)
    else
        M.enable(buf)
    end
end

--- Flush the cached groups (they carry literal colors a theme swap strands) and repaint every
--- enabled buffer — wired to ColorScheme by init.
---@return nil
function M.on_colorscheme()
    groups = {}
    for buf in pairs(enabled) do
        if api.nvim_buf_is_valid(buf) then
            refresh(buf)
        end
    end
end

--- Install the FileType autocmd that auto-enables the highlighter in the configured filetypes, and
--- the ColorScheme flush. Attaches to already-open matching buffers too.
---@return nil
function M.setup()
    local set = {}
    for _, ft in ipairs(config.highlighter.auto or {}) do
        set[ft] = true
    end
    local group = api.nvim_create_augroup("lvim-color-picker-highlighter", { clear = true })
    api.nvim_create_autocmd("FileType", {
        group = group,
        callback = function(ev)
            if set[vim.bo[ev.buf].filetype] then
                M.enable(ev.buf)
            end
        end,
    })
    api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            M.on_colorscheme()
        end,
    })
    for _, buf in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(buf) and set[vim.bo[buf].filetype] then
            M.enable(buf)
        end
    end
end

return M
