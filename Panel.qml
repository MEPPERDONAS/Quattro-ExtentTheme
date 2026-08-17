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

  readonly property string barAwkScript:
    'BEGIN { q = sprintf("%c", 34); insec = 0; sawBar = 0; found = 0 }\n' +
    '/^\\[/ {\n' +
    '  if (insec && !found) { print key" = "q val q; found = 1 }\n' +
    '  insec = ($0 == "[bar]")\n' +
    '  if (insec) sawBar = 1\n' +
    '  print\n' +
    '  next\n' +
    '}\n' +
    '{\n' +
    '  if (insec && $0 ~ "^"key"[ \\t]*=") { print key" = "q val q; found = 1; next }\n' +
    '  print\n' +
    '}\n' +
    'END {\n' +
    '  if (insec && !found) print key" = "q val q\n' +
    '  else if (!sawBar) { print ""; print "[bar]"; print key" = "q val q }\n' +
    '}\n'

  function setBarColor(key, hex) {
    if (key !== "background" && key !== "text") return
    if (!/^#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(hex)) return

    if (key === "background") root.barBackgroundColor = hex
    else root.barTextColor = hex

    var path = root.userShellPath
    writeShellProc.command = ["bash", "-c",
      "mkdir -p \"$(dirname '" + path + "')\" && [ -f '" + path + "' ] || touch '" + path + "'; "
      + "awk -v key='" + key + "' -v val='" + hex + "' '" + root.barAwkScript + "' '" + path + "' > '" + path + ".tmp' "
      + "&& mv '" + path + ".tmp' '" + path + "'"]
    if (!writeShellProc.running) writeShellProc.running = true
  }

  // Removes the [bar] background/text overrides this plugin wrote into the
  // user shell.toml so the bar falls back to the active theme's defaults.
  // Everything else in the file (e.g. [font]) is preserved.
  readonly property string barResetAwkScript:
    'BEGIN { insec = 0; buf = ""; nonempty = 0 }\n' +
    '/^\\[/ {\n' +
    '  if (insec) { if (nonempty) print buf; insec = 0; buf = ""; nonempty = 0 }\n' +
    '  if ($0 == "[bar]") { insec = 1; buf = $0 }\n' +
    '  else print\n' +
    '  next\n' +
    '}\n' +
    'insec && $0 ~ /^[ \\t]*(background|text)[ \\t]*=/ { next }\n' +
    'insec {\n' +
    '  if ($0 !~ /^[ \\t]*$/) nonempty = 1\n' +
    '  buf = buf "\\n" $0\n' +
    '  next\n' +
    '}\n' +
    '{ print }\n' +
    'END { if (insec && nonempty) print buf }\n'

  function resetBarColors() {
    root.barBackgroundColor = ""
    root.barTextColor = ""
    var path = root.userShellPath
    writeShellProc.command = ["bash", "-c",
      "mkdir -p \"$(dirname '" + path + "')\" && [ -f '" + path + "' ] || touch '" + path + "'; "
      + "awk '" + root.barResetAwkScript + "' '" + path + "' > '" + path + ".tmp' "
      + "&& mv '" + path + ".tmp' '" + path + "'"]
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
              model: root.themeColors

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
              model: root.themeColors

              BarColorSwatch {
                required property var modelData

                swatchName: modelData.name
                swatchHex: modelData.hex
                selectedHex: root.barBackgroundColor
                swatchSize: 36
                keyboardNavigable: true
                onPicked: function(hex) { root.setBarColor("background", hex) }
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

    signal picked(string hex)

    readonly property bool isSelected:
      barSwatch.selectedHex !== "" && barSwatch.selectedHex === barSwatch.swatchHex

    readonly property bool hasCursor:
      barSwatchArea.containsMouse ||
      (barSwatch.keyboardNavigable &&
       root.cursorActive &&
       root.selectedIndex === barSwatch.swatchIndex)

    width: Style.space(barSwatch.swatchSize)
    height: Style.space(barSwatch.swatchSize / 2)
    radius: root.swatchRadius
    color: swatchHex
    border.width: isSelected ? 3 : (hasCursor ? 2 : 1)
    border.color: isSelected ? Color.accent : Qt.darker(root.bar.foreground, 1.6)

    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(barSwatch)

    readonly property var tooltipSpec:
      Border.localOrSurfaceSpec("tooltip", "border", Color.tooltip.border, Color.tooltip.border, Math.max(1, Style.normalBorderWidth))

    ToolTip {
      visible: barSwatchArea.containsMouse
      text: barSwatch.swatchName
      delay: 400
      padding: 0
      background: BorderSurface {
        color: Color.tooltip.background
        borderSpec: barSwatch.tooltipSpec
        radius: 0
      }
      contentItem: Text {
        text: barSwatch.swatchName
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
      cursorShape: Qt.PointingHandCursor

      onContainsMouseChanged: {
        if (containsMouse && barSwatch.keyboardNavigable && barSwatch.swatchIndex >= 0) {
          root.cursorActive = true
          root.selectedIndex = barSwatch.swatchIndex
        }
      }

      onClicked: barSwatch.picked(barSwatch.swatchHex)
    }
  }
}