# NHL Open Ice sur Analogue Pocket

![NHL Open Ice cover](docs/images/openice-cover.jpg)

Portage openFPGA expérimental de **NHL Open Ice: 2 on 2 Challenge, révision 1.21**, à partir du cœur [Wolf Unit de blahm1d](https://github.com/blahm1d/wolf-unit). La version **0.1.0-test.5** a été testée sur Pocket : le testeur a confirmé un jeu plus fluide et le bon fonctionnement de l’écran de chargement le 25 octobre 2026. Le démarrage, les crédits, le jeu et le son avaient été validés avec test.4.

Test.5 remplace les stries par l’écran titre, une barre et un pourcentage de chargement réel. Les optimisations réduisent les attentes mémoire du processeur, accélèrent les écritures RAM alignées, ajoutent un cache de programme et regroupent les lectures de graphismes. Les fréquences du processeur, de la vidéo, de la mémoire et du son restent inchangées. L’amélioration ressentie n’est pas une mesure de fréquence d’images ni une garantie de vitesse identique à la borne.

**Aucune ROM du jeu n’est incluse.** Chaque utilisateur fournit ses propres fichiers et les prépare avec l’outil Python fourni, qui ne télécharge rien.

## Installation

1. Télécharger `auricom79.OpenIce_0.1.0-test.5.zip` dans les [Releases](https://github.com/auricom79/openfpga-openice/releases).
2. Extraire l’archive à la racine de la microSD en fusionnant les dossiers `Cores`, `Platforms` et `Assets`.
3. Fournir `openice.zip` en révision 1.21, ou un dossier contenant les ROMs extraites. Avec Python 3.9 ou plus récent, sur Mac avec une carte nommée `BOOT` :

   ```sh
   python3 /Volumes/BOOT/Cores/auricom79.OpenIce/tools/prepare_roms.py ~/Downloads/openice.zip --output /Volumes/BOOT/Assets/openice/common
   ```

   Adapter les chemins. Le script vérifie les 22 fichiers avant de créer `openice-program.bin`, `openice-graphics.bin` et `openice-sound.bin`. Aucun module Python supplémentaire n’est nécessaire. Les fichiers originaux restent inchangés. Une autre révision est refusée, ainsi que le remplacement de fichiers de sortie différents déjà présents.
4. Éjecter la carte proprement puis lancer **openFPGA → NHL Open Ice** sur la Pocket.

L’écran titre, la barre et le pourcentage restent affichés pendant le transfert des fichiers. Attendre la fin sans ouvrir le menu. **100 % indique la fin du transfert des fichiers** ; les contrôles de démarrage du jeu suivent. Les fichiers du jeu déjà préparés peuvent être réutilisés lors d’une mise à jour.

## Jouer

Le message `CMOS INVALID — FACTORY SETTINGS RESTORED` peut apparaître au démarrage : la sauvegarde persistante des réglages n’est pas encore implémentée. Appuyer sur un bouton du jeu pour continuer.

Les réglages d’usine demandent **deux crédits pour démarrer**. Faire plusieurs appuis sur **Select**, en le relâchant entre les appuis, puis **Start**. La séquence vérifiée sur Pocket est de quatre appuis Select séparés, puis Start. **B** valide les menus, notamment la demande de saisie des initiales.

| Commande | Action |
| --- | --- |
| Croix | Déplacement / sélection |
| A | Turbo |
| B | Tir / blocage ; validation des menus |
| X | Passe / interception |
| Select | Crédit |
| Start | Démarrer / rejoindre |

Si un écran semble bloqué, essayer une extinction complète de la Pocket, puis relancer et attendre la fin du chargement. Cette procédure a résolu un signalement pendant les essais, sans que la cause exacte de cet écran ait été identifiée.

## Limites

- Le pourcentage couvre le chargement des fichiers ; les contrôles internes du jeu suivent et ne sont pas inclus dans cette progression.
- Pas de sauvegarde des réglages CMOS ou des records, pas de save states ni de veille.
- Dock et multijoueur non validés sur matériel ; sortie analogique désactivée.
- Seule la révision 1.21 d’Open Ice est prise en charge.
- Jeu plus fluide et écran de chargement confirmés avec test.5. Le gain n’a pas été chiffré et la caméra n’a pas été mesurée séparément face à la borne. Stabilité prolongée, match complet et fidélité à la borne d’origine restent à vérifier.

Pour signaler un problème, préciser la version du cœur, le firmware Pocket, l’écran concerné, la séquence de touches et l’état du son. Ne pas joindre de ROMs aux [issues](https://github.com/auricom79/openfpga-openice/issues).

Les sources correspondantes et les instructions de compilation sont dans [BUILDING.md](BUILDING.md). Ce projet repose sur le travail de blahm1d, Kevin Coleman, Sorgelig, des contributeurs MiSTer, d’Adam Gastineau, d’Analogue et de MAME. Portage et essais Pocket par **auricom79**, avec assistance d’OpenAI Codex. Voir [NOTICE.txt](NOTICE.txt) pour les licences et attributions.
