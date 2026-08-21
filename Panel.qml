import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "famas.theme-extend"
  ipcTarget: "famas.theme-extend"
  manageIpc: false

  // Color picker: swatches parsed from the active Omarchy theme's
  // colors.toml, plus whichever hex is currently written into
  // hyprland.lua as active_border_color (so the matching swatch can
  // show as selected).
  readonly property string omarchyStateDir: Quickshell.env("HOME") + "/.local/state/omarchy/current"
  readonly property string themeDir: omarchyStateDir + "/theme"
  readonly property string userShellPath: Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
  property var themeColors: []
  property string currentColor: ""
  // Whichever theme-palette hex is currently written into [bar] background /
  // text in shell.toml, so the matching swatch in each grid can show as
  // selected. Empty when unset or when the file holds a role name instead of
  // a literal hex (this plugin only ever writes literal hex).
  property string barBackgroundColor: ""
  property string barTextColor: ""
  // Display name for the active theme. Prefers the "theme.name" file that
  // sits next to the theme symlink (omarchyStateDir/theme.name); falls back
  // to the basename of the theme directory itself once symlinks are
  // resolved (e.g. "current/theme" -> ~/.config/omarchy/themes/tokyo-night
  // -> "tokyo-night").
  property string themeName: ""

  // WCAG AA contrast ratio used to gate Bar Background swatches against the
  // currently selected Bar Text color (4.5:1 is the AA threshold for normal text).
  property real contrastThreshold: 4.5

  // Effective text color: the explicit Bar Text override when set, otherwise
  // the theme's `foreground` color (Omarchy's default for bar text), so
  // contrast can be judged even before the user picks a text color.
  readonly property string effectiveTextColor: {
    if (root.barTextColor) return root.barTextColor
    for (var i = 0; i < root.themeColors.length; i++) {
      if (root.themeColors[i].name === "foreground") return root.themeColors[i].hex
    }
    return ""
  }

  // True when the applied bar background fails the contrast threshold against
  // the effective text color, no matter which of the two was chosen first.
  readonly property bool barBackgroundConflict:
    root.barBackgroundColor !== "" &&
    root.effectiveTextColor !== "" &&
    !Model.hasEnoughContrast(root.barBackgroundColor, root.effectiveTextColor, root.contrastThreshold)

  // Swatch corner rounding: half the system corner radius so small swatches
  // stay subtle, clamped to at least 1px so corners never look cut off.
  readonly property int swatchRadius: Math.max(1, Math.round(Style.cornerRadius / 2))

  // Cursor model shared by keyboard and mouse. There's a single section now
  // (the color grid), so no per-section bookkeeping is needed: selectedIndex
  // is just an index into themeColors, -1 when nothing is focused/available.
  property int selectedIndex: -1
  property bool cursorActive: false

  function clampCursor() {
    if (!themeColors.length) { selectedIndex = -1; return }
    if (selectedIndex < 0 || selectedIndex >= themeColors.length) selectedIndex = 0
  }

  // h/l: walk the grid left/right, in reading order.
  function moveCursorH(delta) {
    if (!themeColors.length) return
    var next = (selectedIndex < 0 ? 0 : selectedIndex) + delta
    if (next < 0) next = 0
    if (next > themeColors.length - 1) next = themeColors.length - 1
    selectedIndex = next
  }

  // j/k: walk the grid up/down a row at a time, based on however many
  // columns the grid is currently laid out with.
  function moveCursorV(delta) {
    if (!themeColors.length) return
    var cols = Math.max(1, colorsGrid.columns)
    var current = selectedIndex < 0 ? 0 : selectedIndex
    var next = current + delta * cols
    if (next < 0) next = current % cols
    if (next > themeColors.length - 1) next = themeColors.length - 1
    selectedIndex = next
  }

  function activateCursor() {
    if (selectedIndex < 0 || selectedIndex >= themeColors.length) return
    var c = themeColors[selectedIndex]
    if (c) setCurrentColor(c.hex)
  }

  // Keep the keyboard-focused swatch inside the viewport when the panel
  // grows taller than its allotted height (lots of theme colors).
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function summonImagePicker() {
    root.close()
    if (!bgSwitcherProc.running) bgSwitcherProc.running = true
  }

  // Semantic guard: a swatch named like "background" must not be pickable as
  // bar text and one named like "foreground" must not be pickable as bar
  // background, or the bar would be illegible by design.
  function isBackgroundLike(name) { return Model.matchesRole(name, "background") }
  function isForegroundLike(name) { return Model.matchesRole(name, "foreground") }

  // Looks up the theme-palette name of a hex, for readable tooltips.
  function colorNameFor(hex) {
    if (!hex) return ""
    for (var i = 0; i < root.themeColors.length; i++) {
      if (root.themeColors[i].hex === hex) return root.themeColors[i].name
    }
    return hex
  }

  // Accessibility gate: a Bar Background candidate is unusable when a Bar
  // Text color is selected and the pair fails the WCAG contrast threshold
  // (which includes the exact same color, ratio 1:1). No selection means no
  // restriction yet.
  function isBarBackgroundDisabled(hex) {
    if (!root.barTextColor) return false
    return !Model.hasEnoughContrast(hex, root.barTextColor, root.contrastThreshold)
  }

  // Resolves the contrast conflict by writing a compliant text color: the
  // theme's `foreground` when it qualifies (the default), otherwise the
  // available color with the highest contrast against the selected background.
  function fixTextColor() {
    if (!root.barBackgroundColor) return
    var candidates = root.themeColors.filter(function(c) {
      return !root.isBackgroundLike(c.name) &&
             Model.hasEnoughContrast(c.hex, root.barBackgroundColor, root.contrastThreshold)
    })
    if (!candidates.length) return
    var chosen = null
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i].name === "foreground") { chosen = candidates[i]; break }
    }
    if (!chosen) {
      chosen = candidates[0]
      var best = Model.contrastRatio(chosen.hex, root.barBackgroundColor)
      for (var j = 1; j < candidates.length; j++) {
        var ratio = Model.contrastRatio(candidates[j].hex, root.barBackgroundColor)
        if (ratio > best) { chosen = candidates[j]; best = ratio }
      }
    }
    root.setBarColor("text", chosen.hex)
  }

  // Nueva función para lanzar el theme switcher
  function runThemeSwitcher() {
    root.close()
    if (!themeSwitcherProc.running) themeSwitcherProc.running = true
  }

  IpcHandler {
    target: "famas.theme-extend"

    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    if (!colorsProc.running) colorsProc.running = true
  }

  function setCurrentColor(hex) {
    if (!/^#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(hex)) return
    root.currentColor = hex
    writeColorProc.command = ["bash", "-c",
      "mkdir -p " + root.themeDir
      + " && if [ -f " + root.themeDir + "/hyprland.lua ]; then"
      + " sed -i 's/^local active_border_color *= *.*/local active_border_color = \"" + hex + "\"/' " + root.themeDir + "/hyprland.lua;"
      + " else printf 'local active_border_color = \"" + hex + "\"\\nlocal inactive_border_color = \"rgba(595959aa)\"\\n\\nhl.config({\\n  general = {\\n    col = {\\n      active_border = active_border_color,\\n      inactive_border = inactive_border_color,\\n    },\\n  },\\n\\n  group = {\\n    col = {\\n      border_active = active_border_color,\\n      border_inactive = inactive_border_color,\\n    },\\n  },\\n\\n})\\n' > " + root.themeDir + "/hyprland.lua; fi"]
    if (!writeColorProc.running) writeColorProc.running = true
  }

  // Builds the awk script that upserts `key = val` inside the given TOML
  // section: replaces an existing key in place, appends it at the section's
  // end when missing, or creates the whole section when absent.
  function sectionAwkScript(section) {
    return 'BEGIN { q = sprintf("%c", 34); insec = 0; saw = 0; found = 0; managedSeen = 0; restorePending = 0 }\n' +
      '/^\\[/ {\n' +
      '  if (insec && !found) { print managed; print key" = "q val q; found = 1 }\n' +
      '  insec = ($0 == "' + section + '")\n' +
      '  if (insec) { saw = 1; found = 0; managedSeen = 0; restorePending = 0 }\n' +
      '  print\n' +
      '  next\n' +
      '}\n' +
      'insec && $0 == managed { managedSeen = 1; next }\n' +
      'insec && index($0, restore) == 1 {\n' +
      '  print\n' +
      '  restorePending = 1\n' +
      '  next\n' +
      '}\n' +
      'insec && $0 ~ "^[ \\t]*"key"[ \\t]*=" {\n' +
      '  if (!managedSeen && !restorePending) print restore $0\n' +
      '  print managed\n' +
      '  print key" = "q val q\n' +
      '  found = 1\n' +
      '  managedSeen = 0\n' +
      '  restorePending = 0\n' +
      '  next\n' +
      '}\n' +
      '{ print }\n' +
      'END {\n' +
      '  if (insec && !found) { print managed; print key" = "q val q }\n' +
      '  else if (!saw) { print ""; print "' + section + '"; print managed; print key" = "q val q }\n' +
      '}\n'
  }

  function managedMarker(section, key) {
    return "# famas.theme-extend managed " + section + " " + key
  }

  function restoreMarker(section, key) {
    return "# famas.theme-extend restore " + section + " " + key + ": "
  }

  readonly property string barAwkScript: root.sectionAwkScript("[bar]")
  readonly property string popupsAwkScript: root.sectionAwkScript("[popups]")

  function setBarColor(key, hex) {
    if (key !== "background" && key !== "text") return
    if (!/^#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(hex)) return

    if (key === "background") root.barBackgroundColor = hex
    else root.barTextColor = hex

    var path = root.userShellPath
    var cmd = "mkdir -p \"$(dirname '" + path + "')\" && [ -f '" + path + "' ] || touch '" + path + "'; "

    function writeSection(section, script) {
      return "awk " +
        "-v key='" + key + "' " +
        "-v val='" + hex + "' " +
        "-v managed='" + root.managedMarker(section, key) + "' " +
        "-v restore='" + root.restoreMarker(section, key) + "' " +
        "'" + script + "' '" + path + "' > '" + path + ".tmp' && " +
        "mv '" + path + ".tmp' '" + path + "'; "
    }

    cmd += writeSection("[bar]", root.barAwkScript)
    if (key === "background")
      cmd += writeSection("[popups]", root.popupsAwkScript)

    writeShellProc.command = ["bash", "-c", cmd]
    if (!writeShellProc.running) writeShellProc.running = true
  }

  readonly property string barResetAwkScript:
    'BEGIN {\n' +
    '  insec = ""\n' +
    '  restoreKey = ""\n' +
    '  skipKey = ""\n' +
    '  managed["[bar]\\034background"] = "# famas.theme-extend managed [bar] background"\n' +
    '  managed["[bar]\\034text"] = "# famas.theme-extend managed [bar] text"\n' +
    '  managed["[popups]\\034background"] = "# famas.theme-extend managed [popups] background"\n' +
    '  restore["[bar]\\034background"] = "# famas.theme-extend restore [bar] background: "\n' +
    '  restore["[bar]\\034text"] = "# famas.theme-extend restore [bar] text: "\n' +
    '  restore["[popups]\\034background"] = "# famas.theme-extend restore [popups] background: "\n' +
    '}\n' +
    '/^\\[/ {\n' +
    '  insec = ($0 == "[bar]" || $0 == "[popups]") ? $0 : ""\n' +
    '  restoreKey = ""; skipKey = ""\n' +
    '  print\n' +
    '  next\n' +
    '}\n' +
    'insec != "" {\n' +
    '  if (restoreKey != "") {\n' +
    '    if ($0 == managed[insec "\\034" restoreKey]) { skipKey = restoreKey; restoreKey = ""; next }\n' +
    '    restoreKey = ""\n' +
    '  }\n' +
    '  if (skipKey != "") {\n' +
    '    key = skipKey; skipKey = ""\n' +
    '    if ($0 ~ "^[ \\t]*" key "[ \\t]*=") next\n' +
    '  }\n' +
    '  for (key in managed) {\n' +
    '    split(key, parts, "\\034")\n' +
    '    if (parts[1] == insec && $0 == managed[key]) { skipKey = parts[2]; next }\n' +
    '    if (parts[1] == insec && index($0, restore[key]) == 1) {\n' +
    '      print substr($0, length(restore[key]) + 1)\n' +
    '      restoreKey = parts[2]\n' +
    '      next\n' +
    '    }\n' +
    '  }\n' +
    '}\n' +
    '{ print }\n'

  function resetBarColors() {
    root.barBackgroundColor = ""
    root.barTextColor = ""
    var path = root.userShellPath
    writeShellProc.command = ["bash", "-c",
      "mkdir -p \"$(dirname '" + path + "')\" && [ -f '" + path + "' ] || touch '" + path + "'; " +
      "awk '" + root.barResetAwkScript + "' '" + path + "' > '" + path + ".tmp' && " +
      "mv '" + path + ".tmp' '" + path + "'"
    ]
    if (!writeShellProc.running) writeShellProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
    }
  }

  onThemeColorsChanged: clampCursor()

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // --- Procesos ---

  Process {
    id: themeSwitcherProc
    command: ["bash", "-c",
      "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1"]
    onExited: root.refresh()
  }

  Process {
    id: bgSwitcherProc
    command: ["bash", "-c",
      "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refresh()
  }

  Process {
    id: colorsProc
    command: ["bash", "-c",
      "cat " + root.themeDir + "/colors.toml 2>/dev/null"
      + "; echo '__CURRENT__'"
      + "; grep '^local active_border_color' " + root.themeDir + "/hyprland.lua 2>/dev/null"
      + "; echo '__NAME__'"
      + "; cat " + root.omarchyStateDir + "/theme.name 2>/dev/null"
      + "; echo '__NAMEFALLBACK__'"
      + "; basename $(readlink -f " + root.themeDir + ") 2>/dev/null"
      + "; echo '__SHELLTOML__'"
      + "; cat " + root.userShellPath + " 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var afterColors = String(text || "").split("__CURRENT__")
        root.themeColors = Model.parseColorsToml(afterColors[0])

        var afterCurrent = (afterColors[1] || "").split("__NAME__")
        root.currentColor = Model.parseCurrentColor(afterCurrent[0] || "")

        var afterNameBlock = (afterCurrent[1] || "").split("__NAMEFALLBACK__")
        var explicitName = String(afterNameBlock[0] || "").trim()

        var afterFallback = (afterNameBlock[1] || "").split("__SHELLTOML__")
        var fallbackName = String(afterFallback[0] || "").trim()
        root.themeName = explicitName || fallbackName

        var barColors = Model.parseBarColors(afterFallback[1] || "")
        root.barBackgroundColor = barColors.background
        root.barTextColor = barColors.text
      }
    }
  }

  Process {
    id: writeColorProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: writeShellProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.refresh()
    }
  }

  // Detects theme switches no matter who triggered them (this panel's
  // switcher, the `omarchy theme set` CLI, etc.): omarchy-theme-set rewrites
  // theme.name on every switch, so bar color overrides get reset to the new
  // theme's defaults — replacing the old external theme-set hook.
  FileView {
    id: themeChangeWatcher
    path: root.omarchyStateDir + "/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: root.resetBarColors()
  }

  // --- UI ---

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏘"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursorV(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: palette icon · title/theme name ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, headerButtons.implicitHeight)

            Text {
              id: heroIcon
              text: "󰏘"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: headerButtons.left // Ajustado para el Row de botones
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Theme"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                text: root.themeName ? root.themeName.toUpperCase() : "NO THEME DETECTED"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: headerButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              // Botón del Theme Switcher
              Button {
                id: themeSwitcherButton
                iconText: "󰍜"
                tooltipText: "Switch Theme"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                onClicked: root.runThemeSwitcher()
              }

              // Botón del Image Picker
              Button {
                id: imagePickerButton
                iconText: ""
                tooltipText: "Open Image Picker"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                onClicked: root.summonImagePicker()
              }

              // reset botton: clears the [bar] background/text overrides this plugin wrote into
              Button {
                id: resetBarButton
                iconText: ""
                tooltipText: "Reset Bar Colors"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                onClicked: root.resetBarColors()
              }
            }
          }

          // ---------- Borders Color ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Text {
            width: parent.width
            text: "Borders Color"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Grid {
            id: colorsGrid
            width: parent.width
            visible: root.themeColors.length > 0
            columns: Math.max(1, Math.floor((width + Style.spacing.xs) / (Style.space(36) + Style.spacing.xs)))
            spacing: Style.spacing.xs

            Repeater {
              model: root.themeColors

              BarColorSwatch {
                required property var modelData
                required property int index

                swatchName: modelData.name
                swatchHex: modelData.hex
                selectedHex: root.currentColor
                swatchIndex: index
                keyboardNavigable: true
                onPicked: function(hex) { root.setCurrentColor(hex) }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.themeColors.length === 0
            text: "No theme colors found."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          // ---------- Bar text ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Text {
            width: parent.width
            text: "Bar Text"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Grid {
            id: barTextGrid
            width: parent.width
            visible: root.themeColors.length > 0
            columns: Math.max(1, Math.floor((width + Style.spacing.xs) / (Style.space(36) + Style.spacing.xs)))
            spacing: Style.spacing.xs

            Repeater {
              model: root.themeColors.filter(function(c) { return !root.isBackgroundLike(c.name) })

              BarColorSwatch {
                required property var modelData

                swatchName: modelData.name
                swatchHex: modelData.hex
                selectedHex: root.barTextColor
                swatchSize: 36
                onPicked: function(hex) { root.setBarColor("text", hex) }
              }
            }
          }

          // ---------- Bar background ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Text {
            width: parent.width
            text: "Bar Background"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Grid {
            id: barBackgroundGrid
            width: parent.width
            visible: root.themeColors.length > 0
            columns: Math.max(1, Math.floor((width + Style.spacing.xs) / (Style.space(36) + Style.spacing.xs)))
            spacing: Style.spacing.xs

            Repeater {
              model: root.themeColors.filter(function(c) { return !root.isForegroundLike(c.name) })

              BarColorSwatch {
                required property var modelData

                swatchName: modelData.name
                swatchHex: modelData.hex
                selectedHex: root.barBackgroundColor
                swatchSize: 36
                keyboardNavigable: true
                disabled: root.isBarBackgroundDisabled(modelData.hex)
                onPicked: function(hex) { root.setBarColor("background", hex) }
              }
            }
          }

          // ---------- Contrast warning: applied background vs effective text ----------
          Rectangle {
            visible: root.barBackgroundConflict
            width: parent.width
            radius: root.swatchRadius
            color: Color.tooltip.background
            border.width: 1
            border.color: Qt.darker(root.bar.foreground, 1.6)
            implicitHeight: warningRow.implicitHeight + Style.space(16)

            Row {
              id: warningRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                text: "⚠"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: warningText
                text: "Text color (" + root.colorNameFor(root.effectiveTextColor) + ") has insufficient contrast with this background."
                width: parent.width - warningFixButton.implicitWidth - parent.spacing * 3
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                id: warningFixButton
                iconText: ""
                tooltipText: "Match text to an available color with sufficient contrast (prefers foreground)"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                iconSize: Style.font.subtitle
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.fixTextColor()
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  // Reusable swatch for all color grids.
  component BarColorSwatch: Rectangle {
    id: barSwatch

    required property string swatchName
    required property string swatchHex
    property string selectedHex: ""
    property int swatchIndex: -1
    property bool keyboardNavigable: false
    property int swatchSize: 36
    property bool disabled: false

    signal picked(string hex)

    readonly property bool isSelected:
      barSwatch.selectedHex !== "" && barSwatch.selectedHex === barSwatch.swatchHex

    readonly property bool hasCursor:
      !barSwatch.disabled && (
        barSwatchArea.containsMouse ||
        (barSwatch.keyboardNavigable &&
         root.cursorActive &&
         root.selectedIndex === barSwatch.swatchIndex))

    readonly property string tooltipText:
      barSwatch.disabled
        ? "Insufficient contrast against " + root.colorNameFor(root.barTextColor)
        : barSwatch.swatchName

    // Marker color auto-adapted to the swatch color so the "SET" badge stays
    // readable on both dark and light backgrounds.
    readonly property color markerColor: Model.relativeLuminance(barSwatch.swatchHex) > 0.5 ? "#1a1a1a" : "#ffffff"

    width: Style.space(barSwatch.swatchSize)
    height: Style.space(barSwatch.swatchSize / 2)
    radius: root.swatchRadius
    color: swatchHex
    opacity: disabled ? 0.3 : 1.0
    border.width: isSelected ? 3 : (hasCursor ? 2 : 1)
    border.color: isSelected ? Color.accent : Qt.darker(root.bar.foreground, 1.6)

    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(barSwatch)

    readonly property var tooltipSpec:
      Border.localOrSurfaceSpec("tooltip", "border", Color.tooltip.border, Color.tooltip.border, Math.max(1, Style.normalBorderWidth))

    ToolTip {
      visible: barSwatchArea.containsMouse
      text: barSwatch.tooltipText
      delay: 400
      padding: 0
      background: BorderSurface {
        color: Color.tooltip.background
        borderSpec: barSwatch.tooltipSpec
        radius: 0
      }
      contentItem: Text {
        text: barSwatch.tooltipText
        color: Color.tooltip.text
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        leftPadding: Border.left(barSwatch.tooltipSpec) + Style.spacing.controlPaddingX
        rightPadding: Border.right(barSwatch.tooltipSpec) + Style.spacing.controlPaddingX
        topPadding: Border.top(barSwatch.tooltipSpec) + Style.spacing.controlPaddingY
        bottomPadding: Border.bottom(barSwatch.tooltipSpec) + Style.spacing.controlPaddingY
      }
    }

    MouseArea {
      id: barSwatchArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: barSwatch.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor

      onContainsMouseChanged: {
        if (containsMouse && !barSwatch.disabled && barSwatch.keyboardNavigable && barSwatch.swatchIndex >= 0) {
          root.cursorActive = true
          root.selectedIndex = barSwatch.swatchIndex
        }
      }

      onClicked: {
        if (!barSwatch.disabled) barSwatch.picked(barSwatch.swatchHex)
      }
    }

    // Visual reference for the active color: a dot plus the word "SET" on
    // the selected swatch of each grid.
    Row {
      anchors.centerIn: parent
      visible: barSwatch.isSelected
      spacing: Style.space(3)

      Rectangle {
        width: Style.space(4)
        height: Style.space(4)
        radius: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        color: barSwatch.markerColor
      }

      Text {
        text: "SET"
        color: barSwatch.markerColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}