@echo off
setlocal
cd /d C:\fiscalizadores_satt_build

:: Build APK
call "C:\flutter-dev\bin\flutter.bat" build apk --release --dart-define=FISCALIZADORES_API_KEY=L3nsd@ys --dart-define=FISCALIZADORES_API_BASE_URL=http://190.119.38.13

:: Generar nombre con formato FISCALIZADORES-SATT-YYYYMMDD-HHMM.apk usando PowerShell
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd-HHmm'"') do set timestamp=%%a
set APK_NAME=FISCALIZADORES-SATT-%timestamp%.apk

:: Copiar APK generado al destino final
copy /Y "C:\fiscalizadores_satt_build\build\app\outputs\flutter-apk\app-release.apk" "\\192.168.1.6\fiscalizadores_satt\%APK_NAME%"

echo.
echo APK generado: \\192.168.1.6\fiscalizadores_satt\%APK_NAME%
echo.

pause