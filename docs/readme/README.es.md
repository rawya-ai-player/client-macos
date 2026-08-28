<p align="center"><img src="../assets/rawya-mark.svg" width="160" alt="Logotipo de Rawya"></p>
<h1 align="center">Rawya</h1>
<p align="center">Un reproductor gratuito y de código abierto para macOS que genera y traduce subtítulos automáticamente.</p>

<p align="center"><a href="../../README.md">English</a> · <a href="README.zh.md">简体中文</a> · <a href="README.zh-hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <strong>Español</strong> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.pt.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a></p>

<p align="center"><a href="https://rawya.app/es/">Sitio web</a> · <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">Descargar</a> · <a href="https://github.com/rawya-ai-player/client-macos/issues">Informar de un problema</a></p>

## ¿Qué es Rawya?

Rawya es un reproductor nativo para macOS pensado para quienes ven vídeos en distintos idiomas. Genera subtítulos a partir del audio y los traduce al idioma que lees.

## Funciones destacadas

- Generación y traducción automática de subtítulos en varios idiomas
- Muestra los subtítulos terminados mientras continúa el procesamiento
- Procesamiento local con la IA de Apple en los Mac compatibles
- Reproducción de formatos habituales de vídeo y audio
- Subtítulos, listas, capítulos, imagen dentro de imagen e historial
- Controles configurables de vídeo, audio, subtítulos, teclado, ratón y gestos

## Requisitos

- Subtítulos con IA local de Apple: macOS 26 o posterior
- Reproducción básica en Apple Silicon: macOS 12 o posterior
- Reproducción básica en Intel Mac: macOS 10.15 o posterior

## Descargar

Descarga el DMG más reciente desde [GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest) y arrastra Rawya a Aplicaciones. Las versiones estables están firmadas con Developer ID y notarizadas por Apple.

## Actualizaciones

Rawya busca automáticamente actualizaciones estables una vez al día. También puedes seleccionar **Buscar actualizaciones…** en el menú de la aplicación en cualquier momento. Activa **Descargar e instalar actualizaciones automáticamente** en **Ajustes > General** para descargar en segundo plano las actualizaciones verificadas e instalarlas al cerrar Rawya.

Las actualizaciones automáticas y las descargas manuales utilizan la misma versión estable de GitHub Release. Cada versión estable incluye también su archivo de código fuente y los archivos de suma de comprobación SHA-256.

## Compilar localmente

Instala la última versión de Xcode, ejecuta `./other/download_libs.sh` y abre el `.xcodeproj` en Xcode para compilar el Scheme principal.

## Licencia

Rawya se distribuye bajo la [GNU General Public License v3.0](../../LICENSE). El código y los recursos de terceros conservan sus respectivas licencias.
