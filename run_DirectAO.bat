@echo off
:: 一键打开 MainlineDirectAO 测试
:: 用法：run_DirectAO.bat [scene路径]
::   无参数 -> Arcade
::   run_DirectAO.bat cornell -> CornellBox

set MOGWAI=E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe
set SCRIPT=E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py

if "%~1"=="" (
    set SCENE=E:\GraduateDesign\Falcor_Cp\Scene\Arcade\Arcade.pyscene
) else if /i "%~1"=="cornell" (
    set SCENE=E:\GraduateDesign\Falcor_Cp\Scene\Box\CornellBox.pyscene
) else (
    set SCENE=%~1
)

for %%I in ("%SCENE%") do set DIRECTAO_SCENE_HINT=%%~nI
set DIRECTAO_SCENE_PATH=%SCENE%

echo Starting Mogwai...
echo   Script: %SCRIPT%
echo   Scene:  %SCENE%
echo   Hint:   %DIRECTAO_SCENE_HINT%
echo.

"%MOGWAI%" --script "%SCRIPT%" --scene "%SCENE%"
