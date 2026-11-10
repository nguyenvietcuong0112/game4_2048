@echo off
setlocal
REM ============================================================================
REM  fetch-config-flutter.bat -- Keo config bundle tu server Funtap ve project Flutter.
REM  Copy vao ROOT project (ngang pubspec.yaml) roi DOUBLE-CLICK. Can Node.
REM  Ghi: android/app/src/main/assets/fg_main_config.json + ios/Runner/
REM       android/app/google-services.json, ios/Runner/GoogleService-Info.plist
REM       keystore -> android/ + android/key.properties
REM       + chen AdMob app id vao android/app/build.gradle
REM ============================================================================
set "PROJ=%~dp0"
set "JS=%PROJ%fetch-config-flutter.js"
set "URL=https://fgtool.funtapglobal.com"
REM Bo dau '\' cuoi de tranh cmd hieu \" thanh escaped-quote khi truyen --project.
set "PROJNB=%PROJ%"
if "%PROJNB:~-1%"=="\" set "PROJNB=%PROJNB:~0,-1%"
REM Go 'fetch-config-flutter.bat force' de bo qua cooldown 180s.
set "FORCE="
if /i "%~1"=="force" set "FORCE=--force"

where node >nul 2>&1
if errorlevel 1 ( echo [fetch] LOI: khong tim thay 'node'. Cai Node.js truoc. & pause & exit /b 1 )
if not exist "%JS%" ( echo [fetch] LOI: khong thay fetch-config-flutter.js canh file .bat. & pause & exit /b 1 )
if not exist "%PROJ%pubspec.yaml" ( echo [fetch] LOI: khong thay 'pubspec.yaml' -- .bat phai o ROOT project Flutter. & pause & exit /b 1 )

echo(
set "APIKEY="
set /p "APIKEY=[fetch] Nhap API Key (Enter de dung key da luu): "

if defined APIKEY (
    node "%JS%" --key "%APIKEY%" --url "%URL%" --project "%PROJNB%" %FORCE%
) else (
    node "%JS%" --url "%URL%" --project "%PROJNB%" %FORCE%
)

echo(
echo ============================================================================
echo  [!] Config da ghi vao android/app/src/main/assets + ios/Runner.
echo  [!] keystore + key.properties chua secret -- DUNG commit vao git.
echo  [!] Chay tiep:  flutter pub get  roi  flutter run
echo ============================================================================
echo(
pause
