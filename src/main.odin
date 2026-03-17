package main

import "core:flags"
import "core:fmt"
import "core:os"
import ma "vendor:miniaudio"

main :: proc() {
    if err := run(); err != nil {
        fmt.eprintfln("An error occured: %#v", err); os.exit(1)
    }
}

run :: proc() -> (result: Result) {
    defer free_all()

    opt: CLI_Opts
    parse_cli_opts(&opt) or_return

    ad: Audio_Data
    load_audio(opt, &ad) or_return
    buf := carve_audio(&ad, opt)

    ng: ma.node_graph
    defer ma.node_graph_uninit(&ng, nil)
    ng_config := ma.node_graph_config_init(ad.channels)
    nodes: Graph_Nodes
    build_node_graph(&ng, &ng_config, &nodes, buf, ad.channels, ad.sample_rate, opt)
    if opt.save_path != "" {
        fmt.printfln("Encoding processed audio to: %s in WAV format...", opt.save_path)
        defer fmt.printfln("Finished encoding")
        save_audio(&ng, len(buf), ad.channels, ad.sample_rate, opt) or_return
        return
    }
    fmt.println("Playing processed audio... (Press Control-C to stop)")
    defer fmt.printfln("Finished audio playback")
    play_to_device(&ng, len(buf), ad.channels, ad.sample_rate, opt) or_return
    return
}

parse_cli_opts :: proc(opt: ^CLI_Opts) -> (result: CLI_Result) {
    opt.playback_speed = 1.0
    opt.loop = 1
    flags.parse(opt, os.args[1:])
    if opt.audio_path == "" { return .File_Not_Found }
    if opt.playback_speed <= 0 { opt.playback_speed = 1.0 }
    if opt.loop < 1 { opt.loop = 1 }

    fmt.printfln("Parsed: %#v", opt)
    return
}

CLI_Opts :: struct {
    // Basic options:
    audio_path:     string,
    playback_speed: f32,

    // Effects to apply:
    reverb:         bool,
    eq_preset:      EQ_Preset,
    start_ms:       u64,
    end_ms:         u64,
    fade_in_ms:     u64,
    fade_out_ms:    u64,
    loop:           u32,

    // Where to save the processed audio:
    save_path:      string,
}

Result :: union { CLI_Result, Effects_Result, Audio_IO_Result }

CLI_Result :: Maybe(CLI_Error)
CLI_Error :: enum { File_Not_Found = 1 }

