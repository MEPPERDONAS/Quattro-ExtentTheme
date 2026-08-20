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

function parseCurrentColor(text) {
  var match = /#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})/.exec(String(text || ""))
  return match ? match[0].toLowerCase() : ""
}

// Reads the [bar] section out of shell.toml and returns whichever hex is
// currently set for `background` / `text`, if any. Only recognizes literal
// hex values (not role names like "foreground"), since that's all this
// plugin ever writes there; a role-name value just means "unmanaged by this
// plugin" and comes back as an empty string so no swatch shows as selected.
// WCAG 2.x relative luminance of a hex color (alpha is ignored).
function relativeLuminance(hex) {
  var h = String(hex || "").replace(/^#/, "")
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  if (h.length > 6) h = h.substring(0, 6)
  if (h.length !== 6) return 0
  var r = parseInt(h.substring(0, 2), 16) / 255
  var g = parseInt(h.substring(2, 4), 16) / 255
  var b = parseInt(h.substring(4, 6), 16) / 255
  function linear(c) { return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

// WCAG contrast ratio between two hex colors (1..21).
function contrastRatio(hexA, hexB) {
  var la = relativeLuminance(hexA)
  var lb = relativeLuminance(hexB)
  var lighter = Math.max(la, lb)
  var darker = Math.min(la, lb)
  return (lighter + 0.05) / (darker + 0.05)
}

// True when two colors meet the given contrast ratio threshold (default 4.5,
// the WCAG AA requirement for normal text). Returns true when either color is
// missing so an unset color never disables a swatch.
function hasEnoughContrast(hexA, hexB, threshold) {
  if (!hexA || !hexB) return true
  return contrastRatio(hexA, hexB) >= (threshold || 4.5)
}

// Case-insensitive substring match against a color role name so variants like
// "dark_background" / "light_foreground" are caught too.
function matchesRole(name, role) {
  return String(name || "").toLowerCase().indexOf(String(role || "").toLowerCase()) !== -1
}

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
    parseBarColors: parseBarColors,
    relativeLuminance: relativeLuminance,
    contrastRatio: contrastRatio,
    hasEnoughContrast: hasEnoughContrast,
    matchesRole: matchesRole
  }
}