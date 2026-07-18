-- lvim-color-picker.picker: the interactive slider panel — the third tool. Built on the canonical
-- lvim-ui surface chassis (a centered, themed float; never a raw window): one block PROVIDER renders
-- a full-width preview swatch, the mode/output columns and the sliders, and a footer BAR carries the
-- insert / yank / palette / cancel actions. Each slider is a GRADIENT of full blocks — every cell is
-- FG-painted with the actual colour at that point (so the H bar is a real rainbow), a hollow diamond
-- `◊` marking the current value (the ccc approach). The panel buffer owns the (hidden) cursor; its
-- row selects the active channel, `h`/`l` step ±1, `H`/`L` ±5, `<C-h>`/`<C-l>` ±10, `=` an exact value,
-- `m` cycles the slider model (rgb → hsl → cmyk), `o` the output syntax, `a` toggles the A slider —
-- the model / alpha changes the channel count, so the panel resizes (relayout). RGB is authoritative;
-- the HSL and CMYK views are synced on each edit so repeated steps do not drift.
--
---@module "lvim-color-picker.picker"

local api = vim.api

local config = require("lvim-color-picker.config")
local lib = require("lvim-color-picker.lib")
local surface = require("lvim-ui.surface")

local ok_uc, uc = pcall(require, "lvim-utils.colors")

local M = {}

--- The slider is a gradient of full blocks (each cell FG-colored by the color at that point, the ccc
--- approach), with a hollow diamond marking the current value.
local BAR, POINT = "█", "◊"
--- 1-based panel row of the first slider — the content is: preview(1), blank(2), [M]ode/[O]utput
--- titles(3), the button rows(4), blank(5), then the sliders.
local SLIDER_BASE = 6

--- Paint one gradient cell's highlight group, keyed by its POSITION (row + cell) rather than its
--- colour, and redefine it in place each render. Positional names bound the group set to the panel
--- geometry (≈ rows × cells), so dragging a slider through the colour space reuses the same handful
--- of groups instead of minting a new global group per distinct colour (which never got freed and
--- grew without bound over an interactive session). `nvim_set_hl` on an existing name overwrites it.
---@param rowidx integer  1-based panel row of the slider
---@param cell integer    1-based cell inside the track
---@param color LvimColor the gradient colour at this cell
---@param handle boolean  true for the `◊` value cell (bg-painted + contrast fg), false for a track cell (fg only)
---@return string  the group name to attach to the cell
local function cell_group(rowidx, cell, color, handle)
    local name = ("LvimColorPickerCell_%d_%d"):format(rowidx, cell)
    if handle then
        -- the handle cell: the gradient colour dimmed 50% as bg (so the ◊ reads AND the colour shows
        -- through), a contrast fg so the diamond stays visible over it
        local dark = { r = color.r * 0.5, g = color.g * 0.5, b = color.b * 0.5 }
        api.nvim_set_hl(0, name, {
            bg = lib.format(dark, "hex"),
            fg = lib.luminance(dark) > 0.5 and "#000000" or "#ffffff",
        })
    else
        api.nvim_set_hl(0, name, { fg = lib.format({ r = color.r, g = color.g, b = color.b }, "hex") })
    end
    return name
end

--- The [M]ode slider-model chips and the [O]utput syntax chips (label text + value). Module-level so
--- the panel WIDTH (size()) and the RENDER agree on the chip geometry — adding a chip widens the panel
--- to keep the columns aligned. `hex0x` ("0x") is an OUTPUT-only syntax (the numeric Lua/Neovim literal
--- `0xRRGGBB`, so a `0x…` config value edited by the picker round-trips as `0x…`); it is rgb in base-16
--- with nothing extra to slide, so it is never a slider MODE.
local SEP = 1
---@type { t: string, v: "rgb"|"hsl"|"cmyk" }[]
local MODE_BTNS = { { t = " rgb ", v = "rgb" }, { t = " hsl ", v = "hsl" }, { t = " cmyk ", v = "cmyk" } }
---@type { t: string, v: "hex"|"hex0x"|"rgb"|"hsl"|"cmyk" }[]
local OUT_BTNS = {
    { t = " hex ", v = "hex" },
    { t = " 0x ", v = "hex0x" },
    { t = " rgb ", v = "rgb" },
    { t = " hsl ", v = "hsl" },
    { t = " cmyk ", v = "cmyk" },
}

--- Total display width of a chip group (each chip is ASCII, so bytes == display cells) + the SEP
--- between chips.
---@param btns { t: string }[]
---@return integer
local function group_width(btns)
    local total = 0
    for i, b in ipairs(btns) do
        total = total + #b.t + (i > 1 and SEP or 0)
    end
    return total
end

--- The panel content width: 2-col left margin + [M]ode group + 1 space + │ + 1 space + [O]utput group
--- + 2-col right margin (= 2 + mode + 5 + output). Derived from the chip geometry so the layout stays
--- aligned when a chip is added/removed.
---@return integer
local function panel_width()
    return 2 + group_width(MODE_BTNS) + 5 + group_width(OUT_BTNS)
