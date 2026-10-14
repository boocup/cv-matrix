# Where we left off (2026-10-13)

Steps 1-3 of `swift-matrix-plan.md` are done and pushed (last commit `1c2f557`). Step 3 was run on the real ES-8 and sounds right.

## Works
- Grid UI: rows, 8 knobs (drag, Shift = fine, double-click = 0 V), time/glide, speed, loop, add/duplicate/delete, autosave.
- Play/Stop with progress bar and live voltage readout under each "Out n".
- "Send to ES-8" switch (ON at every launch, untick for a dry run). On: Core Audio output on ES-8 outs 1-8, +-5 V cap, shared-slew glide, glide to 0 V on Stop and on quit.
- "Load grid..." loads a matrix_grid.json (pulled forward from step 5). Grid file: `~/Library/Application Support/CVMatrix/matrix_grid.json`.
- Run it: `swift run` from this folder. Quit with Cmd-Q (glides to 0 V first).

## Step 4 (built, awaiting your test)
- Jump to a row while playing (click the row number).
- Live knob edits while playing (Python re-applies the edited row with a 0.5 s glide).
- Check the readout and Stop behaviour with the rack connected.

## Later
- Step 5: load/export pieces (`pieces/*.json`), double-click .app bundle script, icon, optional menu bar.
- Per-channel slew (smaller changes currently arrive early).
- Open choices from the plan: menu bar app, app name and icon.

## Rules
Short replies, one change at a time, no network/LLM calls, never delete files without showing them first, do not drive the ES-8 unprompted (the user starts the first real run), commit and push after each step.
