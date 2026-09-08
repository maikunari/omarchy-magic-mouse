import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Ui

// Mouse battery pill: shows the charge of the first UPower device that is a
// mouse (or, failing that, the first HID battery). Hidden when there is none.
// Settings on the bar entry in shell.json:
//   "match": "MMM"   only consider devices whose model contains this text
//   "lowAt": 20      highlight at or below this percentage
BarWidget {
  id: root
  moduleName: "io.github.maikunari.magic-mouse"

  readonly property string match: String(setting("match", ""))
  readonly property int lowAt: Number(setting("lowAt", 20))
  readonly property var devices: UPower.devices ? UPower.devices.values : []

  readonly property var device: {
    var list = devices
    var i
    if (match !== "") {
      for (i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].model).indexOf(match) >= 0) return list[i]
      }
      return null
    }
    for (i = 0; i < list.length; i++) {
      if (list[i] && list[i].type === UPowerDeviceType.Mouse) return list[i]
    }
    for (i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].nativePath).indexOf("hid-") === 0) return list[i]
    }
    return null
  }

  // Quickshell exposes UPower's percentage as a 0..1 fraction.
  // The magic-mouse daemon asks the mouse directly and publishes the answer
  // here; UPower only learns the level when the mouse volunteers it.
  property var status: null
  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/magic-mouse/battery.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseStatus(text())
    onLoadFailed: root.status = null
  }
  function parseStatus(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.status = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.status = null
    }
  }

  readonly property bool daemonHas: status !== null && status.connected === true && status.percent !== undefined
  readonly property bool upowerKnown: device !== null && !(Math.round(device.percentage * 100) === 0 && device.state === UPowerDeviceState.Unknown)
  readonly property bool connected: daemonHas || (status !== null && status.connected === true) || device !== null
  readonly property bool known: daemonHas || upowerKnown
  readonly property int percent: daemonHas ? Number(status.percent) : (device ? Math.round(device.percentage * 100) : -1)
  readonly property bool charging: daemonHas ? status.charging === true : (device !== null && device.state === UPowerDeviceState.Charging)
  readonly property bool low: known && percent <= lowAt
  readonly property string modelName: daemonHas && status.model ? String(status.model) : (device && device.model ? device.model : "Mouse")

  readonly property string stateText: {
    if (!known) return ""
    if (charging) return "charging"
    if (!daemonHas && device && device.state === UPowerDeviceState.FullyCharged) return "full"
    return "discharging"
  }

  // ---- settings popup
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("batteryText" in target) target.batteryText = root.known ? root.percent + "% · " + root.stateText : (root.connected ? "connected" : "not connected")
  }
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onKnownChanged: injectPanel()
  onPercentChanged: injectPanel()
  onConnectedChanged: injectPanel()

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "io.github.maikunari.magic-mouse"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  visible: connected
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.connected ? (root.charging ? "󰍽󱐋 " : "󰍽 ") + (root.known ? root.percent + "%" : "–") : ""
    active: root.low
    tooltipText: root.connected ? root.modelName + (root.known ? " battery " + root.percent + "% (" + root.stateText + ")" : " battery: waiting for the mouse to report") : ""
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-shell shell toggle omarchy.bluetooth")
      else root.togglePanel()
    }
  }
}
