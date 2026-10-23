# Coop en ligne : monde ouvert et expéditions en groupe

## Pour les joueurs

Ouvrez **HoALauncher.exe**. L'hôte choisit **Create a game** et peut jouer immédiatement. Ses amis choisissent **Join a friend**, collent son invitation et arrivent dans le même monde, même si une expédition est déjà en cours. Dans le jeu, **Échap → Invite friends** copie l'invitation ; une sélection du texte permet aussi Ctrl+C si le presse-papiers est indisponible.

**Échap → Players & party** affiche les personnages connectés et permet de les inviter dans un groupe WoW. Les factions peuvent jouer ensemble. Au-delà de cinq héros, le chef peut utiliser un raid ; l'interface convertit son groupe lors de l'invitation suivante. Le monde n'impose plus la limite de deux joueurs. Un groupe de mission conserve les limites natives du client WoW : cinq en groupe, quarante en raid. La capacité pratique dépend du PC et de la connexion de l'hôte.

Un membre choisit l'expédition au maître des expéditions ou via **Échap → Choose expedition**. Les autres membres présents à l'auberge reçoivent une fenêtre **Ready to depart** : ils acceptent sans devoir se déplacer. Les refus et les absences ne bloquent pas le groupe ; une proposition expire après 45 secondes. Son initiateur peut l'annuler. Les héros déjà engagés dans une autre mission restent dans celle-ci.

Un ami qui rejoint le groupe en cours de mission reçoit **Join in progress**. Il arrive auprès du responsable de l'expédition et rattrape son niveau avec les choix d'amélioration correspondants. Après un refus, **Players & party → Join party expedition** permet de redemander l'invitation. Les restrictions de difficulté et de défi restent vérifiées.

Les ennemis sont partagés entre les participants. Leur vie vaut **1 + 0,7 × (nombre de participants − 1)** fois la vie solo : ×1,7 à deux, ×2,4 à trois. Les ennemis déjà présents s'ajustent à l'arrivée et au départ en conservant leur proportion de vie. Chaque héros garde ses armes, améliorations, récompenses et progression. Les choix et les menus mettent la mission en pause. Après le boss, tous les participants confirment leur portail après leurs récompenses. Le départ ou la défaite d'un membre n'arrête plus les autres.

Le HUD propose des icônes de monnaie avec infobulles, une barre de progression vers le prochain coffre, une chronologie de mission, une minimap carrée plus grande avec zoom et carte, ainsi qu'un panneau de groupe avec barres de vie. La liste des joueurs comporte des pages et le panneau de raid se parcourt à la molette.

Les personnages des invités sont enregistrés **sur le PC de l'hôte**. Revenez avec le même compte Windows chez le même hôte pour les retrouver. L'identité locale de l'invité est conservée dans `%LOCALAPPDATA%\HordesOfAzeroth\coop-identity.dat`, protégée par Windows ; elle ne doit pas être distribuée. L'hôte doit garder son jeu et son lanceur ouverts : leur fermeture arrête le monde. Une nouvelle session reprend les personnages à l'auberge, pas la mission interrompue.

Aucune adresse IP, ouverture de port, inscription ou installation de VPN n'est demandée. Partagez l'invitation seulement avec les personnes souhaitées. Toutes les copies doivent provenir du même paquet coop. **Play** conserve le mode solo hors ligne.

Le lanceur vérifie et répare avant chaque démarrage le client modifié, les fichiers de l'écran des héros et le composant natif de connexion, à partir de copies intégrées au lanceur. Si l'interface classique apparaît malgré tout, le composant natif tente la connexion avec le profil préparé. **Saisir `123` puis cliquer sur Login** permet de réessayer avec ce même profil. Ce code est un raccourci local, pas le mot de passe partagé des comptes : les mots de passe distincts et le contrôle de l'invitation restent en place. Il fonctionne uniquement dans la version corrigée, lancée par HoALauncher, pendant que la session est ouverte. Il ne répare pas une liaison réseau coupée.

## Préparation de la version à envoyer

