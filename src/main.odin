package faaer

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"
import ma "vendor:miniaudio"

main :: proc() {
    config := Config {
        playback_speed = 1.0,
        reverb         = false,
        eq             = .none,
    }

    flags.parse_or_exit(&config, os.args, .Odin)

    if config.audio_path == "" {
        fmt.eprintln("Error: Provide an audio file")
        return
    }

    engine: ma.engine
    if ma.engine_init(nil, &engine) != .SUCCESS {
        fmt.eprintfln("Error: Failed to initialize audio engine")
        return
    }
    defer ma.engine_uninit(&engine)

    audio_path := strings.clone_to_cstring(
        config.audio_path,
        context.temp_allocator,
    )

    sound: ma.sound
    sound_res := ma.sound_init_from_file(
        &engine,
        audio_path,
        {.STREAM},
        nil,
        nil,
        &sound,
    )
    if sound_res != .SUCCESS {
        fmt.eprintfln(
            "Error: Failed to load sound file: %s",
            config.audio_path,
        )
        return
    }
    defer ma.sound_uninit(&sound)

    fx: Effects
    fx_res, err := setup_effects(&engine, &sound, &config, &fx)
    if fx_res != .SUCCESS {
        fmt.eprintfln("Error: %s", err)
        return
    }
    defer cleanup_effects(&config, &fx)

    apply_audio_carving_and_fades(&sound, &config)

    ma.sound_set_pitch(&sound, config.playback_speed)

    if config.save != "" {
        render_audio(&engine, &sound, &config)
        return
    }

    ma.sound_start(&sound)
    fmt.printfln(
        "Playing '%s' at %.2fx speed. Press Enter to quit...",
        config.audio_path,
        config.playback_speed,
    )

    buf: [1]byte
    _, _ = os.read(os.stdin, buf[:])
}

