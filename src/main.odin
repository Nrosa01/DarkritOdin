package main

import "core:log"
import sdl "vendor:sdl3"

main :: proc() {
    context.logger = log.create_console_logger()

    ok := sdl.Init({.VIDEO}); assert(ok)
    
    window := sdl.CreateWindow("Darkrit", 1280, 720, {}); assert(window != nil)
    
    log.debug("Testing")
    
    main_loop : for {
        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
                case .QUIT:
                    break main_loop
            }
        }
    }
}
