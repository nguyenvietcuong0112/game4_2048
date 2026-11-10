@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM  build-info-flutter.bat -- Sinh file BUILD INFO canh thu muc build.
REM
REM  CHAY SAU KHI BUILD:  flutter build apk   (hoac flutter build ios)
REM  Dat o ROOT project Flutter (ngang pubspec.yaml) roi DOUBLE-CLICK.
REM
REM  Mac dinh lam ca 2 nen: android + ios. File ra:
REM     build\app\outputs\flutter-apk\<pkg>_<ver>_ANDROID_BUILD_INFO.txt
REM     build\ios\<pkg>_<ver>_IOS_BUILD_INFO.txt
REM
REM  Noi dung = bo cuc y het ban Unity (BuildInfo.cs): id quang cao, khoa, version
REM  third-party Android (fgsdk-deps.gradle) va iOS (ios\Podfile.lock), va khoi
REM  ANDROID vs iOS chi ra cho 2 nen khai lech nhau.
REM ============================================================================

set "PROJ=%~dp0"
set "JS=%PROJ%funtap_global_sdk\tools\fg-build-info.js"

if not exist "%PROJ%pubspec.yaml" (
    echo [build-info] LOI: khong thay pubspec.yaml -- dat file .bat nay o ROOT project Flutter.
    pause & exit /b 2
)
if not exist "%JS%" (
    echo [build-info] LOI: khong thay funtap_global_sdk\tools\fg-build-info.js
    echo               Chay lai install-fgsdk-flutter-^<batver^>.bat de keo package moi.
    pause & exit /b 2
)
where node >nul 2>&1
if errorlevel 1 ( echo [build-info] LOI: chua cai Node.js. & pause & exit /b 2 )

REM Version package de ghi vao file (doc tu pubspec cua plugin).
set "PKGVER="
for /f "tokens=2 delims= " %%v in ('findstr /b /c:"version:" "%PROJ%funtap_global_sdk\pubspec.yaml"') do set "PKGVER=%%v"

call node "%JS%" --project "%PROJ%" --engine flutter --platform android --pkg-version "funtap-global-sdk-flutter !PKGVER!"
call node "%JS%" --project "%PROJ%" --engine flutter --platform ios     --pkg-version "funtap-global-sdk-flutter !PKGVER!"

echo(
echo [build-info] XONG. Mo file .txt trong thu muc build de soat truoc khi nop ban build.
pause
exit /b 0
