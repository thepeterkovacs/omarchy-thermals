# Thermals

An [Omarchy](https://omarchy.org) bar widget that shows your CPU and GPU
temperatures at a glance, with a detailed thermal panel on click.

- **Bar** — CPU package temperature and GPU hotspot, side by side. Turns the
  bar's urgent color when things get too hot.
- **Panel** (click the widget) — a full breakdown of every thermal sensor the
  machine reports: CPU package and per-core/CCD channels, GPU hotspot / edge /
  memory, plus storage (NVMe/SATA), RAM, motherboard, and network sensors.
  Readings approaching their critical threshold are highlighted.

Reads temperatures from [`lm_sensors`](https://github.com/lm-sensors/lm-sensors)
(`sensors -j`) and works with AMD and Intel CPUs and GPUs out of the box.

## Requirements

- Omarchy (Quickshell-based shell)
- `lm_sensors` installed and configured (`sudo sensors-detect`, then verify with
  `sensors`)

> **Note on NVIDIA GPUs:** discrete NVIDIA cards do not expose temperatures
> through `lm_sensors`, so their GPU reading will show `--`. AMD and Intel GPUs
> are fully supported.

## Install

```bash
omarchy plugin add https://github.com/thepeterkovacs/omarchy-thermals --enable
```

Or clone it into your plugins directory manually:

```bash
git clone https://github.com/thepeterkovacs/omarchy-thermals \
  ~/.config/omarchy/plugins/io.github.thepeterkovacs.thermals
omarchy restart shell
```

Then place it on the bar (if it isn't already):

```bash
omarchy plugin enable io.github.thepeterkovacs.thermals right
```

## Configuration

The refresh interval and "too hot" thresholds are near the top of
`BarWidget.qml`:

```qml
readonly property int refreshMs: 3000   // how often to read sensors, in ms
readonly property int cpuHot: 90        // CPU °C that turns the bar urgent
readonly property int gpuHot: 95        // GPU °C that turns the bar urgent
```

## License

[MIT](LICENSE)
