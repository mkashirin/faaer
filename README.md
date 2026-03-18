# Faaer (Fast Audio Effects Processor)

Faaer is a very small and limited AEP. It is built to produce the *"slowed + reverb"* versions of a
songs (or their specific parts) and music in general. Executable takes audio file as input, then it
can either save processed audio to a specified path, or start a playback of it.

The following options are available for configuration:
* `-audio-path` — path to the input audio file,
* `-reverb` — whether to apply reverb effect or not (flag),
* `-eq-preset` — equalizeer preset (`None`, `Bass_Boost`, `Treble_Boost`, `Muffled`),
* `-start-ms` — where to seek in the output audio, to set the start of a trimmed region,
* `-end-ms` — where to seek in the output audio, to set the end of a trimmed region,
* `-fade-in-ms` — how long would volume fade in,
* `-fade-out-ms` — how long would volume fade out,
* `-loop` — how many times the trimmed region should be replayed (with volume fading applied),
* `-save-path` — where the output audio file should be saved.

## Building and Running

To build an executable:
```
./build.sh
```

To run (example):
```
./run.sh
```

On Windows, use external Bash executable to run these scripts.

## Licensing

This software is distributed under MIT License.
