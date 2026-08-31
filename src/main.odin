package main

import "base:runtime"
import "core:log"
import "core:mem"
import "core:math/linalg"
import sdl "vendor:sdl3"
import sdli "vendor:sdl3/image"

default_context: runtime.Context

frag_shader_code := #load("..\\assets\\shader.spv.frag")
vert_shader_code := #load("..\\assets\\shader.spv.vert")
coblestone_image_pixels := #load("..\\assets\\textures\\cobblestone_1.png")
colormap_image_pixels := #load("..\\assets\\textures\\colormap.png")

Vec3 :: [3]f32
Vec2 :: [2]f32
DEPTH_TEXTURE_FORMAT :: sdl.GPUTextureFormat.D24_UNORM
WHITE :: sdl.FColor {1,1,1,1}

gpu: ^sdl.GPUDevice
window: ^sdl.Window
pipeline: ^sdl.GPUGraphicsPipeline 
win_size: [2]i32
depth_texture: ^sdl.GPUTexture
sampler: ^sdl.GPUSampler

VertexData :: struct {
    pos: Vec3,
    color: sdl.FColor,
    uv: [2]f32,
}

Model :: struct {
    vertex_buf: ^sdl.GPUBuffer,
    index_buf: ^sdl.GPUBuffer,
    num_indices: u32,
    texture: ^sdl.GPUTexture,
}

init :: proc() {
        sdl.SetLogPriorities(.VERBOSE)
    sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
        context = default_context
        log.debugf("SDL {} [{}]: {}", category, priority, message)
    }, nil)

    ok := sdl.Init({.VIDEO}); assert(ok)

    window = sdl.CreateWindow("Darkrit", 1280, 720, {}); assert(window != nil)
    
    gpu = sdl.CreateGPUDevice({.SPIRV}, true, nil)

    ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)

    ok = sdl.GetWindowSize(window, &win_size.x, &win_size.y); assert(ok)

    depth_texture = sdl.CreateGPUTexture(gpu, {
        format = DEPTH_TEXTURE_FORMAT,
        usage = {.DEPTH_STENCIL_TARGET},
        width = u32(win_size.x),
        height = u32(win_size.y),
        layer_count_or_depth = 1,
        num_levels = 1,
    })
}

setup_pipeline :: proc() {
        vert_shader := load_shader(gpu, vert_shader_code, .VERTEX, num_uniform_buffers = 1, num_samplers = 0)
    fragment_shader := load_shader(gpu, frag_shader_code, .FRAGMENT, num_uniform_buffers = 0, num_samplers = 1)
    
    vertex_attrs := []sdl.GPUVertexAttribute {
        {
            location = 0,
            format = .FLOAT3,
            offset = u32(offset_of(VertexData, pos)),
        },
        {
            location = 1,
            format = .FLOAT4,
            offset = u32(offset_of(VertexData, color)),
        },
        {
            location = 2,
            format = .FLOAT2,
            offset = u32(offset_of(VertexData, uv)),
        },
    }

    pipeline = sdl.CreateGPUGraphicsPipeline(gpu, {
        vertex_shader = vert_shader,
        fragment_shader = fragment_shader,
        primitive_type = .TRIANGLELIST,
        vertex_input_state = {
            num_vertex_buffers = 1,
            vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription{
                slot = 0,
                pitch = size_of(VertexData),
            }),
            num_vertex_attributes = u32(len(vertex_attrs)),
            vertex_attributes = raw_data(vertex_attrs),
        },
        depth_stencil_state = {
            enable_depth_test = true,
            enable_depth_write = true,
            compare_op = .LESS,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
            }),
            has_depth_stencil_target = true,
            depth_stencil_format = DEPTH_TEXTURE_FORMAT
        },
    })

    sdl.ReleaseGPUShader(gpu, vert_shader)
    sdl.ReleaseGPUShader(gpu, fragment_shader)

    sampler = sdl.CreateGPUSampler(gpu, {})
}

