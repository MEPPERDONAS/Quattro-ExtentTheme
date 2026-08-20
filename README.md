# Theme Extend

![Theme Extend preview](preview.png)

Bar widget for Omarchy that extends your theme color control: choose the **border color (Hyprland)**, **bar text color**, and **bar background color** directly from a color picker with all colors from your active theme.

## Features

- **Borders Color**: select a color and write it to the `hyprland.lua` file in your theme state (`active_border_color`), applying it to active window and group borders.
- **Bar Text**: change the bar text color (`[bar] text` in `shell.toml`).
- **Bar Background**: change the bar background color (`[bar] background` and `[popup] background`  in `shell.toml`).
- **Built-in hero**: displays the active theme name and three action buttons with tooltips:
  - `Switch Theme` — opens the Omarchy theme selector.
  - `Open Image Picker` — opens the Omarchy background image selector.
  - `Reset Bar Colors` — clears the custom `[bar]` background/text overrides written by the plugin so the bar falls back to the active theme defaults.
- **Theme swatches**: all color palettes are read from the active theme's `colors.toml` (the palette for whichever theme is currently active in Omarchy) and displayed in grids, with the currently selected color marked by an accent border.
- **Shell-styled tooltips**: each swatch shows the color name with the same tooltip style as the hero buttons.
- **Keyboard navigation** within color grids (the "Borders Color" and "Bar Background" sections).

## Install

```bash
omarchy plugin add https://github.com/MEPPERDONAS/Quattro-ExtentTheme.git --enable
```

Then place the widget in the bar:

```bash
omarchy bar put famas.theme-extend
```

The widget appears as a small palette icon in the bar. Move it if you want:

```bash
omarchy bar move famas.theme-extend --section center
```

You can also validate it with:

```bash
omarchy plugin validate famas.theme-extend
```

### Updating

```bash
omarchy plugin update famas.theme-extend
omarchy restart shell
```

### Removing it

```bash
omarchy plugin remove famas.theme-extend
```

That removes the plugin and its bar entry. The theme files it edits (`hyprland.lua` and `shell.toml`) remain in your Omarchy config, since they are part of your personal theme setup and not managed by the plugin itself.

## Usage

Click the palette icon (󰏘) in the bar to open the panel. Three sections are displayed, and the hero includes the extra reset action next to the theme switcher and image picker. The swatches are always generated from the `colors.toml` of the currently active theme, so when you switch themes the palette updates automatically.

1. **Borders Color** — click a swatch to apply the color to Hyprland active borders. The swatch that matches the color written in `hyprland.lua` as `active_border_color` appears highlighted.
2. **Bar Text** — click a swatch to change the bar text color.
3. **Bar Background** — click a swatch to change the bar background color.
4. **Quick actions** — use `Switch Theme`, `Open Image Picker`, or `Reset Bar Colors` to restore the bar to the theme defaults.

Hover over any swatch to see its tooltip with the color name.

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

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
