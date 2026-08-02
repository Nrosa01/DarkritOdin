package main

import "core:log"
import sdl "vendor:sdl3"

main :: proc() {
    context.logger = log.create_console_logger()

    ok := sdl.Init({.VIDEO}); assert(ok)
    
    window := sdl.CreateWindow("Darkrit", 1280, 720, {}); assert(window != nil)
    
    gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil)

    ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)

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
        // Begin render pass
        color_target := sdl.GPUColorTargetInfo {
            texture = swapchain_texture,
            load_op = .CLEAR,
            clear_color = {0, 0.2, 0.4, 1},
            store_op = .STORE,
        }
        render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
        // Draw stuff
        
        // End render pass
        sdl.EndGPURenderPass(render_pass)
        // More render passes
        ok = sdl.SubmitGPUCommandBuffer(cmd_buf); assert(ok)
    }
}
