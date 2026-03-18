#!/bin/bash

odin run src -- \
  -audio-path:./audio/Alan_Fitzpatrick_-_We_Do_What_We_Want.mp3 \
  -playback-speed:0.70 \
  -reverb \
  -eq-preset:Muffled \
  -start-ms:10750 \
  -end-ms:32650 \
  -fade-in-ms:2000 \
  -fade-out-ms:2000 \
  -loop:4 \
  -save-path:./audio/Alan_Fitzpatrick_-_We_Do_What_We_Want_\(Slowed\).wav
