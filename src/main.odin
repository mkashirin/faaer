package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import ma "vendor:miniaudio"

Eq_Preset :: enum {
    none,
    bass_boost,
    treble_boost,
    muffled,
}

Config :: struct {
    audio_path:     string,
    playback_speed: f32,
    reverb:         bool,
    eq:             Eq_Preset,
    start_ms:       u64,
    end_ms:         u64,
    fade_in_ms:     u64,
    fade_out_ms:    u64,
    loop:           u32,
    save:           string,
}

Effects :: struct {
    eq_lo: ma.loshelf_node,
    eq_hi: ma.hishelf_node,
    delay: ma.delay_node,
}

Audio_Data :: struct {
    buffer:      []f32,
    channels:    u32,
    sample_rate: u32,
}

data_callback :: proc "c" (
    pDevice: ^ma.device,
    pOutput, pInput: rawptr,
    frameCount: u32,
) {
    graph := cast(^ma.node_graph)pDevice.pUserData
    ma.node_graph_read_pcm_frames(graph, pOutput, u64(frameCount), nil)
}

main :: proc() {
    if !run() do os.exit(1)
}

run :: proc() -> bool {
    config, ok := parse_config()
    if !ok do return false

    audio_data, load_ok := load_audio(config)
    if !load_ok do return false
    defer delete(audio_data.buffer)

    final_buffer := apply_edits(audio_data, config)
    defer delete(final_buffer)

    return execute_audio_graph(
        final_buffer,
        audio_data.channels,
        audio_data.sample_rate,
        config,
    )
}

parse_config :: proc() -> (Config, bool) {
    config: Config
    config.playback_speed = 1.0
    config.loop = 1
    flags.parse(&config, os.args[1:], .Odin)
    if config.audio_path == "" {
        fmt.eprintln("Error: `-audio-path` is required")
        return config, false
    }
    if config.playback_speed <= 0 do config.playback_speed = 1.0
    if config.loop == 0 do config.loop = 1

    fmt.printfln("Parsed config: %#v\n", config)
    return config, true
}

load_audio :: proc(config: Config) -> (data: Audio_Data, ok: bool) {
    audio_path_c := strings.clone_to_cstring(config.audio_path)
    defer delete(audio_path_c)

    probe_dec: ma.decoder
    if ma.decoder_init_file(audio_path_c, nil, &probe_dec) != .SUCCESS {
        fmt.eprintfln(
            "Error: Failed to open/probe audio file: %s",
            config.audio_path,
        )
        return data, false
    }
    native_sr := probe_dec.outputSampleRate
    channels := probe_dec.outputChannels
    ma.decoder_uninit(&probe_dec)

    decode_sr := u32(f32(native_sr) / config.playback_speed)
    dec_config := ma.decoder_config_init(ma.format.f32, channels, decode_sr)

    dec: ma.decoder
    if ma.decoder_init_file(audio_path_c, &dec_config, &dec) != .SUCCESS {
        fmt.eprintfln(
            "Error: Failed to initialize decoder for file: %s",
            config.audio_path,
        )
        return data, false
    }
    defer ma.decoder_uninit(&dec)

    buffer := make([dynamic]f32)
    chunk := make([]f32, 4096 * channels)
    defer delete(chunk)
    for {
        read_count: u64
        ma.decoder_read_pcm_frames(&dec, raw_data(chunk), 4096, &read_count)
        if read_count == 0 do break
        append(&buffer, ..chunk[:read_count * u64(channels)])
    }

    data.buffer = buffer[:]
    data.channels = channels
    data.sample_rate = native_sr
    return data, true
}

apply_edits :: proc(data: Audio_Data, config: Config) -> []f32 {
    buffer := data.buffer
    channels := u64(data.channels)
    native_sr := u64(data.sample_rate)

    start_frame := (config.start_ms * native_sr) / 1000
    end_frame := (config.end_ms * native_sr) / 1000
    total_decoded_frames := u64(len(buffer)) / channels
    if end_frame == 0 || end_frame > total_decoded_frames {
        end_frame = total_decoded_frames
    }
    if start_frame > end_frame do start_frame = 0

    trimmed := buffer[start_frame * channels:end_frame * channels]
    total_trimmed_frames := u64(len(trimmed)) / channels

    fade_in_frames := (config.fade_in_ms * native_sr) / 1000
    fade_in_frames = min(fade_in_frames, total_trimmed_frames)
    for i in 0 ..< fade_in_frames {
        vol := f32(i) / f32(fade_in_frames)
        for c in 0 ..< channels {
            trimmed[i * channels + c] *= vol
        }
    }

    fade_out_frames := (config.fade_out_ms * native_sr) / 1000
    fade_out_frames = min(fade_out_frames, total_trimmed_frames)
    for i in 0 ..< fade_out_frames {
        vol := 1.0 - (f32(i) / f32(fade_out_frames))
        frame_idx := total_trimmed_frames - fade_out_frames + i
        for c in 0 ..< channels {
            trimmed[frame_idx * channels + c] *= vol
        }
    }

    final_buffer := make([]f32, len(trimmed) * int(config.loop))
    for l in 0 ..< int(config.loop) {
        copy(final_buffer[l * len(trimmed):(l + 1) * len(trimmed)], trimmed)
    }
    return final_buffer
}

