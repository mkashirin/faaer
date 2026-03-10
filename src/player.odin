package faaer

import "core:fmt"
import "core:strings"
import "core:thread"
import "core:time"
import ma "vendor:miniaudio"

Playback_Ctx :: struct {
    sound:       ^ma.sound,
    config:      Config,
    start_frame: u64,
    end_frame:   u64,
    loops:       u32,
}

monitor_playback :: proc(t: ^thread.Thread) {
    ctx := cast(^Playback_Ctx)t.user_args[0]
    defer free(ctx)

    sample_rate: u32
    ma.sound_get_data_format(ctx.sound, nil, nil, &sample_rate, nil, 0)

    segment_frames := ctx.end_frame - ctx.start_frame
    segment_ms := segment_frames * 1000 / u64(sample_rate)

    dur := f32(segment_ms) / ctx.config.playback_speed

    fade_in := f32(ctx.config.fade_in_ms)
    fade_out := f32(ctx.config.fade_out_ms)

    for i: u32 = 0; i < ctx.loops; i += 1 {
        ma.sound_seek_to_pcm_frame(ctx.sound, ctx.start_frame)

        if fade_in > 0 {
            ma.sound_set_fade_in_milliseconds(
                ctx.sound,
                0.0,
                1.0,
                u64(fade_in),
            )
        }

        if fade_out > 0 && dur > fade_out {
            sleep_time := time.Duration(dur - fade_out)
            time.sleep(sleep_time * time.Millisecond)

            ma.sound_set_fade_in_milliseconds(
                ctx.sound,
                1.0,
                0.0,
                u64(fade_out),
            )

            time.sleep(time.Duration(fade_out) * time.Millisecond)

        } else { time.sleep(time.Duration(dur) * time.Millisecond) }
    }
    ma.sound_stop(ctx.sound)
}

apply_audio_carving_and_fades :: proc(sound: ^ma.sound, config: ^Config) {
    sample_rate: u32
    ma.sound_get_data_format(sound, nil, nil, &sample_rate, nil, 0)

    start_frame: u64 = 0
    end_frame: u64 = 0
    length: u64 = 0

    ma.sound_get_length_in_pcm_frames(sound, &length)

    if config.start_ms > 0 {
        start_frame = config.start_ms * u64(sample_rate) / 1000
    }

    if config.end_ms > 0 {
        end_frame = config.end_ms * u64(sample_rate) / 1000
    } else { end_frame = length }

    if end_frame > length { end_frame = length }

    if start_frame >= end_frame { return }

    ma.sound_seek_to_pcm_frame(sound, start_frame)

    ctx := new(Playback_Ctx)
    ctx.sound = sound
    ctx.config = config^
    ctx.start_frame = start_frame
    ctx.end_frame = end_frame
    ctx.loops = max(config.loop, 1)

    t := thread.create(monitor_playback)
    t.user_args[0] = ctx
    thread.start(t)
}

render_audio :: proc(
    engine: ^ma.engine,
    sound: ^ma.sound,
    config: ^Config,
) -> (
    ma.result,
    string,
) {
    sample_rate := ma.engine_get_sample_rate(engine)
    channels := ma.engine_get_channels(engine)

    output := strings.clone_to_cstring(config.save, context.temp_allocator)
    encoder_cfg := ma.encoder_config_init(
        .mp3,
        ma.format.f32,
        channels,
        sample_rate,
    )

    encoder: ma.encoder
    res := ma.encoder_init_file(output, &encoder_cfg, &encoder)
    if res != .SUCCESS { return res, "Failed to open encoder." }
    defer ma.encoder_uninit(&encoder)

    frames_per_chunk: u32 = 4096
    buffer := make([]f32, frames_per_chunk * channels)

    total_frames: u64
    ma.sound_get_length_in_pcm_frames(sound, &total_frames)

    if config.loop > 1 { total_frames *= u64(config.loop) }

    written: u64 = 0
    for written < total_frames {
        frames := min(u64(frames_per_chunk), total_frames - written)
        ma.engine_read_pcm_frames(engine, raw_data(buffer), frames, nil)
        ma.encoder_write_pcm_frames(&encoder, raw_data(buffer), frames, nil)
        written += frames
    }

    fmt.println("Saved processed audio.")
    return .SUCCESS, ""
}

