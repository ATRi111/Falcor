@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO_ROOT=E:\GraduateDesign\Falcor_Cp"
set "MOGWAI=%REPO_ROOT%\build\windows-vs2022\bin\Release\Mogwai.exe"
set "SCENE=%REPO_ROOT%\Scene\MultiMultiBunny.pyscene"
set "SCRIPT=%REPO_ROOT%\scripts\Voxelization_MultiBunny_VoxelOnly.py"
set "VOXEL_CACHE=%REPO_ROOT%\resource\MultiMultiBunny_(512, 41, 499)_512.bin_CPU"

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

if not exist "!VOXEL_CACHE!" (
    echo Warning: MultiMultiBunny voxel cache is missing.
    echo          First launch will generate:
    echo          !VOXEL_CACHE!
    echo          Relaunch once after generation finishes to view the generated cache.
    echo.
)

set "HYBRID_SCENE_HINT=MultiMultiBunny"
set "HYBRID_CPU_SCENE_NAME=MultiMultiBunny"
set "HYBRID_VOXEL_CACHE_FILE=%VOXEL_CACHE%"
set "HYBRID_CPU_VOXEL_RESOLUTION=512"
set "HYBRID_CPU_SAMPLE_FREQUENCY=512"

echo Starting Mogwai (MultiMultiBunny VoxelOnly)...
echo   Script: %SCRIPT%
echo   Scene:  %SCENE%
echo.

"%MOGWAI%" --script "%SCRIPT%" --scene "%SCENE%" --width=1600 --height=900
exit /b %errorlevel%
