package faaer

import "core:fmt"
import ma "vendor:miniaudio"

Eq_Preset :: enum {
    none,
    bass_boost,
    treble_boost,
    muffled,
}

Config :: struct {
    // Base settings
    audio_path:     string,
    playback_speed: f32,
    reverb:         bool,
    eq:             Eq_Preset,
    // Duration and audio volume fading
    start_ms:       u64,
    end_ms:         u64,
    fade_in_ms:     u64,
    fade_out_ms:    u64,
    // Looping and saving
    loop:           u32,
    save:           string,
}

Effects :: struct {
    eq_lo: ma.loshelf_node,
    eq_hi: ma.hishelf_node,
    delay: ma.delay_node,
}

setup_effects :: proc(
    engine: ^ma.engine,
    sound: ^ma.sound,
    config: ^Config,
    fx: ^Effects,
) -> (
    ma.result,
    string,
) {
    current_tail := cast(^ma.node)sound
    channels := ma.engine_get_channels(engine)
    sample_rate := ma.engine_get_sample_rate(engine)

    switch config.eq {
        case .none:
        case .bass_boost:
            cfg := ma.loshelf_node_config_init(
                channels,
                sample_rate,
                8.0,
                0.707,
                150.0,
            )
            result := ma.loshelf_node_init(
                ma.engine_get_node_graph(engine),
                &cfg,
                nil,
                &fx.eq_lo,
            )
            if result != .SUCCESS {
                return result, "Failed to initialize BB EQ node."
            }
            ma.node_attach_output_bus(
                current_tail,
                0,
                cast(^ma.node)&fx.eq_lo,
                0,
            )
            current_tail = cast(^ma.node)&fx.eq_lo
            fmt.println("EQ: Bass Boost applied.")
        case .treble_boost:
            cfg := ma.hishelf_node_config_init(
                channels,
                sample_rate,
                6.0,
                0.707,
                3000.0,
            )
            result := ma.hishelf_node_init(
                ma.engine_get_node_graph(engine),
                &cfg,
                nil,
                &fx.eq_hi,
            )
            if result != .SUCCESS {
                return result, "Failed to initialize TB EQ node."
            }
            ma.node_attach_output_bus(
                current_tail,
                0,
                cast(^ma.node)&fx.eq_hi,
                0,
            )
            current_tail = cast(^ma.node)&fx.eq_hi
            fmt.println("EQ: Treble Boost applied.")
        case .muffled:
            cfg := ma.hishelf_node_config_init(
                channels,
                sample_rate,
                -20.0,
                0.707,
                800.0,
            )
            result := ma.hishelf_node_init(
                ma.engine_get_node_graph(engine),
                &cfg,
                nil,
                &fx.eq_hi,
            )
            if result != .SUCCESS {
                return result, "Failed to initialize MF EQ node."
            }
            ma.node_attach_output_bus(
                current_tail,
                0,
                cast(^ma.node)&fx.eq_hi,
                0,
            )
            current_tail = cast(^ma.node)&fx.eq_hi
            fmt.println("EQ: Muffled (High-Cut) applied.")
    }

    if config.reverb {
        cfg := ma.delay_node_config_init(channels, sample_rate, 100, 0.4)
        result := ma.delay_node_init(
            ma.engine_get_node_graph(engine),
            &cfg,
            nil,
            &fx.delay,
        )
        if result != .SUCCESS {
            return result, "Failed to initialize delay node (reverb effect)."
        }
        ma.node_attach_output_bus(current_tail, 0, cast(^ma.node)&fx.delay, 0)
        current_tail = cast(^ma.node)&fx.delay
        fmt.println("Reverb: Delay-based slapback applied.")
    }

    ma.node_attach_output_bus(
        current_tail,
        0,
        ma.engine_get_endpoint(engine),
        0,
    )
    return .SUCCESS, ""
}

cleanup_effects :: proc(config: ^Config, fx: ^Effects) {
    if config.eq == .bass_boost {
        ma.loshelf_node_uninit(&fx.eq_lo, nil)
    } else if config.eq == .treble_boost || config.eq == .muffled {
        ma.hishelf_node_uninit(&fx.eq_hi, nil)
    }

    if config.reverb {
        ma.delay_node_uninit(&fx.delay, nil)
    }
}

