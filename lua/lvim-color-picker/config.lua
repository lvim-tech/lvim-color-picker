-- lvim-color-picker.config: the live configuration table for the three tools (picker / converter /
-- highlighter). setup() merges user overrides into THIS table in place, so every
-- require("lvim-color-picker.config") reader sees the effective values (the highlighter reads its
-- style/auto list live so the control center can flip them without a restart).
--
---@module "lvim-color-picker.config"

---@class LvimColorPickerPicker
---@field mode   "rgb"|"hsl"|"cmyk"       Which sliders the panel opens with (`m` cycles rgb→hsl→cmyk)
---@field output "hex"|"hex0x"|"rgb"|"hsl"|"cmyk" The output syntax the panel inserts/yanks in (`o` cycles it; `hex0x` = the numeric `0xRRGGBB` Lua literal)
---@field alpha  "auto"|boolean    "auto"/true = show the A slider (auto emits alpha only when < 1 or the source had it; true always emits); false = no A slider

---@class LvimColorPickerHighlighter
---@field auto  string[]           Filetypes the inline highlighter auto-enables in
---@field style "bg"|"fg"|"virtual" How a color literal is painted (background / foreground / a chip before it)
---@field named boolean            Match CSS named colors (off outside css/scss/html is safest — they collide with words)
---@field chip_icon string          The swatch glyph the `virtual` style paints before the literal (Nerd Font; trailing space = gap)

---@class LvimColorPickerKeys
---@field help        string  Open the keymap cheatsheet (the set-wide `g?` chord)
---@field dec1        string  Step the focused channel down by 1
---@field inc1        string  Step the focused channel up by 1
---@field dec5        string  Step the focused channel down by 5
---@field inc5        string  Step the focused channel up by 5
---@field dec10       string  Step the focused channel down by 10
---@field inc10       string  Step the focused channel up by 10
---@field next_channel string  Focus the next slider
---@field prev_channel string  Focus the previous slider
---@field cycle_mode  string  Cycle the SLIDERS: rgb → hsl → cmyk
---@field cycle_output string  Cycle the OUTPUT syntax: hex → rgb → hsl → cmyk
---@field toggle_alpha string  Show / hide the alpha (A) slider
---@field set_value   string  Type an exact value for the focused channel
---@field insert      string  Insert the color at the cursor (footer button)
---@field yank        string  Yank the color (footer button)
---@field palette     string  Open the palette picker (footer button)
---@field close       string  Close the panel (footer button)

---@class LvimColorPickerConfig
---@field picker        LvimColorPickerPicker
---@field keys          LvimColorPickerKeys  The picker panel's keymaps (channels, cycles, footer, the cheatsheet)
---@field highlighter   LvimColorPickerHighlighter
---@field convert_cycle ("hex"|"hex0x"|"rgb"|"hsl")[]  The order the converter rotates a literal through (add `hex0x` to keep numeric `0xRRGGBB` literals)

---@type LvimColorPickerConfig
return {
    -- The slider panel: which channels it opens with, what syntax it inserts, and whether the alpha
    -- slider appears (auto = only when the seeded color carried an alpha channel).
    picker = {
        mode = "rgb",
        output = "hex",
        alpha = "auto",
    },
    -- The slider panel's LIVE keys — the channel stepping (three step sizes on the same axis), the mode /
    -- output cycles, the footer actions and the cheatsheet chord. The `g?` help window is built from THIS
    -- table, so a rebind shows up in it.
    keys = {
        help = "g?", -- the set-wide cheatsheet chord (the panel owns the `g` prefix — see lvim-ui)
        dec1 = "h",
        inc1 = "l",
        dec5 = "H",
        inc5 = "L",
        dec10 = "<C-h>",
        inc10 = "<C-l>",
        next_channel = "j",
        prev_channel = "k",
        cycle_mode = "m",
        cycle_output = "o",
        toggle_alpha = "a",
        set_value = "=",
        insert = "<CR>",
        yank = "y",
        palette = "p",
        close = "q",
    },
    -- The inline highlighter: a decoration provider paints color literals in the visible lines. `bg`
    -- tints the literal's background (fg auto-chosen for contrast), `fg` colors the text, `virtual`
    -- shows a swatch chip before it. Named-color matching is off by default (collides with words).
    highlighter = {
        auto = { "css", "scss", "sass", "less", "html", "conf", "lua" },
        style = "bg",
        named = false,
        -- The swatch glyph the `virtual` style paints before the literal (Nerd Font). Trailing space = gap.
        chip_icon = "󰝤 ",
    },
    -- The converter rotation: `:LvimColorPicker convert` rewrites the literal under the cursor in the
    -- NEXT syntax of this list, wrapping around.
    convert_cycle = { "hex", "rgb", "hsl" },
}
