# Notes

xterm.dart is a terminal emulator engine and Flutter widget for Dart.

## Documents
- [Terminal Driver and Automation Design](terminal_driver_automation_design.md): Design for script automation, quiet period detection, special tag signaling, bell detection, and capturing TUI/alt-buffer scrollback.

## Features and Status
- Viewport snapping: snaps viewport height to whole cell multiples to prevent fractional cell clipping at the bottom edge.
- Terminal Driver: script driver for running automation with quiet detection, tags, bells, and back-buffer capture.
