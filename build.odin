package build

import "core:path/filepath"
import "core:log"
import "core:strings"
import "core:slice"
import "core:os"

main :: proc() {
	context.logger = log.create_console_logger()

    EXE :: "program"
    OUT :: EXE + ".exe" when ODIN_OS == .Windows else EXE
    OUT_DEBUG :: EXE + "_d.exe" when ODIN_OS == .Windows else EXE

	config := "debug"
	run_program := slice.contains(os.args, "run")

	if slice.contains(os.args, "release") {
		config = "release"
	}

	// Create bin directory if it doesn't exist
	if !os.exists("bin") {
		err := os.make_directory_all("bin")
		if err != nil {
			log.errorf("Error creating bin directory: {}", err)
			os.exit(1)
		}
	}

	// Copy DLLs
	if os.exists("lib") {
		files, err := os.glob("lib/*.dll", context.temp_allocator)
		if err != nil {
			log.errorf("Error finding DLLs: {}", err)
			os.exit(1)
		}

		for file in files {
			dst, err := os.join_path({"bin", os.base(file)}, context.temp_allocator)
			if os.exists(dst) && err == nil {
				continue
			}

			copy_err := os.copy_file(dst, file)
			if copy_err != nil {
				log.errorf("Error copying {} to {}: {}", file, dst, copy_err)
				os.exit(1)
			}
		}
	}

    files, err := os.read_all_directory_by_path("assets/shaders/src", context.temp_allocator)
    if err != nil {
        log.errorf("Error within shader sources {}", err)
        os.exit(1)
    }

    if !os.exists("assets/shaders/out") {
        directory_err := os.make_directory_all("assets/shaders/out")
        
        if directory_err != nil {
            log.errorf("Error creating directory out for shaders {}", directory_err)
            os.exit(1)
        }
    }

    for file in files {
        shadercross(file, "spv")
        shadercross(file, "dxil")
        shadercross(file, "msl")
        shadercross(file, "json")
    }

	if config == "debug" {
		run_str("odin build ./src -debug -out:bin/" + OUT_DEBUG)
		if run_program do run_str("bin\\" + OUT_DEBUG)
	} else {
		run_str("odin build ./src -o:speed -out:bin/" + OUT)
		if run_program do run_str("bin\\" + OUT)
	}

	free_all(context.temp_allocator)
}

shadercross :: proc(file: os.File_Info, format: string) {
    context.allocator = context.temp_allocator
    basename := filepath.stem(file.name)
    outfile, err := filepath.join({"assets/shaders/out", strings.concatenate({basename, ".", format})})
    
    if err != nil {
		log.errorf("Error creating output file for shadercross {}", err)
		os.exit(1)
	}
    
    run({"shadercross", file.fullpath, "-o", outfile})
}

run_str :: proc(cmd: string) { run(strings.split(cmd, " ", context.temp_allocator)) }

run :: proc(cmd: []string) {
	log.infof("Running {}", cmd)
	code, err := exec(cmd)
	if err != nil {
		log.errorf("Error executing process {}", err)
		os.exit(1)
	}

	if code != 0 {
		log.errorf("Process exited with non-zero code {}", code)
		os.exit(1)
	}
}

exec :: proc(cmd: []string) -> (code: int, error: os.Error) {
	process := os.process_start({ command = cmd, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr }) or_return
    state := os.process_wait(process) or_return
	return state.exit_code, nil
}
