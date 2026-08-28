import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.thepeterkovacs.thermals"

  // ------------------------------------------------------------------ state
  // All temperatures in °C. -1 means "not reported by this machine".
  //
  // CPU: the package/die temperature (Tctl on AMD, Package id 0 on Intel) is
  // the industry-standard headline number and what appears on the bar.
  // GPU: modern cards throttle on the hotspot (junction) sensor, so that is
  // the headline number; we fall back to edge when a card has no junction.
  property real cpuTemp: -1        // CPU package/die
  property real gpuHeadline: -1    // hotspot if present, else edge
  property real gpuEdge: -1
  property real gpuJunction: -1
  property real gpuMem: -1
  property string cpuChip: ""
  property string gpuChip: ""

  // Extra thermal channels for the detail panel: array of
  // { group, label, temp, crit } rows. Populated on every refresh.
  property var detailRows: []

  // Refresh interval and "too hot" thresholds (bar turns to the urgent color).
  readonly property int refreshMs: 3000
  readonly property int cpuHot: 90
  readonly property int gpuHot: 95

  // Hard limits so a malformed or unexpectedly large `sensors -j` output can
  // never exhaust this long-lived shell process. Typical output is a few KB,
  // so these leave ample headroom for many-sensor machines while bounding the
  // worst case. Bytes and time are capped at the OS level (see sensorsProc)
  // before the collector retains anything; maxRows/maxLabelLen bound only the
  // detail-panel model, never the CPU/GPU headline detection.
  readonly property int maxBytes: 262144    // 256 KiB producer byte cap
  readonly property int procTimeout: 5      // seconds; hard process deadline
  readonly property int maxRows: 256        // detail rows to keep
  readonly property int maxLabelLen: 64     // per-row label length

  // ---------------------------------------------------------- panel wiring
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Widen the open-panel underline to span both temperature values, rather
  // than the bar's default 55%-of-slot mark which is too short for our label.
  readonly property real openPanelIndicatorWidth:
    (button.labelWidth > 0 ? button.labelWidth : button.implicitWidth) + Style.space(4)

  onBarChanged: injectPanel()

  function fmt(t) {
    return t >= 0 ? Math.round(t) + "°" : "--"
  }

  // --------------------------------------------------------------- parsing
  //
  // Vendor-agnostic parse of `sensors -j`. Rather than hard-coding one chip
  // name per vendor, we classify each chip by well-known driver prefixes and
  // fall back to sensible heuristics, so AMD, Intel, and common add-in
  // sensors all light up without per-machine tweaks.

  function firstInput(obj) {
    if (!obj || typeof obj !== "object") return -1
    for (var k in obj)
      if (k.indexOf("_input") >= 0 && typeof obj[k] === "number")
        return obj[k]
    return -1
  }

  // Pull a *_crit reading out of a channel object, if present.
  function critOf(obj) {
    if (!obj || typeof obj !== "object") return -1
    for (var k in obj)
      if (k.indexOf("_crit") >= 0 && k.indexOf("_crit_") < 0
          && typeof obj[k] === "number")
        return obj[k]
    return -1
  }

  function isCpuChip(chip) {
    // AMD: k10temp / zenpower ; Intel: coretemp / (some) k8temp
    return chip.indexOf("k10temp") === 0
        || chip.indexOf("zenpower") === 0
        || chip.indexOf("coretemp") === 0
        || chip.indexOf("k8temp") === 0
  }

  function isGpuChip(chip) {
    // AMD discrete/APU: amdgpu ; Intel: i915 / xe / intel
    return chip.indexOf("amdgpu") === 0
        || chip.indexOf("i915") === 0
        || chip.indexOf("xe") === 0
        || chip.indexOf("intel") === 0 && chip.indexOf("gpu") >= 0
  }

  // Clamp a label to a sane length so a pathological chip/channel name can't
  // bloat the model or the panel layout.
  function clampLabel(s) {
    s = String(s)
    return s.length > root.maxLabelLen ? s.substring(0, root.maxLabelLen) : s
  }

  function parseSensors(jsonText) {
    // `jsonText` is already bounded to `maxBytes` by the OS-level `head -c`
    // in sensorsProc, so JSON.parse can never see an unbounded string.
    var data
    try {
      data = JSON.parse(jsonText)
    } catch (e) {
      // Keep the last-good readings rather than blanking the bar. This is the
      // fail-safe path for a truncated/garbled producer; with ~100x headroom
      // over typical output it should only ever fire under abuse.
      return
    }
    if (!data || typeof data !== "object") return

    var cpu = -1, cpuName = ""
    var gEdge = -1, gJunc = -1, gMem = -1, gpuName = ""
    var gpuScore = -1
    var rows = []

    // The total chip count is already bounded by `maxBytes` (JSON.parse only
    // sees a capped string), so we scan every chip for the CPU/GPU headline —
    // never skipping one, since its key order in `sensors -j` is not
    // guaranteed. Only `rows` (the detail-panel model) grows per channel, so
    // that is where the item cap lives, below.
    for (var chip in data) {
      var block = data[chip]
      if (!block || typeof block !== "object") continue

      // ---------------------------------------------------------- CPU
      if (isCpuChip(chip)) {
        // Preferred package channels first, then any channel as a fallback.
        var pkg = -1
        if (block["Tctl"] !== undefined) pkg = firstInput(block["Tctl"])
        else if (block["Package id 0"] !== undefined) pkg = firstInput(block["Package id 0"])
        else if (block["Tdie"] !== undefined) pkg = firstInput(block["Tdie"])
        if (pkg < 0) {
          // fall back to the first temp channel in the chip
          for (var ck in block) {
            var cv = firstInput(block[ck])
            if (cv >= 0) { pkg = cv; break }
          }
        }
        if (pkg >= 0 && (cpu < 0 || pkg > cpu)) { cpu = pkg; cpuName = chip }

        // Per-core / CCD detail rows.
        for (var cc in block) {
          if (rows.length >= root.maxRows) break
          if (cc === "Adapter") continue
          var ct = firstInput(block[cc])
          if (ct >= 0)
            rows.push({ group: "CPU", label: clampLabel(cc), temp: ct, crit: critOf(block[cc]) })
        }
      }

      // ---------------------------------------------------------- GPU
      else if (isGpuChip(chip)) {
        // Prefer the GPU with the most temp channels (the discrete card over
        // an integrated one). Score by presence of junction/mem.
        var score = 0
        if (block["junction"] !== undefined) score += 2
        if (block["mem"] !== undefined) score += 1
        var edge = block["edge"] !== undefined ? firstInput(block["edge"]) : -1
        var junc = block["junction"] !== undefined ? firstInput(block["junction"]) : -1
        var memt = block["mem"] !== undefined ? firstInput(block["mem"]) : -1
        // Intel GPUs typically expose a single "temp1" channel.
        if (edge < 0 && junc < 0) edge = firstInput(block)

        if ((edge >= 0 || junc >= 0) && score >= gpuScore) {
          gEdge = edge
          gJunc = junc
          gMem = memt
          gpuName = chip
          gpuScore = score
        }
      }

      // ------------------------------------------------ everything else
      // NVMe drives, motherboard, RAM, chipset — surface them all in the
      // panel under a friendly group so nothing useful is thrown away.
      // (Network-adapter sensors are dropped; they add noise, not signal.)
      else {
        var group = "Other"
        if (chip.indexOf("nvme") === 0) group = "Storage"
        else if (chip.indexOf("drivetemp") === 0) group = "Storage"
        else if (chip.indexOf("spd5118") === 0 || chip.indexOf("jc42") === 0) group = "Memory"
        else if (chip.indexOf("mt7921") === 0 || chip.indexOf("iwlwifi") === 0
                 || chip.indexOf("r8169") === 0) continue  // network sensors are noise
        else if (chip.indexOf("nct") === 0 || chip.indexOf("it87") === 0) group = "Motherboard"

        for (var ok in block) {
          if (rows.length >= root.maxRows) break
          if (ok === "Adapter") continue
          var ov = firstInput(block[ok])
          if (ov >= 0)
            rows.push({ group: group, label: clampLabel(shortChip(chip) + " · " + ok),
                        temp: ov, crit: critOf(block[ok]) })
        }
      }
    }

    root.cpuTemp = cpu
    root.cpuChip = cpuName
    root.gpuEdge = gEdge
    root.gpuJunction = gJunc
    root.gpuMem = gMem
    root.gpuHeadline = gJunc >= 0 ? gJunc : gEdge
    root.gpuChip = gpuName
    root.detailRows = rows
  }

  // Trim the "-pci-00c3" bus suffix off a chip name for tidy labels.
  function shortChip(chip) {
    var i = chip.indexOf("-")
    return i > 0 ? chip.substring(0, i) : chip
  }

  Process {
    id: sensorsProc
    // Bound the producer at the OS level *before* QML collects anything:
    //   timeout -k 1 N ...  — hard deadline; kills a hung `sensors` process
    //   head -c BYTES       — caps stdout bytes (SIGPIPEs sensors once full)
    // so the StdioCollector below can never retain more than `maxBytes`.
    command: ["sh", "-c",
      "timeout -k 1 " + root.procTimeout
        + " sensors -j | head -c " + root.maxBytes]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSensors(text)
    }
  }

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sensorsProc.running) sensorsProc.running = true
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // CPU package temp and GPU hotspot, side by side.
    text: root.fmt(root.cpuTemp) + " " + root.fmt(root.gpuHeadline)
    active: (root.cpuTemp >= root.cpuHot) || (root.gpuHeadline >= root.gpuHot)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
