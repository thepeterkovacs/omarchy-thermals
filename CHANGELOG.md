# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1]

### Fixed

- Bounded `sensors -j` output so a malformed or unusually large run can no
  longer accumulate in the long-lived shell process: the command now runs
  under a 5-second timeout and its output is capped at 256 KiB.
- Capped the number of detail rows (256) and label length (64 characters)
  parsed from sensor output, without ever blocking CPU/GPU headline detection.
- Kept the last-good readings when parsing fails instead of blanking the bar.

## [1.1.0]

### Changed

- Renamed the detail panel title from "Temperatures" to "Thermals".
- Widened the bar's open-panel underline so it spans both temperature values.
- Removed the chip-name subtitles (e.g. `k10temp-pci-00c3`) from the CPU and
  GPU panel section headers.

### Removed

- Network-adapter temperature sensors are no longer shown; they added noise
  without useful signal.

## [1.0.0]

### Added

- CPU and GPU temperature bar widget for the Omarchy bar.
- Detailed thermal panel shown on click.
- Sensor readings via lm_sensors (AMD, Intel, and other sensors).
