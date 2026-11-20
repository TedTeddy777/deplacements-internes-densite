# Déplacements internes et densité de population en Haïti

Article (Quarto), **version 2.1 du 19 novembre 2026** (la version 2.0 date du 18 novembre). Il répond à deux questions :
- Que deviennent les populations et les densités communales d'Haïti une fois corrigées des déplacements recensés par l'OIM ?
- Dans quelle mesure leur évolution est-elle associée à la violence des gangs ?

La version 2.0 applique le plan de corrections d'un groupe de quatre relecteurs (`Plan de corrections — Déplacements internes et densité de population en Haïti.md`). Les décisions de l'utilisateur ont été les suivantes :
- un seul article complet ;
- couverture, sommaire et résumé chacun sur sa page, puis des sections qui s'enchaînent ;
- des cartes 2D dans le texte et la 3D seulement en couverture ;
- l'UCDP seul, avec sa couverture chiffrée face aux décomptes de l'ONU.

Le 19 novembre 2026, les retouches de texte de `revisions.md` ont été appliquées. Elles comprennent environ 110 reformulations, dont 44 deux-points superflus, et six références. La mise en page a aussi changé :
- sigles, liste des tableaux et liste des figures en pages liminaires ;
- annexes renommées A (spécifications), B (sensibilité) et C (populations) ;
- intertitres numérotés en sections 2 et 11 ;
- encadré LaTeX en section 4.2 ;
- listes à tirets courts.

Version 2.1 : les encadrés de Quarto (« callouts ») sont remplacés par des cadres `tcolorbox` du même style, `cadrepro` : fond gris-bleu clair, bordure ardoise, titre en blanc dans une étiquette à cheval sur le filet supérieur.
- **Environnements** : `cadreresume` pour le résumé et l'abstract, `encadre` pour l'encadré 1 de la section 4.2.
- **HTML** : classes `.cadre` et `.encadre` dans `industry.css`.
- **Figures** : `fig-pos: "H"` (paquet float). Chaque figure reste à l'endroit exact de son appel, ce qui peut laisser un blanc en bas de page quand une carte ne tient pas. Les cartes du solde et des LISA sont réduites à 4,4 pouces de haut.
- **Figures 6 et 7 (projection agrandie)** : `carte_2p()` dessine dans un même repère la carte d'Haïti réduite (A, 44 % de la largeur) et une copie de la zone métropolitaine et de ses abords agrandie environ 5,5 fois (B). Deux traits relient le cadre de A au cadre de B. Chaque carte a sa barre d'échelle (50 km et 10 km). Hauteur : 4 pouces.
- **Paquet** : `tcolorbox` est chargé dans l'en-tête, car Quarto ne le charge plus sans callout.

WorldPop et les estimations officielles de l'IHSI reprennent la répartition communale d'avant la crise.

## Contenu

