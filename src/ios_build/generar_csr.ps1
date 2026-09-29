# ===========================================================================
# Genera el Certificate Signing Request (CSR) para el certificado de
# desarrollo de Apple, sin necesidad de un Mac.
#
# Apple exige que el certificado de desarrollo se pida desde un CSR. Normalmente
# se genera con Keychain Access en macOS, pero OpenSSL produce el mismo
# archivo, asi que se puede hacer desde Windows.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File ios_build\generar_csr.ps1
#
# Despues de ejecutarlo, suba el archivo CertSigningRequest.certSigningRequest
# a https://developer.apple.com/account/resources/certificates/add
# ===========================================================================

$ErrorActionPreference = 'Stop'

# OpenSSL viene con Git for Windows; si no esta en PATH, se usa esa ruta.
$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    $gitOpenSSL = 'C:\Program Files\Git\usr\bin\openssl.exe'
    if (Test-Path $gitOpenSSL) {
        $openssl = $gitOpenSSL
    } else {
        Write-Host 'ERROR: no se encontro OpenSSL.' -ForegroundColor Red
        Write-Host 'Instale Git for Windows (https://git-scm.com/download/win) ' -NoNewline
        Write-Host 'o OpenSSL y vuelva a intentar.'
        exit 1
    }
} else {
    $openssl = $openssl.Source
}

Write-Host 'OpenSSL:' $openssl -ForegroundColor Green
& $openssl version
Write-Host

# ------------------------------------------------------------- Datos del certificado
# Estos datos aparecen en el certificado. El Common Name debe ser reconocible:
# cuando Apple pida elegir el certificado, el operador sabra cual es.
$nombre   = Read-Host 'Su nombre (ej. Juan Perez)'
$email    = Read-Host 'Su correo (el del Apple ID)'
$pais     = Read-Host 'Codigo de pais de 2 letras (ej. PE)'
$organizacion = Read-Host 'Organizacion (opcional, puede dejar vacio)'

if ([string]::IsNullOrWhiteSpace($pais)) { $pais = 'PE' }
$pais = $pais.ToUpper()
if ($pais.Length -ne 2) {
    Write-Host 'ERROR: el codigo de pais debe tener exactamente 2 letras.' -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------- Generar llave y CSR
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dir = if ($dir) { $dir } else { '.' }
$key = Join-Path $dir 'ios_build\private_key.pem'
$csr = Join-Path $dir 'ios_build\CertSigningRequest.certSigningRequest'

Write-Host 'Generando llave privada de 2048 bits...' -ForegroundColor Cyan
& $openssl genrsa -out $key 2048
if ($LASTEXITCODE -ne 0) { Write-Host 'ERROR al generar la llave.' -ForegroundColor Red; exit 1 }

Write-Host 'Generando el CSR...' -ForegroundColor Cyan
$subj = "/C=$pais/O=$organizacion/CN=$nombre/emailAddress=$email"
& $openssl req -new -key $key -out $csr -subj $subj
if ($LASTEXITCODE -ne 0) { Write-Host 'ERROR al generar el CSR.' -ForegroundColor Red; exit 1 }

Write-Host
Write-Host '=============================================================' -ForegroundColor Green
Write-Host '  LISTO' -ForegroundColor Green
Write-Host '=============================================================' -ForegroundColor Green
Write-Host
Write-Host 'Archivos generados:' -ForegroundColor Cyan
Write-Host '  Llave privada : ' $key
Write-Host '  CSR           : ' $csr
Write-Host
Write-Host 'Proximos pasos:' -ForegroundColor Yellow
Write-Host '  1. Cree un Apple ID gratis en https://appleid.apple.com si no tiene.'
Write-Host '  2. Entre a https://developer.apple.com/account/resources/certificates'
Write-Host '  3. Pulse "+", elija "Apple Development" y suba el CSR.'
Write-Host '  4. Descargue el certificado (.cer) y haga doble clic para instalarlo'
Write-Host '     en un Mac... ' -NoNewline
Write-Host '(aqui viene el problema, vea el README)' -ForegroundColor Red
Write-Host
Write-Host 'IMPORTANTE: el certificado .cer solo se puede exportar a .p12 desde un' -ForegroundColor Red
Write-Host 'Mac. Sin Mac, la opcion mas simple es Codemagic (vea el README).' -ForegroundColor Red
Write-Host
