import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property real hue: 30
  property real sat: 1
  property int planeRadius: Math.max(Style.space(4), Style.cornerRadius)
  readonly property color planeBorder: Qt.rgba(
    Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)
  signal moved(real h, real s)
  signal released(real h, real s)

  implicitHeight: Style.space(64)

  onHueChanged: refreshMarker()
  onSatChanged: refreshMarker()
  Component.onCompleted: refreshMarker()

  function refreshMarker() {
    var rgb = Model.hsvToRgb(hue, sat, 1)
    marker.color = Qt.rgba(rgb.r / 255, rgb.g / 255, rgb.b / 255, 1)
  }

  function markerLeft() {
    if (width <= 0) return 0
    var half = markerOuter.width / 2
    var inset = half * 0.65
    var center = Math.max(inset, Math.min(width - inset, (hue / 360) * width))
    return center - half
  }

  function markerTop() {
    if (height <= 0) return 0
    var half = markerOuter.height / 2
    var inset = half * 0.65
    var center = Math.max(inset, Math.min(height - inset, sat * height))
    return center - half
  }

  function applyPosition(x, y) {
    var fx = Math.max(0, Math.min(1, x / Math.max(1, width)))
    var fy = Math.max(0, Math.min(1, y / Math.max(1, height)))
    hue = fx * 360
    sat = fy
  }

  // GPU-accelerated 2D color plane (zero CPU Canvas repaints)
  Rectangle {
    id: plane
    anchors.fill: parent
    radius: root.planeRadius
    clip: true

    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.000; color: "#ff0000" }
      GradientStop { position: 0.167; color: "#ffff00" }
      GradientStop { position: 0.333; color: "#00ff00" }
      GradientStop { position: 0.500; color: "#00ffff" }
      GradientStop { position: 0.667; color: "#0000ff" }
      GradientStop { position: 0.833; color: "#ff00ff" }
      GradientStop { position: 1.000; color: "#ff0000" }
    }

    Rectangle {
      anchors.fill: parent
      radius: root.planeRadius
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: "#ffffffff" }
        GradientStop { position: 1.0; color: "#00ffffff" }
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: root.planeRadius
    border.color: root.planeBorder
    border.width: Style.normalBorderWidth
  }

  Rectangle {
    id: markerOuter
    width: Style.space(17)
    height: width
    radius: width / 2
    color: "transparent"
    border.color: Qt.rgba(0, 0, 0, 0.55)
    border.width: 3
    visible: root.width > 0 && root.height > 0
    x: root.markerLeft()
    y: root.markerTop()

    Behavior on x {
      enabled: !area.pressed && root.width > 0
      NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
    }
    Behavior on y {
      enabled: !area.pressed && root.height > 0
      NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
    }

    Rectangle {
      id: marker
      anchors.centerIn: parent
      width: parent.width - Style.space(4)
      height: width
      radius: width / 2
      border.color: "#ffffff"
      border.width: 2
      color: "#ffffff"
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor

    onPressed: function(mouse) {
      root.applyPosition(mouse.x, mouse.y)
      root.moved(root.hue, root.sat)
    }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      root.applyPosition(mouse.x, mouse.y)
      root.moved(root.hue, root.sat)
    }
    onReleased: function(mouse) {
      root.applyPosition(mouse.x, mouse.y)
      root.released(root.hue, root.sat)
    }
  }
}
