@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM MultiBunny one-click launcher.
REM Usage:
REM   run_HybridMeshVoxel.bat
REM   run_HybridMeshVoxel.bat mesh
REM   run_HybridMeshVoxel.bat voxel

set "REPO_ROOT=E:\GraduateDesign\Falcor_Cp"
set "MOGWAI=%REPO_ROOT%\build\windows-vs2022\bin\Release\Mogwai.exe"
set "SCENE=%REPO_ROOT%\Scene\MultiBunny.pyscene"
set "SCRIPT_MESH=%REPO_ROOT%\scripts\Voxelization_MultiBunny_MeshRoute.py"
set "SCRIPT_VOXEL=%REPO_ROOT%\scripts\Voxelization_MultiBunny_VoxelRoute.py"
set "VOXEL_CACHE=%REPO_ROOT%\resource\MultiBunny_(128, 8, 128)_128.bin_CPU"

if "%~1"=="" (
    set "MODE=mesh"
) else (
    set "MODE=%~1"
)

if /i "%MODE%"=="mesh" (
    set "SCRIPT=%SCRIPT_MESH%"
) else (
    if /i "%MODE%"=="voxel" (
        set "SCRIPT=%SCRIPT_VOXEL%"
    ) else (
        echo Usage:
        echo   run_HybridMeshVoxel.bat [mesh^|voxel]
        exit /b 1
    )
)

if not exist "%MOGWAI%" (
    echo Error: Mogwai executable not found:
    echo   %MOGWAI%
    exit /b 1
)

if not exist "%SCRIPT%" (
    echo Error: Script not found:
    echo   %SCRIPT%
    exit /b 1
)

if not exist "%SCENE%" (
    echo Error: Scene not found:
    echo   %SCENE%
    exit /b 1
)

set "HYBRID_REPO_ROOT=%REPO_ROOT%"
set "HYBRID_SCENE_PATH=%SCENE%"
set "HYBRID_SCENE_HINT=MultiBunny"
set "HYBRID_FRAMEBUFFER_WIDTH=1600"
set "HYBRID_FRAMEBUFFER_HEIGHT=900"

if /i "%MODE%"=="voxel" (
    if not exist "!VOXEL_CACHE!" (
        echo Warning: MultiBunny voxel cache is missing.
        echo          First launch will generate:
        echo          !VOXEL_CACHE!
        echo          Relaunch once after generation finishes to view the generated cache.
        echo.
    )
)

echo Starting Mogwai (MultiBunny)...
echo   Mode:   %MODE%
echo   Script: %SCRIPT%
echo   Scene:  %SCENE%
echo.

"%MOGWAI%" --script "%SCRIPT%" --scene "%SCENE%" --width=1600 --height=900
exit /b %errorlevel%