load_model :: proc(mesh_file: string, texture_file: []u8) -> Model {
        img := load_image_rw(colormap_image_pixels); assert(img != nil)
    texture := sdl.CreateGPUTexture(gpu, {
        format = .R8G8B8A8_UNORM,
        usage = {.SAMPLER},
        width = u32(img.w),
        height = u32(img.h),
        layer_count_or_depth = 1,
        num_levels = 1,
    })
    pixels_byte_size := img.w * img.h * 4

    // assign texture coordinates to vertices
    // create a sampler for the shader
    // make shader sample colors from texture

    obj_data := obj_load(mesh_file)

    vertices := make([dynamic]VertexData, len(obj_data.faces))
    indices := make([dynamic]u16, len(obj_data.faces))

    for face, i in obj_data.faces {
        uv := obj_data.uvs[face.uv]
        vertices[i] = {
            pos = obj_data.positions[face.pos],
            color = WHITE,
            uv = {uv.x, 1 -uv.y},
        }
        indices[i] = u16(i)
    }

    obj_destroy(&obj_data)

    num_indices := len(indices)

    vertices_byte_size := len(vertices) * size_of(VertexData)
    indices_byte_size := len(indices) * size_of(indices[0])

    vertex_buf := sdl.CreateGPUBuffer(gpu, {
        usage = {.VERTEX},
        size = u32(vertices_byte_size),
    })

    index_buf := sdl.CreateGPUBuffer(gpu, {
        usage = {.INDEX},
        size = u32(indices_byte_size),
    })

    transfer_buff := sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = u32(vertices_byte_size + indices_byte_size),
    })

    delete(indices)
    delete(vertices)

    transfer_mem := cast([^]byte)sdl.MapGPUTransferBuffer(gpu, transfer_buff, false)
    mem.copy(transfer_mem, raw_data(vertices), vertices_byte_size)
    mem.copy(transfer_mem[vertices_byte_size:], raw_data(indices), indices_byte_size)
    sdl.UnmapGPUTransferBuffer(gpu, transfer_buff)

    tex_transfer_buff := sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = u32(pixels_byte_size),
    })
    tex_transfer_mem := cast([^]byte)sdl.MapGPUTransferBuffer(gpu, tex_transfer_buff, false)
    mem.copy(tex_transfer_mem, img.pixels, int(pixels_byte_size))
    sdl.UnmapGPUTransferBuffer(gpu, tex_transfer_buff)

    copy_cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)

    sdl.UploadToGPUBuffer(copy_pass, 
        {transfer_buffer = transfer_buff},
        {buffer = vertex_buf, size =  u32(vertices_byte_size)},
        false,
    )

    sdl.UploadToGPUBuffer(copy_pass, 
        {transfer_buffer = transfer_buff, offset = u32(vertices_byte_size)},
        {buffer = index_buf, size =  u32(indices_byte_size)},
        false,
    )

    sdl.UploadToGPUTexture(copy_pass,
        {transfer_buffer = tex_transfer_buff},
        {texture = texture, w = u32(img.w), h = u32(img.h), d = 1},
        false,
    )

    sdl.EndGPUCopyPass(copy_pass)
    ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buf); assert(ok)
    sdl.ReleaseGPUTransferBuffer(gpu, transfer_buff)
    sdl.ReleaseGPUTransferBuffer(gpu, tex_transfer_buff)

    return {
        vertex_buf = vertex_buf,
        index_buf = index_buf,
        num_indices = u32(num_indices),
        texture = texture,
    }
}

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    init()
    setup_pipeline()

    model := load_model("assets\\models\\sedan-sports.obj", colormap_image_pixels)
    ROTATION_SPEED := linalg.to_radians(f32(90))
    rotation := f32(0)

    proj_mat :=  linalg.matrix4_perspective_f32(linalg.to_radians(f32(70)), f32(win_size.x) / f32(win_size.y), 0.0001, 1000)

    // The data being pushed must respect std140 layout conventions. 
    // In practical terms this means you must ensure that vec3 
    // and vec4 fields are 16-byte aligned.
    // https://wiki.libsdl.org/SDL3/SDL_PushGPUFragmentUniformData
    UBO :: struct #max_field_align(16) {
        mvp: matrix[4,4]f32,
    }

    last_ticks := sdl.GetTicks()

    main_loop : for {
        free_all(context.temp_allocator)
        
        new_ticks := sdl.GetTicks()
        delta_time := f32(new_ticks - last_ticks) / 1000
        last_ticks =new_ticks

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
        rotation += ROTATION_SPEED * delta_time

        // Render
        cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
        swapchain_texture : ^sdl.GPUTexture
        ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain_texture, nil, nil); assert(ok)
       
        model_mat := linalg.matrix4_translate_f32({0, -0.5, -2}) * linalg.matrix4_rotate_f32(rotation, {0, 1, 0})

        ubo := UBO { mvp = proj_mat * model_mat }

       if swapchain_texture != nil {
            // Begin render pass
            color_target := sdl.GPUColorTargetInfo {
                texture = swapchain_texture,
                load_op = .CLEAR,
                clear_color = {0, 0.2, 0.4, 1},
                store_op = .STORE,
            }
            depth_target_info := sdl.GPUDepthStencilTargetInfo {
                texture = depth_texture,
                load_op = .CLEAR,
                clear_depth = 1, // Matches far plane clipping
                store_op = .DONT_CARE,
            }
            render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info)
            sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
            sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = model.vertex_buf }), 1)
            sdl.BindGPUIndexBuffer(render_pass, {buffer = model.index_buf}, ._16BIT)
            sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
            sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = model.texture, sampler = sampler }), 1)
            sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
            sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indices, 1, 0, 0, 0)
            sdl.EndGPURenderPass(render_pass)
        }
        
        ok = sdl.SubmitGPUCommandBuffer(cmd_buf); assert(ok)
    }
}

load_shader :: proc(device: ^sdl.GPUDevice, code: []u8, stage: sdl.GPUShaderStage, num_uniform_buffers: u32, num_samplers: u32) -> ^sdl.GPUShader {
    return sdl.CreateGPUShader(device, {
        code_size = len(code),
        code = raw_data(code),
        entrypoint = "main",
        format = {.SPIRV},
        stage = stage,
        num_uniform_buffers = num_uniform_buffers,
        num_samplers = num_samplers,
    })
}

load_image_rw :: proc(image_data: []u8) -> ^sdl.Surface {
    io := sdl.IOFromConstMem(raw_data(image_data), len(image_data))
    img := sdli.Load_IO(io, true)
    assert(img != nil)

    if img.format != .ABGR8888 {
        next := sdl.ConvertSurface(img, .ABGR8888)
        sdl.DestroySurface(img)
        img = next
    }

    return img
}