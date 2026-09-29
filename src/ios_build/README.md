# Compilar el .ipa de Fiscalizadores SAT-T sin Mac

El proyecto iOS ya está configurado (bundle ID `com.fiscalizadores.satt`,
permisos, iconos y `NSAppTransportSecurity`). Lo único que falta es compilar,
y para eso se necesita macOS con Xcode. Estas son las opciones, de más simple
a más flexible.

---

## Opción 1: Codemagic (recomendada)

[Codemagic](https://codemagic.io) es un servicio de integración continua
especializado en Flutter. Es la opción más simple porque **gestiona los
certificados automáticamente** con tu cuenta de Apple: no hay que generar
certificados ni perfiles a mano.

### Pasos

1. **Crea un Apple ID gratis** en https://appleid.apple.com (si no tienes).
   No necesitas pagar: la cuenta gratuita permite compilar e instalar en tu
   propio iPhone. La única limitación es que el perfil caduca a los 7 días y
   hay que reinstalar.

2. **Sube el código a un repositorio** (GitHub, GitLab o Bitbucket). Puede ser
   privado; el plan gratuito de GitHub lo permite.

3. **Crea una cuenta gratis** en https://codemagic.io con el mismo correo.

4. **Conecta el repositorio** en Codemagic (Add application > elige el repo).

5. **Conecta tu cuenta de Apple Developer** en Codemagic:
   `App settings > iOS code signing > Add account`.
   Codemagic te pide el Apple ID y la contraseña, y genera el certificado de
   desarrollo y el perfil de aprovisionamiento por ti.

6. **Compila**: en Codemagic pulsa `Start build` y elige el workflow de
   release. El `.ipa` aparece en los artefactos de la build.

### Instalar el .ipa en el iPhone

Con cuenta gratuita no se puede usar TestFlight. Se instala con un
instalador de terceros:

- **AltStore** (https://altstore.io): se instala en el iPhone con AltServer
  (corre en Windows/Mac). Arrastra el `.ipa` y listo. Hay que renovar cada
  7 días conectando el iPhone al computador.
- **Sideloadly** (https://sideloadly.io): similar, corre en Windows.

---

## Opción 2: GitHub Actions (gratuito, más trabajo)

GitHub ofrece runners de macOS gratis (2000 minutos/mes en repos privados).
El workflow ya está preparado en
[`.github/workflows/build_ios.yml`](.github/workflows/build_ios.yml).

### El problema: los certificados

Para firmar el `.ipa` se necesita un certificado de desarrollo (`.p12`) y un
perfil de aprovisionamiento (`.mobileprovision`). Normalmente se generan en un
Mac con Keychain Access. Sin Mac hay dos caminos:

**A. Generarlos desde Windows (técnico)**

1. Ejecuta `ios_build/generar_csr.ps1` para crear el CSR con OpenSSL.
2. Sube el CSR a https://developer.apple.com/account/resources/certificates
   y crea un certificado de "Apple Development".
3. Descarga el `.cer`... pero **aquí se atora**: para exportarlo a `.p12` hace
   falta Keychain Access, que solo existe en Mac. Hay herramientas de terceros
   que lo hacen desde Windows, pero son frágiles.

**B. Pedirle a Codemagic que te los genere y descargarlos**

1. Haz una build en Codemagic (Opción 1) solo para que genere los certificados.
2. En Codemagic: `App settings > iOS code signing > Certificates` puedes
   descargar el `.p12` y el perfil.
3. Sube ambos a GitHub como secretos (`IOS_CERTIFICATE`,
   `IOS_CERTIFICATE_PWD`, `IOS_PROVISIONING`).
4. Ejecuta el workflow de GitHub Actions.

### Instalar el .ipa

Igual que en la Opción 1: AltStore o Sideloadly.

---

## Opción 3: Alquilar un Mac en la nube

Si prefieres control total y no te importa pagar:

- **MacInCloud** (https://www.macincloud.com): desde ~$1/hora o ~$20/mes.
- **MacStadium** (https://www.macstadium.com): Mac mini dedicado, ~$99/mes.
- **AWS EC2 Mac**: desde ~$1.08/hora (mínimo 24 h).

Te conectas por RDP/SSH, abres Xcode, y compiles con:

```bash
cd ios
pod install
cd ..
flutter build ipa --release \
  --dart-define=FISCALIZADORES_API_KEY=L3nsd@ys \
  --dart-define=FISCALIZADORES_API_BASE_URL=http://190.119.38.13
```

El `.ipa` queda en `build/ios/ipa/`.

---

## La cuenta de pago ($99/año)

Si en el futuro quieres olvidarte de los perfiles de 7 días y de AltStore,
la cuenta de pago de Apple Developer desbloquea:

- Perfiles de aprovisionamiento de 1 año.
- **TestFlight**: instala el `.ipa` en el iPhone por wifi, sin computador.
- Publicar en la App Store.

El proceso de build es exactamente el mismo; solo cambia la cuenta.

---

## Resumen

| Opción | Costo | Esfuerzo | Perfil caduca |
|--------|-------|----------|---------------|
| Codemagic | Gratis | Bajo | 7 días |
| GitHub Actions | Gratis | Alto* | 7 días |
| Mac en la nube | $1-99/mes | Medio | 7 días |
| Cuenta de pago | $99/año | — | 1 año |

\* Requiere generar certificados sin Mac.

**Recomendación: empieza por Codemagic.** Es el camino más corto para tener
el `.ipa` en tu iPhone hoy.
