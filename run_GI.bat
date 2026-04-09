@echo off
:: 一键打开原 GI 路径（对照用）
:: 用法：直接双击，或 run_GI.bat [scene路径]

set MOGWAI=E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe
set SCRIPT=E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_GPU.py

if "%~1"=="" (
    set SCENE=E:\GraduateDesign\Falcor_Cp\Scene\Arcade\Arcade.pyscene
) else (
    set SCENE=%~1
)

echo Starting Mogwai (GI)...
echo   Script: %SCRIPT%
echo   Scene:  %SCENE%
echo.

"%MOGWAI%" --script "%SCRIPT%" --scene "%SCENE%"
