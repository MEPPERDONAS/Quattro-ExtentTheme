# Theme Extend

![Theme Extend preview](preview.png)

Bar widget for Omarchy that extends your theme color control: choose the **border color (Hyprland)**, **bar text color**, and **bar background color** directly from a color picker with all colors from your active theme.

## Features

- **Borders Color**: select a color and write it to the `hyprland.lua` file in your theme state (`active_border_color`), applying it to active window and group borders.
- **Bar Text**: change the bar text color (`[bar] text` in `shell.toml`).
- **Bar Background**: change the bar background color (`[bar] background` in `shell.toml`).
- **Built-in hero**: displays the active theme name and two action buttons with tooltips:
  - `Switch Theme` — opens the Omarchy theme selector.
  - `Open Image Picker` — opens the Omarchy background image selector.
- **Theme swatches**: all color palettes are read from the active theme's `colors.toml` and displayed in grids, with the currently selected color marked by an accent border.
- **Shell-styled tooltips**: each swatch shows the color name with the same tooltip style as the hero buttons.
- **Keyboard navigation** within color grids (the "Borders Color" and "Bar Background" sections).

## Installation

1. Copy the plugin folder to your Omarchy configuration:

   ```bash
   mkdir -p ~/.config/omarchy/plugins
   cp -r famas.theme-extend ~/.config/omarchy/plugins/
   ```

2. Enable the plugin:

   ```bash
   omarchy plugin enable famas.theme-extend
   ```

3. Place it in the bar (bar widget):

   ```bash
   omarchy bar put famas.theme-extend
   ```

You can also validate the plugin with `omarchy plugin validate famas.theme-extend`.

## Usage

Click the palette icon (󰏘) in the bar to open the panel. Three sections are displayed:

1. **Borders Color** — click a swatch to apply the color to Hyprland active borders. The swatch that matches the color written in `hyprland.lua` as `active_border_color` appears highlighted.
2. **Bar Text** — click a swatch to change the bar text color.
3. **Bar Background** — click a swatch to change the bar background color.

Hover over any swatch to see its tooltip with the color name.

### Keyboard

With the panel open, you can navigate with the keyboard in the enabled grids (Borders Color and Bar Background):

- `h` / `l` — move left / right.
- `j` / `k` — move down / up (row by row).
- `Enter` / `Space` — apply the focused color.
- `Tab` / `Shift+Tab` — move between panels.
- `Esc` — close.

## Modified Files

| Action | File |
| --- | --- |
| Borders Color | `~/.local/state/omarchy/current/theme/hyprland.lua` (variable `active_border_color`) |
| Bar Text / Background | `~/.config/omarchy/shell.toml` (section `[bar]`) |

If `hyprland.lua` does not exist, the plugin creates a complete template with `hl.config(...)` and a default inactive border color.

> Note: grid swatches use the colors that Omarchy writes as hexadecimal values. If `shell.toml` uses a role name (e.g. `foreground`) instead of a hex value, no swatch appears selected until you choose a color with the plugin.

## Requirements

- Omarchy (shell `quickshell`).
- Font with Nerd Fonts icons for the hero and bar button icons.
- Commands `omarchy-theme-switcher`, `omarchy-theme-set`, `omarchy-theme-bg-switcher`, and `omarchy-theme-bg-set` (included in Omarchy) for the theme and background pickers.

## Customization

Integration paths are defined as properties at the beginning of `Panel.qml` and can be adjusted:

- `omarchyStateDir` — active theme state directory.
- `userShellPath` — path to the user's `shell.toml`.

## License

Personal use. Distributed as-is, without warranties.