end

---@class LvimColorPickerState
---@field color LvimColor          authoritative RGB (+ optional alpha)
---@field hsl { h: number, s: number, l: number }  the HSL view (h 0..360, s/l 0..100)
---@field cmyk { c: number, m: number, y: number, k: number }  the CMYK view (each 0..100)
---@field mode "rgb"|"hsl"|"cmyk"
---@field output "hex"|"hex0x"|"rgb"|"hsl"|"cmyk"
---@field has_alpha boolean          whether the A slider is shown
---@field source_had_alpha boolean   the seeded literal carried an alpha channel
---@field always_emit_alpha boolean  config alpha = true: always write the alpha channel
---@field span { row: integer, s: integer, e: integer }|nil  the literal under the cursor to replace
---@field src_buf integer          the buffer the picker was opened from
---@field src_win integer          the window to insert/replace into

-- Seeded with a valid default so every accessor is total (M.open reassigns it per invocation); never
-- nil, so no per-field guard is needed.
---@type LvimColorPickerState
local st = {
    color = { r = 0, g = 0, b = 0 },
    hsl = { h = 0, s = 0, l = 0 },
    cmyk = { c = 0, m = 0, y = 0, k = 100 },
    mode = "rgb",
    output = "hex",
    has_alpha = false,
    source_had_alpha = false,
    always_emit_alpha = false,
    span = nil,
    src_buf = 0,
    src_win = 0,
}
---@type table  the live surface panel handle (set in the provider's keys())
local pan = nil
---@type fun(resize?: boolean)|nil  redraw hook set by M.open: repaints the preview header band + the
--- content (and re-lays-out when the channel count changed). Called wherever the colour/mode changes.
local redraw = nil
---@type table<integer, integer>  panel row (1-based) → channel index
local row_channel = {}
---@type table<integer, { label_dw: integer, cells_n: integer, ch_idx: integer }>  slider row (1-based) →
--- its track geometry, in DISPLAY columns (label width + cell count), for mouse hit-testing a click on the
--- track. Display columns (not bytes) because the active-row label ` ▸R◂ ` is multibyte while an inactive
--- `  R  ` is ASCII — same 5 cells, different byte width — so a byte offset would shift when the row activates.
local slider_geom = {}
---@type { row: integer, dc0: integer, dc1: integer, set: fun() }[]  the [M]ode / [O]utput chip click targets
--- of the LAST render (row 1-based; dc0/dc1 = DISPLAY column range; `set` applies that chip).
local chip_geom = {}
---@type "rgb"|"hsl"|"cmyk"|nil  the last-used slider mode, remembered across picker sessions (nil = use config)
local last_mode = nil
---@type "hex"|"hex0x"|"rgb"|"hsl"|"cmyk"|nil  the last-used output syntax, remembered across sessions
local last_output = nil

--- Recompute the HSL view from the authoritative RGB.
---@return nil
local function sync_hsl()
    local h, s, l = lib.rgb_to_hsl(st.color.r, st.color.g, st.color.b)
    st.hsl = { h = h, s = s * 100, l = l * 100 }
end

--- Recompute RGB from the HSL view (after an H/S/L edit).
---@return nil
local function sync_rgb()
    st.color.r, st.color.g, st.color.b = lib.hsl_to_rgb(st.hsl.h, st.hsl.s / 100, st.hsl.l / 100)
end

--- Recompute the CMYK view (each 0..100) from the authoritative RGB.
---@return nil
local function sync_cmyk()
    local c, m, y, k = lib.rgb_to_cmyk(st.color.r, st.color.g, st.color.b)
    st.cmyk = { c = c * 100, m = m * 100, y = y * 100, k = k * 100 }
end

--- Recompute RGB from the CMYK view (after a C/M/Y/K edit) and re-sync HSL.
---@return nil
local function sync_rgb_from_cmyk()
    st.color.r, st.color.g, st.color.b =
        lib.cmyk_to_rgb(st.cmyk.c / 100, st.cmyk.m / 100, st.cmyk.y / 100, st.cmyk.k / 100)
    sync_hsl()
end

--- The theme panel background as an RGB color (alpha is composited over it).
---@return LvimColor
local function bg_color()
    local bg = lib.parse_at((ok_uc and uc.bg) or "#1e1e1e", 0)
    return (bg and bg.color) or { r = 30, g = 30, b = 30 }
end

--- Composite `col` over the theme bg by `a` (0..1) — a terminal cell cannot be semi-transparent, so
--- alpha is simulated by blending toward the background.
---@param col LvimColor
---@param a number
---@return LvimColor
local function composite(col, a)
    if a >= 1 then
        return { r = col.r, g = col.g, b = col.b }
    end
    local br = bg_color()
    return {
        r = col.r * a + br.r * (1 - a),
        g = col.g * a + br.g * (1 - a),
        b = col.b * a + br.b * (1 - a),
    }
end

---@class LvimColorPickerChannel
---@field key string           the channel letter shown in the label (R/G/B/H/S/L/C/M/Y/K/A)
---@field min number
---@field max number
---@field get fun(): number
---@field set fun(v: number)
---@field at fun(value: number): LvimColor  the color when THIS channel is set to `value` (the gradient at a point)

--- The active channels for the current mode (+ alpha when shown). Each carries `at(value)` — the
--- color with this channel replaced by `value` — so a slider's track can be painted as a gradient of
--- the actual colors it spans (the ccc approach).
---@return LvimColorPickerChannel[]
local function channels()
    local list
    if st.mode == "hsl" then
        list = {
            {
                key = "H",
                min = 0,
                max = 360,
                get = function()
                    return st.hsl.h
                end,
                set = function(v)
                    st.hsl.h = v % 360
                    sync_rgb()
                end,
                at = function(value)
                    -- The HUE bar is a full rainbow at a FIXED vivid reference (S=100%, L=50%): rendered at the
                    -- current S/L it would wash out to white/black at extreme lightness (e.g. a near-white color's
                    -- hue bar became solid white) and stop being a rainbow. The handle still marks the true H.
                    local r, g, b = lib.hsl_to_rgb(value, 1, 0.5)
                    return { r = r, g = g, b = b }
                end,
            },
            {
                key = "S",
                min = 0,
                max = 100,
                get = function()
                    return st.hsl.s
                end,
                set = function(v)
                    st.hsl.s = v
                    sync_rgb()
                end,
                at = function(value)
                    -- The SATURATION bar is drawn at a fixed readable L=50% (gray → full colour at the current
                    -- hue): at the current L it collapses to white/black for a light/dark colour, hiding the
                    -- gradient. The handle still marks the true S.
                    local r, g, b = lib.hsl_to_rgb(st.hsl.h, value / 100, 0.5)
                    return { r = r, g = g, b = b }
                end,
            },
            {
                key = "L",
                min = 0,
                max = 100,
                get = function()
                    return st.hsl.l
                end,
                set = function(v)
                    st.hsl.l = v
                    sync_rgb()
                end,
                at = function(value)
                    local r, g, b = lib.hsl_to_rgb(st.hsl.h, st.hsl.s / 100, value / 100)
                    return { r = r, g = g, b = b }
                end,
            },
        }
    elseif st.mode == "cmyk" then
        local mk = function(k, field)
            return {
                key = k,
                min = 0,
                max = 100,
                get = function()
                    return st.cmyk[field]
                end,
                set = function(v)
                    st.cmyk[field] = v
                    sync_rgb_from_cmyk()
                end,
                at = function(value)
                    local c = { c = st.cmyk.c, m = st.cmyk.m, y = st.cmyk.y, k = st.cmyk.k }
                    c[field] = value
                    local r, g, b = lib.cmyk_to_rgb(c.c / 100, c.m / 100, c.y / 100, c.k / 100)
                    return { r = r, g = g, b = b }
                end,
            }
        end
        list = { mk("C", "c"), mk("M", "m"), mk("Y", "y"), mk("K", "k") }
    else
        local mk = function(k, field)
            return {
                key = k,
                min = 0,
                max = 255,
                get = function()
                    return st.color[field]
                end,
                set = function(v)
                    st.color[field] = v
                    sync_hsl()
                end,
                at = function(value)
                    local c = { r = st.color.r, g = st.color.g, b = st.color.b }
                    c[field] = value
                    return c
                end,
            }
        end
        list = { mk("R", "r"), mk("G", "g"), mk("B", "b") }
    end
    if st.has_alpha then
        list[#list + 1] = {
            key = "A",
            min = 0,
            max = 100,
            get = function()
                return (st.color.a or 1) * 100
            end,
            set = function(v)
                st.color.a = math.max(0, math.min(1, v / 100))
            end,
            at = function(value)
                return composite(st.color, value / 100)
            end,
        }
    end
    return list
end

--- The formatted color string in the current output syntax. A fully-opaque alpha is dropped unless
--- the source literal carried one (or `alpha = true` forces it), so a plain `#ff8800` stays
--- `#ff8800` while `#ff880080` round-trips.
---@return string
local function formatted()
    local col = st.color
    if col.a ~= nil and col.a >= 1 and not st.always_emit_alpha and not st.source_had_alpha then
        col = { r = col.r, g = col.g, b = col.b }
    end
    return lib.format(col, st.output)
end

--- The color to PAINT the preview swatch with: the RGB composited over the panel background by its
--- alpha, so lowering the A slider visibly fades the swatch toward the theme bg.
---@return LvimColor
local function preview_color()
    return composite(st.color, (st.has_alpha and st.color.a) or 1)
end

--- Build the panel lines + highlight spans. Records the row→channel map for the key handlers.
---@param width integer
---@return string[], table[]
local function render(width)
    row_channel = {}
    slider_geom = {}
    chip_geom = {}
    local lines, hls = {}, {}
    local function pad(s, w)
        return s .. string.rep(" ", math.max(0, w - vim.fn.strdisplaywidth(s)))
    end

    -- preview swatch (row 1) — the colour composited over the theme bg by its alpha; full-width strip
    local pv = preview_color()
    api.nvim_set_hl(0, "LvimColorPickerPreview", {
        bg = lib.format(pv, "hex"),
        fg = lib.luminance(pv) > 0.5 and "#000000" or "#ffffff",
        bold = true,
    })
    local prev = pad("  " .. formatted(), width)
    lines[1] = prev
    hls[#hls + 1] = { 0, 0, #prev, "LvimColorPickerPreview" }
    lines[2] = ""

    -- 50/50 title + button rows, drawn on the plain panel bg (colour ONLY on the labels + chips).
    -- `set_cells` places single-display-width glyphs into a per-column grid; `build_row` concatenates
    -- them, accumulating byte offsets so a multibyte │ / chip does not desync the highlights.
    local function center(x0, w, len)
        return x0 + math.max(0, math.floor((w - len) / 2))
    end
    local function set_cells(cells, x, text, hlg)
        for i, ch in ipairs(vim.fn.split(text, "\\zs")) do
            cells[x + i - 1] = { ch = ch, hl = hlg }
        end
    end
    local function build_row(rowidx, cells)
        local parts, bpos = {}, 0
        for col = 0, width - 1 do
            local cell = cells[col]
            local ch = (cell and cell.ch) or " "
            if cell and cell.hl then
                hls[#hls + 1] = { rowidx, bpos, bpos + #ch, cell.hl }
            end
            parts[#parts + 1] = ch
            bpos = bpos + #ch
        end
        return table.concat(parts)
    end
    -- [M]ode group hugs the LEFT (2-space margin); [O]utput hugs the RIGHT (2-space margin); a │ divider
    -- sits ONE plain space after the mode group (and one before the output). Titles centered over each.
    -- Build the display chip lists from the module chip defs, marking the current mode / output `on`.
    local mode_btns = {}
    for _, b in ipairs(MODE_BTNS) do
        mode_btns[#mode_btns + 1] = { t = b.t, v = b.v, on = st.mode == b.v }
    end
    local out_btns = {}
    for _, b in ipairs(OUT_BTNS) do
        out_btns[#out_btns + 1] = { t = b.t, v = b.v, on = st.output == b.v }
    end
    local mode_w, out_w = group_width(MODE_BTNS), group_width(OUT_BTNS)
    local mode_x = 2 -- 2-space left margin
    local sep_col = mode_x + mode_w + 1 -- the │ one plain space after the mode group
    local out_x = sep_col + 2 -- output one plain space after the │ (its right edge = the 2-space margin)
    -- titles (row 3): each centered over its own group
    local tcells = {}
    set_cells(tcells, center(mode_x, mode_w, #"[M]ode"), "[M]ode", "LvimColorPickerColTitle")
    set_cells(tcells, center(out_x, out_w, #"[O]utput"), "[O]utput", "LvimColorPickerColTitle")
    lines[3] = build_row(2, tcells)
    -- buttons (row 4)
    local bcells = {}
    -- `kind` = "mode" | "output": clicking a chip applies that value directly (a superset of the m/o cycle
    -- keys). `x` is a DISPLAY column and every chip glyph is single-width, so [x, x+#b.t) is its display span.
    local function emit_group(btns, x, kind)
        for i, b in ipairs(btns) do
            if i > 1 then
                x = x + SEP
            end
            set_cells(bcells, x, b.t, b.on and "LvimColorPickerChipOn" or "LvimColorPickerChipOff")
            chip_geom[#chip_geom + 1] = {
                row = 4, -- the button row (1-based)
                dc0 = x,
                dc1 = x + #b.t,
                set = function()
                    if kind == "mode" then
                        if st.mode ~= b.v and redraw then
                            st.mode = b.v
                            last_mode = st.mode
                            redraw(true) -- the channel count can change (cmyk has 4) → resize + repaint
                        end
                    elseif st.output ~= b.v and redraw then
                        st.output = b.v
                        last_output = st.output
                        redraw(false)
                    end
                end,
            }
            x = x + #b.t
        end
    end
    emit_group(mode_btns, mode_x, "mode")
    emit_group(out_btns, out_x, "output")
    bcells[sep_col] = { ch = "│", hl = "LvimColorPickerColTitle" }
    lines[4] = build_row(3, bcells)
    lines[5] = ""

    -- sliders — the ACTIVE row (the hidden cursor's row) frames its channel letter with small inward
    -- pointers (▸R◂) in the active (yellow) label colour, so the focused channel is visible without a
    -- hardware cursor. Active and inactive labels are both 5 display cells, so the tracks stay aligned.
    -- The active row is CLAMPED into the slider range, so the marker never vanishes when the cursor
    -- lands on a non-slider row (a click on the chrome).
    local base = SLIDER_BASE
    local raw = (pan and pan.win and api.nvim_win_is_valid(pan.win)) and api.nvim_win_get_cursor(pan.win)[1] or base
    local cur = math.max(base, math.min(raw, base + #channels() - 1))
    for i, chn in ipairs(channels()) do
        local rowidx = base + i - 1
        row_channel[rowidx] = i
        local active = rowidx == cur
        local v = chn.get()
        -- active row: the channel letter is FLUSH-framed by small inward pointers (▸R◂); inactive
        -- rows pad to the same 5-cell width so R stays column-aligned and the tracks line up
        local label = active and (" ▸" .. chn.key .. "◂ ") or ("  " .. chn.key .. "  ")
        local ls = #label
        -- the track fills to the right, reserving the last 7 columns for the value: 2 spaces + 3-wide
        -- number + 2 spaces
        local label_dw = vim.fn.strdisplaywidth(label)
        local cells_n = math.max(1, width - label_dw - 7)
        -- Record the track geometry (DISPLAY columns) so a click on this row maps to a cell → a value.
        slider_geom[rowidx] = { label_dw = label_dw, cells_n = cells_n, ch_idx = i }
        local point = math.max(1, math.min(cells_n, math.floor((v - chn.min) / (chn.max - chn.min) * cells_n + 0.5)))
        -- each cell is a glyph (█ or ◊), all 3 bytes wide, so the byte layout is uniform
        local cells = {}
        for cell = 1, cells_n do
            cells[cell] = (cell == point) and POINT or BAR
        end
        local track = table.concat(cells)
        local val = ("  %3d  "):format(math.floor(v + 0.5))
        local line = pad(label .. track .. val, width)
        lines[rowidx] = line
        hls[#hls + 1] = { rowidx - 1, 0, ls, active and "LvimColorPickerLabelActive" or "LvimColorPickerLabel" }
        -- gradient: each cell FG-painted with the color at its midpoint value; the handle cell is a ◊
        -- over that colour dimmed 50% so the diamond reads AND the colour shows through. Groups are
        -- named by POSITION (cell_group) and redefined each render — a bounded set, no per-colour leak.
        for cell = 1, cells_n do
            local value = (cell - 0.5) / cells_n * (chn.max - chn.min) + chn.min
            local c0 = ls + (cell - 1) * 3
            local color = chn.at(value)
            hls[#hls + 1] = { rowidx - 1, c0, c0 + 3, cell_group(rowidx, cell, color, cell == point) }
        end
        hls[#hls + 1] = { rowidx - 1, ls + cells_n * 3, #line, "LvimColorPickerValue" }
    end
    return lines, hls
end

--- The channel index the cursor is on (or the first channel if the cursor is off the sliders).
---@return integer
local function current_channel()
    if not (pan and pan.win and api.nvim_win_is_valid(pan.win)) then
        return 1
    end
    local r = api.nvim_win_get_cursor(pan.win)[1]
    return row_channel[r] or 1
end

--- Move the panel cursor to the first slider row of channel `idx`.
---@param idx integer
---@return nil
local function focus_channel(idx)
    for row, ch in pairs(row_channel) do
        if ch == idx then
            pcall(api.nvim_win_set_cursor, pan.win, { row, 0 })
            return
        end
    end
end

--- Step the active channel by `delta` (clamped to its range) and repaint.
---@param delta number
---@return nil
local function step(delta)
    local chn = channels()[current_channel()]
    if not chn then
        return
    end
    chn.set(math.max(chn.min, math.min(chn.max, chn.get() + delta)))
    if redraw then
        redraw(false) -- the value changed → repaint the preview swatch too, not just the slider
    elseif pan and pan.refresh then
        pan.refresh()
    end
end

--- Insert (or replace the seeded span with) the formatted color into the source window, then close.
---@param close fun()
---@return nil
local function do_insert(close)
    local text = formatted()
    local buf, win = st.src_buf, st.src_win
    local span = st.span
    close()
    vim.schedule(function()
        if not api.nvim_buf_is_valid(buf) then
            return
        end
        if span then
            pcall(api.nvim_buf_set_text, buf, span.row, span.s, span.row, span.e, { text })
        else
            local cur = api.nvim_win_is_valid(win) and api.nvim_win_get_cursor(win) or { 1, 0 }
            pcall(api.nvim_buf_set_text, buf, cur[1] - 1, cur[2], cur[1] - 1, cur[2], { text })
        end
    end)
end

--- Open the palette select and insert the chosen color in the output syntax.
---@param close fun()
---@return nil
local function do_palette(close)
    local items = require("lvim-color-picker.palette").items()
    if #items == 0 then
        vim.notify("lvim-color-picker: no lvim-utils palette available", vim.log.levels.WARN)
        return
    end
    local buf, win, span, output = st.src_buf, st.src_win, st.span, st.output
    close()
    require("lvim-ui").select({
        title = "Palette",
        items = items,
        callback = function(confirmed, index)
            if not confirmed or not index then
                return
            end
            local color = items[index].color
            local text = lib.format(color, output)
            if not api.nvim_buf_is_valid(buf) then
                return
            end
            if span then
                pcall(api.nvim_buf_set_text, buf, span.row, span.s, span.row, span.e, { text })
            else
                local cur = api.nvim_win_is_valid(win) and api.nvim_win_get_cursor(win) or { 1, 0 }
                pcall(api.nvim_buf_set_text, buf, cur[1] - 1, cur[2], cur[1] - 1, cur[2], { text })
            end
        end,
    })
end

--- The output syntax a literal is written in, from its leading characters (or nil if not a color). A
--- `0x…` literal maps to "hex0x" (not "hex") so the picker seeds its output to the numeric form and
--- inserts `0x…` back — round-tripping the Lua/Neovim config literal instead of breaking it as `#…`.
---@param text string
---@return "hex"|"hex0x"|"rgb"|"hsl"|"cmyk"|nil
local function detect_format(text)
    if text:match("^0[xX]") then
        return "hex0x"
    elseif text:match("^#") then
        return "hex"
    elseif text:match("^[cC][mM][yY][kK]") then
        return "cmyk"
    elseif text:match("^[hH][sS][lL]") then
        return "hsl"
    elseif text:match("^[rR][gG][bB]") then
        return "rgb"
    end
    return nil
end

--- Open the picker, seeded from the color under the cursor (else black). The panel is centered,
--- themed and cursor-hidden; every mutation repaints through the provider.
---@return nil
-- ── the help window (the canonical cheatsheet) ───────────────────────────────

-- Key id → description, in display order. Built from the LIVE `config.keys`, so a rebind shows up.
---@type { [1]: string, [2]: string }[]
local HELP = {
    { "prev_channel", "focus the previous slider" },
    { "next_channel", "focus the next slider" },
    { "dec1", "step the channel down by 1" },
    { "inc1", "step the channel up by 1" },
    { "dec5", "step the channel down by 5" },
    { "inc5", "step the channel up by 5" },
    { "dec10", "step the channel down by 10" },
    { "inc10", "step the channel up by 10" },
    { "set_value", "type an exact value for the channel" },
    { "cycle_mode", "cycle the sliders: rgb → hsl → cmyk" },
    { "cycle_output", "cycle the output: hex → rgb → hsl → cmyk" },
    { "toggle_alpha", "show / hide the alpha slider" },
    { "insert", "insert the color at the cursor" },
    { "yank", "yank the color" },
    { "palette", "open the palette picker" },
    { "help", "this help" },
    { "close", "close the picker" },
}

--- The picker's keymap cheatsheet — the shared `lvim-ui.help` component owns the rows, the striping, the
--- colours and the window; this only supplies the plugin's LIVE keys.
local function show_help()
    local k = config.keys or {}
    local items = {}
    for _, e in ipairs(HELP) do
        local lhs = k[e[1]]
        if lhs and lhs ~= "" then
            items[#items + 1] = { lhs, e[2] }
        end
    end
    require("lvim-ui").help({
        title = "Color picker keymaps",
        items = items,
        close_keys = { k.close or "q", "<Esc>", k.help or "g?" },
    })
end

function M.open()
    local win = api.nvim_get_current_win()
    -- If a transient FLOAT is current (an LSP progress / notification popup can grab it right as the
    -- command fires), seed from the real editor window instead — otherwise the picker reads the
    -- popup's text, not the code under the cursor.
    if api.nvim_win_get_config(win).relative ~= "" then
        for _, w in ipairs(api.nvim_list_wins()) do
            if api.nvim_win_get_config(w).relative == "" then
                win = w
                break
            end
        end
    end
    local buf = api.nvim_win_get_buf(win)
    local cur = api.nvim_win_get_cursor(win)
    local line = api.nvim_buf_get_lines(buf, cur[1] - 1, cur[1], false)[1] or ""
    local hit = lib.parse_at(line, cur[2], config.highlighter.named)
    local seed = hit and hit.color or { r = 0, g = 0, b = 0 }
    -- Seed the mode + output from the FORMAT of the literal under the cursor, so opening a cmyk() (or
    -- rgb()/hsl()/#hex) picks the matching sliders and inserts in the same format by default; falls
    -- back to the remembered / configured values otherwise.
    local src_fmt = hit and detect_format(line:sub(hit.s + 1, hit.e)) or nil
    -- rgb / hsl / cmyk have matching sliders; hex AND hex0x are OUTPUT formats only (both are rgb in
    -- base-16, so there is nothing extra to slide) — so neither is ever a slider mode.
    local slider_fmt = (src_fmt ~= "hex" and src_fmt ~= "hex0x" and src_fmt or nil) --[[@as "rgb"|"hsl"|"cmyk"|nil]]
    -- The A slider is shown unless alpha is explicitly disabled (alpha = false). It is always
    -- adjustable, but the output only GAINS an alpha channel when it is meaningful — reduced below 1,
    -- or the seeded literal already carried one (alpha = true forces it always).
    local alpha_cfg = config.picker.alpha
    local has_alpha = alpha_cfg ~= false
    st = {
        color = { r = seed.r, g = seed.g, b = seed.b, a = has_alpha and (seed.a or 1) or nil },
        hsl = { h = 0, s = 0, l = 0 },
        cmyk = { c = 0, m = 0, y = 0, k = 100 },
        mode = slider_fmt or last_mode or config.picker.mode,
        output = src_fmt or last_output or config.picker.output,
        has_alpha = has_alpha,
        source_had_alpha = seed.a ~= nil,
        always_emit_alpha = alpha_cfg == true,
        span = hit and { row = cur[1] - 1, s = hit.s, e = hit.e } or nil,
        src_buf = buf,
        src_win = win,
    }
    sync_hsl()
    sync_cmyk()

    -- redraw after a colour / mode / output change: re-lay-out when the channel count moved (a mode / A
    -- toggle), then repaint — the render rebuilds the swatch, the [M]ode/[O]utput rows and the sliders.
    redraw = function(resize)
        if resize and pan and pan.frame and pan.frame.relayout then
            pcall(pan.frame.relayout)
        end
        if pan and pan.refresh then
            pan.refresh()
        end
    end

    local provider = {
        hide_cursor = true,
        size = function()
            -- width derived from the chip geometry (panel_width) so adding an [O]utput chip keeps the
            -- [M]ode / [O]utput columns aligned; height = 5 chrome rows + one row per active channel.
            return panel_width(), 5 + #channels()
        end,
        render = render,
        -- MOUSE: a left-click on a slider sets that channel to the clicked position; a click on a [M]ode /
        -- [O]utput chip selects it — mirroring the keyboard adjust (h/l steps, m/o cycles) and live-updating
        -- the preview via the same `step`/`redraw` path. The chassis has already moved the (hidden) cursor to
        -- the clicked row (so the row is focused + the ▸R◂ marker follows) and passes the 1-based `line` +
        -- 0-based byte `col`. Hit-testing is in DISPLAY columns (the row has a multibyte label / │ divider), so
        -- it maps to the exact cell. No-op off the track / any chip. `'mouse'` empty ⇒ never invoked.
        ---@param _pan table
        ---@param _st table
        ---@param line integer  1-based clicked buffer row
        ---@param col integer   0-based clicked byte column
        on_click = function(_pan, _st, line, col)
            local text = api.nvim_buf_get_lines(pan.buf, line - 1, line, false)[1] or ""
            local dcol = vim.fn.strdisplaywidth(text:sub(1, col)) -- 0-based DISPLAY column of the clicked cell
            local sg = slider_geom[line]
            if sg then
                local cell = dcol - sg.label_dw + 1 -- 1-based cell inside the track
                if cell >= 1 and cell <= sg.cells_n then
                    local chn = channels()[sg.ch_idx]
                    if chn then
                        local value = chn.min + (cell - 0.5) / sg.cells_n * (chn.max - chn.min)
                        chn.set(math.max(chn.min, math.min(chn.max, value)))
                        if redraw then
                            redraw(false)
                        end
                    end
                end
                return
            end
            for _, chip in ipairs(chip_geom) do
                if chip.row == line and dcol >= chip.dc0 and dcol < chip.dc1 then
                    chip.set()
                    return
                end
            end
        end,
        keys = function(map, p, state)
            pan = p
            local k = config.keys
            -- The close function lives on `state` (3rd arg), not the panel handle `p`.
            local close = function()
                state.close()
            end
            -- Start on the first slider so the active-row marker (▸R◂) is visible from the open.
            focus_channel(1)
            -- Repaint so the active-row marker (▸R◂) follows the (hidden) cursor as j/k move it. If the
            -- cursor lands OFF the sliders (a click on the chrome), snap it back to the LAST slider it
            -- was on — not the nearest edge — so clicking above the first bar keeps the current channel.
            local last_row = SLIDER_BASE
            api.nvim_create_autocmd("CursorMoved", {
                buffer = p.buf,
                callback = function()
                    local last = SLIDER_BASE + #channels() - 1
                    last_row = math.min(last_row, last) -- the channel count may have shrunk
                    local row = api.nvim_win_get_cursor(p.win)[1]
                    if row >= SLIDER_BASE and row <= last then
                        last_row = row
                    elseif row ~= last_row then
                        pcall(api.nvim_win_set_cursor, p.win, { last_row, 0 })
                    end
                    if p.refresh then
                        p.refresh()
                    end
                end,
            })
            local function refresh_move(delta)
                return function()
                    local n = #channels()
                    local idx = math.max(1, math.min(current_channel() + delta, n))
                    focus_channel(idx)
                end
            end
            -- h/l step the focused channel; three step sizes on the same axis (ccc's ±1/±5/±10):
            --   h/l = ±1   H/L = ±5   <C-h>/<C-l> = ±10. <C-k>/<C-j> are left to the surface — they
            -- move the focus DOWN to the footer action bar (and back).
            map(k.dec1, function()
                step(-1)
            end)
            map(k.inc1, function()
                step(1)
            end)
            map(k.dec5, function()
                step(-5)
            end)
            map(k.inc5, function()
                step(5)
            end)
            map(k.dec10, function()
                step(-10)
            end)
            map(k.inc10, function()
                step(10)
            end)
            map(k.next_channel, refresh_move(1))
            map(k.prev_channel, refresh_move(-1))
            map("<Down>", refresh_move(1))
            map("<Up>", refresh_move(-1))
            -- advance `cur` to the next entry of `cyc` (wraps)
            local function next_in(cyc, cur_val)
                for i, s in ipairs(cyc) do
                    if s == cur_val then
                        return cyc[(i % #cyc) + 1]
                    end
                end
                return cyc[1]
            end
            map(k.cycle_mode, function()
                -- Mode + Output are INDEPENDENT: `m` only cycles the sliders, `o` only the output
                st.mode = next_in({ "rgb", "hsl", "cmyk" }, st.mode)
                last_mode = st.mode
                redraw(true) -- the channel count can change (cmyk has 4) → resize + repaint header
            end)
            map(k.cycle_output, function()
                st.output = next_in({ "hex", "hex0x", "rgb", "hsl", "cmyk" }, st.output)
                last_output = st.output -- remember for the next picker session
                redraw(false)
            end)
            map(k.toggle_alpha, function()
                st.has_alpha = not st.has_alpha
                if st.has_alpha and st.color.a == nil then
                    st.color.a = 1
                end
                redraw(true) -- the A slider appears/disappears → resize + repaint
            end)
            map(k.set_value, function()
                local chn = channels()[current_channel()]
                if not chn then
                    return
                end
                require("lvim-ui").input({
                    title = chn.key .. " value",
                    default = tostring(math.floor(chn.get() + 0.5)),
                    callback = function(confirmed, value)
                        local n = confirmed and tonumber(value)
                        if n then
                            chn.set(math.max(chn.min, math.min(chn.max, n)))
                            if redraw then
                                redraw(false) -- the value changed → repaint the preview too
                            end
                        end
                    end,
                })
            end)
            -- <CR> is always SKIPPED by the footer-bar hotkeys (a content provider owns it), so the
            -- insert action is bound here. `y` and `p`, by contrast, ARE claimed by the footer bar —
            -- their real actions live in the footer button `run`s below (a provider map would be
            -- clobbered by the footer hotkey).
            map(k.insert, function()
                do_insert(close)
            end)
            map(k.help, show_help)
        end,
    }

    surface.open({
        mode = "float",
        border = surface.FRAME_BORDER,
        title = "Color picker",
        title_pos = "center",
        panel_border = "none",
        size = { width = { auto = true, max = 0.6 }, height = { auto = true, max = 0.8 } },
        close_keys = { config.keys.close, "<Esc>" },
        content = { blocks = { { id = "picker", provider = provider } } },
        footer = {
            bars = {
                surface.bar({ { "insert", "yank", "palette" }, { "help", "close" } }, {
                    -- the cheatsheet chip: the panel's keys (three step sizes, the cycles, `=`) are not
                    -- discoverable from the sliders, so the bar has to say where they are written down
                    help = { name = "help", key = config.keys.help, run = show_help },
                    insert = {
                        name = "insert",
                        key = config.keys.insert,
                        run = function(state)
                            do_insert(function()
                                state.close()
                            end)
                        end,
                    },
                    yank = {
                        name = "yank",
                        key = config.keys.yank,
                        run = function(state)
                            local text = formatted()
                            vim.fn.setreg('"', text) -- the unnamed register always works (paste with `p`)
                            pcall(vim.fn.setreg, "+", text) -- the system clipboard, if available
                            state.close()
                            vim.notify("Copied " .. text, vim.log.levels.INFO, { title = "lvim-color-picker" })
                        end,
                    },
                    palette = {
                        name = "palette",
                        key = config.keys.palette,
                        run = function(state)
                            do_palette(function()
                                state.close()
                            end)
                        end,
                    },
                    close = {
                        name = "close",
                        key = config.keys.close,
                        run = function(state)
                            state.close()
                        end,
                    },
                }),
            },
        },
    })
end

return M
