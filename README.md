# Faaer (Fast Audio Effects Processor)

To build:
```
odin build src -o:size -out:faaer
```

To run (example):
```
odin run src -- \
  -audio-path:./audios/Alan_Fitzpatrick_-_We_Do_What_We_Want.mp3 \
  -playback-speed:0.75 \
  -reverb \
  -eq:muffled \
  -start-ms:9600 \
  -end-ms:23750 \
  -fade-in-ms:2000 \
  -fade-out-ms:4000 \
  -loop:2 \
  -save:./audios/Alan_Fitzpatrick_-_We_Do_What_We_Want_\(Slowed\).mp3
```

Built with Miniaudio.
