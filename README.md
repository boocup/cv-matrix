# THEREELPEET CV Matrix

A native Mac app that sends slowly changing control voltages to the eight outputs of an Expert Sleepers **ES-8**, for a modular rack.

Chapters run down the left. Each row has eight knobs (ES-8 outputs 1-8, -5 to +5 V), a time, and a glide. Rows play top to bottom, optionally looping, with a speed multiplier. The outputs glide between rows and glide back to 0 V on Stop and on quit. It runs fully offline.

## Run

    swift run

Needs macOS 14 or later and Xcode. "Send to ES-8" is on at launch; untick it for a dry run that only shows the computed voltages.

## Use

- Drag a knob up or down; hold Shift for fine steps; double-click for 0 V.
- Click a row number to select it, or to jump there while playing.
- Knob edits on the playing row take effect while it plays (0.5 s glide).
- "Load grid..." opens a `matrix_grid.json`. The grid autosaves to `~/Library/Application Support/CVMatrix/matrix_grid.json`.

Output is capped at +-5 V. Full scale (+-1.0 in the audio stream) is taken as about +-10 V; check your unit with a meter.

`reference/` holds the Python prototype this was ported from.

## License

[MIT](./LICENSE), by Pete Buchhop.
