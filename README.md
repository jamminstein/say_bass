# say bass

hum a bassline. lock it. loop it. build a song.

pitch-tracking bass looper for monome norns.

## features

- real-time pitch detection via norns mic input
- auto scale detection from your humming
- scale-quantized note snapping
- 8 loop slots with independent record/play
- mini piano roll visualization
- MIDI out for external synths
- song mode (play all loops simultaneously)
- animated teeth splash screen

## controls

- **ENC1**: tempo (BPM)
- **ENC2**: loop length (1-8 bars)
- **ENC3**: select loop slot
- **KEY1**: toggle song mode (play all loops)
- **KEY2**: arm/start recording
- **KEY3**: clear selected loop

## how it works

1. hum or sing a bass note into the norns mic
2. the script detects pitch and locks to a scale
3. press K2 to arm recording, hum your bassline
4. loop auto-locks when the bar count completes
5. stack up to 8 loops and play them all in song mode

## requirements

- monome norns
- working mic input
- MIDI connection (optional, for external synth)

## install

```
;install https://github.com/jamminstein/say_bass
```
