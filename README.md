# THEREELPEET CV Matrix

![THEREELPEET CV Matrix playing chapter 4 of a five-chapter grid (dry run)](res/CVMatrix-screenshot.png)

A small Mac app that turns an Expert Sleepers **ES-8** into eight slowly moving control voltages for a modular rack.

You write a piece as a list of **chapters** (rows). Each row holds eight voltages (one per ES-8 output, -5 to +5 V), how long the row lasts, and how much of that time is spent gliding in from the previous row. Press play and the rows run top to bottom, optionally looping. The outputs never jump: every change is a glide. It runs fully offline and sends nothing anywhere except the ES-8.

It is made for long, evolving pieces: level or rate CVs, slow offsets, crossfades, anything that should drift over minutes rather than steps.

## What you need

- A Mac running macOS 14 or later
- An Expert Sleepers ES-8 connected over USB (not needed for a dry run)
- To build it: Xcode and Swift 5.9 or later (it was built and tested with the full Xcode, not the Command Line Tools alone)

It has been tested on Apple Silicon with an ES-8. There is no prebuilt download, so you build it yourself (below).

## Install

    git clone https://github.com/boocup/cv-matrix.git
    cd cv-matrix
    ./scripts/make-app.sh

That makes `dist/CVMatrix.app` (a release build with an icon, signed ad hoc). Drag it into `/Applications`.

The first time you open it, macOS may refuse because the app is not notarised. Right-click it, choose **Open**, then confirm. You only need to do this once.

macOS may ask for microphone access. The ES-8 is one audio device with both inputs and outputs, so the system treats opening it as possible recording. CV Matrix only sends voltages and never reads the inputs, so you can allow or deny it.