| Fichier | Rôle |
|---|---|
| `scripts/01_preparation_donnees.R` | Télécharge et prépare toutes les données (environ 7 min) → `data/*.rds` |
| `scripts/02_ihsi_population.R` | Estimations de l'IHSI extraites des PDF avec `pdftotext` → `data/ihsi_communes.rds` (communes, 2015 et 2024) et `data/ihsi_sections.rds` (570 sections, 2015) |
| `scripts/03_carte_3d_violence.R` | Image 3D rayshader de la **couverture** (`figures/rendus/haiti_violence_finale.png`) et carte annotée `figures/carte_3d_violence.png`, qui n'est plus insérée dans le texte. Hauteur : densité corrigée de juillet 2026 ; couleur : écart de densité associé à la violence (section 10). Lit `data/densite_violence.rds`, écrit par l'article. `finale` ≈ 5 min. |
| `scripts/04_cartes_3d_departements.R` | Cartes 3D de l'Ouest et de l'Artibonite (version 1.0). Elles ne sont plus utilisées : la version 2.0 les remplace par des cartes 2D avec un panneau sur la zone métropolitaine. |
| `article_deplacements_densite.qmd` | Article : analyse, modèles, figures, texte (environ 1 min) |
| `references.bib`, `industry.css` | Bibliographie et feuille de style (reprise de l'article sur les transferts). Le bandeau du titre HTML utilise `figures/couverture_bandeau.jpg` en arrière-plan. |
| `partials/before-body.tex` | Page de couverture du PDF (A4) : rendu 3D en arrière-plan, légende non causale. La version ne figure plus sur la couverture : elle est dans le nom du PDF (`article_deplacements_densite_V_2.1.pdf`, option `output-file` du format pdf). Après chaque nouveau rendu final de la carte 3D, recréer le bandeau HTML (recadrage magick en 1 800 px). Le sommaire tient sur une page ; les sections s'enchaînent sans saut de page forcé. |
| `filtres/garder-tableaux.lua` | Filtre Lua (PDF) : `\gardertableau` (macro de l'en-tête) avant chaque tableau de 25 lignes au plus, et avant l'intertitre qui le précède, pour qu'il ne soit pas coupé par un saut de page. Ne pas revenir à `\needspace` : sa pénalité de −100, avec `\raggedbottom`, repousse des tableaux qui tenaient sur la page. Tableaux en `\small`, largeurs fixées par `tbl-colwidths`. Dans les légendes, la partie « notes » est entourée de `\horsliste{...}` (macro définie dans l'en-tête) : elle s'affiche sous le tableau mais pas dans les listes des tableaux et des figures. |
| `data/publication/` | Populations corrigées publiées, écrites par l'article : `populations_communes_juillet2026.csv` (scénario central, enveloppe min et max, densités) et `populations_sections_juillet2026.csv` (scénario E). |
| `data/brut/` | Fichiers sources téléchargés (ne pas modifier) |

## Exécution

```powershell
Rscript "Deplacements Internes & Densite/scripts/01_preparation_donnees.R"
Rscript "Deplacements Internes & Densite/scripts/02_ihsi_population.R"     # nécessite pdftotext (MiKTeX ou Poppler)
# la carte 3D lit data/densite_violence.rds, écrit par l'article : rendre l'article une fois, puis
cd "Deplacements Internes & Densite"; Rscript scripts/03_carte_3d_violence.R finale refaire; Rscript scripts/04_cartes_3d_departements.R finale refaire
cd "Deplacements Internes & Densite"; quarto render article_deplacements_densite.qmd   # HTML + PDF
```

Paquets R : `data.table`, `sf`, `terra`, `readxl`, `ggplot2`, `patchwork`, `ggrepel`, `spdep`, `spatialreg`, `splm`, `SDPDmod`, `fixest`, `plm`. Le rendu complet (HTML et PDF) prend environ 7 minutes.

## Population de base (IHSI, et non WorldPop)

À la demande de l'utilisateur, toutes les populations viennent de l'IHSI.
- **Population de base** (avant les déplacements ; appelée « population de référence » dans la version 1.0) : structure communale de l'IHSI 2015, portée au total national IHSI 2024 (× 1,0875). C'est l'IHSI 2024 sans son ajustement aux déplacés. On ne prend pas l'IHSI 2024 tel quel : la correction par la DTM compterait alors une seconde fois les départs entre départements.
- **Superficies** : celles de l'IHSI pour toutes les densités communales.
- **WorldPop** ne sert qu'à répartir la population d'une commune entre ses km² (grille de 1 km recalée sur les totaux communaux de l'IHSI).
- **Sections communales** : les populations IHSI 2015 par section, appariées par rang aux P-codes OCHA (570 sur 570), ne sont pas combinées avec la grille. Leur répartition s'écarte trop de celle de WorldPop (rapport de 0,28 à 1,81 pour 90 % des sections), et un recalage par section produisait des km² à 98 000 hab./km².

## Architecture (version 2.0)

1. **Données et mesures.**
   - Zone métropolitaine = sept communes (définition de la DTM), listées en section 3.
   - Violence principale : décès UCDP **localisés précisément**, sur les **12 mois se terminant au mois de départ** de chaque localité (date de la DTM), pondérés par les départs. Les communes sans départ prennent la distribution nationale des mois de départ.
   - Couverture de l'UCDP face à l'ONU : 8 % en 2023, 23 % en 2024, 41 % en 2025 (tableau 3).
2. **Correction démographique.**
   - Scénarios : A (brut) ; **B (central, « axes routiers »)** ; C (toutes provenances) ; **S (surcomptage, borne basse)** ; D ; E (sections).
   - D : 300 tirages ; la part non majoritaire va aux provenances proches (noyau de 50 km) ; erreur par localité (20 %) et par commune d'accueil (15 %).
   - **Enveloppe globale** : plafonds × règles, surcomptage, tirages D, *rounds* 10 à 13. Zone métropolitaine de 2,31 à 2,72 M (2,41 M en central).
   - **Décomposition de la perte de la zone** (tableau 7) : départs nets propres, excédents de Gressier et de Mirebalais, croissance 2015-2024 supposée.
   - Section « Contrôles de cohérence » (ex-« Validation »).
3. **Modèle en coupe.**
   - **PPML-SLX** sur les départs du **scénario B** (et non plus bruts) et sur les arrivées, avec la population de base en exposition ; plus d'équation du solde. **Écarts-types robustes (HC) seuls** depuis le 20 novembre 2026. Les écarts-types de Conley (50 km) sont encore calculés (`E_dep_c`, `E_arr_c`), mais plus utilisés, car ils ne sont pas fiables ici. Avec le noyau uniforme de fixest, la matrice n'est pas définie positive et les écarts-types diminuent quand le rayon augmente (0,02 à 150 km). Même avec un noyau de Bartlett, ils restent plus petits que les écarts-types robustes. En conséquence, l'effet total de la violence sur les arrivées n'est plus présenté comme significatif (p = 0,105).
   - Calendrier : cumul depuis 2022, 12 mois avant le *round*, placebo août-septembre 2026 ; partie logit ; effets en grandeurs naturelles.
   - Les huit modèles linéaires (asinh) passent en annexe A, avec des diagnostics présentés tels quels.
4. **Gravitaire.** Écarts-types regroupés par provenance × destination ; effets fixes de destination ; option « rester » ; bootstrap de Webb par provenance.
5. **Panel.** Fenêtres non chevauchantes alignées sur les *rounds* ; test de pré-tendance (intervalle suivant) ; GMM d'Arellano-Bond (instruments y t-3 à t-5) ; SDPD en comparaison. **Pas d'association robuste** (l'ancien effet tenait aux fenêtres glissantes).
6. **Robustesse.** 14 variantes du PPML-SLX ; 100 tirages combinés par les règles de Rubin.
7. **Section 10 (densité).**
   - Traduction des effets directs PPML : départs × exp(−β v), arrivées × exp(−γ v), résidu conservé.
   - Écart associé à la violence (pas une perte) ; Gressier et Mirebalais censurées ; sensibilité à l'indicatrice et aux classes ; cartes 2D avec panneau sur la zone métropolitaine.

## Sources (toutes ouvertes)

- **OIM, Cadre méthodologique de la DTM** (2e édition, 2022, version française ; PDF transmis par l'utilisateur). Il est cité pour les quatre composantes, les informateurs clés (« estimations et perceptions »), les relevés d'urgence (ETT) qui ne couvrent pas tous les mouvements, et le fait que l'évaluation de base vise des populations stables, les personnes en transit relevant du suivi des flux. C'est la cause du biais de Gressier.
- **OIM, DTM Haïti** (HDX) : API DTM, PDI par commune d'accueil, rounds 0 à 14 (avril 2022 – juillet 2026) ; évaluations de référence détaillées, rounds 10 à 14 (localités d'accueil, commune de provenance majoritaire, retournés).
  - **Round de référence : 14** (juillet 2026, collecte du 15 mai au 12 août 2026, 1 150 localités ; `R_OD <- 14` dans l'article). Passage du round 13 au round 14 le 18 novembre 2026, à la demande de l'utilisateur.
  - Le xlsx du round 14 est publié sur HDX depuis le 4 novembre 2026, mais il y est « en quarantaine » (`in_quarantine = TRUE`, téléchargement en 404). Le même fichier est sur le site de la DTM : https://dtm.iom.int/dtm_download_track/106181?file=1&type=node&id=68786 (« 2026_07_MSLA_Round_14_Synthèse_Public_vF.xlsx », mêmes en-têtes que le round 13).
  - Les affirmations du texte qui dépendent de la significativité sont conditionnelles (`DENS_SIG`, `VIOL_SUR`, `rho_p`, `phr_lr`) : elles s'ajustent quand on change de round.
- **WorldPop Global2 R2025A**, 100 m, contraint (2020, 2022, 2025, 2026). Pour Haïti, un seul point de référence : COD-PS 2022 (140 communes, 129 unités).
- **UCDP** (Uppsala) : Georeferenced Event Dataset 26.1 (jusqu'à fin 2025) et événements candidats 2026 (provisoires). Ce sont des événements de violence mortelle, géolocalisés et attribués à des acteurs nommés (Viv Ansanm, Gran Grif…). Le nom du fichier candidat change à chaque mise à jour mensuelle : adapter `UCDP_CANDIDATS` dans le script.
- **IHSI** : estimations de la population, des ménages, de la superficie et de la densité par commune et section communale.
  - 2015 : PDF archivé sur la Wayback Machine.
  - 2024 : « Estimations désagrégées de la population haïtienne en 2024 », PDF de 509 pages, sur le site de l'IHSI (copie identique sur HaitiDocs).
  - 2025 : rien de publié à la mi-novembre 2026. La page des projections infranationales est « en attente » ; seule figure une croissance nationale moyenne de 1,28 % par an pour 2020-2025.
  - Méthode 2024 : projections nationales du CELADE ; poids des départements de 2015, ajustés avec les données de l'OIM sur les déplacés ; structure communale de 2015 à l'intérieur de chaque département.
  - Conséquence : pas de déplacement entre communes d'un même département (Ouest +0,2 % entre 2015 et 2024, Sud +23 %).
- **HDX HAPI** : population COD-PS 2024 par commune (chargée, plus utilisée dans l'article).
- **OCHA COD-AB** : limites des 140 communes ; P-codes communs à toutes les sources.

ACLED n'est pas utilisé. Le compte gratuit (niveau Open) ne donne que des agrégats par département, sans les auteurs ; la version 2.0 chiffre à la place la couverture de l'UCDP face aux décomptes de l'ONU (HCDH, BINUH).

La section « Déclarations » a été supprimée à la demande de l'utilisateur (version 2.1). Affiliations, contact, financement, liens d'intérêts (en particulier tout lien avec un opérateur de téléphonie mobile), licence et dépôt du code avec DOI restent à fixer par les auteurs avant diffusion.

## Points d'attention

- **Violence des gangs** = tous les événements UCDP sauf les violences de l'État contre des civils.
- **Rattachement à la commune** selon la précision de localisation de l'événement :
  - lieu exact ou proche : commune la plus proche ;
  - arrondissement ou département seulement : décès répartis au prorata de la population ;
  - pays seulement : événement écarté.
- La « provenance » DTM est le dernier lieu quitté, attribué à toute la localité d'accueil. Les départs déclarés depuis Gressier (267 873 au round 14, 6,8 fois sa population) et Mirebalais (181 231, 1,7 fois) sont plafonnés à 75 %. L'excédent est réattribué selon sa cause (règle `realloc = "axes"`, retenue le 17 novembre 2026 d'après les indications de l'utilisateur) :
  - **Gressier** (excédent de 238 140 au round 14), lieu de transit sur la RN2 : au sud-ouest de la capitale (Carrefour, Fontamara, Martissant), au prorata des départs déclarés, avec Carrefour entier et Port-au-Prince pour la seule part de la section de Martissant (30 % de sa population). Carrefour en reçoit 59 %. Contrôle : dans les communes qui accueillent les déplacés rattachés à Gressier, les déplacés venus directement de la ZMPP viennent à 52 % de Carrefour, 38 % de Port-au-Prince, 8 % de Delmas et 1 % de Croix-des-Bouquets, soit 58/42 entre Carrefour et Port-au-Prince.
  - **Mirebalais** (excédent de 101 497 au round 14) : il ne s'agit pas de transit. 83 % des départs sont datés de mars-avril 2025, au moment de l'attaque, et Mirebalais n'hébergeait que 7 500 PDI en décembre 2024. L'excédent tient à l'attribution des localités à leur provenance majoritaire. Il est réparti sur toutes les communes de départ, au prorata de leurs départs, sauf les communes refuges Delmas, Tabarre et Pétion-Ville ; 69 % vont à la ZMPP.
  - **Croix-des-Bouquets** n'est pas un lieu de transit vers Gressier ni vers Mirebalais : 68 % de ses départs sont antérieurs à 2025, 6 % seulement datent du printemps ou de l'été 2025, et ses déplacés partent vers le Sud-Est (35 %), le Nord (14 %) et Delmas (11 %).
  - Variantes en annexe : Port-au-Prince entier, excédent de Mirebalais à Croix-des-Bouquets (−66 %), anciennes règles (ZMPP au prorata des départs ou de la population, toutes communes de départ).
- Relevés d'urgence de la DTM sur Gressier (fiches 42 et 107) et estimation du maire en 2024 : les départs réels se comptent en dizaines de milliers. Ils sont cités en section 3.1 et confortent le plafond.
- La zone métropolitaine suit la définition DTM : 7 communes, Port-au-Prince, Delmas, Carrefour, Pétion-Ville, Cité Soleil, Tabarre et Croix-des-Bouquets.
