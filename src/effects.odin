package main

import ma "vendor:miniaudio"

node_graph_build :: proc(
    ng: ^ma.node_graph,
    ng_config: ^ma.node_graph_config,
    nodes: ^Graph_Nodes,
    final_buf: []f32,
    channels, sr: u32,
    opt: CLI_Opts,
) -> (result: Effects_Result) {
    if ma.node_graph_init(ng_config, nil, ng) != MA_OK { return .No_Node_Graph_Init }

    ab_config := ma.audio_buffer_config_init(
        .f32,
        channels,
        u64(len(final_buf)) / u64(channels),
        raw_data(final_buf),
        nil,
    )
    ma.audio_buffer_init(&ab_config, &nodes.audio_buffer)

    dsn_config := ma.data_source_node_config_init(cast(^ma.data_source)&nodes.audio_buffer)
    if ma.data_source_node_init(ng, &dsn_config, nil, &nodes.data_source_node) != MA_OK {
        return .No_DSN_Init
    }

    dsn_attach_eq(
        opt.eq_preset,
        ng,
        &nodes.data_source_node,
        &nodes.effects,
        channels,
        sr,
    ) or_return
    node_graph_finalize(ng, &nodes.effects, channels, sr, opt.reverb) or_return
    return
}

dsn_attach_eq :: proc(
    eq_preset: EQ_Preset,
    ng: ^ma.node_graph,
    ds_node: ^ma.data_source_node,
    fx: ^Effects,
    channels, sr: u32,
) -> (result: Effects_Result) {
    loshelf_gain, hishelf_gain: f64
    #partial switch eq_preset {
        case .None:
        case .Bass_Boost:   loshelf_gain = 12
        case .Treble_Boost: hishelf_gain = 12
        case .Muffled:      loshelf_gain, hishelf_gain = 6, -24
    }

    loshelf_freq, hishelf_freq: f64 = 250, 2000
    loshelf_config := ma.loshelf_node_config_init(channels, sr, loshelf_gain, 0.5, loshelf_freq)
    if ma.loshelf_node_init(ng, &loshelf_config, nil, &fx.eq_loshelf) != MA_OK {
        return .No_Loshelf_Init
    }
    hishelf_config := ma.hishelf_node_config_init(channels, sr, hishelf_gain, 0.5, hishelf_freq)
    if ma.hishelf_node_init(ng, &hishelf_config, nil, &fx.eq_hishelf) != MA_OK {
        return .No_Hishelf_Init
    }

    if ma.node_attach_output_bus(cast(^ma.node)ds_node, 0, cast(^ma.node)&fx.eq_loshelf, 0) !=
        MA_OK { return .Loshelf_Could_Not_Attach }
    if ma.node_attach_output_bus(
        cast(^ma.node)&fx.eq_loshelf,
        0,
        cast(^ma.node)&fx.eq_hishelf,
        0,
    ) != MA_OK { return .Loshelf_Could_Not_Attach }
    return
}

node_graph_finalize :: proc(
    ng: ^ma.node_graph,
    fx: ^Effects,
    channels, sr: u32,
    reverb: bool,
) -> (result: Effects_Result) {
    delay_config := ma.delay_node_config_init(channels, sr, sr / 8, 0.4)
    ma.delay_node_init(ng, &delay_config, nil, &fx.delay)
    endpoint := ma.node_graph_get_endpoint(ng)

    if reverb {
        if ma.node_attach_output_bus(
            cast(^ma.node)&fx.eq_hishelf,
            0,
            cast(^ma.node)&fx.delay,
            0,
        ) != MA_OK { return .Delay_Could_Not_Attach }

        if ma.node_attach_output_bus(cast(^ma.node)&fx.delay, 0, endpoint, 0) != MA_OK {
            return .Failed_To_Finalize
        }
    } else {
        if ma.node_attach_output_bus(cast(^ma.node)&fx.eq_hishelf, 0, endpoint, 0) != MA_OK {
            return .Failed_To_Finalize
        }
    }
    return
}

EQ_Preset :: enum { Invalid, None, Bass_Boost, Treble_Boost, Muffled }

Graph_Nodes :: struct {
    audio_buffer:     ma.audio_buffer,
    data_source_node: ma.data_source_node,
    effects:          Effects,
}

Effects :: struct {
    eq_loshelf: ma.loshelf_node,
    eq_hishelf: ma.hishelf_node,
    delay:      ma.delay_node,
}

Effects_Result :: Maybe(Effects_Error)
Effects_Error :: enum {
    No_Node_Graph_Init = 9,
    No_DSN_Init,
    No_Loshelf_Init,
    No_Hishelf_Init,
    Loshelf_Could_Not_Attach,
    Hishelf_Could_Not_Attach,
    Delay_Could_Not_Attach,
    Failed_To_Finalize,
}