To run it without building the `.app`, or if the build fails, see [Build from source](#build-from-source).

## Build from source

1. **Install Xcode** from the App Store (it was built and tested with the full Xcode, not the Command Line Tools alone), open it once so it finishes installing components, and accept the license if asked:

        sudo xcodebuild -license accept

2. **Check the toolchain** points at the full Xcode and that Swift works:

        xcode-select -p        # should print /Applications/Xcode.app/Contents/Developer
        swift --version

   If `xcode-select -p` shows `/Library/Developer/CommandLineTools`, switch it:

        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

3. **Get the code:**

        git clone https://github.com/boocup/cv-matrix.git
        cd cv-matrix

4. **Build and run it**, either way:

        swift run                 # debug build, starts the app straight away
        ./scripts/make-app.sh     # release build, makes dist/CVMatrix.app

   `make-app.sh` builds in release mode, draws the icon, writes the `Info.plist`, and signs the app ad hoc. It needs only Xcode and the tools that ship with macOS (`swift`, `sips`, `iconutil`, `codesign`). The result is `dist/CVMatrix.app`; the `dist/` folder is not committed.

Other commands:

    swift build               # compile only (debug)
    swift build -c release    # compile only (release)
    rm -rf .build dist        # clean everything built

The project is a Swift package (`Package.swift`) with no third-party dependencies, so there is nothing to download besides the code. There is no Xcode project file; to work on it in Xcode, open the folder (File > Open) and Xcode will use the package.

If the build fails, the usual causes are an older Xcode than macOS 14 supports, or the toolchain still pointing at the Command Line Tools (step 2).

## First run: do this before patching it into anything

A wrong voltage goes into real gear. The first time:

1. Patch **only Out 1** to a multimeter or to an ES-8 input you can read back. Leave everything else unpatched.
2. Set one row with Out 1 at +2 V, Time Short and Glide Low (a 7.5 s glide).
3. Press play and check the meter. It should read about +2 V.

Full scale (+-1.0 in the audio stream) is assumed to be about +-10 V on the jack. The author measured it about 1% low at 1, 2.5 and 5 V. Your unit may differ, so check it.

## Using it

| To do this | Do this |
|---|---|
| Change a voltage | Drag a knob up or down (200 px is the full 10 V) |
| Fine adjust | Hold **Shift** while dragging (ten times finer) |
| Set a knob to 0 V | Double-click it |
| Set a chapter's Time or Glide | Click a position on its switch, or drag the lever. Hover the switch to see what each position means for that chapter |
| Shift Out 5 up or Out 6 down by an interval | Drag its stepped knob up or down: None, 3rd, 5th, Octave (1 V/oct). Double-click for None |
| Gate on Out 7 | Flip its switch to On (+5 V). It is held for the whole row and snaps, with no glide |
| Trigger on Out 8 | Flip its switch to On. It sends a 20 ms +5 V pulse at the start of the row |
| Play from a row | Click its round number badge, or click its chapter in the visualizer |
| Jump to another row while playing | Click that row's badge |
| Stop | Press **Stop** (⌘.); every output glides to 0 V |
| Add, copy or remove a row | **Add Chapter** under the rows, or the copy and trash buttons at the end of each row |
| Leave a text box | Press **Escape** or click empty space |

Each row has:

- **Chapter**: a name, up to 40 characters, shown as a title. Double-click it to rename; Return or Escape finishes.
- **Time**: a three-way switch for how long the row lasts: Short 30 s, Standard 60 s, Long 120 s.
- **Glide**: a three-way switch for how much of that time is spent moving from the previous row's voltages to this row's: Low a quarter, Medium a third, High half.
- **Outputs 1 to 4** (Lead, Harmony, Drone, Texture, on a blue band): knobs, -5 to +5 V.
- **Outputs 5 and 6** (Pitch ↑ and Pitch ↓, on an orange band): stepped pitch-shift knobs (None, major 3rd, 5th, octave), Out 5 upward and Out 6 downward.
- **Output 7** (Gate): an Off / On switch.
- **Output 8** (Trigger): an Off / On switch; On fires at the start of the row.

The numbered badge in each column heading is the ES-8 output it drives.

Along the top, next to the THEREELPEET wordmark: the name of the grid file you are working on ("Untitled" until it is saved), with **Edited** when it has unsaved changes, then **Open…** (⌘O), **Save** (⌘S), **Save As…** (⇧⌘S) and **Export to OXI** (⌘E, see below).

Under that is the dark **display**:

- **Play** (⌘Return) starts from the selected chapter; **Stop** (⌘.) glides every output to 0 V.
- The readout shows the chapter that is playing (or the selected one, when stopped), with its time and the whole piece's time.
- **Half / Normal / Double**: playback speed for the whole piece. A grid saved with some other speed keeps it, and none of the three is highlighted.
- **Loop**: go back to row 1 after the last row. Otherwise it stops and glides to 0 V.
- **ES-8 / Dry run**: on at every launch. Switch it off for a **dry run** that shows the computed voltages without sending anything.
- The **visualizer** draws the whole piece, one colored line per output (1 Lead, 2 Harmony, 3 Drone, 4 Texture, 5 Pitch ↑, 6 Pitch ↓), as it plays from chapter 1, with chapter numbers along the top, gate-high stretches as an amber bar along the bottom and triggers as small ticks. While playing, a playhead moves across it, the part already played lights up, and a dot on each line shows where that output really is. Click anywhere in it to play from that chapter, or to jump there while playing.
- The **meters** on the right show outputs 1 to 6 live, as bars up or down from 0 V. **G** lights while the gate is high, and **T** flashes on each trigger.

The small numbers under each column heading are where that output is right now, so you can watch the glides.

If you change a knob on the row that is playing, that output follows it with a half-second glide. Edits to other rows take effect when those rows play.

The window sizes itself to show every row when it opens (up to the size of your screen).

## How the glide works

When a row starts, the largest voltage change across the eight outputs takes exactly the glide time. Outputs with smaller changes get there sooner and then wait. All eight share one speed in volts per second. Very short glides are treated as at least 0.2 s so an output never snaps.

On Stop, on reaching the end of a piece, and on quit, the outputs glide back to 0 V at 10 V per second before the audio device is closed.

## Files

The grid is a small JSON file:

    {
      "rows": [
        {
          "name": "Quiet Dawn Emergence",
          "time": 120,
          "glide": 30,
          "values": [1.75, 0, 0.6, 2.5, 0, 0, 0, 0]
        }
      ],
      "speed": 1.0,
      "loop": false
    }

Grid files live in `~/Documents/CV Matrix/`: **Open…** and **Save As…** start there. The folder is created the first time it is needed, and macOS may ask once whether the app may use your Documents folder.

- **Open…** loads a file like this and stops playback first. Opening never writes to the file; only Save does.
- Times and glides in a file are seconds. One that isn't a switch position (say a 90 s chapter with a 37.5 s glide) snaps to the nearest positions when it loads: the time to 30, 60 or 120 s, and the glide to the nearest quarter, third or half of that. Out 5 and 6 snap the same way to None, 3rd, 5th or octave, Out 7 to off or on, and a trigger saved as `"after"` (after the glide, from older versions) now fires at the start. The file itself only changes if you save over it.
- **Save As…** saves the grid under a new name and from then on Save writes there. It suggests the name of the file you last opened or saved, without the date or corpus-id prefix.
- **Save** writes to the file you opened or last saved; for an Untitled grid it asks for a name, like **Save As…**. Nothing is saved until you do.
- The app reopens that file at launch. If you open another grid, close the window or quit with unsaved changes, it asks whether to save them first.

## Export to an OXI ONE

**Export to OXI** (⌘E) writes the grid as an OXI ONE MKII project (firmware 2.2.10), so the OXI can play the piece without the Mac:

- It always writes `~/Downloads/Projects/cvm.oxipro`, replacing the last export, so it lands in the same slot every time. macOS may ask once whether the app may use your Downloads folder.
- In the OXI App's Projects tab, drag it from **On Computer** onto a slot **On Device**, then load that slot on the OXI and press Play.
- Outputs 1 to 7 become sequencer 1's mod lanes 1 to 7, routed to **CV 1 to 7**. The gate (Out 7) switches instead of gliding. Triggers (Out 8) become short notes on sequencer 2, routed to **Gate 1**.
- A lane has 128 steps, so the piece is played in steps: 3.75 s each at 64 BPM, with glides written as ramps of those steps. A longer piece gets longer steps (up to 10 s, about 21 minutes in all); the message under the display says which. A piece longer than that is refused.
- Lanes reach +5 V and −3 V, the OXI's output range. Pitch shifts are rounded to the nearest lane value: Out 6 (down) within 10 cents, Out 5 (up) up to about 22 cents.

The file format and the measurements behind this are in `~/vcv-dev/llm/OXI_EXPORT_NOTES.md`; `conductor/oxi_project.py` there writes the same file from the command line.

## Safety and limits

- Every output is capped at **+-5 V** in the code, whatever the grid says.
- Outputs 1 to 6 move by gliding only; they never jump to a new value. The two exceptions are marked in the grid: **Out 7** is a gate that snaps between 0 V and +5 V, and **Out 8** only ever sends a short +5 V trigger pulse (20 ms) and is otherwise 0 V. Both are capped at +5 V like everything else, and both go to 0 V on Stop and quit. Keep Out 7 and 8 away from level or pitch inputs.
- The ES-8 is opened only when you press play with **Send to ES-8** ticked, and released when the outputs reach 0 V.
- Only ES-8 outputs 1 to 8 are used. macOS reports 16 outputs, but the rest are ADAT channels that only carry signal with an expander.
- After the rack is power cycled, the ES-8 can disappear from the Mac until its USB cable is unplugged and plugged back in. If the app says it can't find or start the ES-8, do that and try again.
- Quit with Cmd-Q or by closing the window, not by killing the process. A quit glides the outputs to 0 V first; a kill does not.
- This is a hobby project with no warranty. Check voltages before patching into anything you can't afford to damage.

## Project layout

    Sources/CVMatrix/
      CVMatrixApp.swift   app entry, window and quit handling
      ContentView.swift   the grid screen
      Display.swift       the dark display: transport, readout, visualizer, meters
      KnobView.swift      the knobs and output menus
      Theme.swift         the THEREELPEET panel colors
      Model.swift         rows and the grid file format
      Store.swift         the grid, loading, saving
      Player.swift        play logic and glides
      ES8Output.swift     Core Audio output to the ES-8
      OXIExport.swift     Export to OXI: the grid as an OXI ONE project
    scripts/
      make-app.sh         builds dist/CVMatrix.app
      make-icon.swift     draws the app icon

## Not yet done

- A separate glide speed per output, so every output takes the full glide time

## License

[MIT](./LICENSE), by Pete Buchhop.
