# say_bass

**norns script** — Hum a bassline. Lock it. Loop it. Build a song.

Sing or hum a bass line into the norns microphone input. The script detects pitch in real time, snaps notes to a detected scale, and records a clock-synced MIDI loop. Stack up to 8 loops to build a complete song structure — all from your voice.

## Controls

| Control | Action |
|---------|--------|
| ENC1 | BPM |
| ENC2 | Loop length (bars) |
| ENC3 | Select loop slot (1–8) |
| K1 | Play / Stop all loops (song mode) |
| K2 | Arm recording (press again to cancel) |
| K3 | Clear selected loop |

## How it works

1. Open the app — a denture splash screen greets you
2. Press any key to enter the main view
3. Hum or sing — the app detects your pitch and the key/scale automatically
4. Press **K2** to arm recording. Recording starts on the next beat.
5. Hum your bassline. Notes are snapped to the detected scale and sent as MIDI.
6. Recording ends automatically when the loop length is reached.
7. Select another slot with **ENC3** and record another layer.
8. Press **K1** to play all active loops together.

## Features
- Real-time pitch detection via `pitch_in_l` poll
- Automatic scale detection (Major, Minor, Dorian, Phrygian, Mixolydian, Pentatonic, Blues)
- Scale-locked MIDI output on channel 1
- 8 loop slots with mini piano-roll display
- Recording progress bar
- Denture splash screen

## Installation
```
~/dust/code/say_bass/say_bass.lua
```
Load from the norns SELECT menu. Connect a MIDI device to receive output.
