import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.thepeterkovacs.thermals"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function fmt(t) {
    return (t !== undefined && t >= 0) ? Math.round(t) + "°C" : "--"
  }

  // Build an ordered list of section groups from the host's detailRows,
  // keeping a stable, sensible order and skipping empty groups.
  function groupedRows() {
    var rows = (root.hostWidget && root.hostWidget.detailRows)
      ? root.hostWidget.detailRows : []
    var order = ["CPU", "GPU", "Storage", "Memory", "Motherboard", "Other"]
    var byGroup = {}
    for (var i = 0; i < rows.length; i++) {
      var g = rows[i].group
      if (!byGroup[g]) byGroup[g] = []
      byGroup[g].push(rows[i])
    }
    var out = []
    for (var j = 0; j < order.length; j++) {
      var name = order[j]
      // CPU/GPU headline sections are rendered explicitly below; here we only
      // add the non-headline groups plus any per-core CPU rows.
      if (name === "GPU") continue
      if (byGroup[name] && byGroup[name].length)
        out.push({ name: name, rows: byGroup[name] })
    }
    return out
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---- Title ----
        Text {
          width: parent.width
          text: "Thermals"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        // ---------------------------------------------------------- CPU
        SectionHeader { title: "CPU" }

        TempRow {
          label: "Package"
          value: root.fmt(root.hostWidget ? root.hostWidget.cpuTemp : -1)
          bold: true
        }
        // Per-core / CCD channels reported by the CPU chip.
        Repeater {
          model: root.hostWidget ? root.hostWidget.detailRows : []
          delegate: TempRow {
            visible: modelData.group === "CPU"
              && modelData.label !== "Tctl"
              && modelData.label !== "Package id 0"
              && modelData.label !== "Tdie"
            height: visible ? implicitHeight : 0
            label: modelData.label
            value: root.fmt(modelData.temp)
            crit: modelData.crit
          }
        }

        Divider {}

        // ---------------------------------------------------------- GPU
        SectionHeader { title: "GPU" }

        Repeater {
          model: [
            { label: "Hotspot", key: "gpuJunction", bold: true },
            { label: "Edge",    key: "gpuEdge",     bold: false },
            { label: "Memory",  key: "gpuMem",      bold: false }
          ]
          delegate: TempRow {
            property real t: root.hostWidget ? root.hostWidget[modelData.key] : -1
            visible: t >= 0
            height: visible ? implicitHeight : 0
            label: modelData.label
            value: root.fmt(t)
            bold: modelData.bold
          }
        }

        // -------------------------------------------- other sensor groups
        Repeater {
          model: root.groupedRows()
          delegate: Column {
            width: content.width
            spacing: Style.space(10)
            visible: modelData.name !== "CPU"   // CPU handled above

            Divider {}
            SectionHeader { title: modelData.name }
            Repeater {
              model: modelData.rows
              delegate: TempRow {
                label: modelData.label
                value: root.fmt(modelData.temp)
                crit: modelData.crit
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components
  component SectionHeader : Row {
    property string title: ""
    width: content.width
    spacing: Style.space(6)
    Text {
      text: parent.title
      color: root.barForeground
      opacity: 0.7
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  component TempRow : Row {
    property string label: ""
    property string value: "--"
    property bool bold: false
    property real crit: -1
    // Turn the value red as it approaches its crit threshold (within 5°C).
    readonly property bool hot: {
      if (crit <= 0) return false
      var n = parseInt(value)
      return !isNaN(n) && n >= crit - 5
    }
    width: content.width
    Text {
      width: parent.width * 0.62
      text: parent.label
      elide: Text.ElideRight
      color: root.barForeground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      width: parent.width * 0.38
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: parent.hot ? (root.bar ? root.bar.urgent : Color.urgent) : root.barForeground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: parent.bold
    }
  }

  component Divider : Rectangle {
    width: content.width
    height: 1
    color: root.barForeground
    opacity: 0.15
  }
}
