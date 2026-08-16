function parseColorsToml(text) {
  var colors = []
  var seen = {}
  var re = /^[ \t]*([A-Za-z0-9_.-]+)[ \t]*=[ \t]*["']?(#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3}))["']?/gm
  var str = String(text || "")
  var match
  while ((match = re.exec(str)) !== null) {
    var hex = match[2].toLowerCase()
    if (seen[hex]) continue
    seen[hex] = true
    colors.push({ name: match[1], hex: hex })
  }
  return colors
}

// Reads `local active_border_color = "..."` out of the theme's
// hyprland.lua and returns whichever hex it holds, if any.
function parseCurrentColor(text) {
  var match = /local[ \t]+active_border_color[ \t]*=[ \t]*["']?(#[0-9a-fA-F]{8}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{3})/.exec(String(text || ""))
  return match ? match[1].toLowerCase() : ""
}

// Reads the [bar] section out of shell.toml and returns whichever hex is
// currently set for `background` / `text`, if any. Only recognizes literal
// hex values (not role names like "foreground"), since that's all this
// plugin ever writes there; a role-name value just means "unmanaged by this
// plugin" and comes back as an empty string so no swatch shows as selected.
function parseBarColors(text) {
  var result = { background: "", text: "" }
  var str = String(text || "")
  var sectionMatch = /\[bar\]([\s\S]*?)(?:\n\[|$)/.exec(str)
  if (!sectionMatch) return result
  var body = sectionMatch[1]
  var hex = "#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})"
  var bgMatch = new RegExp("^[ \\t]*background[ \\t]*=[ \\t]*[\"']?(" + hex + ")", "m").exec(body)
  if (bgMatch) result.background = bgMatch[1].toLowerCase()
  var txMatch = new RegExp("^[ \\t]*text[ \\t]*=[ \\t]*[\"']?(" + hex + ")", "m").exec(body)
  if (txMatch) result.text = txMatch[1].toLowerCase()
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    parseColorsToml: parseColorsToml,
    parseCurrentColor: parseCurrentColor,
    parseBarColors: parseBarColors
  }
}