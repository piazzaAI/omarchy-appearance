import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One row per themed surface. The helper script does all of the work and
// answers in JSON; this file only lists what it reports and sends choices back.
Panel {
  id: root
  moduleName: "piazza.appearance"
  ipcTarget: "piazza.appearance"
  manageIpc: false

  // --- theme -----------------------------------------------------------------
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // --- state -----------------------------------------------------------------
  property var snapshot: null
  property string errorText: ""
  property string statusText: ""
  property string busyTarget: ""
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property string helper: Qt.resolvedUrl(".").toString().replace("file://", "") + "omarchy-appearance"

  readonly property var themeOptions: snapshot ? snapshot.themes : []
  readonly property var followOptions: [{ value: "follow", label: "Follow desktop" }].concat(themeOptions)

  // Rows in display order; the cursor walks the visible ones.
  readonly property var rows: {
    var s = snapshot
    var list = ["desktop", "background", "bar", "terminal"]
    if (s && s.hasNvim) list.push("nvim")
    if (s && s.hasZed) list.push("zed")
    if (s && s.hasHerdr) list.push("herdr")
    return list
  }

  function refresh() {
    if (stateProc.running) return
    stateProc.command = [root.helper, "state"]
    stateProc.running = true
  }

  function apply(target, value) {
    if (root.busyTarget !== "" || !value) return
    root.busyTarget = target
    root.statusText = "Applying " + target + "…"
    setProc.target = target
    setProc.command = [root.helper, "set", target, value]
    setProc.running = true
  }

  // The native pickers grab the screen, so the panel gets out of the way.
  function launch(args) {
    root.close()
    Quickshell.execDetached([root.helper].concat(args))
  }

  function toggleMenuEntry() {
    if (!root.snapshot || setProc.running) return
    root.busyTarget = "menu"
    setProc.target = "menu entry"
    setProc.command = [root.helper, "menu", root.snapshot.inMenu ? "remove" : "install"]
    setProc.running = true
  }

  function rowItem(name) {
    for (var i = 0; i < column.children.length; i++) {
      var child = column.children[i]
      if (child.rowName === name) return child
    }
    return null
  }

  function moveCursor(dy) {
    if (!root.cursorActive) { root.cursorActive = true; return }
    var n = root.rows.length
    if (n === 0) return
    root.cursorIndex = (root.cursorIndex + dy + n) % n
  }

  function activateCursor() {
    var item = rowItem(root.rows[root.cursorIndex])
    if (item && item.picker) item.picker.open()
  }

  function hasCursor(name) {
    return root.cursorActive && root.rows[root.cursorIndex] === name
  }

  // --- lifecycle -------------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: root.refresh()

  onOpenedChanged: if (opened) {
    root.cursorActive = false
    root.cursorIndex = 0
    root.errorText = ""
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    id: statusResetTimer
    interval: 3500
    onTriggered: root.statusText = ""
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = null
        try { payload = JSON.parse(String(text || "")) } catch (e) { payload = null }
        if (payload && payload.ok === true) {
          root.snapshot = payload
          root.errorText = ""
        } else {
          root.errorText = payload && payload.error ? String(payload.error) : "Could not read the current themes"
        }
      }
    }
  }

  Process {
    id: setProc
    property string target: ""
    property bool reported: false

    onRunningChanged: if (running) reported = false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = null
        try { payload = JSON.parse(String(text || "")) } catch (e) { payload = null }
        setProc.reported = true
        root.busyTarget = ""
        if (payload && payload.ok === true) {
          root.statusText = setProc.target + " updated"
          root.errorText = ""
        } else {
          root.statusText = ""
          root.errorText = payload && payload.error ? String(payload.error) : setProc.target + " failed"
        }
        statusResetTimer.restart()
        root.refresh()
      }
    }
    onExited: function(exitCode) {
      if (setProc.reported) return
      root.busyTarget = ""
      root.errorText = "Could not run omarchy-appearance"
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  // --- bar icon --------------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏘"
    tooltipText: root.opened ? "" : "Appearance"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.launch(["pick", "desktop"])
      else root.toggle()
    }
  }

  // --- panel -----------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "n" || t === "N") root.apply("background", "next")
        else if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Appearance"
            meta: root.busyTarget !== "" ? root.statusText
              : (root.snapshot ? "Desktop: " + root.labelFor(root.themeOptions, root.snapshot.desktop) : "Loading…")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰏘"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.errorText !== "" || (root.statusText !== "" && root.busyTarget === "")
            width: parent.width
            textFormat: Text.PlainText
            text: root.errorText !== "" ? root.errorText : root.statusText
            color: root.errorText !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          ThemeRow {
            rowName: "desktop"
            label: "DESKTOP"
            options: root.themeOptions
            value: root.snapshot ? root.snapshot.desktop : ""
            actionIcon: "󰸌"
            actionTip: "Open the theme switcher"
            onAction: root.launch(["pick", "desktop"])
          }

          ThemeRow {
            rowName: "background"
            label: "BACKGROUND"
            options: root.snapshot ? root.snapshot.backgrounds : []
            value: root.snapshot ? root.snapshot.background : ""
            actionIcon: "󰒭"
            actionTip: "Next background (n)"
            onAction: root.apply("background", "next")
            secondIcon: "󰸉"
            secondTip: "Open the background switcher"
            onSecondAction: root.launch(["set", "background", "picker"])
          }

          ThemeRow {
            rowName: "bar"
            label: "BAR"
            options: root.followOptions
            value: root.snapshot ? root.snapshot.bar : "follow"
          }

          ThemeRow {
            rowName: "terminal"
            label: "TERMINAL"
            options: root.followOptions
            value: root.snapshot ? root.snapshot.terminal : "follow"
          }

          ThemeRow {
            rowName: "nvim"
            label: "NEOVIM"
            visible: root.snapshot ? root.snapshot.hasNvim : false
            options: root.followOptions
            value: root.snapshot ? root.snapshot.nvim : "follow"
          }

          ThemeRow {
            rowName: "zed"
            label: "ZED"
            visible: root.snapshot ? root.snapshot.hasZed : false
            options: root.snapshot ? root.snapshot.zedThemes : []
            value: root.snapshot ? root.snapshot.zed : ""
          }

          ThemeRow {
            rowName: "herdr"
            label: "HERDR"
            visible: root.snapshot ? root.snapshot.hasHerdr : false
            options: root.snapshot ? root.snapshot.herdrThemes : []
            value: root.snapshot ? root.snapshot.herdr : ""
          }

          PanelSeparator { foreground: root.foreground }

          Button {
            width: parent.width
            leftAlign: true
            iconText: "󰍜"
            text: root.snapshot && root.snapshot.inMenu ? "Remove from the Omarchy menu" : "Add to the Omarchy menu (Style → Appearance)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            enabled: root.snapshot !== null && root.busyTarget === ""
            onClicked: root.toggleMenuEntry()
          }
        }
      }
    }
  }

  function labelFor(options, value) {
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return options[i].label
    return value
  }

  // --- building blocks -------------------------------------------------------
  component ThemeRow: Column {
    id: themeRow
    property string rowName: ""
    property string label: ""
    property var options: []
    property string value: ""
    property string actionIcon: ""
    property string actionTip: ""
    property string secondIcon: ""
    property string secondTip: ""
    property alias picker: dropdown
    signal action()
    signal secondAction()

    width: parent.width
    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: themeRow.label
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      SearchableDropdown {
        id: dropdown
        width: parent.width - (actionButton.visible ? actionButton.width + parent.spacing : 0)
                            - (secondButton.visible ? secondButton.width + parent.spacing : 0)
        showLabel: false
        options: themeRow.options
        value: themeRow.value
        fontFamily: root.fontFamily
        placeholderText: "Search…"
        enabled: root.busyTarget === ""
        hasCursor: root.hasCursor(themeRow.rowName)
        onHovered: function(h) {
          if (!h) return
          root.cursorActive = true
          root.cursorIndex = Math.max(0, root.rows.indexOf(themeRow.rowName))
        }
        onChanged: function(v) { if (v !== themeRow.value) root.apply(themeRow.rowName, v) }
      }

      PanelActionButton {
        id: actionButton
        visible: themeRow.actionIcon !== ""
        anchors.verticalCenter: dropdown.verticalCenter
        iconText: themeRow.actionIcon
        tooltipText: themeRow.actionTip
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: themeRow.action()
      }

      PanelActionButton {
        id: secondButton
        visible: themeRow.secondIcon !== ""
        anchors.verticalCenter: dropdown.verticalCenter
        iconText: themeRow.secondIcon
        tooltipText: themeRow.secondTip
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: themeRow.secondAction()
      }
    }
  }
}
