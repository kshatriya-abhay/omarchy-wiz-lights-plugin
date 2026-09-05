.pragma library

function parse(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || typeof parsed !== "object") {
      return { ok: false, error: "Could not parse wizctl output" }
    }
    if (parsed.ok !== true) {
      return { ok: false, error: parsed.error ? String(parsed.error) : "Operation failed" }
    }
    return {
      ok: true,
      lights: Array.isArray(parsed.lights) ? parsed.lights : null,
      discovered: Array.isArray(parsed.discovered) ? parsed.discovered : null,
      raw: parsed
    }
  } catch (error) {
    return { ok: false, error: "Could not parse wizctl output" }
  }
}

function countOn(lights, uiState) {
  var total = Array.isArray(lights) ? lights.length : 0
  var on = 0
  for (var i = 0; i < total; i++) {
    var l = lights[i]
    if (l && l.reachable) {
      var mac = String(l.mac || "")
      var override = (uiState && uiState[mac] && uiState[mac].power !== undefined) ? uiState[mac].power : l.state
      if (override) on++
    }
  }
  return { on: on, total: total }
}

function rssiText(dbm) {
  if (dbm === null || dbm === undefined || dbm === "") return ""
  var value = Number(dbm)
  if (!isFinite(value) || value === 0) return ""
  return Math.round(value) + " dBm"
}

function metaText(light) {
  if (!light) return ""
  if (!light.reachable) return "offline · " + String(light.ip || "")
  var parts = []
  if (light.moduleName) parts.push(String(light.moduleName))
  if (light.ip) parts.push(String(light.ip))
  var rssi = rssiText(light.rssi)
  if (rssi !== "") parts.push(rssi)
  return parts.join(" · ")
}

function hsvToRgb(h, s, v) {
  var hue = ((Number(h) || 0) % 360 + 360) % 360
  var sat = Math.max(0, Math.min(1, Number(s) || 0))
  var val = Math.max(0, Math.min(1, Number(v) || 0))
  var c = val * sat
  var x = c * (1 - Math.abs((hue / 60) % 2 - 1))
  var m = val - c
  var rp = 0, gp = 0, bp = 0
  if (hue < 60) { rp = c; gp = x } else if (hue < 120) { rp = x; gp = c }
  else if (hue < 180) { gp = c; bp = x } else if (hue < 240) { gp = x; bp = c }
  else if (hue < 300) { rp = x; bp = c } else { rp = c; bp = x }
  return {
    r: Math.round((rp + m) * 255),
    g: Math.round((gp + m) * 255),
    b: Math.round((bp + m) * 255)
  }
}

function rgbToHsv(r, g, b) {
  var rn = (Number(r) || 0) / 255
  var gn = (Number(g) || 0) / 255
  var bn = (Number(b) || 0) / 255
  var max = Math.max(rn, gn, bn)
  var min = Math.min(rn, gn, bn)
  var d = max - min
  var h = 0
  if (d > 0) {
    if (max === rn) h = 60 * (((gn - bn) / d) % 6)
    else if (max === gn) h = 60 * ((bn - rn) / d + 2)
    else h = 60 * ((rn - gn) / d + 4)
  }
  if (h < 0) h += 360
  return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function rgbToHex(r, g, b) {
  function byte(v) {
    var n = Math.max(0, Math.min(255, Math.round(Number(v) || 0)))
    var hex = n.toString(16)
    return hex.length < 2 ? "0" + hex : hex
  }
  return ("#" + byte(r) + byte(g) + byte(b)).toUpperCase()
}

function hueToHex(h) {
  var rgb = hsvToRgb(h, 1, 1)
  return rgbToHex(rgb.r, rgb.g, rgb.b).toUpperCase()
}

function kelvinToHex(k) {
  var temp = (Number(k) || 2700) / 100
  var r, g, b
  if (temp <= 66) r = 255
  else {
    r = temp - 60
    r = 329.698727446 * Math.pow(r, -0.1332047592)
    r = Math.max(0, Math.min(255, r))
  }
  if (temp <= 66) {
    g = temp
    g = 99.4708025861 * Math.log(g) - 161.1195681661
    g = Math.max(0, Math.min(255, g))
  } else {
    g = temp - 60
    g = 288.1221695283 * Math.pow(g, -0.0755148492)
    g = Math.max(0, Math.min(255, g))
  }
  if (temp >= 66) b = 255
  else if (temp <= 19) b = 0
  else {
    b = temp - 10
    b = 138.5177312231 * Math.log(b) - 305.0447927307
    b = Math.max(0, Math.min(255, b))
  }
  return rgbToHex(r, g, b).toUpperCase()
}

function hexToRgb(hex) {
  if (!hex || typeof hex !== "string") return null
  var clean = hex.replace(/^#/, "")
  if (clean.length === 3) {
    clean = clean.split("").map(function(c) { return c + c }).join("")
  }
  if (clean.length !== 6) return null
  var num = parseInt(clean, 16)
  if (isNaN(num)) return null
  return {
    r: (num >> 16) & 255,
    g: (num >> 8) & 255,
    b: num & 255
  }
}

var exportsObject = {
  parse: parse,
  countOn: countOn,
  rssiText: rssiText,
  metaText: metaText,
  hsvToRgb: hsvToRgb,
  rgbToHsv: rgbToHsv,
  rgbToHex: rgbToHex,
  hexToRgb: hexToRgb,
  hueToHex: hueToHex,
  kelvinToHex: kelvinToHex
}

if (typeof module !== "undefined" && module.exports) module.exports = exportsObject
