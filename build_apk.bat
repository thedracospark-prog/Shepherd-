@echo off
setlocal
title Shepherd - Build Android APK
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] flutter was not found on PATH.
  echo Install the Flutter SDK and add its bin folder to your user PATH,
  echo then double-click this script again.
  pause
  exit /b 1
)

set SDKFOUND=
if defined ANDROID_HOME set SDKFOUND=1
if defined ANDROID_SDK_ROOT set SDKFOUND=1
if exist "%LOCALAPPDATA%\Android\Sdk" set SDKFOUND=1
if not defined SDKFOUND (
  echo [ERROR] Android SDK not found.
  echo Install Android Studio from https://developer.android.com/studio,
  echo then run "flutter doctor --android-licenses" once and accept them.
  echo After that, double-click this script again.
  pause
  exit /b 1
)

echo === Building Shepherd Android APK (release) ===
echo First build takes a few minutes. Leave this window open.
echo.
call flutter build apk --release
if errorlevel 1 (
  echo.
  echo [ERROR] The build failed. Copy the red text above and send it to Spark.
  pause
  exit /b 1
)

if not exist "build\app\outputs\flutter-apk\app-release.apk" (
  echo [ERROR] Build finished but app-release.apk was not found where expected.
  pause
  exit /b 1
)

echo.
echo === Copying APK to your Desktop ===
for /f "delims=" %%D in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetFolderPath('Desktop')"') do set DESKTOPDIR=%%D
if not defined DESKTOPDIR set DESKTOPDIR=%USERPROFILE%\Desktop
copy /y "build\app\outputs\flutter-apk\app-release.apk" "%DESKTOPDIR%\shepherd.apk" >nul
if errorlevel 1 (
  echo [ERROR] Copy failed, but the APK built fine. Find it at:
  echo %CD%\build\app\outputs\flutter-apk\app-release.apk
  pause
  exit /b 1
)

echo.
echo DONE. The installer is on your Desktop: shepherd.apk
echo.
echo TO INSTALL ON YOUR PHONE:
echo 1. Copy shepherd.apk to the phone (USB cable, or send it to yourself).
echo 2. On the phone, tap the APK file to install.
echo 3. Android will ask you to allow "install unknown apps" - allow it once.
echo.
echo NOTE: on Android the Wi-Fi disturbance sensing is simulated for now
echo (real sensing is Windows-only). BLE scan, GPS positioning and the
echo Silvus radio link work for real if the phone can reach the radio IP.
pause
