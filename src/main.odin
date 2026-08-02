package main

import "base:runtime"
import "core:log"
import sdl "vendor:sdl3"

default_context: runtime.Context

frag_shader_code := #load("..\\assets\\shader.spv.frag")
vert_shader_code := #load("..\\assets\\shader.spv.vert")

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    sdl.SetLogPriorities(.VERBOSE)
    sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
        context = default_context
        log.debugf("SDL {} [{}]: {}", category, priority, message)
    }, nil)

    ok := sdl.Init({.VIDEO}); assert(ok)
    
    window := sdl.CreateWindow("Darkrit", 1280, 720, {}); assert(window != nil)
    
    gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil)

    ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)

    vert_shader := load_shader(gpu, vert_shader_code, .VERTEX)
    fragment_shader := load_shader(gpu, frag_shader_code, .FRAGMENT)

    pipeline := sdl.CreateGPUGraphicsPipeline(gpu, {
        vertex_shader = vert_shader,
        fragment_shader = fragment_shader,
        primitive_type = .TRIANGLELIST,
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
            }),
        },
    })

    sdl.ReleaseGPUShader(gpu, vert_shader)
    sdl.ReleaseGPUShader(gpu, fragment_shader)

    main_loop : for {
        // Process events
        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
                case .QUIT:
                    break main_loop
                case .KEY_DOWN:
                    if ev.key.scancode == .ESCAPE do break main_loop
            }
        }

        // Update game state


        // Render
        cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
        swapchain_texture : ^sdl.GPUTexture
        // Acquire gpu swapchain texture
        ok = sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain_texture, nil, nil); assert(ok)
       
       if swapchain_texture != nil {
            // Begin render pass
            color_target := sdl.GPUColorTargetInfo {
                texture = swapchain_texture,
                load_op = .CLEAR,
                clear_color = {0, 0.2, 0.4, 1},
                store_op = .STORE,
            }
            render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
            // Draw stuff
            //  - bind pipeline
            sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
            sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
            //  - bind vertex data
            //  - bind uniform data
            //  - draw calls
            // End render pass
            sdl.EndGPURenderPass(render_pass)
            // More render passes
            ok = sdl.SubmitGPUCommandBuffer(cmd_buf); assert(ok)
        }
    }
}

load_shader :: proc(device: ^sdl.GPUDevice, code: []u8, stage: sdl.GPUShaderStage) -> ^sdl.GPUShader {
    return sdl.CreateGPUShader(device, {
        code_size = len(code),
        code = raw_data(code),
        entrypoint = "main",
        format = {.SPIRV},
        stage = stage,
    })
}