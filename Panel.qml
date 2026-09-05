import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: mainPanel
  moduleName: "kshatriya-abhay.wiz-lights"
  ipcTarget: "kshatriya-abhay.wiz-lights"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var counts: Model.countOn(service.lights, mainPanel.uiState)
  property string expandedMac: ""
  property string editingMac: ""
  property var uiState: ({})
  property int phraseIndex: 0
  property int scanPhraseIndex: 0

  property bool cursorActive: false
  property string focusSection: "bulbs"
  property int headerIndex: 1
  property int selectedIndex: 0
  property bool actionFocused: false
  property string expandedItem: ""
  property int subIndex: 0
  property bool wasReturnKey: false

  readonly property var scanningPhrases: [
    "Scanning network",
    "Discovering bulbs",
    "Searching for lumens"
  ]
  readonly property string currentScanPhrase: scanningPhrases[scanPhraseIndex % scanningPhrases.length]

  Timer {
    id: scanPhraseTimer
    interval: 2800
    running: mainPanel.opened && service.scanning
    repeat: true
    onTriggered: mainPanel.scanPhraseIndex = (mainPanel.scanPhraseIndex + 1) % mainPanel.scanningPhrases.length
  }

  Connections {
    target: service
    function onScanningChanged() {
      if (service.scanning) {
        mainPanel.scanPhraseIndex = (mainPanel.scanPhraseIndex + 1) % mainPanel.scanningPhrases.length
      }
    }
  }

  readonly property var activePhrases: [
    mainPanel.counts.on + " of " + mainPanel.counts.total + " on",
    "Casting lumens",
    "Bending spectra",
    "Photons in flight",
    "Illuminating spaces",
    "Tuning kelvins",
    "Warming atmosphere",
    "Chasing shadows",
    "Painting with light"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  Timer {
    id: phraseTimer
    interval: 2800
    running: mainPanel.opened && (mainPanel.counts.on > 0)
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: mainPanel.phraseIndex = (mainPanel.phraseIndex + 1) % mainPanel.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  onCountsChanged: {
    if (counts.on === 0) {
      phraseSwap.stop()
      if (hero) hero.metaOpacity = 1.0
    }
  }

  function uiGet(mac, key, fallback) {
    var entry = uiState[String(mac)]
    var value = entry ? entry[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function uiSet(mac, key, value) {
    var entry = Object.assign({}, uiState[String(mac)] || {})
    entry[key] = value
    var next = Object.assign({}, uiState)
    next[String(mac)] = entry
    uiState = next
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openAndLoad() {
    if (mainPanel.opened) {
      mainPanel.close()
      return
    }
    mainPanel.open()
  }

  onOpenedChanged: if (opened) {
    mainPanel.cursorActive = false
    mainPanel.focusSection = service.lights.length > 0 ? "bulbs" : "header"
    mainPanel.selectedIndex = 0
    mainPanel.headerIndex = 1
    mainPanel.actionFocused = false
    mainPanel.expandedItem = ""
    mainPanel.subIndex = 0
    if (service.lights.length === 0 && !service.scanning) service.scan()
    else service.refresh()
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: mainPanel.settings
  }

  Connections {
    target: service
    function onLightsChanged() {
      for (var i = 0; i < service.lights.length; i++) {
        var l = service.lights[i]
        if (l) {
          mainPanel.uiClearKey(String(l.mac), "power")
          mainPanel.uiClearKey(String(l.mac), "pending")
        }
      }
    }
  }

  function uiClearKey(mac, key) {
    var entry = Object.assign({}, uiState[String(mac)] || {})
    delete entry[key]
    var next = Object.assign({}, uiState)
    next[String(mac)] = entry
    uiState = next
  }

  function markBulbOn(mac) {
    mainPanel.uiSet(String(mac), "power", true)
  }

  function toggleLight(index) {
    var light = service.lights[index]
    if (!light || !light.reachable || light.pending || service.busy) return
    var curPower = mainPanel.uiGet(String(light.mac), "power", undefined)
    var turnOn = curPower !== undefined ? !curPower : !light.state
    var mac = String(light.mac)
    mainPanel.uiSet(mac, "power", turnOn)
    mainPanel.uiSet(mac, "pending", true)
    service.setPower(light.ip, turnOn, function(parsed, exitCode) {
      mainPanel.uiClearKey(mac, "pending")
      if (exitCode !== 0) {
        mainPanel.uiSet(mac, "power", !turnOn)
      }
      service.refresh()
    })
  }

  function toggleAll(turnOn) {
    if (service.busy || service.lights.length === 0) return
    if (!turnOn) {
      mainPanel.expandedMac = ""
      mainPanel.editingMac = ""
    }
    for (var i = 0; i < service.lights.length; i++) {
      var l = service.lights[i]
      if (l && l.reachable) {
        mainPanel.uiSet(String(l.mac), "power", turnOn)
        mainPanel.uiSet(String(l.mac), "pending", true)
      }
    }
    service.setAllPower(turnOn, function(parsed, exitCode) {
      for (var i = 0; i < service.lights.length; i++) {
        var l = service.lights[i]
        if (l) mainPanel.uiClearKey(String(l.mac), "pending")
      }
      service.refresh()
    })
  }

  function scrollItemIntoView(item) {
    if (!scroll || !item || !scroll.contentItem) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(8)
      var flick = scroll.contentItem
      var point = item.mapToItem(flick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = flick.contentY
      var viewBottom = viewTop + flick.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < viewTop + margin) {
        flick.contentY = Math.max(0, top - margin)
      } else if (bottom > viewBottom - margin) {
        flick.contentY = Math.min(maxY, bottom + margin - flick.height)
      }
    })
  }

  function moveCursorV(dy) {
    mainPanel.cursorActive = true
    var count = service.lights.length
    if (focusSection === "header") {
      if (dy > 0 && count > 0) {
        focusSection = "bulbs"
        selectedIndex = 0
        actionFocused = false
        expandedItem = ""
      }
      return
    }

    var curMac = (selectedIndex >= 0 && selectedIndex < count) ? String(service.lights[selectedIndex].mac) : ""
    var isExpanded = curMac !== "" && mainPanel.expandedMac === curMac

    if (!isExpanded) {
      if (dy > 0) {
        if (selectedIndex < count - 1) {
          selectedIndex++
          actionFocused = false
          expandedItem = ""
        }
      } else {
        if (selectedIndex > 0) {
          selectedIndex--
          actionFocused = false
          expandedItem = ""
        } else {
          focusSection = "header"
          headerIndex = 1
          actionFocused = false
          expandedItem = ""
        }
      }
    } else {
      var seq = ["row", "presets", "scenes", "bright", "temp", "color"]
      var curItem = expandedItem === "" ? "row" : expandedItem
      var idx = seq.indexOf(curItem)
      if (idx < 0) idx = 0

      if (dy > 0) {
        if (idx < seq.length - 1) {
          expandedItem = seq[idx + 1]
          subIndex = 0
          actionFocused = false
        } else {
          if (selectedIndex < count - 1) {
            selectedIndex++
            expandedItem = ""
            actionFocused = false
          }
        }
      } else {
        if (idx > 0) {
          expandedItem = seq[idx - 1] === "row" ? "" : seq[idx - 1]
          subIndex = 0
          actionFocused = false
        } else {
          if (selectedIndex > 0) {
            selectedIndex--
            expandedItem = ""
            actionFocused = false
          } else {
            focusSection = "header"
            headerIndex = 1
            actionFocused = false
            expandedItem = ""
          }
        }
      }
    }
  }

  function moveCursorH(dx) {
    mainPanel.cursorActive = true
    if (focusSection === "header") {
      if (dx < 0) headerIndex = 0
      else if (dx > 0) headerIndex = 1
      return
    }

    var count = service.lights.length
    if (selectedIndex < 0 || selectedIndex >= count) return
    var curMac = String(service.lights[selectedIndex].mac)
    var isExpanded = curMac !== "" && mainPanel.expandedMac === curMac

    if (!isExpanded || expandedItem === "" || expandedItem === "row") {
      if (dx > 0) actionFocused = true
      else if (dx < 0) actionFocused = false
      return
    }

    if (expandedItem === "presets") {
      var rowItem = bulbsRepeater.itemAt(selectedIndex)
      var presetsList = rowItem ? (rowItem.bulbPresets || []) : (mainPanel.uiGet(curMac, "presets", null) || service.lights[selectedIndex].presets || [])
      var hasTweaked = rowItem ? rowItem.hasTweaked : mainPanel.uiGet(curMac, "hasTweaked", false)
      var totalPresetItems = presetsList.length + (hasTweaked ? 1 : 0)
      var maxP = Math.max(0, totalPresetItems - 1)
      subIndex = Math.max(0, Math.min(maxP, subIndex + dx))
    } else if (expandedItem === "scenes") {
      subIndex = Math.max(0, Math.min(11, subIndex + dx))
    } else if (expandedItem === "bright") {
      var curDim = mainPanel.uiGet(curMac, "dimming", Number(service.lights[selectedIndex].dimming) || 100)
      var nextDim = Math.max(0, Math.min(100, Math.round(curDim) + dx * 5))
      mainPanel.uiSet(curMac, "dimming", nextDim)
      mainPanel.uiSet(curMac, "power", true)
      service.hold(4000)
      service.setBright(String(service.lights[selectedIndex].ip), nextDim, null, "slider:" + curMac + ":bright")
    } else if (expandedItem === "temp") {
      var curT = mainPanel.uiGet(curMac, "temp", Number(service.lights[selectedIndex].temp) || 2700)
      var nextT = Math.max(2200, Math.min(6500, Math.round(curT / 100) * 100 + dx * 100))
      mainPanel.uiSet(curMac, "temp", nextT)
      mainPanel.uiSet(curMac, "lastTweakedMode", "temp")
      mainPanel.uiSet(curMac, "hasTweaked", true)
      mainPanel.uiSet(curMac, "power", true)
      service.hold(4000)
      service.setTemp(String(service.lights[selectedIndex].ip), nextT, null, "slider:" + curMac + ":temp")
    } else if (expandedItem === "color") {
      var curH = mainPanel.uiGet(curMac, "hue", 35)
      var nextH = (Math.round(curH) + dx * 15 + 360) % 360
      mainPanel.uiSet(curMac, "hue", nextH)
      mainPanel.uiSet(curMac, "lastTweakedMode", "color")
      mainPanel.uiSet(curMac, "hasTweaked", true)
      mainPanel.uiSet(curMac, "power", true)
      service.hold(2500)
      var hex = Model.hueToHex(nextH)
      service.setHex(String(service.lights[selectedIndex].ip), hex, null, "slider:" + curMac + ":color")
    }
  }

  function activateCursor() {
    var isEnter = wasReturnKey
    wasReturnKey = false

    if (focusSection === "header") {
      if (headerIndex === 0) service.scan()
      else mainPanel.toggleAll(mainPanel.counts.on === 0)
      return
    }

    var count = service.lights.length
    if (selectedIndex < 0 || selectedIndex >= count) return
    var curMac = String(service.lights[selectedIndex].mac)
    var isExpanded = curMac !== "" && mainPanel.expandedMac === curMac

    if (!isExpanded || expandedItem === "" || expandedItem === "row") {
      if (actionFocused || !isEnter) {
        mainPanel.toggleLight(selectedIndex)
      } else {
        mainPanel.toggleFocusedExpand()
      }
      return
    }

    if (expandedItem === "presets") {
      var rowItem = bulbsRepeater.itemAt(selectedIndex)
      if (rowItem) {
        var pList = rowItem.bulbPresets || []
        if (subIndex >= 0 && subIndex < pList.length) {
          rowItem.applyPreset(pList[subIndex])
        } else if (subIndex === pList.length && rowItem.hasTweaked) {
          mainPanel.uiSet(curMac, "savedFeedback", true)
          if (typeof rowItem.saveCurrentPreset === "function") {
            rowItem.saveCurrentPreset()
          }
        }
      } else {
        var pList = mainPanel.uiGet(curMac, "presets", null) || service.lights[selectedIndex].presets || []
        var hasTweaked = mainPanel.uiGet(curMac, "hasTweaked", false)
        if (subIndex >= 0 && subIndex < pList.length) {
          var p = pList[subIndex]
          if (p) {
            mainPanel.markBulbOn(curMac)
            mainPanel.uiSet(curMac, "lastTweakedMode", p.mode)
            mainPanel.uiSet(curMac, "activePresetColor", p.color || p.hex)
            mainPanel.uiSet(curMac, "activeSceneId", 0)
            mainPanel.uiSet(curMac, "hasTweaked", false)
            service.hold(3000)
            if (p.mode === "temp" && p.temp) {
              var k = Math.round(p.temp / 50) * 50
              mainPanel.uiSet(curMac, "temp", k)
              service.setTemp(String(service.lights[selectedIndex].ip), k, null)
            } else if (p.hex || p.color) {
              var targetHex = String(p.hex || p.color)
              var rgb = Model.hexToRgb(targetHex)
              if (rgb) {
                var hsv = Model.rgbToHsv(rgb.r, rgb.g, rgb.b)
                mainPanel.uiSet(curMac, "hue", Math.round(hsv.h))
                mainPanel.uiSet(curMac, "sat", Math.round(hsv.s * 100))
              }
              service.setHex(String(service.lights[selectedIndex].ip), targetHex, null)
            }
          }
        }
      }
    } else if (expandedItem === "scenes") {
      var scenes = [
        { id: 10, name: "Bedtime" },
        { id: 1, name: "Ocean" },
        { id: 2, name: "Romance" },
        { id: 3, name: "Sunset" },
        { id: 4, name: "Party" },
        { id: 5, name: "Fireplace" },
        { id: 6, name: "Cozy" },
        { id: 7, name: "Forest" },
        { id: 29, name: "Candlelight" },
        { id: 31, name: "Pulse" },
        { id: 32, name: "Steampunk" },
        { id: 33, name: "Diwali" }
      ]
      var sc = scenes[subIndex % scenes.length]
      var rowItem = bulbsRepeater.itemAt(selectedIndex)
      if (rowItem && sc) {
        rowItem.applyScene(sc.id, sc.name)
      } else if (sc && selectedIndex >= 0 && selectedIndex < service.lights.length) {
        mainPanel.markBulbOn(curMac)
        mainPanel.uiSet(curMac, "activeSceneId", sc.id)
        mainPanel.uiSet(curMac, "activePresetColor", null)
        mainPanel.uiSet(curMac, "lastTweakedMode", "scene")
        mainPanel.uiSet(curMac, "hasTweaked", false)
        service.setScene(String(service.lights[selectedIndex].ip), sc.id, null)
      }
    }
  }

  function toggleFocusedPower() {
    if (focusSection === "header") {
      mainPanel.toggleAll(mainPanel.counts.on === 0)
    } else if (selectedIndex >= 0 && selectedIndex < service.lights.length) {
      mainPanel.toggleLight(selectedIndex)
    }
  }

  function toggleFocusedExpand() {
    if (focusSection === "bulbs" && selectedIndex >= 0 && selectedIndex < service.lights.length) {
      var mac = String(service.lights[selectedIndex].mac || "")
      mainPanel.expandedMac = (mainPanel.expandedMac === mac ? "" : mac)
      if (mainPanel.expandedMac !== "") service.hold(1500)
    }
  }

  function startRenameFocused() {
    if (focusSection === "bulbs" && selectedIndex >= 0 && selectedIndex < service.lights.length) {
      var mac = String(service.lights[selectedIndex].mac || "")
      mainPanel.expandedMac = mac
      mainPanel.editingMac = mac
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: mainPanel.bar
    text: " "
    fixedWidth: vertical ? -1 : content.implicitWidth + Style.space(16)
    tooltipText: "WiZ Lights · " + mainPanel.counts.on + "/" + mainPanel.counts.total + " on"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) {
        service.scan()
      } else {
        if (mainPanel.opened) mainPanel.close()
        else mainPanel.openAndLoad()
      }
    }

    Row {
      id: content
      anchors.centerIn: parent

      Image {
        width: Style.space(13)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        source: Qt.resolvedUrl("bulb.svg")
        sourceSize: Qt.size(26, 26)
        layer.enabled: true
        layer.effect: MultiEffect {
          colorization: 1
          colorizationColor: mainPanel.counts.on > 0 ? mainPanel.foreground : mainPanel.dim
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: mainPanel
    bar: mainPanel.bar
    open: mainPanel.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      blocked: mainPanel.editingMac !== ""
      onCloseRequested: mainPanel.close()
      onMoveRequested: function(dx, dy) {
        if (!mainPanel.cursorActive) {
          mainPanel.cursorActive = true
          return
        }
        if (dy !== 0) mainPanel.moveCursorV(dy)
        if (dx !== 0) mainPanel.moveCursorH(dx)
      }
      onTabRequested: function(direction) {
        if (!mainPanel.cursorActive) {
          mainPanel.cursorActive = true
          return
        }
        mainPanel.moveCursorV(direction)
      }
      onReturnRequested: mainPanel.wasReturnKey = true
      onActivateRequested: {
        if (mainPanel.cursorActive) mainPanel.activateCursor()
      }
      onDeleteRequested: {
        if (mainPanel.cursorActive && mainPanel.expandedItem === "presets") {
          var rowItem = bulbsRepeater.itemAt(mainPanel.selectedIndex)
          if (rowItem && typeof rowItem.deletePreset === "function") {
            rowItem.deletePreset(mainPanel.subIndex)
            var pLen = (rowItem.bulbPresets || []).length
            if (mainPanel.subIndex >= pLen) {
              mainPanel.subIndex = Math.max(0, pLen - 1)
            }
          }
        }
      }
      onTextKey: function(text) {
        if (mainPanel.editingMac !== "") return
        if (text === "r" || text === "R") service.scan()
        else if (text === "t" || text === "T") mainPanel.toggleFocusedPower()
        else if (text === "e" || text === "E" || text === "o" || text === "O") mainPanel.toggleFocusedExpand()
        else if (text === "n" || text === "N") mainPanel.startRenameFocused()
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: (mainPanel.opened && body.implicitHeight > panel.contentHeight)
                                   ? ScrollBar.AsNeeded
                                   : ScrollBar.AlwaysOff
        Binding {
          target: scroll.contentItem
          property: "interactive"
          value: mainPanel.opened && body.implicitHeight > panel.contentHeight
        }

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "WiZ Lights"
            meta: service.scanning
                  ? mainPanel.currentScanPhrase
                  : (mainPanel.counts.total > 0
                     ? (mainPanel.counts.on > 0 ? mainPanel.heroPhraseText : "Lights out")
                     : "No bulbs found")
            foreground: mainPanel.foreground
            fontFamily: mainPanel.fontFamily
            iconComponent: Component {
              Image {
                width: Style.font.display
                height: width
                source: Qt.resolvedUrl("bulb.svg")
                sourceSize: Qt.size(48, 48)
                layer.enabled: true
                layer.effect: MultiEffect {
                  colorization: 1
                  colorizationColor: mainPanel.counts.on > 0 ? mainPanel.foreground : mainPanel.dim
                }
              }
            }

            trailingControl: Component {
              RowLayout {
                spacing: Style.space(8)

                Button {
                  id: scanBtn
                  iconText: service.scanning ? "" : "⌕"
                  implicitWidth: Style.space(28)
                  tooltipText: service.scanning
                               ? mainPanel.currentScanPhrase
                               : (service.lastUpdated.getTime() > 0
                                  ? "Scan network (R) · updated " + Qt.formatDateTime(service.lastUpdated, "hh:mm:ss")
                                  : "Scan network for WiZ bulbs (R)")
                  foreground: mainPanel.foreground
                  fontFamily: mainPanel.fontFamily
                  iconSize: Style.font.subtitle * 1.5
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(2)
                  Layout.alignment: Qt.AlignVCenter
                  enabled: !service.scanning
                  hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "header" && mainPanel.headerIndex === 0
                  onHovered: function(on) {
                    if (on) {
                      mainPanel.cursorActive = true
                      mainPanel.focusSection = "header"
                      mainPanel.headerIndex = 0
                    }
                  }
                  onClicked: service.scan()

                  Loader {
                    anchors.centerIn: parent
                    active: service.scanning
                    sourceComponent: Component {
                      Row {
                        spacing: Style.space(2.5)

                        Repeater {
                          model: 3
                          delegate: Rectangle {
                            required property int index
                            width: Style.space(3.5)
                            height: width
                            radius: width / 2
                            color: mainPanel.foreground
                            opacity: 0.25

                            SequentialAnimation on opacity {
                              loops: Animation.Infinite
                              PauseAnimation { duration: index * 160 }
                              NumberAnimation { to: 1.0; duration: 320; easing.type: Easing.InOutQuad }
                              NumberAnimation { to: 0.25; duration: 320; easing.type: Easing.InOutQuad }
                              PauseAnimation { duration: (2 - index) * 160 }
                            }

                            SequentialAnimation on scale {
                              loops: Animation.Infinite
                              PauseAnimation { duration: index * 160 }
                              NumberAnimation { to: 1.35; duration: 320; easing.type: Easing.OutQuad }
                              NumberAnimation { to: 1.0; duration: 320; easing.type: Easing.InQuad }
                              PauseAnimation { duration: (2 - index) * 160 }
                            }
                          }
                        }
                      }
                    }
                  }
                }

                ToggleSwitch {
                  id: masterToggle
                  visible: mainPanel.counts.total > 0
                  checked: mainPanel.counts.on > 0
                  busy: service.busy
                  cursorRing: true
                  hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "header" && mainPanel.headerIndex === 1
                  foreground: mainPanel.foreground
                  accent: Color.accent
                  onHovered: function(on) {
                    if (on) {
                      mainPanel.cursorActive = true
                      mainPanel.focusSection = "header"
                      mainPanel.headerIndex = 1
                    }
                  }
                  onToggled: mainPanel.toggleAll(mainPanel.counts.on === 0)

                  PanelToolTip {
                    visible: masterToggle.containsMouse
                    text: mainPanel.counts.on > 0 ? "Turn all lights off" : "Turn all lights on"
                    fontFamily: mainPanel.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: service.lastError !== "" && service.lastError !== "undefined"
            width: parent.width
            text: service.lastError
            color: mainPanel.urgent
            font.family: mainPanel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !service.scanning && service.lights.length === 0 && service.lastError === ""
            width: parent.width
            text: "No bulbs saved yet. Press R or the scan button to search your local network."
            color: mainPanel.dim
            font.family: mainPanel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: mainPanel.foreground }

          Repeater {
            id: bulbsRepeater
            model: service.lights

            delegate: ColumnLayout {
              id: row
              required property var modelData
              required property int index
              width: body.width
              spacing: Style.space(10)

              readonly property bool expanded: mainPanel.expandedMac === String(modelData.mac)
              readonly property bool editing: mainPanel.editingMac === String(modelData.mac)
              readonly property bool pending: (mainPanel.uiGet(macStr, "pending", undefined) !== undefined ? !!mainPanel.uiGet(macStr, "pending", false) : !!modelData.pending)
              readonly property bool onState: (mainPanel.uiGet(macStr, "power", undefined) !== undefined ? !!mainPanel.uiGet(macStr, "power", false) : !!modelData.state) && modelData.reachable
              readonly property string bulbMode: {
                var tweaked = mainPanel.uiGet(macStr, "lastTweakedMode", "")
                if (tweaked === "temp" || tweaked === "color") return tweaked
                return String(modelData.mode || "") === "color"
                       ? "color"
                       : (modelData.temp ? "temp" : "")
              }
              readonly property string macStr: String(modelData.mac || "")

              function ensureOn() {
                if (!row.onState) {
                  mainPanel.markBulbOn(row.macStr)
                }
              }

              function applyScene(sceneId, sceneName) {
                if (!row.modelData.reachable) return
                row.ensureOn()
                row.resetSavedFeedback(false)
                mainPanel.uiSet(row.macStr, "activeSceneId", sceneId)
                mainPanel.uiSet(row.macStr, "activePresetColor", null)
                mainPanel.uiSet(row.macStr, "lastTweakedMode", "scene")
                mainPanel.uiSet(row.macStr, "hasTweaked", false)
                service.setScene(String(row.modelData.ip), sceneId, function(parsed, exitCode) {
                  row.reportFailure(parsed, exitCode, "failed to set " + sceneName + " scene")
                })
              }
              readonly property bool hasTweaked: mainPanel.uiGet(macStr, "hasTweaked", false)
              readonly property bool savedFeedback: mainPanel.uiGet(macStr, "savedFeedback", false)

              readonly property var defaultPresets: [
                {
                  name: "Warm White",
                  color: "#FFA757",
                  mode: "temp",
                  temp: 2700,
                  hex: "#FFA757"
                },
                {
                  name: "Daylight",
                  color: "#FFE4CE",
                  mode: "temp",
                  temp: 5000,
                  hex: "#FFE4CE"
                },
                {
                  name: "Cool White",
                  color: "#BCD4FF",
                  mode: "temp",
                  temp: 6500,
                  hex: "#BCD4FF"
                },
                {
                  name: "Night Light",
                  color: "#FF9227",
                  mode: "temp",
                  temp: 2200,
                  hex: "#FF9227"
                }
              ]

              readonly property var bulbPresets: {
                var fromUi = mainPanel.uiGet(row.macStr, "presets", null)
                if (fromUi && Array.isArray(fromUi)) return fromUi
                if (modelData.presets && Array.isArray(modelData.presets) && modelData.presets.length > 0) {
                  return modelData.presets
                }
                return row.defaultPresets
              }

              readonly property int currentSceneId: {
                var fromUi = mainPanel.uiGet(row.macStr, "activeSceneId", undefined)
                if (fromUi !== undefined) return Number(fromUi)
                return Number(modelData.sceneId) || 0
              }

              function isPresetActive(preset) {
                if (!row.onState || row.currentSceneId > 0 || !preset) return false
                var activeColor = mainPanel.uiGet(row.macStr, "activePresetColor", null)
                if (activeColor !== null) {
                  var pCol = String(preset.color || preset.hex || "")
                  return pCol.toUpperCase() === String(activeColor).toUpperCase()
                }
                if (preset.mode === "temp" && preset.temp) {
                  if (row.bulbMode !== "temp") return false
                  var currentTemp = Math.round(tempSlider.value)
                  return Math.abs(currentTemp - Number(preset.temp)) < 150
                }
                if (preset.mode === "color") {
                  if (row.bulbMode !== "color") return false
                  var pColor = String(preset.hex || preset.color || "").toUpperCase()
                  var curRgb = Model.hsvToRgb(colorPlane.hue, colorPlane.sat, 1)
                  var curHex = Model.rgbToHex(curRgb.r, curRgb.g, curRgb.b).toUpperCase()
                  return pColor !== "" && pColor === curHex
                }
                return false
              }

              function resetSavedFeedback(keepTweaked) {
                if (savedFeedbackTimer.running) {
                  savedFeedbackTimer.stop()
                }
                if (row.savedFeedback) {
                  mainPanel.uiSet(row.macStr, "savedFeedback", false)
                }
                if (!keepTweaked && row.hasTweaked) {
                  mainPanel.uiSet(row.macStr, "hasTweaked", false)
                }
              }

              Timer {
                id: savedFeedbackTimer
                interval: 1000
                onTriggered: {
                  mainPanel.uiSet(row.macStr, "savedFeedback", false)
                  mainPanel.uiSet(row.macStr, "hasTweaked", false)
                }
              }

              function saveCurrentPreset() {
                var mode = mainPanel.uiGet(row.macStr, "lastTweakedMode", row.bulbMode || "temp")
                var kelvin = Math.round(tempSlider.value)
                var rgb = Model.hsvToRgb(colorPlane.hue, colorPlane.sat, 1)
                var hex = Model.rgbToHex(rgb.r, rgb.g, rgb.b).toUpperCase()
                var dotColor = (mode === "temp") ? Model.kelvinToHex(kelvin) : hex

                var newPreset = {
                  color: dotColor,
                  mode: mode,
                  hex: dotColor
                }
                if (mode === "temp") {
                  newPreset.name = kelvin + "K"
                  newPreset.temp = kelvin
                } else {
                  newPreset.name = hex
                  newPreset.hue = Math.round(colorPlane.hue)
                  newPreset.sat = Math.round(colorPlane.sat * 100)
                  newPreset.r = rgb.r
                  newPreset.g = rgb.g
                  newPreset.b = rgb.b
                }

                var current = row.bulbPresets.slice()
                var previousActiveColor = mainPanel.uiGet(row.macStr, "activePresetColor", null)
                var filtered = current.filter(function(p) {
                  return !(p.mode === mode && (mode === "temp" ? p.temp === kelvin : p.color === dotColor))
                })
                var updated = [newPreset].concat(filtered).slice(0, 12)
                mainPanel.uiSet(row.macStr, "presets", updated)
                mainPanel.uiSet(row.macStr, "activePresetColor", newPreset.color)
                mainPanel.uiSet(row.macStr, "activeSceneId", 0)

                service.savePreset(row.macStr, newPreset, function(parsed, exitCode) {
                  if (parsed && parsed.ok && Array.isArray(parsed.presets)) {
                    mainPanel.uiSet(row.macStr, "presets", parsed.presets)
                  } else {
                    mainPanel.uiSet(row.macStr, "presets", current)
                    mainPanel.uiSet(row.macStr, "activePresetColor", previousActiveColor)
                    row.reportFailure(parsed, exitCode, "failed to save preset")
                  }
                })
              }

              function applyPreset(preset) {
                if (!preset || !row.modelData.reachable) return
                row.ensureOn()
                row.resetSavedFeedback(false)
                var ip = String(row.modelData.ip)
                mainPanel.uiSet(row.macStr, "lastTweakedMode", preset.mode)
                mainPanel.uiSet(row.macStr, "activePresetColor", preset.color || preset.hex)
                mainPanel.uiSet(row.macStr, "activeSceneId", 0)
                mainPanel.uiSet(row.macStr, "hasTweaked", false)
                service.hold(3000)

                if (preset.mode === "temp" && preset.temp) {
                  var k = Math.round(preset.temp / 50) * 50
                  tempSlider.value = k
                  mainPanel.uiSet(row.macStr, "temp", k)
                  service.setTemp(ip, k, function(parsed, exitCode) {
                    row.reportFailure(parsed, exitCode, "failed to apply preset temp")
                  })
                } else if (preset.hex || preset.color) {
                  var targetHex = String(preset.hex || preset.color)
                  if (preset.hue !== undefined && preset.sat !== undefined) {
                    colorPlane.hue = preset.hue
                    colorPlane.sat = preset.sat / 100
                    mainPanel.uiSet(row.macStr, "hue", preset.hue)
                    mainPanel.uiSet(row.macStr, "sat", preset.sat)
                  } else {
                    var rgb = Model.hexToRgb(targetHex)
                    if (rgb) {
                      var hsv = Model.rgbToHsv(rgb.r, rgb.g, rgb.b)
                      colorPlane.hue = hsv.h
                      colorPlane.sat = hsv.s
                      mainPanel.uiSet(row.macStr, "hue", Math.round(hsv.h))
                      mainPanel.uiSet(row.macStr, "sat", Math.round(hsv.s * 100))
                    }
                  }
                  service.setHex(ip, targetHex, function(parsed, exitCode) {
                    row.reportFailure(parsed, exitCode, "failed to apply preset color")
                  })
                }
              }

              function deletePreset(index) {
                var current = row.bulbPresets.slice()
                if (index >= 0 && index < current.length) {
                  var deleted = current[index]
                  var previousPresets = current.slice()
                  var previousActiveColor = mainPanel.uiGet(row.macStr, "activePresetColor", null)
                  current.splice(index, 1)
                  mainPanel.uiSet(row.macStr, "presets", current)
                  var activeColor = mainPanel.uiGet(row.macStr, "activePresetColor", null)
                  if (deleted && activeColor === deleted.color) {
                    mainPanel.uiSet(row.macStr, "activePresetColor", null)
                  }
                  service.deletePreset(row.macStr, index, function(parsed, exitCode) {
                    if (parsed && parsed.ok && Array.isArray(parsed.presets)) {
                      mainPanel.uiSet(row.macStr, "presets", parsed.presets)
                    } else {
                      mainPanel.uiSet(row.macStr, "presets", previousPresets)
                      mainPanel.uiSet(row.macStr, "activePresetColor", previousActiveColor)
                      row.reportFailure(parsed, exitCode, "failed to delete preset")
                    }
                  })
                }
              }

              function seedDimming() {
                var d = Number(modelData.dimming)
                if (!isFinite(d) || d <= 0) d = 100
                return Math.max(0, Math.min(100, d))
              }
              function seedTemp() {
                var t = Number(modelData.temp)
                if (!isFinite(t)) t = 2700
                return Math.max(2200, Math.min(6500, t))
              }
              function seedHue() {
                var rgb = modelData.rgb
                if (rgb && typeof rgb.length === "number" && rgb.length >= 3) {
                  return Math.round(Model.rgbToHsv(rgb[0], rgb[1], rgb[2]).h)
                }
                return 35
              }
              function seedSat() {
                var rgb = modelData.rgb
                if (rgb && typeof rgb.length === "number" && rgb.length >= 3) {
                  return Math.round(Model.rgbToHsv(rgb[0], rgb[1], rgb[2]).s * 100)
                }
                return 100
              }
              function sendRgb() {
                row.ensureOn()
                var rgb = Model.hsvToRgb(colorPlane.hue, colorPlane.sat, 1)
                var hex = Model.rgbToHex(rgb.r, rgb.g, rgb.b).toUpperCase()
                service.setHex(String(row.modelData.ip), hex, function(parsed, exitCode) {
                  row.reportFailure(parsed, exitCode, "failed to set color")
                }, "slider:" + row.macStr + ":color")
              }
              function reportFailure(parsed, exitCode, fallback) {
                if (exitCode !== 0 || (parsed && parsed.ok !== true)) {
                  var msg = parsed && parsed.error ? String(parsed.error) : (fallback || "Action failed")
                  if (msg && msg !== "undefined") {
                    service.lastError = msg
                  }
                  service.refresh()
                }
              }

              // Row Header
              CursorSurface {
                id: bulbHeaderSurface
                Layout.fillWidth: true
                implicitHeight: headerContentRow.implicitHeight + Style.space(6)
                hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && !mainPanel.actionFocused && (mainPanel.expandedItem === "" || mainPanel.expandedItem === "row")
                onHasCursorChanged: if (hasCursor) mainPanel.scrollItemIntoView(bulbHeaderSurface)
                foreground: mainPanel.foreground
                accent: Color.accent

                HoverHandler {
                  onHoveredChanged: if (hovered) {
                    mainPanel.cursorActive = true
                    mainPanel.focusSection = "bulbs"
                    mainPanel.selectedIndex = row.index
                    mainPanel.actionFocused = false
                    mainPanel.expandedItem = ""
                  }
                }

                RowLayout {
                  id: headerContentRow
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(10)

                  MouseArea {
                    id: rowClick
                    Layout.fillWidth: true
                    implicitHeight: innerRow.implicitHeight
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      mainPanel.expandedMac = row.expanded ? "" : String(row.modelData.mac)
                      if (mainPanel.expandedMac !== "") service.hold(1500)
                    }

                    RowLayout {
                      id: innerRow
                      anchors.fill: parent
                      spacing: Style.space(8)

                      Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: row.expanded ? "▾" : "▸"
                        color: mainPanel.dim
                        font.family: mainPanel.fontFamily
                        font.pixelSize: Style.font.subtitle
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(2)

                        RowLayout {
                          Layout.fillWidth: true
                          spacing: Style.space(6)

                          Text {
                            text: row.modelData.name || "WiZ Light"
                            color: !row.modelData.reachable ? mainPanel.dim : (row.onState ? mainPanel.foreground : mainPanel.dim)
                            font.family: mainPanel.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                            elide: Text.ElideRight

                            Behavior on color { ColorAnimation { duration: 150 } }
                          }

                          PanelActionButton {
                            iconText: "✎"
                            tooltipText: "Rename bulb (N)"
                            visible: row.expanded && !row.editing
                            size: Style.space(20)
                            fontSize: Style.font.caption
                            foreground: mainPanel.dim
                            fontFamily: mainPanel.fontFamily
                            onClicked: mainPanel.editingMac = String(row.modelData.mac)
                          }
                        }

                        Text {
                          Layout.fillWidth: true
                          text: Model.metaText(row.modelData)
                          color: row.modelData.reachable ? mainPanel.dim : mainPanel.urgent
                          font.family: mainPanel.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }

                  ToggleSwitch {
                    id: bulbSwitch
                    Layout.alignment: Qt.AlignVCenter
                    checked: row.onState
                    busy: row.pending
                    interactive: row.modelData.reachable
                    cursorRing: true
                    hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && mainPanel.actionFocused
                    foreground: mainPanel.foreground
                    accent: Color.accent
                    onHovered: function(on) {
                      if (on) {
                        mainPanel.cursorActive = true
                        mainPanel.focusSection = "bulbs"
                        mainPanel.selectedIndex = row.index
                        mainPanel.actionFocused = true
                      }
                    }
                    onToggled: mainPanel.toggleLight(row.index)

                    PanelToolTip {
                      visible: bulbSwitch.containsMouse
                      text: row.onState ? "Turn light off" : "Turn light on"
                      fontFamily: mainPanel.fontFamily
                    }
                  }
                }
              }

              TextField {
                id: renameField
                Layout.fillWidth: true
                visible: row.editing
                text: row.modelData.name || ""
                placeholderText: "Bulb name"
                color: mainPanel.foreground
                font.family: mainPanel.fontFamily
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(2)
                onAccepted: commit()
                onVisibleChanged: if (visible) {
                  selectAll()
                  forceActiveFocus()
                }
                onActiveFocusChanged: if (!activeFocus && mainPanel.editingMac === String(row.modelData.mac)) {
                  commit()
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    text = row.modelData.name || ""
                    mainPanel.editingMac = ""
                    event.accepted = true
                  }
                }
                function commit() {
                  var name = text.trim()
                  mainPanel.editingMac = ""
                  if (name === "" || name === String(row.modelData.name || "")) return
                  var mac = String(row.modelData.mac)
                  service.rename(mac, name, function(parsed, exitCode) {
                    row.reportFailure(parsed, exitCode, "rename failed")
                  })
                }
              }

              // Expanded content
              ColumnLayout {
                id: expandedSection
                Layout.fillWidth: true
                Layout.leftMargin: Style.space(12)
                Layout.rightMargin: Style.space(4)
                visible: row.expanded
                opacity: !row.modelData.reachable ? 0.35 : (row.onState ? 1.0 : 0.55)
                spacing: Style.space(12)

                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

                // Presets & Quick Actions
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  RowLayout {
                    Layout.fillWidth: true

                    Text {
                      text: "Presets"
                      color: mainPanel.dim
                      font.family: mainPanel.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    PillButton {
                      id: savePresetBtn
                      visible: row.hasTweaked || opacity > 0.01
                      opacity: row.hasTweaked ? 1.0 : 0.0
                      label: row.savedFeedback ? "Saved" : "Save Preset"
                      iconText: row.savedFeedback ? "✓" : "💾"
                      accent: true
                      hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && mainPanel.expandedItem === "presets" && mainPanel.subIndex === row.bulbPresets.length
                      onHasCursorChanged: if (hasCursor) mainPanel.scrollItemIntoView(savePresetBtn)
                      onHovered: function(on) {
                        if (on) {
                          mainPanel.cursorActive = true
                          mainPanel.focusSection = "bulbs"
                          mainPanel.selectedIndex = row.index
                          mainPanel.expandedItem = "presets"
                          mainPanel.subIndex = row.bulbPresets.length
                        }
                      }
                      tooltip: row.savedFeedback ? "Preset saved" : "Save current color or temperature as a quick preset dot"
                      onChosen: {
                        if (row.savedFeedback) return
                        mainPanel.uiSet(row.macStr, "savedFeedback", true)
                        savedFeedbackTimer.restart()
                        row.saveCurrentPreset()
                      }
                      Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                  }

                  RowLayout {
                    id: presetsRow
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    layer.enabled: !row.onState
                    layer.effect: MultiEffect {
                      saturation: -0.9
                      brightness: -0.05
                    }

                    // Presets Dots
                    Repeater {
                      model: row.bulbPresets

                      delegate: ColorSwatch {
                        required property var modelData
                        required property int index
                        swatchColor: modelData.color || modelData.hex || "#ffffff"
                        selected: row.onState && row.isPresetActive(modelData)
                        hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && mainPanel.expandedItem === "presets" && mainPanel.subIndex === index
                        onHasCursorChanged: if (hasCursor) mainPanel.scrollItemIntoView(this)
                        onHovered: function(on) {
                          if (on) {
                            mainPanel.cursorActive = true
                            mainPanel.focusSection = "bulbs"
                            mainPanel.selectedIndex = row.index
                            mainPanel.expandedItem = "presets"
                            mainPanel.subIndex = index
                          }
                        }
                        tooltip: (modelData.name ? (modelData.name + " · ") : "")
                                 + (modelData.mode === "color" ? (modelData.hex || modelData.color) : (modelData.temp ? modelData.temp + "K" : "Preset"))
                                 + "\n(Click to apply · Right-click to remove)"
                        onChosen: row.applyPreset(modelData)
                        onRightChosen: row.deletePreset(index)
                      }
                    }

                    Text {
                      visible: row.bulbPresets.length === 0 && !row.hasTweaked
                      text: "No presets saved yet"
                      color: mainPanel.dim
                      font.family: mainPanel.fontFamily
                      font.pixelSize: Style.font.caption
                      opacity: 0.7
                    }
                  }
                }

                PanelSeparator {
                  Layout.fillWidth: true
                  foreground: mainPanel.foreground
                }

                // Scenes Section
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  Text {
                    text: "Scenes"
                    color: mainPanel.dim
                    font.family: mainPanel.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Flow {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Repeater {
                      model: [
                        { id: 10, name: "Bedtime", tip: "Bedtime (Scene 10) · 30-minute progressive routine, starting warm and gently dimming to night light" },
                        { id: 1, name: "Ocean", tip: "Ocean (Scene 1) · Calm aquatic cycle between deep blues and cyans" },
                        { id: 2, name: "Romance", tip: "Romance (Scene 2) · Soft purples, magenta, and gentle rose hues" },
                        { id: 3, name: "Sunset", tip: "Sunset (Scene 3) · Slow, relaxing cycle across deep reds, oranges, and warm amber" },
                        { id: 4, name: "Party", tip: "Party (Scene 4) · Dynamic energetic color-cycling bursts" },
                        { id: 5, name: "Fireplace", tip: "Fireplace (Scene 5) · Randomized flickering flame tones between amber, gold, and red" },
                        { id: 6, name: "Cozy", tip: "Cozy (Scene 6) · Soft, comforting warm ambience" },
                        { id: 7, name: "Forest", tip: "Forest (Scene 7) · Shifting tranquil greens and earthen tones" },
                        { id: 29, name: "Candlelight", tip: "Candlelight (Scene 29) · Warm, gentle flickering flame effect" },
                        { id: 31, name: "Pulse", tip: "Pulse (Scene 31) · Dynamic rhythmic breathing effect" },
                        { id: 32, name: "Steampunk", tip: "Steampunk (Scene 32) · Vintage brass, copper, and warm antique tungsten" },
                        { id: 33, name: "Diwali", tip: "Diwali (Scene 33) · Festive vibrant celebration colors" }
                      ]

                      delegate: PillButton {
                        required property var modelData
                        required property int index
                        label: modelData.name
                        selected: row.onState && row.currentSceneId === modelData.id
                        hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && mainPanel.expandedItem === "scenes" && mainPanel.subIndex === index
                        onHasCursorChanged: if (hasCursor) mainPanel.scrollItemIntoView(this)
                        tooltip: modelData.tip
                        onHovered: function(on) {
                          if (on) {
                            mainPanel.cursorActive = true
                            mainPanel.focusSection = "bulbs"
                            mainPanel.selectedIndex = row.index
                            mainPanel.expandedItem = "scenes"
                            mainPanel.subIndex = index
                          }
                        }
                        onChosen: row.applyScene(modelData.id, modelData.name)
                      }
                    }
                  }
                }

                PanelSeparator {
                  Layout.fillWidth: true
                  foreground: mainPanel.foreground
                }

                // Controls Section
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    text: "Controls"
                    color: mainPanel.dim
                    font.family: mainPanel.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  // Brightness
                  CursorSurface {
                    id: brightRowSurface
                    Layout.fillWidth: true
                    implicitHeight: brightRow.implicitHeight + Style.space(6)
                    hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && mainPanel.expandedItem === "bright"
                    onHasCursorChanged: if (hasCursor) mainPanel.scrollItemIntoView(brightRowSurface)
                    foreground: mainPanel.foreground
                    accent: Color.accent

                    HoverHandler {
                      onHoveredChanged: if (hovered) {
                        mainPanel.cursorActive = true
                        mainPanel.focusSection = "bulbs"
                        mainPanel.selectedIndex = row.index
                        mainPanel.expandedItem = "bright"
                      }
                    }

                    RowLayout {
                      id: brightRow
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(8)

                      Text {
                        Layout.preferredWidth: Style.space(80)
                        text: "Brightness"
                        color: mainPanel.dim
                        font.family: mainPanel.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      PillSlider {
                        id: brightSlider
                        Layout.fillWidth: true
                        sliderType: "brightness"
                        minimum: 0
                        maximum: 100
                        value: mainPanel.uiGet(row.macStr, "dimming", row.seedDimming())

                        onMoved: function(v) {
                          value = v
                          row.ensureOn()
                          mainPanel.uiSet(row.macStr, "dimming", Math.round(v))
                          mainPanel.uiSet(row.macStr, "activeSceneId", 0)
                          mainPanel.uiSet(row.macStr, "activePresetColor", null)
                          service.hold(4000)
                          brightTimer.restart()
                        }
                        onReleased: function(v) {
                          value = v
                          row.ensureOn()
                          brightTimer.stop()
                          service.hold(4000)
                          service.setBright(String(row.modelData.ip), Math.round(v), function(parsed, exitCode) {
                            row.reportFailure(parsed, exitCode, "failed to set brightness")
                          }, "slider:" + row.macStr + ":bright")
                        }

                        Timer {
                          id: brightTimer
                          interval: 200
                          onTriggered: service.setBright(String(row.modelData.ip), Math.round(brightSlider.value), function(parsed, exitCode) {
                            row.reportFailure(parsed, exitCode, "failed to set brightness")
                          }, "slider:" + row.macStr + ":bright")
                        }
                      }

                      Text {
                        Layout.preferredWidth: Style.space(60)
                        text: Math.round(brightSlider.value) + "%"
                        color: mainPanel.foreground
                        font.family: mainPanel.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                      }
                    }
                  }

                  // Warm/Cool
                  CursorSurface {
                    id: tempRowSurface
                    Layout.fillWidth: true
                    implicitHeight: tempRow.implicitHeight + Style.space(6)
                    opacity: row.bulbMode === "temp" ? 1.0 : 0.6
                    Behavior on opacity { enabled: mainPanel.opened; NumberAnimation { duration: 120 } }
                    hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && mainPanel.expandedItem === "temp"
                    onHasCursorChanged: if (hasCursor) mainPanel.scrollItemIntoView(tempRowSurface)
                    foreground: mainPanel.foreground
                    accent: Color.accent

                    HoverHandler {
                      onHoveredChanged: if (hovered) {
                        mainPanel.cursorActive = true
                        mainPanel.focusSection = "bulbs"
                        mainPanel.selectedIndex = row.index
                        mainPanel.expandedItem = "temp"
                      }
                    }

                    RowLayout {
                      id: tempRow
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(8)

                      Text {
                        Layout.preferredWidth: Style.space(80)
                        text: "Warm/Cool"
                        color: row.bulbMode === "temp" ? mainPanel.foreground : mainPanel.dim
                        font.family: mainPanel.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: row.bulbMode === "temp"
                      }

                      PillSlider {
                        id: tempSlider
                        Layout.fillWidth: true
                        sliderType: "temp"
                        minimum: 2200
                        maximum: 6500
                        value: mainPanel.uiGet(row.macStr, "temp", row.seedTemp())

                        onMoved: function(v) {
                          value = v
                          row.ensureOn()
                          row.resetSavedFeedback(true)
                          mainPanel.uiSet(row.macStr, "temp", Math.round(v))
                          mainPanel.uiSet(row.macStr, "lastTweakedMode", "temp")
                          mainPanel.uiSet(row.macStr, "activeSceneId", 0)
                          mainPanel.uiSet(row.macStr, "activePresetColor", null)
                          mainPanel.uiSet(row.macStr, "hasTweaked", true)
                          service.hold(4000)
                          tempTimer.restart()
                        }
                        onReleased: function(v) {
                          value = v
                          row.ensureOn()
                          row.resetSavedFeedback(true)
                          tempTimer.stop()
                          service.hold(4000)
                          service.setTemp(String(row.modelData.ip), Math.round(v / 50) * 50, function(parsed, exitCode) {
                            row.reportFailure(parsed, exitCode, "failed to set temperature")
                          }, "slider:" + row.macStr + ":temp")
                        }

                        Timer {
                          id: tempTimer
                          interval: 200
                          onTriggered: service.setTemp(String(row.modelData.ip), Math.round(tempSlider.value / 50) * 50, function(parsed, exitCode) {
                            row.reportFailure(parsed, exitCode, "failed to set temperature")
                          }, "slider:" + row.macStr + ":temp")
                        }
                      }

                      Text {
                        Layout.preferredWidth: Style.space(60)
                        text: Math.round(tempSlider.value) + "K"
                        color: mainPanel.foreground
                        font.family: mainPanel.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                      }
                    }
                  }

                  // Color
                  CursorSurface {
                    id: colorRowSurface
                    Layout.fillWidth: true
                    implicitHeight: colorRow.implicitHeight + Style.space(6)
                    opacity: row.bulbMode === "color" ? 1.0 : 0.6
                    Behavior on opacity { enabled: mainPanel.opened; NumberAnimation { duration: 120 } }
                    hasCursor: mainPanel.cursorActive && mainPanel.focusSection === "bulbs" && mainPanel.selectedIndex === row.index && mainPanel.expandedItem === "color"
                    onHasCursorChanged: if (hasCursor) mainPanel.scrollItemIntoView(colorRowSurface)
                    foreground: mainPanel.foreground
                    accent: Color.accent

                    HoverHandler {
                      onHoveredChanged: if (hovered) {
                        mainPanel.cursorActive = true
                        mainPanel.focusSection = "bulbs"
                        mainPanel.selectedIndex = row.index
                        mainPanel.expandedItem = "color"
                      }
                    }

                    RowLayout {
                      id: colorRow
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(8)

                      Text {
                        Layout.preferredWidth: Style.space(80)
                        Layout.alignment: Qt.AlignVCenter
                        text: "Color"
                        color: row.bulbMode === "color" ? mainPanel.foreground : mainPanel.dim
                        font.family: mainPanel.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: row.bulbMode === "color"
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(4)

                        HueSatPlane {
                          id: colorPlane
                          Layout.fillWidth: true
                          hue: mainPanel.uiGet(row.macStr, "hue", row.seedHue())
                          sat: mainPanel.uiGet(row.macStr, "sat", row.seedSat()) / 100

                          onMoved: function(h, s) {
                            row.ensureOn()
                            var mac = row.macStr
                            row.resetSavedFeedback(true)
                            mainPanel.uiSet(mac, "hue", Math.round(h))
                            mainPanel.uiSet(mac, "sat", Math.round(s * 100))
                            mainPanel.uiSet(mac, "lastTweakedMode", "color")
                            mainPanel.uiSet(mac, "activeSceneId", 0)
                            mainPanel.uiSet(mac, "activePresetColor", null)
                            mainPanel.uiSet(mac, "hasTweaked", true)
                            service.hold(2500)
                            colorTimer.restart()
                          }
                          onReleased: function(h, s) {
                            row.ensureOn()
                            row.resetSavedFeedback(true)
                            colorTimer.stop()
                            service.hold(2500)
                            row.sendRgb()
                          }

                          Timer {
                            id: colorTimer
                            interval: 200
                            onTriggered: row.sendRgb()
                          }
                        }

                        Text {
                          Layout.alignment: Qt.AlignRight
                          property var rgbValue: Model.hsvToRgb(colorPlane.hue, colorPlane.sat, 1)
                          text: Model.rgbToHex(rgbValue.r, rgbValue.g, rgbValue.b).toUpperCase()
                          color: row.bulbMode === "color" ? mainPanel.foreground : mainPanel.dim
                          font.family: mainPanel.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }
                    }
                  }
                }
                }

              PanelSeparator {
                Layout.fillWidth: true
                visible: row.index < service.lights.length - 1
                foreground: mainPanel.foreground
              }
            }
          }
        }
      }
    }
  }

  component ColorSwatch: Item {
    id: swatch
    property color swatchColor: "#ffffff"
    property string tooltip: ""
    property bool selected: false
    property bool hasCursor: false
    signal chosen()
    signal rightChosen()
    signal hovered(bool isHovered)

    implicitWidth: Style.space(20)
    implicitHeight: width

    // Selection / Cursor ring
    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.space(2)
      radius: width / 2
      color: "transparent"
      border.color: swatch.hasCursor
                    ? (swatch.selected ? Color.accent : mainPanel.foreground)
                    : Color.accent
      border.width: Style.space(2)
      visible: swatch.selected || swatch.hasCursor
      opacity: (swatch.selected || swatch.hasCursor) ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    Rectangle {
      id: innerDot
      anchors.fill: parent
      radius: width / 2
      color: swatch.swatchColor
      border.color: (swatch.selected || swatch.hasCursor)
                    ? Qt.rgba(0, 0, 0, 0.4)
                    : Qt.rgba(mainPanel.foreground.r, mainPanel.foreground.g, mainPanel.foreground.b, 0.25)
      border.width: 1
      scale: (swatchMouse.containsMouse || swatch.hasCursor) ? 1.15 : 1.0
      Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      id: swatchMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: swatch.hovered(containsMouse)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) swatch.rightChosen()
        else swatch.chosen()
      }
    }

    PanelToolTip {
      visible: swatchMouse.containsMouse && swatch.tooltip !== ""
      text: swatch.tooltip
      fontFamily: mainPanel.fontFamily
    }
  }

  component PillButton: Rectangle {
    id: pill
    property string label: ""
    property string tooltip: ""
    property bool accent: false
    property bool selected: false
    property bool hasCursor: false
    property string iconText: ""
    signal chosen()
    signal hovered(bool isHovered)

    implicitHeight: Style.space(22)
    implicitWidth: pillRow.implicitWidth + Style.space(12)
    radius: height / 2
    scale: pillMouse.pressed ? 0.94 : 1.0
    Behavior on scale { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }

    color: accent
           ? (pillMouse.pressed ? Qt.darker(Color.accent, 1.2) : ((pillMouse.containsMouse || hasCursor) ? Qt.darker(Color.accent, 1.1) : Color.accent))
           : (selected
              ? Style.selectedFillFor(mainPanel.foreground, Color.accent)
              : (pillMouse.pressed
                 ? Style.selectedFillFor(mainPanel.foreground, Color.accent)
                 : ((pillMouse.containsMouse || hasCursor)
                    ? Style.hoverFillFor(mainPanel.foreground, Color.accent)
                    : Style.normalFillFor(mainPanel.foreground, Color.accent))))
    border.color: accent
                  ? (hasCursor ? mainPanel.foreground : "transparent")
                  : (hasCursor
                     ? (selected ? Color.accent : mainPanel.foreground)
                     : (selected
                        ? Color.accent
                        : (pillMouse.containsMouse
                           ? Qt.rgba(mainPanel.foreground.r, mainPanel.foreground.g, mainPanel.foreground.b, 0.45)
                           : Qt.rgba(mainPanel.foreground.r, mainPanel.foreground.g, mainPanel.foreground.b, 0.2))))
    border.width: (accent && !hasCursor) ? 0 : ((selected || hasCursor) ? Style.space(1.5) : Style.normalBorderWidth)

    Behavior on color { ColorAnimation { duration: 80 } }

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        visible: pill.iconText !== ""
        text: pill.iconText
        color: pill.accent
               ? Color.background
               : (pill.selected ? Color.accent : mainPanel.foreground)
        font.family: mainPanel.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: pill.label
        color: pill.accent
               ? Color.background
               : (pill.selected ? Color.accent : mainPanel.foreground)
        font.family: mainPanel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: pill.hovered(containsMouse)
      onClicked: pill.chosen()
    }

    PanelToolTip {
      visible: pillMouse.containsMouse && pill.tooltip !== ""
      text: pill.tooltip
      fontFamily: mainPanel.fontFamily
    }
  }

  component PillSlider: Item {
    id: ps
    property real minimum: 0
    property real maximum: 100
    property real value: 50
    property string sliderType: "brightness" // "brightness", "temp", "color"
    readonly property real range: Math.max(0.0001, maximum - minimum)
    readonly property real fraction: Math.max(0, Math.min(1, (value - minimum) / range))

    signal moved(real val)
    signal released(real val)

    implicitHeight: Style.space(22)
    implicitWidth: Style.space(160)

    Rectangle {
      id: track
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(6)
      radius: height / 2
      clip: true

      color: ps.sliderType === "brightness"
             ? Qt.rgba(mainPanel.foreground.r, mainPanel.foreground.g, mainPanel.foreground.b, 0.2)
             : "transparent"

      Rectangle {
        visible: ps.sliderType === "brightness"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: parent.radius
        color: "#ffffff"
        width: Math.max(0, track.width * ps.fraction)
      }

      gradient: ps.sliderType === "temp" ? tempGradient : (ps.sliderType === "color" ? colorGradient : null)

      Gradient {
        id: tempGradient
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#FFA550" }
        GradientStop { position: 0.5; color: "#FFFFFF" }
        GradientStop { position: 1.0; color: "#BCD4FF" }
      }

      Gradient {
        id: colorGradient
        orientation: Gradient.Horizontal
        GradientStop { position: 0.00; color: "#FF0000" }
        GradientStop { position: 0.17; color: "#FFFF00" }
        GradientStop { position: 0.33; color: "#00FF00" }
        GradientStop { position: 0.50; color: "#00FFFF" }
        GradientStop { position: 0.67; color: "#0000FF" }
        GradientStop { position: 0.83; color: "#FF00FF" }
        GradientStop { position: 1.00; color: "#FF0000" }
      }
    }

    Rectangle {
      id: knob
      width: Style.space(15)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(ps.width - width, (ps.width - width) * ps.fraction))
      color: "#ffffff"
      border.color: Qt.rgba(0, 0, 0, 0.25)
      border.width: 1
      scale: psArea.containsMouse || psArea.pressed ? 1.15 : 1.0

      Behavior on scale { NumberAnimation { duration: 80 } }
      Behavior on x {
        enabled: !psArea.pressed
        NumberAnimation { duration: 40 }
      }
    }

    function valueFromX(x) {
      var f = Math.max(0, Math.min(1, x / Math.max(1, ps.width)))
      return minimum + f * (maximum - minimum)
    }

    MouseArea {
      id: psArea
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPressed: function(mouse) {
        var p = psArea.mapToItem(ps, mouse.x, mouse.y).x
        var v = ps.valueFromX(p)
        ps.value = v
        ps.moved(v)
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var p = psArea.mapToItem(ps, mouse.x, mouse.y).x
        var v = ps.valueFromX(p)
        ps.value = v
        ps.moved(v)
      }
      onReleased: function(mouse) {
        var p = psArea.mapToItem(ps, mouse.x, mouse.y).x
        var v = ps.valueFromX(p)
        ps.released(v)
      }
    }
  }
}
