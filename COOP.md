# Coop en ligne à deux

## Pour les joueurs

Ouvrez **HoALauncher.exe**. L'un choisit **Create a game**, copie l'invitation et l'envoie à l'autre. L'autre choisit **Join a friend**, colle l'invitation puis confirme. Le jeu s'ouvre automatiquement sur les deux PC.

Choisissez chacun votre héros. Votre groupe se forme à l'avant-poste. Au maître des expéditions, le premier joueur propose la difficulté et le parcours ; le second confirme avec **Ready together**. L'expédition commence lorsque les deux sont prêts. La confirmation expire au bout de deux minutes et peut être annulée dans le panneau coop.

Les ennemis sont communs, leurs points de vie sont multipliés par 1,7. Chaque héros conserve ses armes, choix d'amélioration, récompenses et progression. Le jeu fait une pause pour les deux pendant les choix et les menus. Après le boss, chacun prend son portail lorsqu'il a fini de choisir ses récompenses ; les deux passent à l'étape suivante ensemble. Si un héros épuise ses résurrections, l'expédition se termine pour les deux.

Les personnages de l'invité sont enregistrés **sur le PC de l'hôte**. Revenez avec le même compte Windows chez le même hôte pour les retrouver. L'identité de l'invité est conservée dans `%LOCALAPPDATA%\HordesOfAzeroth\coop-identity.dat`, protégée par Windows ; elle ne doit pas être incluse dans une copie du jeu. Il n'y a pas de transfert automatique de héros entre deux hôtes. L'hôte doit garder le jeu et le lanceur ouverts. Une interruption termine l'expédition ; une nouvelle invitation permet de revenir à l'avant-poste.

Aucune adresse IP, ouverture de port, inscription ou installation de VPN n'est demandée. Le code est une invitation privée : partagez-le seulement avec votre ami. Les deux copies doivent provenir du même paquet coop. Le bouton Play garde le mode solo hors ligne.

## Préparation de la version à envoyer

Le dépôt seul ne contient pas le client WoW 1.12.1 enUS, ses données extraites, les cartes de navigation ou la base installée. Il faut une copie du jeu déjà installée avec le lanceur d'origine. Fermez le jeu et son lanceur avant de préparer une copie.

Depuis les sources, avec Rust 1.91 ou ultérieur, .NET et Visual Studio C++ installés :

```powershell
.\tools\package-coop.ps1 -GameFolder 'D:\Jeux\HordesOfAzeroth'
```

Le script compile le pont P2P, le lanceur et le moteur modifié, puis produit `release\coop\HordesOfAzeroth-Coop.zip`. Les joueurs extraient chacun leur copie et ouvrent **HoALauncher.exe**. Le script ne modifie pas le jeu d'origine. Sans `-GameFolder`, il produit seulement un paquet de modifications `HordesOfAzeroth-Coop-Overlay.zip` à appliquer à une installation existante. **Ce paquet de modifications ne constitue pas le jeu complet.**

L'édition préparée est protégée contre le remplacement par une mise à jour solo du dépôt d'origine. Distribuez une nouvelle archive coop pour la mettre à jour. La publication classique via `tools/release.ps1` inclut le composant `coop` et annonce `coopProtocol: 1` dans le manifeste. Les modifications du sous-module serveur doivent être conservées et publiées avec celles du lanceur.

Le client et les données WoW ne sont pas fournis par ce projet. Ne publiez pas ces fichiers dans le dépôt ou dans une release publique. Le code source correspondant aux modifications et les licences doivent accompagner toute distribution des binaires du projet.

## Architecture et limites réseau

Le serveur local VMaNGOS reste la simulation autoritaire sur le PC de l'hôte. Le composant natif `hoa-coop.exe` utilise Iroh 1.2.0 pour relier les deux machines. Deux types de flux QUIC fiables transportent les connexions TCP WoW de connexion et de monde ; les datagrammes sans retransmission seraient inadaptés au protocole existant. Les services MariaDB, realmd et mangosd restent liés à `127.0.0.1`.

L'invitation contient l'identité éphémère de l'hôte et un secret aléatoire de 128 bits avec contrôle de saisie. La clé persistante de l'invité détermine son compte distinct sans droits d'administration. Les mots de passe automatiques transitent dans la liaison chiffrée. Le pont ne peut ouvrir que les deux ports locaux du jeu et limite le nombre de flux. Il s'arrête avec le lanceur.

Iroh tente une liaison directe et peut utiliser les relais publics communautaires de n0 en secours. **Aucun serveur n'est à louer ou à gérer**, mais ce n'est pas une absence totale d'infrastructure : ces services gratuits ont des limites de trafic et aucune garantie de disponibilité. Un réseau interdisant aussi l'accès aux relais peut empêcher une connexion. Il n'existe pas de solution P2P directe garantie sur tous les réseaux restrictifs.

Sources primaires consultées le 21 octobre 2026 : [API Iroh](https://docs.rs/iroh/1.2.0/iroh/), [préréglages et découverte](https://docs.rs/iroh/1.2.0/iroh/endpoint/presets/index.html), [offre communautaire et garanties](https://www.iroh.computer/pricing), [relais publics et partagés](https://www.iroh.computer/blog/shared-relays).

## Validation

```powershell
cargo test --locked --manifest-path tools\coop\Cargo.toml
cargo build --release --locked --manifest-path tools\coop\Cargo.toml
python tools\coop\test_transport.py
dotnet build tools\launcher\HordesOfAzerothLauncher.csproj -c Release
cmake --build server\build-coop --config Release
```

Le test de transport utilise deux processus, de faux serveurs locaux et des données aléatoires. Il vérifie les deux flux du jeu, la restitution exacte des octets, les fermetures TCP et le relais public forcé. Il ne remplace pas une partie réelle avec deux clients WoW.

Les outils `tools/verify-coop.cs` et `tools/coop/test_world.py` ont aussi été exécutés contre le moteur compilé et les données installées : deux clients simulés de classes et factions différentes, groupe automatique, confirmation et annulation, pause commune, ennemis et crédit de victoire partagés, boss, double confirmation des portails, étape suivante et déconnexion. Le lancement depuis le dossier distribué a été vérifié. `tools/verify-coop-package.py` contrôle les fichiers nécessaires, les versions des exécutables et l'intégrité de chaque fichier du ZIP après sa création.

Avant diffusion, vérifier sur deux PC : création et collage du code, héros différents (y compris factions différentes), confirmation et annulation du départ, attaques des deux héros sur un même ennemi, choix et pauses simultanés, boss et zones de danger, récompenses individuelles, portails, résurrection et défaite commune, départ de l'invité et fermeture de l'hôte, reconnexion au même hôte, lancement solo après coop. Ces essais nécessitent le client et les données de jeu.
