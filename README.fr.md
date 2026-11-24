# Debian 12 + OpenMediaVault 7 sur un QNAP TS-219P+ (sans toucher au firmware d'origine)

Ce dépôt explique comment un **QNAP TS-219P+** (Kirkwood 88F6282, ARMv5, 512 Mo de RAM, flash SPI de 16 Mo)
est passé de QTS 4.0.5 à **Debian 12 (armel)** avec l'interface web **OpenMediaVault 7**, avec un filet de
sécurité qui ne demande **ni adaptateur série, ni soudure, ni réécriture du noyau/système QTS en flash**.

Il contient la procédure, les scripts, le raisonnement et tous les pièges rencontrés. Il ne contient
**aucun binaire** (ni sauvegarde de flash, ni firmware QNAP, ni images noyau/rootfs) : tout se reconstruit
depuis des sources publiques.

**Principe** : U-Boot, le noyau et le système QTS restent intacts en flash. Seul l'environnement U-Boot
(4 Ko) est modifié pour charger le noyau Debian **depuis le disque SATA** (secteurs bruts à la fin de
l'ancienne partition de swap). À chaque démarrage, U-Boot met à zéro l'en-tête du noyau sur le disque ;
Debian le restaure 60 s plus tard **s'il est en bonne santé**. Sinon, le démarrage suivant retombe tout
seul sur QTS, accessible par le réseau. Voir [docs/03-boot-architecture.md](docs/03-boot-architecture.md).

**Avertissements** : testé sur un seul exemplaire ; sans mises à jour de sécurité (Debian 12 `armel`) donc
**réseau local uniquement, jamais de redirection de port** ; sauvegardez les 6 partitions MTD d'abord et
ne les publiez jamais ; n'écrivez jamais MTD0 (U-Boot) ; aucune garantie.

Le reste de la documentation est en anglais, dans [`docs/`](docs/).
