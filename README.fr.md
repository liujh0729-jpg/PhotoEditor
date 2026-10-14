# AIPDD PhotoEditor（base Compositor）

[English](README.md) · [简体中文](README.zh-Hans.md) · **Français** · [日本語](README.ja.md) · [العربية](README.ar.md) · [Tiếng Việt](README.vi.md) · [Español](README.es.md) · [Русский](README.ru.md)

![AIPDD PhotoEditor — canvas with Layers panel and Hue/Saturation, Levels, Color Picker adjustment panels](docs/screenshots/hero.jpg)

Adobe Photoshop coûte trop cher et des outils comme GIMP ne me semblent pas assez familiers pour rester dans le flux. C'est pour cela que j'ai écrit Compositor.

L'objectif était de créer un éditeur d'images complet, entièrement gratuit et open source. J'utilisais Photoshop pour la composition et la post-production ; Compositor est donc construit autour de ce flux de travail, avec les outils nécessaires pour produire une image finale au pixel près.

Comme il est open source, vous pouvez télécharger le projet Xcode et ajouter, retirer ou modifier n'importe quelle fonction pour l'adapter à votre façon de travailler.

## Installation

### Téléchargement
Téléchargez Compositor depuis [robbietilton.com/compositor](https://robbietilton.com/compositor), ou directement depuis la dernière version sur [GitHub Releases](https://github.com/robbietilton/Compositor/releases/latest).

### Homebrew

```sh
brew install --cask robbietilton-compositor
```

## Fonctionnalités

### Calques
- Calques et dossiers, avec opacité et la gamme complète des modes de fusion de Photoshop, dans le même ordre ; l'opacité d'un dossier assombrit tout ce qu'il contient
- Masques de fusion : peindre, remplir, inverser, flouter et adoucir n'importe où sur le canevas, même au-delà des pixels du calque ; liaisez-les ou déliez-les pour transformer un masque isolément
- Masques d'écrêtage et masques de dossier
- Calques de réglage : Teinte/Saturation, Niveaux, Courbes, Exposition, Carte de dégradé, Grain, Noir et blanc, Balance des couleurs, Intervertir, Flou gaussien, Flou de mouvement et Ajout de bruit
- Styles de calque : Contour, Ombre portée, Incrustation de couleur, Ombre interne, Halo externe et Halo interne, rendus sur GPU et modifiables à tout moment
- Fusioner la calque en dessous, Fusioner les calques, Fusioner le groupe (⌘E)
- Dupliquer, renommer en place, réordonner et imbriquer par glisser-déposer ; Option-glisser pour dupliquer ; menu contextuel dans le panneau Calques
- Copier-coller des calques et dossiers entiers (⌘C/⌘V sans sélection), dans un projet ou entre projets, ou les glisser d'un projet à l'autre

### Transformation
- Déplacement, mise à l'échelle, rotation et retournement non destructifs — les images gardent leur résolution complète, aussi petites que vous les réduisiez
- Déformation libre (⌘-glisser une poignée), avec Maj pour verrouiller sur un axe
- Transformer plusieurs calques, ou tout un dossier, ensemble
- Aimantation aux bords et centres du canevas et des calques, avec repères
- Valeurs exactes de position, taille, échelle et angle, ajustables aux flèches
- Retourner le calque et Retourner le canevas, horizontal et vertical

### Sélections
- Rectangle et ellipse de sélection, lasso libre et lasso polygonal, et l'outil intelligent — la baguette magique sélectionne par couleur, l'outil Objet trace ce sur quoi vous cliquez (Tab pour basculer)
- Sélectionner le sujet, et Étendre, Contracter et Adoucir toute sélection
- Ajouter et retrancher des sélections, déplacer le contour, ou déplacer et dupliquer les pixels à l'intérieur
- Charger les pixels d'un calque ou un masque comme sélection
- Remplissage d'après le contenu, qui peut aussi étendre une image au-delà de ses bords

### Peinture et retouche
- Pinceau avec taille, dureté, opacité et lissage, en peinture ou en effacement (B et E), Maj pour les lignes droites
- Outil Spot de restauration (d'après le contenu)
- Tampon de duplication, aligné ou non, en échantillonnant un calque ou tous
- Outil Flou, sur les pixels ou les masques
- Outil Dégradé et Outil Forme (rectangles, rectangles arrondis, ellipses et lignes), qui restent éditables au lieu d'être rasterisés
- Outil Texte (T) : édition multiligne en place dans des blocs par paragraphe déplaçables et redimensionnables ; police, taille, couleur, alignement et interlignage dans l'en-tête de l'outil ; transformez le texte et utilisez-le comme masque d'écrêtage
- Pipette et sélecteur de couleur complet

### Réglages et filtres
- Filtre Camera Raw : lumière, couleur, courbes, mélangeur de couleurs, étalonnage, détail, optique et géométrie, dans un panneau à côté du canevas ; chaque section se réinitialise depuis son en-tête
- Niveaux (avec Auto), Courbes, Teinte/Saturation, Exposition, Carte de dégradé, Grain, Noir et blanc, Balance des couleurs et Intervertir
- Flou gaussien et Flou de mouvement qui se propagent au-delà des bords du calque
- Ajout de bruit, Vignettage, Bloom / Halo, Tramage, Lignes de balayage, Contraste tonal, Correction d'objectif et Retrait d'arrière-plan
- Aperçus en direct, limités à la sélection s'il y en a une
- Dernier filtre (⌃⌘F) relance le dernier filtre avec les mêmes réglages

### Canevas et fichiers
- Plusieurs projets dans des onglets
- Recherche de commandes (⌘F) : trouvez chaque commande de menu et chaque outil par leur nom, comme dans Raycast ou Obsidian, et exécutez avec Entrée
- Basculer en plein écran (F) : le canevas seul sur fond noir couvrant tout l'écran, tous les panneaux rangés ; F ou Échap les fait réapparaître
- Règles (⌘R), repères tirés depuis elles, grille de mise en page à espacement et sous-divisions réglables, et Aimantation aux repères, grille, calques et limites du document
- Recadrage avec aimantation, ratios incluant 3:4 et 9:16, et Option pour un recadrage symétrique ; avec une sélection, le recadrage part d'elle
- Taille du canevas, Taille de l'image et Rogner
- Une mini-carte Navigateur dans le coin du canevas en dessous de 300 % de zoom : le document entier en petit avec un encadré autour de la vue ; cliquez ou glissez pour vous y rendre (Présentation › Navigateur)
- Sous-échantillonnage de haute qualité en dézoomant, et grille de pixels en zoomant
- Import JPEG, PNG, HEIC, TIFF, WebP, SVG, RAW caméra (avec une étape de développement d'abord) et Photoshop PSD et PSB (RVB 8 bits ; pas CMYK). Les dossiers, masques, modes de fusion, rectangles/ellipses de remplissage et le texte horizontal simple de Photoshop restent éditables ; les autres vecteurs et le texte vertical deviennent des pixels. Un rapport de conversion est affiché avant application
- Gros documents : le budget mémoire suit votre Mac, et un fichier Photoshop trop volumineux est recadré aux dimensions du canevas plutôt que de refuser de s'ouvrir
- Export PNG (⇧⌘E), Export JPEG (⇧⌥⌘S) et Exporter sous (⇧⌥⌘W) pour PNG, JPEG ou un PDF d'une page à la dimension d'impression, éventuellement mis à l'échelle, avec aperçu en direct, qualité JPEG et taille du fichier ; Copier les calques fusionnés
- Continuez à travailler pendant qu'un projet s'enregistre
- Raccourcis clavier de type Photoshop partout, remappables dans Édition › Raccourcis clavier
- Glissez le libellé d'un nombre pour le faire varier, comme dans Photoshop
- Mises à jour automatiques, signées et notarisées

### IA (avec votre propre passerelle)
- La passerelle IA (⌘,) dirige toutes les fonctions IA vers n'importe quel serveur compatible OpenAI que vous jugez digne de confiance — hébergé, proxy d'entreprise, ou exécuteur local. Les canaux ont priorité, poids, délai d'expiration, proxy HTTP/HTTPS/SOCKS optionnel, et des overrides par capacité pour le modèle, le chemin et le canal ; les clés d'API vivent dans le Trousseau macOS, jamais dans un fichier de préférences. Un canal AIPDD est pré-configuré pour démarrer avec juste une clé. « Tester la connexion » vérifie un canal avant l'enregistrement
- Les capacités sont des emplacements, pas des endpoints codés en dur : conversation texte, génération d'image, édition d'image, vidéo, synthèse vocale, transcription, embeddings et modèle de décision choisissent chacun leur propre canal et modèle — vous pouvez par exemple router les images vers un fournisseur et le texte vers un autre
- Chaque action IA est une commande de menu : elle apparaît dans la Recherche de commandes (⌘F) et peut être remappée dans Édition › Raccourcis clavier
- Générer une image : texte-vers-image avec taille, qualité, style, nombre et invite négative ; déposez les résultats sur le canevas comme nouveaux calques, ou enregistrez-les sur disque
- Édition d'image et Inpainting (image-vers-image) : envoyez les pixels du calque actif à la passerelle avec une invite, et remplacez le calque en place (annulable, masque conservé) ou ajoutez le résultat comme nouveau calque ; si le calque actif porte un masque activé, ce masque est envoyé aussi, pour que le modèle ne modifie que ce que vous avez marqué
- Transfert de style : donnez à la passerelle une image de référence et une intensité (0–100 %), appliquez son ton au calque actif
- Édition en langage naturel : décrivez une édition en français courant — « booste la saturation », « renomme en ciel », « ne rien sélectionner sur le sujet », « groupe ces calques » — le modèle de dialogue renvoie une intention structurée et l'éditeur l'exécute par les mêmes chemins de code qu'un clic dans un menu, avec un analyseur par mots-clés en repli hors ligne. Les intentions destructives (supprimer, remplacer des pixels) demandent confirmation
- Sélection sémantique : le pipeline masque-vers-canevas est branché — un masque de segmentation renvoyé par la passerelle devient soit un masque de fusion (le blanc révèle), soit une sélection en pointillés tracée le long des bords exacts des pixels, placée sous la transformation du calque. Le modèle texte-vers-masque reste pour l'instant un espace réservé ; les endpoints sont prêts pour un service compatible SAM
- Vidéo, Voix et Transcription passent par la file de tâches asynchrone : soumettre → interroger avec backoff exponentiel → télécharger. L'interrogation a une date limite et respecte l'annulation, donc une passerelle bloquée ne fige plus le panneau ; un bouton Annuler dépose une tâche en place
- Rien ne quitte votre Mac hormis vers le canal que vous avez configuré ; l'app n'appelle pas à la maison, n'inclut aucune clé d'API et ne mesure aucune consommation

### Fonctionne avec des agents IA
- Les agents IA et les scripts peuvent construire et éditer des projets directement : un `.comp` est un dossier de calques PNG et un manifeste, et un projet ouvert se met à jour en direct pendant qu'on y écrit. Voir [Écrire des projets Compositor](docs/writing-comp-files.md)

## Configuration requise

- macOS 26.0 ou plus récent sur un Mac à puce Apple
- Xcode 26 ou plus récent (pour compiler depuis les sources)

## Traductions

Compositor est livré avec huit langues d'interface — anglais, chinois simplifié, français, japonais, arabe, vietnamien, espagnol et russe — et vous pouvez en choisir une explicitement dans Réglages de la passerelle IA › Général (ou la laisser sur « Suivre le système » pour suivre l'ordre défini dans Réglages Système). L'interface suit la locale : l'arabe passe en mise en page de droite à gauche au prochain lancement.

Le catalogue de chaînes vit dans `Compositor/Resources/*.lproj/Localizable.strings`, un fichier par locale, la chaîne anglaise littérale servant de clé. Les clés manquantes retombent sur l'anglais, donc une locale à moitié traduite reste utilisable. Les PR de locuteurs natifs qui comblent les trous ou améliorent les libellés existants sont les bienvenues ; si vous prenez en main une locale pour la première fois, commencez par les surfaces visibles (menus, feuilles IA, en-têtes d'outil) avant les infobulles les plus profondes.

## Compilation

Ouvrez `Compositor.xcodeproj` et lancez le schéma **Compositor**.

## Publication

`scripts/release.sh` compile une version Release, la signe avec un Developer ID, la fait notariser et agréger, et l'emballage dans `dist/Compositor-<version>.dmg`.

Cela nécessite, tout hors de ce dépôt :

- un certificat **Developer ID Application** dans le trousseau de session
- des identifiants de notarisation enregistrés avec `xcrun notarytool store-credentials "compositor-notary" …`
- [`create-dmg`](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`)

## Communauté

AIPDD PhotoEditor (base Compositor) est développé en public, et la façon la plus rapide d'y participer est de rejoindre la discussion. Je tiens un petit groupe WeChat (ID : **raikkonenlxx**) pour que les utilisateurs et développeurs échangent des prompts, signalent des bugs, partagent des fichiers `.comp` et parlent de la configuration des passerelles et des workflows IA. Pour rejoindre, ajoutez-moi sur WeChat **raikkonenlxx** avec la mention « AIPDD ». Veuillez inclure « Compositor » dans votre demande d'ami pour que je sache que vous n'êtes pas un robot.

<div align="center">
  <img src="./docs/references/canvas-group-qr.png" width="260" alt="QR code WeChat — rejoindre le groupe de discussion AIPDD-Agent-Claw"/>
</div>
<br>

Pour tout ce qui doit rester dans les annales — bugs reproductibles, demandes de fonctionnalités, PR — ouvrez-les s'il vous plaît sur GitHub afin que la discussion reste trouvable.

## Licence

MIT — voir [LICENSE](LICENSE).
