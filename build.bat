@echo off
setlocal

set CONFIG=debug
set RUN=0

:parse
if "%~1"=="" goto build

if /I "%~1"=="release" (
    set CONFIG=release
)

if /I "%~1"=="debug" (
    set CONFIG=debug
)

if /I "%~1"=="run" (
    set RUN=1
)

shift
goto parse

:build

if not exist bin mkdir bin

if exist lib (
    for %%F in (lib\*.dll) do (
        if not exist "bin\%%~nxF" (
            copy "%%F" "bin\" >nul
        )
    )
)

glslc .\assets\shader.glsl.frag -o .\assets\shader.spv.frag
if %errorlevel% neq 0 exit /b %errorlevel%

glslc .\assets\shader.glsl.vert -o .\assets\shader.spv.vert
if %errorlevel% neq 0 exit /b %errorlevel%x

if /I "%CONFIG%"=="debug" (
    odin build ./src -debug -out:bin/program_d.exe
    if errorlevel 1 exit /b %errorlevel%

    if %RUN%==1 bin\program_d.exe
) else (
    odin build ./src -o:speed -out:bin/program.exe
    if errorlevel 1 exit /b %errorlevel%

    if %RUN%==1 bin\program.exe
)