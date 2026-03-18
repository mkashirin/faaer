package main

import ma "vendor:miniaudio"

MA_OK : ma.result : .SUCCESS

// This procedure adopts Miniaduio's naming convention, since the sole purpose of it is to preset a
// device config, which would be used as an input to `ma.device_init()`. Basically, this would be
// in C, if the program was linked against literal libminiaudio. Same goes for any other function
// in this file.
device_config_preset :: proc(
    pConfig: ^ma.device_config, pNodeGraph: ^ma.node_graph,
    channels, sampleRate: u32,
) {
    data_callback :: proc "c" (pDevice: ^ma.device, pOutput, pInput: rawptr, frameCount: u32) {
        nodeGraph := cast(^ma.node_graph)pDevice.pUserData
        ma.node_graph_read_pcm_frames(nodeGraph, pOutput, u64(frameCount), nil)
    }

    pConfig.playback.format   = .f32
    pConfig.playback.channels = channels
    pConfig.sampleRate        = sampleRate
    pConfig.dataCallback      = data_callback
    pConfig.pUserData         = pNodeGraph
}

decoder_output_fields :: proc(decoder: ^ma.decoder) -> (
    format: ma.format,
    channels: u32,
    sr: u32,
) {
    format = decoder.outputFormat
    channels = decoder.outputChannels
    sr = decoder.outputSampleRate
    return
}

decoder_read_pcm_frames_to_buffer :: proc(
    decoder: ^ma.decoder,
    buf: ^[dynamic]f32,
    channels: u32,
) -> ma.result {
    chunk := make([]f32, 4096 * channels)
    defer delete(chunk)
    for {
        framesRead: u64
        result := ma.decoder_read_pcm_frames(decoder, raw_data(chunk), 4096, &framesRead)
        if framesRead > 0 { append(buf, ..chunk[:framesRead * u64(channels)]) }
        if result == .AT_END { break } else if result != .SUCCESS { return result }
    }
    return .SUCCESS
}

