import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var lights: []
  property bool busy: false
  property bool scanning: false
  property string lastError: ""
  property date lastUpdated: new Date(0)

  readonly property string scriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("wizctl.py")).replace(/^file:\/\//, ""))
  readonly property int pollSec: intSetting("pollIntervalSec", 15, 5, 600)
  readonly property int scanTimeoutSec: intSetting("scanTimeoutSec", 8, 4, 30)

  property var queue: []
  property var currentJob: null
  property string latestOutput: ""
  property real holdUntil: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function run(args, onDone, coalesceKey) {
    if (coalesceKey) {
      for (var i = queue.length - 1; i >= 0; i--) {
        if (queue[i].coalesceKey === coalesceKey) {
          queue[i] = { args: args, onDone: onDone, coalesceKey: coalesceKey }
          pump()
          return
        }
      }
    }
    queue.push({ args: args, onDone: onDone, coalesceKey: coalesceKey || "" })
    pump()
  }

  function refresh() {
    if (queue.length > 1) return
    run(["status"], null)
  }

  function scan() {
    scanning = true
    run(["discover"], function(parsed) { scanning = false })
    scanGuard.restart()
  }

  function setPower(ip, turnOn, onDone) {
    run(["set", ip, turnOn ? "on" : "off"], onDone)
  }

  function setAllPower(turnOn, onDone) {
    run(["set-all", turnOn ? "on" : "off"], onDone)
  }

  function setScene(ip, sceneId, onDone) {
    hold(2000)
    run(["scene", ip, String(sceneId)], onDone)
  }

  function hold(milliseconds) {
    holdUntil = Date.now() + milliseconds
  }

  function setBright(ip, percent, onDone, coalesceKey) {
    hold(2000)
    run(["bright", ip, String(Math.round(percent))], onDone, coalesceKey)
  }

  function setTemp(ip, kelvin, onDone, coalesceKey) {
    hold(2000)
    run(["temp", ip, String(Math.round(kelvin))], onDone, coalesceKey)
  }

  function setRgb(ip, r, g, b, onDone) {
    hold(2000)
    var hex = "#" + [r, g, b].map(function(c) {
      var h = Math.max(0, Math.min(255, Math.round(Number(c) || 0))).toString(16)
      return h.length < 2 ? "0" + h : h
    }).join("")
    run(["color", ip, hex], onDone)
  }

  function setHex(ip, hex, onDone, coalesceKey) {
    hold(2000)
    run(["color", ip, String(hex)], onDone, coalesceKey)
  }

  function rename(mac, name, onDone) {
    run(["rename", mac, name], onDone)
  }

  function forget(mac, onDone) {
    run(["forget", mac], onDone)
  }

  function savePreset(mac, presetObj, onDone) {
    run(["save-preset", String(mac), JSON.stringify(presetObj)], onDone)
  }

  function deletePreset(mac, index, onDone) {
    run(["delete-preset", String(mac), String(index)], onDone)
  }

  function pump() {
    if (busy || queue.length === 0) return
    currentJob = queue.shift()
    lastError = ""
    proc.command = ["python3", scriptPath].concat(currentJob.args)
    proc.running = true
    busy = true
  }

  Timer {
    interval: root.pollSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!root.scanning && root.queue.length === 0 && Date.now() >= root.holdUntil) root.refresh()
  }

  Timer {
    id: scanGuard
    interval: root.scanTimeoutSec * 1000
    onTriggered: root.scanning = false
  }

  Process {
    id: proc
    command: []
    stdout: StdioCollector {
      id: collectorOutput
      waitForEnd: true
      onStreamFinished: root.latestOutput = text
    }
    stderr: StdioCollector {
      id: collectorStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.busy = false
      var job = root.currentJob
      root.currentJob = null
      var parsed = Model.parse(root.latestOutput)
      if (parsed.ok) {
        if (Array.isArray(parsed.lights)) {
          root.lights = parsed.lights
          root.lastUpdated = new Date()
        }
        if (!root.scanning || (parsed.lights && parsed.lights.length > 0)) {
          root.lastError = ""
        }
      } else {
        var detail = String(collectorStderr.text || "").replace(/\s+/g, " ").trim()
        var errMsg = detail ? detail.slice(0, 160) : (parsed && parsed.error ? String(parsed.error) : "")
        if (errMsg && errMsg !== "undefined") {
          root.lastError = errMsg
        }
      }
      if (job && job.onDone) job.onDone(parsed, exitCode)
      pump()
    }
  }
}
