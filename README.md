# THEREELPEET CV Matrix

![THEREELPEET CV Matrix playing a six-row grid](res/CVMatrix-screenshot.png)

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
2. Set one row with Out 1 at +2 V and a glide of a few seconds.
3. Press play and check the meter. It should read about +2 V.

Full scale (+-1.0 in the audio stream) is assumed to be about +-10 V on the jack. The author measured it about 1% low at 1, 2.5 and 5 V. Your unit may differ, so check it.

## Using it

| To do this | Do this |
|---|---|
| Change a voltage | Drag a knob up or down (200 px is the full 10 V) |
| Fine adjust | Hold **Shift** while dragging (ten times finer) |
| Set a knob to 0 V | Double-click it |
| Play from a row | Click its round number badge |
| Jump to another row while playing | Click that row's badge |
| Stop | Press **Stop**; every output glides to 0 V |
| Add, copy or remove a row | **+ Add row**, the copy button, the delete button on each row |
| Leave a text box | Press **Escape** or click empty space |

Each row has:

- **Chapter**: a name, up to 40 characters.
- **Time**: how long the row lasts, in seconds (1 to 3600).
- **Glide**: how many of those seconds are spent moving from the previous row's voltages to this row's. It can't be longer than the time.
- **Out 1 to Out 8**: the eight knobs, -5 to +5 V.

Along the top:

- **Play from row N**: starts from the selected row.
- **Send to ES-8**: on at every launch. Untick it for a **dry run** that shows the computed voltages without sending anything.
- **Speed**: multiplies every row's time and glide. 0.5 is twice as fast, 2 is half speed.
- **Loop**: go back to row 1 after the last row. Otherwise it stops and glides to 0 V.
- **Autosave**: off at every launch (see Files below).

The small green numbers under each "Out" heading are where that output is right now, so you can watch the glides.

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

- **Load grid...** opens a file like this. It asks before replacing the current grid and stops playback first. Loading never writes back to the file you opened.
- **Save grid...** saves a copy of the current grid wherever you choose.
- **Autosave** is a switch, off at every launch. When ticked, the current grid is written as you edit, to `~/Library/Application Support/CVMatrix/matrix_grid.json`, and that file is what the app opens at launch. With it off, your edits are lost when you quit unless you used Save grid.

## Safety and limits

- Every output is capped at **+-5 V** in the code, whatever the grid says.
- Outputs move by gliding only. They never jump to a new value.
- The ES-8 is opened only when you press play with **Send to ES-8** ticked, and released when the outputs reach 0 V.
- Only ES-8 outputs 1 to 8 are used. macOS reports 16 outputs, but the rest are ADAT channels that only carry signal with an expander.
- After the rack is power cycled, the ES-8 can disappear from the Mac until its USB cable is unplugged and plugged back in. If the app says it can't find or start the ES-8, do that and try again.
- Quit with Cmd-Q or by closing the window, not by killing the process. A quit glides the outputs to 0 V first; a kill does not.
- This is a hobby project with no warranty. Check voltages before patching into anything you can't afford to damage.

## Project layout

    Sources/CVMatrix/
      CVMatrixApp.swift   app entry, window and quit handling
      ContentView.swift   the grid screen
      KnobView.swift      the knobs
      Model.swift         rows and the grid file format
      Store.swift         the grid, loading, saving
      Player.swift        play logic and glides
      ES8Output.swift     Core Audio output to the ES-8
    scripts/
      make-app.sh         builds dist/CVMatrix.app
      make-icon.swift     draws the app icon

## Not yet done

- A separate glide speed per output, so every output takes the full glide time

## License

[MIT](./LICENSE), by Pete Buchhop.
