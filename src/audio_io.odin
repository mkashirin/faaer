package main

import "core:strings"
import "core:time"
import ma "vendor:miniaudio"

load_audio :: proc(opt: CLI_Opts, ad: ^Audio_Data) -> (result: Audio_IO_Result) {
    audio_path := strings.clone_to_cstring(opt.audio_path)
    defer delete(audio_path)

    probe_decoder: ma.decoder
    if ma.decoder_init_file(audio_path, nil, &probe_decoder) != MA_OK {
        return .No_Decoder_Init
    }
    format, channels, sr := decoder_output_fields(&probe_decoder)
    ma.decoder_uninit(&probe_decoder) // `*uninit` should never fail

    decoder_sr := u32(f32(sr) / opt.playback_speed)
    decoder_config := ma.decoder_config_init(format, channels, decoder_sr)
    decoder: ma.decoder
    if ma.decoder_init_file(audio_path, &decoder_config, &decoder) != MA_OK {
        return .No_Decoder_Init
    }
    defer ma.decoder_uninit(&decoder)
    buf := make([dynamic]f32)
    if decoder_read_pcm_frames_to_buffer(&decoder, &buf, channels) != MA_OK {
        return .Read_Failed
    }

    ad.raw_buffer = buf[:]
    ad.channels = channels
    ad.sample_rate = sr
    return
}

save_audio :: proc(
    ng: ^ma.node_graph,
    buf_len: int,
    channels, sr: u32,
    opt: CLI_Opts,
) -> (result: Audio_IO_Result) {
    save_path := strings.clone_to_cstring(opt.save_path)
    defer delete(save_path)

    config := ma.encoder_config_init(.wav, .f32, channels, sr)
    encoder: ma.encoder
    if ma.encoder_init_file(save_path, &config, &encoder) != MA_OK { return .No_Encoder_Init }
    defer ma.encoder_uninit(&encoder) // `*uninit` should never fail

    buf := make([]f32, 4096 * channels)
    defer delete(buf)

    tail_frames := sr * 2 if opt.reverb else 0
    total_frames := u64(buf_len) / u64(channels) + u64(tail_frames)
    total_read: u64 = 0
    for total_read < total_frames {
        left := min(4096, total_frames - total_read)
        frames_read: u64
        if ma.node_graph_read_pcm_frames(ng, raw_data(buf), left, &frames_read) != MA_OK {
            return .Node_Graph_Failed
        }
        if frames_read == 0 { break }

        if ma.encoder_write_pcm_frames(&encoder, raw_data(buf), frames_read, nil) != MA_OK {
            return .Write_Failed
        }
        total_read += u64(frames_read)
    }
    return
}

play_to_device :: proc(
    ng: ^ma.node_graph,
    buf_len: int,
    channels, sr: u32,
    opt: CLI_Opts,
) -> (result: Audio_IO_Result) {
    config := ma.device_config_init(.playback)
    device_config_preset(&config, ng, channels, sr)
    device: ma.device
    if ma.device_init(nil, &config, &device) != MA_OK { return .No_Device_Init }
    defer ma.device_uninit(&device) // `*uninit` should never fail

    if ma.device_start(&device) != MA_OK { return .Start_Failed }
    tail_ms := u64(2000) if opt.reverb else 0
    duration_ms := (u64(buf_len) / u64(channels) * 1000) / u64(sr)

    time.sleep(time.Duration(duration_ms + tail_ms) * time.Millisecond)
    return
}

carve_audio :: proc(ad: ^Audio_Data, opt: CLI_Opts) -> (result: []f32) {
    buf := ad.raw_buffer
    channels := u64(ad.channels)
    native_sr := u64(ad.sample_rate)

    trim(&buf, opt.start_ms, opt.end_ms, channels, native_sr)
    fade_volume(&buf, opt.fade_in_ms, opt.fade_out_ms, channels, native_sr)
    result = make([]f32, len(buf) * int(opt.loop))
    for l in 0 ..< int(opt.loop) { copy(result[l * len(buf):(l + 1) * len(buf)], buf) }
    return
}

trim :: proc(buf: ^[]f32, start_ms, end_ms, channels, natvie_sr: u64) {
    f_start := (start_ms * natvie_sr) / 1000
    f_end := (end_ms * natvie_sr) / 1000
    total := u64(len(buf)) / channels
    if f_end == 0 || f_end > total { f_end = total }
    if f_start > f_end { f_start = 0 }
    buf^ = buf[f_start * channels:f_end * channels]
}

fade_volume :: proc(buf: ^[]f32, fade_in_ms, fade_out_ms, channels, native_sr: u64) {
    total := u64(len(buf)) / channels
    fade_in := (fade_in_ms * native_sr) / 1000
    fade_in = min(fade_in, total)
    for i in 0 ..< fade_in {
        volume := f32(i) / f32(fade_in)
        for c in 0 ..< channels { buf[i * channels + c] *= volume }
    }

    fade_out := (fade_out_ms * native_sr) / 1000
    fade_out = min(fade_out, total)
    for i in 0 ..< fade_out {
        volume := 1.0 - (f32(i) / f32(fade_out))
        frame_i := total - fade_out + i
        for c in 0 ..< channels { buf[frame_i * channels + c] *= volume }
    }
}

Audio_IO_Result :: Maybe(Audio_IO_Error)
Audio_IO_Error :: enum {
    No_Device_Init = 2,
    No_Decoder_Init,
    No_Encoder_Init,
    Start_Failed,
    Read_Failed,
    Node_Graph_Failed,
    Write_Failed,
}

Audio_Data :: struct { raw_buffer: []f32, channels: u32, sample_rate: u32 }
