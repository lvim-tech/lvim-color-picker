# lvim-color-picker

Three color tools for the **lvim-tech** set in one plugin: an interactive **picker** (a slider
panel on the lvim-ui chassis), a **converter** that cycles a color literal between hex / `rgb()` /
`hsl()`, and an inline **highlighter** that paints color literals in the buffer — plus a `p` action
inside the picker that inserts straight from the live **lvim-utils** palette.

All three share one pure parse/convert/format core (`lib.lua`): `#rgb`, `#rrggbb`, `#rrggbbaa`,
`rgb()/rgba()`, `hsl()/hsla()`, `0x`-hex and (gated) CSS named colors, with stable RGB⇄HSL
round-trips.

## Requirements

Requires **Neovim >= 0.10**, [lvim-ui](https://github.com/lvim-tech/lvim-ui) (the picker panel + the
palette select) and [lvim-utils](https://github.com/lvim-tech/lvim-utils) (the panel accents + the
live palette the `p` action draws from).

## Installation

### lvim-installer (recommended)

```vim
:LvimInstaller plugins
```

lvim-installer installs plugins through Neovim's built-in `vim.pack`, so no external plugin manager
is needed.

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/lvim-tech/lvim-ui" },
    { src = "https://github.com/lvim-tech/lvim-color-picker" },
})
require("lvim-color-picker").setup({})
```

## Picker

```vim
:LvimColorPicker          " or :LvimColorPicker pick
```

Opens a centered slider panel seeded from the color under the cursor (else the config default). Keys
inside the panel:

| Key | Action |
| --- | --- |
| `j` / `k` (or `↓`/`↑`) | move between the sliders (R/G/B, H/S/L, C/M/Y/K, +A) |
| `h` / `l` | step the focused channel −1 / +1 |
| `H` / `L` | step −5 / +5 |
| `<C-h>` / `<C-l>` | step −10 / +10 |
| `=` | enter an exact value for the channel (lvim-ui input) |
| `m` | cycle the `[M]ode` / slider model (`rgb` → `hsl` → `cmyk`) |
| `o` | cycle the `[O]utput` syntax (`hex` → `0x` → `rgb` → `hsl` → `cmyk`) |
| `a` | toggle the alpha (`A`) slider on / off |
| `<CR>` | insert / replace at the cursor (the seeded literal's span) |
| `y` | yank the formatted color |
| `p` | insert from the live lvim-utils palette (`ui.select`) |
| `g?` | the keymap **cheatsheet** (also a `help` chip on the footer bar) |
| `q` / `<Esc>` | cancel |

**Mode and Output are independent** — `m` only changes which sliders you edit, `o` only the inserted
format. The bracketed letter in the `[M]ode` / `[O]utput` titles is the toggle key.

**Mouse:** left-click a point on a slider track to set that channel to the clicked position (the
handle jumps there and the preview updates live, exactly like the step keys); clicking a slider row
also focuses it. Click a `[M]ode` / `[O]utput` chip to select it directly. The footer actions are
click targets too. A click is a no-op while `'mouse'` is empty.

Each slider is a **gradient** — every cell is painted with the actual color at that point (so the `H`
bar is a real rainbow), a hollow diamond `◊` marks the current value. Top to bottom: a full-width
**preview swatch** of the current color (composited over the theme bg by its alpha); the `[M]ode` /
`[O]utput` titles; the two button rows split 50/50 with a `│` between them; then the sliders. On open,
the mode + output are seeded from the format of the literal under the cursor — so a numeric `0xRRGGBB`
Lua literal seeds the `0x` output and inserts back as `0x…` (it round-trips, never rewritten to `#…`).

## Converter

```vim
:LvimColorPicker convert
```

Rewrites the color literal under the cursor in the **next** syntax of `convert_cycle`
(`hex` → `rgb()` → `hsl()` → …), preserving alpha. Dot-repeatable — map the `<Plug>` and press `.`:

```lua
vim.keymap.set("n", "<leader>cc", "<Plug>(lvim-color-picker-convert)", { desc = "Cycle color format" })
```

## Highlighter

```vim
:LvimColorPicker highlight        " toggle for the current buffer
:LvimColorPicker highlight on
:LvimColorPicker highlight off
```

Paints color literals in the visible lines (only the on-screen range is scanned, so a large file
stays fast). Auto-enables in `highlighter.auto` filetypes. Style:

- `bg` — tint the literal's background (fg auto for contrast)
- `fg` — color the literal's text
- `virtual` — a swatch chip before the literal

Per-color highlight groups are created lazily, cached, and flushed on `:colorscheme` change. CSS
named-color matching is off by default (it collides with ordinary words) — enable `highlighter.named`
in css/scss/html.

## Default configuration

The full default `setup()` options, kept in sync with `lua/lvim-color-picker/config.lua`:

```lua
require("lvim-color-picker").setup({
    -- the slider panel
    picker = {
        mode = "rgb", -- "rgb" | "hsl" | "cmyk": which sliders it opens with
        output = "hex", -- "hex" | "hex0x" | "rgb" | "hsl" | "cmyk": the syntax it inserts/yanks ("hex0x" = the numeric 0xRRGGBB Lua literal)
        alpha = "auto", -- "auto"/true show the A slider (auto emits alpha only when < 1 or the source had it); false hides it
    },
    -- the slider panel's LIVE keys (the `g?` cheatsheet is built from this table)
    keys = {
        help = "g?", -- the keymap CHEATSHEET (also a `help` chip on the footer bar)
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
    -- the inline highlighter
    highlighter = {
        auto = { "css", "scss", "sass", "less", "html", "conf", "lua" },
        style = "bg", -- "bg" | "fg" | "virtual"
        named = false, -- match CSS named colors (collides with words — enable per ft)
        chip_icon = "󰝤 ", -- the `virtual` style's swatch glyph (trailing space = gap)
    },
    -- the converter rotation (add "hex0x" to keep numeric 0xRRGGBB literals through the cycle)
    convert_cycle = { "hex", "rgb", "hsl" },
})
```

## Health

`:checkhealth lvim-color-picker` reports the lvim-ui / lvim-utils dependency state and the configured
picker / highlighter / converter settings.

## License

BSD-3-Clause © lvim-tech