execute_audio_graph :: proc(
    final_buffer: []f32,
    channels, native_sr: u32,
    config: Config,
) -> bool {
    graph: ma.node_graph
    graph_config := ma.node_graph_config_init(channels)
    if ma.node_graph_init(&graph_config, nil, &graph) != .SUCCESS {
        fmt.eprintln("Error: Failed to init node graph")
        return false
    }
    defer ma.node_graph_uninit(&graph, nil)

    audio_buffer: ma.audio_buffer
    buf_config := ma.audio_buffer_config_init(
        ma.format.f32,
        channels,
        u64(len(final_buffer)) / u64(channels),
        raw_data(final_buffer),
        nil,
    )
    ma.audio_buffer_init(&buf_config, &audio_buffer)

    ds_node: ma.data_source_node
    ds_config := ma.data_source_node_config_init(
        cast(^ma.data_source)&audio_buffer,
    )
    ma.data_source_node_init(&graph, &ds_config, nil, &ds_node)

    effects: Effects
    lo_gain, hi_gain: f64 = 0, 0
    switch config.eq {
        case .none:
        case .bass_boost:
            lo_gain = 12.0
        case .treble_boost:
            hi_gain = 12.0
        case .muffled:
            hi_gain = -24.0
    }

    lo_config := ma.loshelf_node_config_init(
        channels,
        native_sr,
        lo_gain,
        0.5,
        250.0,
    )
    ma.loshelf_node_init(&graph, &lo_config, nil, &effects.eq_lo)
    hi_config := ma.hishelf_node_config_init(
        channels,
        native_sr,
        hi_gain,
        0.5,
        2000.0,
    )
    ma.hishelf_node_init(&graph, &hi_config, nil, &effects.eq_hi)
    delay_config := ma.delay_node_config_init(
        channels,
        native_sr,
        native_sr / 8,
        0.4,
    )
    ma.delay_node_init(&graph, &delay_config, nil, &effects.delay)

    ma.node_attach_output_bus(
        cast(^ma.node)&ds_node,
        0,
        cast(^ma.node)&effects.eq_lo,
        0,
    )
    ma.node_attach_output_bus(
        cast(^ma.node)&effects.eq_lo,
        0,
        cast(^ma.node)&effects.eq_hi,
        0,
    )

    endpoint := ma.node_graph_get_endpoint(&graph)
    if config.reverb {
        ma.node_attach_output_bus(
            cast(^ma.node)&effects.eq_hi,
            0,
            cast(^ma.node)&effects.delay,
            0,
        )
        ma.node_attach_output_bus(
            cast(^ma.node)&effects.delay,
            0,
            endpoint,
            0,
        )
    } else {
        ma.node_attach_output_bus(
            cast(^ma.node)&effects.eq_hi,
            0,
            endpoint,
            0,
        )
    }

    if config.save != "" {
        return save_audio_to_file(
            &graph,
            len(final_buffer),
            channels,
            native_sr,
            config,
        )
    } else {
        return play_audio_to_device(
            &graph,
            len(final_buffer),
            channels,
            native_sr,
            config,
        )
    }
}

save_audio_to_file :: proc(
    graph: ^ma.node_graph,
    final_buffer_len: int,
    channels, native_sr: u32,
    config: Config,
) -> bool {
    fmt.printfln("Rendering audio offline and saving to: %s", config.save)
    save_path_c := strings.clone_to_cstring(config.save)
    defer delete(save_path_c)

    enc_config := ma.encoder_config_init(.mp3, .f32, channels, native_sr)
    enc: ma.encoder
    if ma.encoder_init_file(save_path_c, &enc_config, &enc) != .SUCCESS {
        fmt.eprintln(
            "Error: Failed to initialize encoder. Check if destination exists",
        )
        return false
    }
    defer ma.encoder_uninit(&enc)

    read_buf := make([]f32, 4096 * channels)
    defer delete(read_buf)

    tail_frames := config.reverb ? native_sr * 2 : 0
    total_to_read :=
        (u64(final_buffer_len) / u64(channels)) + u64(tail_frames)

    frames_read: u64 = 0
    for frames_read < total_to_read {
        to_read := min(4096, total_to_read - frames_read)
        read_count: u64
        ma.node_graph_read_pcm_frames(
            graph,
            raw_data(read_buf),
            to_read,
            &read_count,
        )
        if read_count == 0 do break

        ma.encoder_write_pcm_frames(&enc, raw_data(read_buf), read_count, nil)
        frames_read += u64(read_count)
    }

    fmt.println("Successfully saved!")
    return true
}

play_audio_to_device :: proc(
    graph: ^ma.node_graph,
    final_buffer_len: int,
    channels, native_sr: u32,
    config: Config,
) -> bool {
    fmt.println("Playing audio... (Ctrl+C to quit)")
    dev_config := ma.device_config_init(ma.device_type.playback)
    dev_config.playback.format = ma.format.f32
    dev_config.playback.channels = channels
    dev_config.sampleRate = native_sr
    dev_config.dataCallback = data_callback
    dev_config.pUserData = graph

    dev: ma.device
    if ma.device_init(nil, &dev_config, &dev) != .SUCCESS {
        fmt.eprintln("Error: Failed to initialize playback device")
        return false
    }
    defer ma.device_uninit(&dev)

    if ma.device_start(&dev) != .SUCCESS {
        fmt.eprintln("Error: Failed to start playback device")
        return false
    }
    tail_ms := config.reverb ? u64(2000) : 0
    duration_ms :=
        ((u64(final_buffer_len) / u64(channels)) * 1000) / u64(native_sr)

    time.sleep(time.Duration(duration_ms + tail_ms) * time.Millisecond)
    fmt.println("Playback finished.")
    return true
}