Le dépôt seul ne contient pas le client WoW 1.12.1 enUS, ses données extraites, les cartes de navigation ou la base installée. Il faut une copie du jeu déjà installée avec le lanceur d'origine. Fermez le jeu et son lanceur avant de préparer une copie.

Depuis les sources, avec Rust 1.91 ou ultérieur, .NET et Visual Studio C++ installés :

```powershell
.\tools\package-coop.ps1 -GameFolder 'D:\Jeux\HordesOfAzeroth'
```

Le script compile le pont P2P, le lanceur, le client natif et le moteur modifié, puis produit `release\coop\HordesOfAzeroth-Coop.zip`. Les joueurs extraient chacun leur copie et ouvrent **HoALauncher.exe**. Le script ne modifie pas le jeu d'origine. Sans `-GameFolder`, il produit seulement un paquet de modifications `HordesOfAzeroth-Coop-Overlay.zip` à appliquer à une installation existante. **Ce paquet de modifications ne constitue pas le jeu complet.**

L'édition préparée est protégée contre le remplacement par une mise à jour solo du dépôt d'origine. Distribuez une nouvelle archive coop pour la mettre à jour. La publication classique via `tools/release.ps1` inclut le composant `coop` et annonce `coopProtocol: 1` dans le manifeste. Les modifications du sous-module serveur doivent être conservées et publiées avec celles du lanceur.

Le client et les données WoW ne sont pas fournis par ce projet. Ne publiez pas ces fichiers dans le dépôt ou dans une release publique. Le code source correspondant aux modifications et les licences doivent accompagner toute distribution des binaires du projet.

## Architecture et limites réseau

Le serveur local VMaNGOS reste la simulation autoritaire sur le PC de l'hôte. Le composant natif `hoa-coop.exe` utilise Iroh 1.2.0 pour relier les invités au PC hôte. Deux types de flux QUIC fiables transportent les connexions TCP WoW de connexion et de monde ; les datagrammes sans retransmission seraient inadaptés au protocole existant. Les services MariaDB, realmd et mangosd restent liés à `127.0.0.1`.

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

Le test de transport vérifie quatre invités simultanés, leurs profils distincts, les admissions dans un ordre différent, la restitution exacte des données, les fermetures TCP, le départ et la reconnexion sans interrompre les autres. Il est exécuté en mode automatique puis avec relais public forcé.

`tools/verify-coop.cs` avec `tools/coop/test_open_world.py` teste trois clients simulés contre le moteur réel et les données installées : démarrage seul, connexion tardive, groupe natif entre factions, popup, refus puis acceptation, variation effective de la vie d'un boss, portails collectifs, départ d'un membre, transfert de responsabilité et proposition par un membre qui n'est pas chef de groupe. Les comptes de test sont distincts des comptes joueurs et supprimés ensuite.

Les clients simulés utilisent désormais le vrai échange de connexion SRP, vérifient la preuve du serveur et la liste des mondes, puis ouvrent la connexion de jeu avec la clé négociée. `tools/coop/test_login_recovery.py` teste le script de secours natif, les accords utilisateur, l'absence de tentatives en boucle, le code `123` et le respect du profil préparé. `tools/coop/test-login-repair.cs` teste des fichiers absents ou altérés et vérifie que la réparation conserve les données du joueur.

`tools/verify-coop-package.py` contrôle les fichiers nécessaires, les exécutables, le client natif, les fichiers d'interface, l'absence d'invitation privée et l'intégrité complète du ZIP. Les sources sont rebasées sur `ede0f08` (0.2.3), vérifié contre la branche officielle le 23 octobre 2026.

Ces essais locaux ne remplacent pas une partie sur deux PC situés sur des réseaux différents. Les relais publics restent une dépendance externe sans garantie de disponibilité.

Le test `tools/coop/test_ui.py` exécute les fichiers d’interface Lua dans un modèle des contrôles WoW : actions du menu, copie avec solution de secours, dédoublonnage des invitations, 25 entrées de lobby, 40 membres de raid, barres et zoom. Il vérifie la logique, pas le rendu graphique du client. Le contrôle visuel natif Windows a été interrompu avec Échap ; le rendu en jeu et l'activation du secours dans le client réel restent à confirmer.
