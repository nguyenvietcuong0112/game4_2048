@echo off
REM  enabledelayedexpansion de rut version SDK tu ten .tgz.
REM  => KHONG dung ky tu '!' trong echo o file nay (se bi nuot ca dong, escape '^!' cung hong).
setlocal enabledelayedexpansion
REM ============================================================================
REM  install-fgsdk-flutter-<BATVER>.bat -- Cai FGSDK vao project Flutter TU REGISTRY.
REM
REM  CACH DUNG: copy file nay vao ROOT project Flutter (cung cap voi pubspec.yaml)
REM             roi DOUBLE-CLICK.
REM
REM  Can: Node/npm.
REM  Vi sao can bat: `pub` KHONG doc duoc npm registry -> phai tai package xuong dia
REM  truoc, roi pubspec khai `path:`. Bat lam dung 3 viec do.
REM
REM  BATVER = version cua CHINH FILE .BAT NAY (khong phai version SDK).
REM  Nam luon trong TEN FILE de nhin phat biet dev dang cam ban bat nao.
REM  Sua logic bat => tang BATVER + doi ten file cho khop.
REM  (SDK van luon keo ban MOI NHAT tren registry.)
REM ============================================================================

set "BATVER=1.0.0"
set "PKG=funtap-global-sdk-flutter"
set "DARTPKG=funtap_global_sdk"
set "REGISTRY=https://packages.funtapglobal.com/"
set "PROJ=%~dp0"
set "TMP=%PROJ%.fgsdk-flutter-tmp"
set "PKGDIR=%TMP%\package"
set "DEST=%PROJ%%DARTPKG%"

echo(
echo [FGSDK-FL] Installer bat : v%BATVER%   ^(version cua file .bat nay^)
echo [FGSDK-FL] Project root  : %PROJ%
echo [FGSDK-FL] Package       : %PKG%  ^<- keo ban MOI NHAT tu registry
echo(

if not exist "%PROJ%pubspec.yaml" goto :no_project
where npm >nul 2>&1
if errorlevel 1 goto :no_npm
where node >nul 2>&1
if errorlevel 1 goto :no_node

echo [FGSDK-FL] [1/4] Tai pack tu registry...
if exist "%TMP%" rmdir /s /q "%TMP%"
mkdir "%TMP%"
pushd "%TMP%"
call npm pack "%PKG%" --registry=%REGISTRY%
if errorlevel 1 goto :pack_fail

set "TGZ="
for /f "delims=" %%f in ('dir /b /o-d "%PKG%-*.tgz" 2^>nul') do if not defined TGZ set "TGZ=%%f"
if not defined TGZ goto :no_tgz

REM --- Rut version SDK vua tai ve tu ten file .tgz (de in ra cho de doi chieu) ---
set "SDKVER=%TGZ:~0,-4%"
set "SDKVER=!SDKVER:%PKG%-=!"
echo         -^> SDK version: !SDKVER!

echo [FGSDK-FL] [2/4] Giai nen -^> %DARTPKG%\ ...
tar -xzf "%TGZ%"
if errorlevel 1 goto :untar_fail
popd
if exist "%DEST%" rmdir /s /q "%DEST%"
move /y "%PKGDIR%" "%DEST%" >nul

echo [FGSDK-FL] [3/4] Rai script tool ^(fetch config^) -^> ROOT project ...
copy /y "%DEST%\tools\fetch-config-flutter.bat" "%PROJ%fetch-config-flutter.bat" >nul
copy /y "%DEST%\tools\fetch-config-flutter.js"  "%PROJ%fetch-config-flutter.js"  >nul

echo [FGSDK-FL] [4/4] Dau day pubspec.yaml + minSdk ...
call node "%DEST%\tools\wire-flutter.js" --project "%PROJ%"
if errorlevel 1 goto :wire_fail

rmdir /s /q "%TMP%" 2>nul

echo(
echo ============================================================================
echo [FGSDK-FL] XONG  ^(bat v%BATVER%  ^|  SDK !SDKVER!^). Cac buoc con lai:
echo   1. Config: DOUBLE-CLICK  fetch-config-flutter.bat  ^(nhap API Key^)
echo   2. flutter pub get
echo   3. flutter run   ^(hoac flutter build apk^)
echo(
echo   [LUU Y] iOS can ios\Frameworks\FGSDK.xcframework trong package.
echo           Neu ban package chua kem binary iOS thi chi build duoc Android.
echo ============================================================================
echo(
pause
exit /b 0

:no_project
echo [FGSDK-FL] LOI: khong thay "pubspec.yaml" -- .bat phai nam o ROOT project Flutter.
goto :fail
:no_npm
echo [FGSDK-FL] LOI: khong tim thay 'npm'. Cai Node.js truoc.
goto :fail
:no_node
echo [FGSDK-FL] LOI: khong tim thay 'node'. Cai Node.js truoc.
goto :fail
:pack_fail
popd
echo [FGSDK-FL] LOI: npm pack that bai. Kiem tra mang / registry / pack da publish chua?
goto :fail
:no_tgz
popd
echo [FGSDK-FL] LOI: khong thay file .tgz sau khi pack.
goto :fail
:untar_fail
popd
echo [FGSDK-FL] LOI: giai nen that bai ^(can Windows 10+ co lenh 'tar'^).
goto :fail
:wire_fail
echo [FGSDK-FL] LOI: dau day that bai -- xem thong bao o tren, sua tay roi chay lai.
goto :fail

:fail
echo(
pause
exit /b 1
