<p align="center"><img src="../assets/rawya-mark.svg" width="160" alt="Logo Rawya"></p>
<h1 align="center">Rawya</h1>
<p align="center">Un lecteur macOS gratuit et open source qui génère et traduit automatiquement les sous-titres.</p>

<p align="center"><a href="../../README.md">English</a> · <a href="README.zh.md">简体中文</a> · <a href="README.zh-hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <strong>Français</strong> · <a href="README.de.md">Deutsch</a> · <a href="README.pt.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a></p>

<p align="center"><a href="https://rawya.app/fr/">Site web</a> · <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">Télécharger</a> · <a href="https://github.com/rawya-ai-player/client-macos/issues">Signaler un problème</a></p>

## Qu'est-ce que Rawya ?

Rawya est un lecteur natif pour macOS conçu pour regarder des vidéos dans différentes langues. Il génère les sous-titres depuis la voix puis les traduit dans la langue que vous lisez.

## Points forts

- Génération et traduction automatiques de sous-titres multilingues
- Affichage des sous-titres prêts pendant la suite du traitement
- Traitement local avec l'IA Apple sur les Mac compatibles
- Lecture des formats vidéo et audio courants
- Sous-titres, listes, chapitres, image dans l'image et historique
- Réglages vidéo, audio, sous-titres, clavier, souris, trackpad et gestes

## Configuration requise

- Sous-titres IA locaux Apple : macOS 26 ou ultérieur
- Lecture de base sur Apple Silicon : macOS 12 ou ultérieur
- Lecture de base sur Intel Mac : macOS 10.15 ou ultérieur

## Télécharger

Téléchargez le dernier DMG depuis [GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest), puis glissez Rawya dans Applications. Les versions stables sont signées Developer ID et notariées par Apple.

## Mises à jour

Rawya recherche automatiquement les mises à jour stables une fois par jour. Vous pouvez aussi choisir **Rechercher les mises à jour…** dans le menu de l'application à tout moment. Activez **Télécharger et installer automatiquement les mises à jour** dans **Réglages > Général** pour télécharger en arrière-plan les mises à jour vérifiées et les installer à la fermeture de Rawya.

Les mises à jour automatiques et les téléchargements manuels utilisent la même version stable de GitHub Release. GitHub fournit également les archives source de chaque version stable.

## Compiler localement

Installez la dernière version de Xcode, exécutez `./other/download_libs.sh`, puis ouvrez le `.xcodeproj` dans Xcode et compilez le Scheme principal.

## Licence

Rawya est distribué sous [GNU General Public License v3.0](../../LICENSE). Les composants tiers conservent leurs licences respectives.
