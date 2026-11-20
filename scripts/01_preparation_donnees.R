# =============================================================================
#  Déplacements internes et densité de population en Haïti
#  01 — Préparation des données
# -----------------------------------------------------------------------------
#  Sources (toutes ouvertes, via HDX sauf WorldPop) :
#   - OIM, Displacement Tracking Matrix (DTM) Haïti :
#       * API DTM (PDI par commune d'accueil, rounds 0 à 14, avr. 2022 – juil. 2026)
#       * évaluations de référence détaillées (rounds 10 à 14) : localités d'accueil,
#         commune de provenance de la majorité des PDI, retournés
#   - WorldPop Global2 R2025A, population contrainte à 100 m (2020, 2022, 2025, 2026)
#   - OCHA COD-PS 2024 (population par commune, via HDX HAPI)
#   - UCDP, Georeferenced Event Dataset 26.1 (1989–2025) et événements candidats 2026 :
#     violence des gangs, événement par événement, géolocalisée
#   - OCHA COD-AB : limites des 140 communes (P-codes communs à toutes les sources)
#
#  Sorties (data/) : communes.rds, dtm_panel.rds, dtm_localites.rds, flux_od.rds,
#                    ucdp_evenements.rds, ucdp_communes_mois.rds, grille_1km.rds
#  Usage : Rscript "Deplacements Internes & Densite/scripts/01_preparation_donnees.R"
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(sf); library(terra); library(readxl)
})
sf_use_s2(FALSE)
options(timeout = 900)

racine <- tryCatch(dirname(dirname(normalizePath(sys.frame(1)$ofile))), error = function(e) {
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a)) return(dirname(dirname(normalizePath(sub("^--file=", "", a)))))
  normalizePath("Deplacements Internes & Densite")
})
brut <- file.path(racine, "data", "brut"); dir.create(brut, recursive = TRUE, showWarnings = FALSE)
prep <- file.path(racine, "data")
UTM  <- "EPSG:32618"

telecharger <- function(url, fichier) {
  f <- file.path(brut, fichier)
  if (!file.exists(f)) { message("Téléchargement : ", fichier); download.file(url, f, mode = "wb", quiet = TRUE) }
  f
}
hdx <- "https://data.humdata.org/dataset/"
f_api  <- telecharger(paste0(hdx, "230d6112-6379-4078-ab85-10ea7013e246/resource/f6a2b764-648d-400b-8eb9-2471dc8a219f/download/hti-iom-dtm-from-api-admin-0-to-2.csv"), "dtm_api_admin0-2.csv")
f_pop  <- telecharger(paste0(hdx, "51f32d92-8dfe-4ca7-b913-70f19292d68d/resource/b0b87ca2-9990-4c94-a645-880cba0befbb/download/hdx_hapi_population_hti.csv"), "hapi_population.csv")
dtm_xlsx <- c(
  r10 = telecharger(paste0(hdx, "eb78c733-25fc-4195-b39c-5b33365cc924/resource/22cd24b9-34ba-40e6-aa22-6183ceab3140/download/msla-round-10-detaille-deplacement-et-besoins-public.xlsx"), "dtm_r10_2025-06.xlsx"),
  r11 = telecharger(paste0(hdx, "eb78c733-25fc-4195-b39c-5b33365cc924/resource/570dad78-b28f-408d-9a6a-f131f382f4a7/download/dtm-haiti-msla-round-11-september-2025-hdx.xlsx"), "dtm_r11_2025-09.xlsx"),
  r12 = telecharger(paste0(hdx, "eb78c733-25fc-4195-b39c-5b33365cc924/resource/74482ee7-c8aa-48da-bfae-2d52b83af554/download/msla-round-12-synthese-public.xlsx"), "dtm_r12_2025-12.xlsx"),
  r13 = telecharger(paste0(hdx, "eb78c733-25fc-4195-b39c-5b33365cc924/resource/e62c86d4-417c-4cc3-8f9f-9807fec49c93/download/2026_05_msla_round_13_synthese_public_vf.xlsx"), "dtm_r13_2026-05.xlsx"),
  # round 14 (juillet 2026, collecte du 15 mai au 12 août 2026) : la copie HDX (ressource 725156ae…) est en
  # quarantaine depuis le 4 novembre 2026 ; même fichier sur le site de la DTM (« Jeux de données publique »)
  r14 = telecharger("https://dtm.iom.int/dtm_download_track/106181?file=1&type=node&id=68786", "dtm_r14_2026-07.xlsx"))
f_cod <- file.path(brut, "cod_ab", "hti_admin2.geojson")
if (!file.exists(f_cod)) {
  z <- telecharger(paste0(hdx, "777e8b06-337f-4295-80bc-ca1515244215/resource/1d89a0d5-897d-4c83-ab37-f363a0dca850/download/hti_admin_boundaries.geojson.zip"), "cod_ab.geojson.zip")
  unzip(z, exdir = file.path(brut, "cod_ab"))
}
# UCDP : version annuelle (jusqu'à fin 2025) et événements candidats mensuels (2026, provisoires).
# Le nom du fichier candidat change à chaque mise à jour : voir https://ucdp.uu.se/downloads/
UCDP_GED       <- "https://ucdp.uu.se/downloads/ged/ged261-csv.zip"
UCDP_CANDIDATS <- "https://ucdp.uu.se/downloads/candidateged/GEDEvent_v26_01_26_09.csv"
dir.create(file.path(brut, "ucdp"), showWarnings = FALSE)
f_ged <- file.path(brut, "ucdp", "ged261", "GEDEvent_v26_1.csv")
if (!file.exists(f_ged)) {
  z <- telecharger(UCDP_GED, file.path("ucdp", basename(UCDP_GED)))
  unzip(z, exdir = file.path(brut, "ucdp", "ged261"))
}
f_cand <- telecharger(UCDP_CANDIDATS, file.path("ucdp", basename(UCDP_CANDIDATS)))

wp_url <- function(y) sprintf("https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/%d/HTI/v1/100m/constrained/hti_pop_%d_CN_100m_R2025A_v1.tif", y, y)
ANS_WP <- c(2020, 2022, 2025, 2026)
f_wp <- setNames(vapply(ANS_WP, function(y) telecharger(wp_url(y), basename(wp_url(y))), ""), ANS_WP)

# ---- 1. Communes (COD-AB) ---------------------------------------------------------------
com <- st_read(f_cod, quiet = TRUE) |> st_make_valid()
com <- com[, c("adm2_pcode", "adm2_name1", "adm1_name1", "adm1_pcode")]
names(com)[1:4] <- c("pcode", "commune", "departement", "dep_pcode")
com$arr <- substr(com$pcode, 1, 5)                       # arrondissement = 5 premiers caractères du P-code
com_u <- st_transform(com, UTM)
com$km2 <- as.numeric(st_area(com_u)) / 1e6
pt <- st_point_on_surface(com_u)
xy <- st_coordinates(pt) / 1e3
com$x_km <- xy[, 1]; com$y_km <- xy[, 2]
pap <- st_coordinates(st_transform(st_sfc(st_point(c(-72.3388, 18.5446)), crs = 4326), UTM)) / 1e3   # Champ-de-Mars
com$dist_pap_km <- sqrt((com$x_km - pap[1])^2 + (com$y_km - pap[2])^2)
# zone métropolitaine de Port-au-Prince : définition de la DTM (colonne « ZMPP » des évaluations détaillées)
ZMPP <- c("HT0111", "HT0112", "HT0113", "HT0114", "HT0117", "HT0118", "HT0131")
com$zmpp <- com$pcode %in% ZMPP
cat("Communes :", nrow(com), "| arrondissements :", length(unique(com$arr)), "\n")

# ---- 2. Population : WorldPop par commune et COD-PS 2024 ---------------------------------
v_com <- vect(com)
for (y in ANS_WP) {
  r <- rast(f_wp[as.character(y)])
  com[[paste0("wp", y)]] <- terra::extract(r, v_com, fun = sum, na.rm = TRUE, exact = TRUE)[, 2]
  cat(sprintf("WorldPop %d : %s hab. (grille : %s)\n", y, format(round(sum(com[[paste0("wp", y)]])), big.mark = " "),
              format(round(global(r, "sum", na.rm = TRUE)[[1]]), big.mark = " ")))
}
# Sections communales (COD-AB, 570 unités) : population WorldPop 2025
sec <- st_read(file.path(brut, "cod_ab", "hti_admin3.geojson"), quiet = TRUE) |> st_make_valid()
sec <- sec[, c("adm3_pcode", "adm3_name1", "adm2_pcode")]
names(sec)[1:3] <- c("section", "nom_section", "pcode")
sec_u <- st_transform(sec, UTM)
sec$km2 <- as.numeric(st_area(sec_u)) / 1e6
sec$wp2025 <- terra::extract(rast(f_wp["2025"]), vect(sec), fun = sum, na.rm = TRUE, exact = TRUE)[, 2]
cat("Sections communales :", nrow(sec), "\n")

pop <- fread(f_pop)[admin_level == 2 & gender == "all" & age_range == "all", .(pcode = admin2_code, codps2024 = population)]
com <- merge(com, pop, by = "pcode", all.x = TRUE)
cat("COD-PS 2024 :", format(sum(com$codps2024), big.mark = " "), "hab.\n")

# ---- 3. DTM : panel des PDI par commune d'accueil (API) ----------------------------------
api <- fread(f_api)[adminLevel == 2 & operation == "Countrywide monitoring"]
api[, raison := fcase(displacementReason %in% c("Conflict", "Insecurity"), "violence",
                      displacementReason == "Natural disaster", "catastrophe", default = "autre")]
panel <- api[, .(pdi = sum(numPresentIdpInd)), by = .(pcode = admin2Pcode, round = roundNumber, date = as.IDate(reportingDate), raison)]
panel <- dcast(panel, pcode + round + date ~ raison, value.var = "pdi", fill = 0)
panel[, pdi := rowSums(.SD), .SDcols = intersect(c("violence", "catastrophe", "autre"), names(panel))]
# panel cylindré à partir du round 7 (couverture nationale) : commune absente = aucune PDI recensée
dates <- unique(panel[, .(round, date)])
grille <- CJ(pcode = com$pcode, round = dates[round >= 7]$round)[dates, on = "round", nomatch = 0]
panel <- rbind(panel[round < 7], merge(grille, panel, by = c("pcode", "round", "date"), all.x = TRUE), fill = TRUE)
for (v in c("pdi", "violence", "catastrophe", "autre")) set(panel, which(is.na(panel[[v]])), v, 0)
setorder(panel, round, pcode)
nat <- fread(f_api)[adminLevel == 0 & operation == "Countrywide monitoring", .(pdi_nat = sum(numPresentIdpInd)), by = .(round = roundNumber, date = as.IDate(reportingDate))]
cat("Panel DTM :", nrow(panel), "observations ; total des rounds 7-14 :\n")
print(merge(panel[round >= 7, .(pdi_communes = sum(pdi)), by = round], nat, by = "round"))

# ---- 4. DTM : localités d'accueil et provenance (évaluations détaillées) -----------------
lire_round <- function(f) {
  s <- grep("data", excel_sheets(f), value = TRUE, ignore.case = TRUE)[1]
  x <- suppressMessages(read_excel(f, sheet = s, col_names = FALSE, col_types = "text"))
  d0 <- which(suppressWarnings(as.numeric(x[[2]])) > 40000)[1]          # 1re ligne de données (date Excel)
  h <- as.matrix(x[seq_len(d0 - 1), ])
  lab <- apply(h, 2, function(z) { z <- z[!is.na(z) & !grepl("^#", z)]; if (length(z)) trimws(tail(z, 1)) else "" })
  col <- function(motif) { j <- grep(motif, lab, perl = TRUE); if (length(j) != 1) stop(basename(f), " : colonne « ", motif, " » trouvée ", length(j), " fois"); j }
  num <- function(j) { v <- suppressWarnings(as.numeric(x[[j]][-seq_len(d0 - 1)])); v[is.na(v)] <- 0; v }
  txt <- function(j) x[[j]][-seq_len(d0 - 1)]
  data.table(
    pcode       = txt(col("^P-code commune$")),
    section     = txt(col("^P-code section communale$")),
    pdi         = num(col("^Personnes déplacées internes \\(PDI\\)$")),
    origine     = txt(col("^P-code commune de provenance de la majorité des PDI")),
    date_depl   = txt(col("^Date de déplacement de la majorité")),
    raison      = txt(col("^Raison de déplacement de la majorité")),
    retournes   = num(col("^Personnes retournées anciennes PDI$")),
    origine_ret = txt(col("^P-code commune de provenance de la majorité des retournés")))
}
loc <- rbindlist(lapply(names(dtm_xlsx), function(r) cbind(round = as.integer(sub("r", "", r)), lire_round(dtm_xlsx[[r]]))))
loc <- loc[!is.na(pcode)]
loc[, origine := fifelse(grepl("^HT[0-9]{4}$", origine), origine, NA_character_)]
loc[, origine_ret := fifelse(grepl("^HT[0-9]{4}$", origine_ret), origine_ret, NA_character_)]
cat("\nLocalités DTM : PDI par round (évaluations détaillées) et part avec commune de provenance :\n")
print(loc[, .(localites = .N, pdi = sum(pdi), part_origine_connue = sum(pdi[!is.na(origine)]) / sum(pdi),
              retournes = sum(retournes)), by = round])

# flux origine → destination (majorité de provenance attribuée à toutes les PDI de la localité)
flux <- loc[pdi > 0, .(pdi = sum(pdi)), by = .(round, origine, destination = pcode)]

# ---- 5. UCDP : violence des gangs, géolocalisée et rattachée aux communes ----------------
g1 <- fread(f_ged)[country == "Haiti"]
g2 <- fread(f_cand)[country == "Haiti"]
cols <- intersect(names(g1), names(g2))
ev <- rbind(cbind(g1[, ..cols], provisoire = FALSE), cbind(g2[, ..cols], provisoire = TRUE)[!id %in% g1$id])
ev[, `:=`(date = as.IDate(date_start), mois = as.IDate(format(as.IDate(date_start), "%Y-%m-01")))]
# Catégories : tout sauf la violence de l'État contre des civils relève de la violence des gangs
# (les acteurs « XXX41 » des données candidates sont des groupes armés non encore identifiés)
ev[, categorie := fcase(
  type_of_violence == 3 & side_a == "Government of Haiti", "État contre civils",
  type_of_violence == 3, "Gangs contre civils",
  type_of_violence == 1, "État contre gangs",
  type_of_violence == 2, "Entre groupes armés")]
ev[, gang := categorie != "État contre civils"]
# Rattachement géographique selon la précision (where_prec) :
#  1, 2, 5, 7 : point de l'événement -> commune la plus proche (5 : zone nommée ; 7 : au large des côtes)
#  3 : seul l'arrondissement est connu -> réparti entre ses communes au prorata de la population
#  4 : seul le département est connu   -> réparti entre ses communes au prorata de la population
#  6 : seul le pays est connu          -> écarté
pts <- st_as_sf(ev, coords = c("longitude", "latitude"), crs = 4326)
ev[, pcode_pt := com$pcode[st_nearest_feature(pts, com)]]
popc <- as.data.table(st_drop_geometry(com))[, .(pcode, arr, dep_pcode, wp2025)]
repartir <- function(e) {
  if (e$where_prec %in% c(1, 2, 5, 7)) return(data.table(pcode = e$pcode_pt, poids = 1))
  if (e$where_prec == 6) return(data.table(pcode = character(0), poids = numeric(0)))
  ref <- popc[pcode == e$pcode_pt]
  zone <- if (e$where_prec == 3) popc[arr == ref$arr] else popc[dep_pcode == ref$dep_pcode]
  zone[, .(pcode, poids = wp2025 / sum(wp2025))]
}
ucdp <- rbindlist(lapply(seq_len(nrow(ev)), function(k) {
  r <- repartir(ev[k]); if (!nrow(r)) return(NULL)
  cbind(r, ev[k, .(id, mois, categorie, gang, morts = best, provisoire, precis = where_prec %in% c(1, 2))])
}))
ucdp[, `:=`(morts = morts * poids, evenements = poids)]
ucdp_cm <- ucdp[, .(morts = sum(morts), evenements = sum(evenements)), by = .(pcode, mois, categorie, gang, precis)]
cat("\nUCDP Haïti :", nrow(ev), "événements,", format(min(ev$date)), "→", format(max(ev$date)),
    "| écartés (pays seulement) :", ev[where_prec == 6, .N], "\n")
print(ev[year(date) >= 2022, .(evenements = .N, morts = sum(best)), by = .(categorie, an = year(date))][order(categorie, an)])

# ---- 6. Grille de 1 km² (WorldPop 2025) rattachée aux communes ---------------------------
r100 <- rast(f_wp["2025"])
tot  <- global(r100, "sum", na.rm = TRUE)[[1]]
d100 <- r100 / cellSize(r100, unit = "km")
e <- project(ext(r100), crs(r100), UTM)
e <- ext(floor(xmin(e) / 1e3) * 1e3, ceiling(xmax(e) / 1e3) * 1e3, floor(ymin(e) / 1e3) * 1e3, ceiling(ymax(e) / 1e3) * 1e3)
pop1k <- aggregate(project(d100, rast(e, resolution = 100, crs = UTM), method = "near") * 0.01, 10, sum, na.rm = TRUE)
pop1k <- pop1k * tot / global(pop1k, "sum", na.rm = TRUE)[[1]]
g <- as.data.table(as.data.frame(pop1k, xy = TRUE, na.rm = TRUE)); setnames(g, c("x", "y", "pop"))
g <- g[pop > 0]
pts <- st_as_sf(g, coords = c("x", "y"), crs = UTM)
i <- vapply(st_intersects(pts, com_u), function(k) if (length(k)) k[1] else NA_integer_, 1L)
i[is.na(i)] <- st_nearest_feature(pts[is.na(i), ], com_u)
g[, pcode := com_u$pcode[i]]
k <- vapply(st_intersects(pts, sec_u), function(z) if (length(z)) z[1] else NA_integer_, 1L)
k[is.na(k)] <- st_nearest_feature(pts[is.na(k), ], sec_u)
g[, section := sec_u$section[k]]
cat("Grille 1 km :", nrow(g), "cellules ;", format(round(sum(g$pop)), big.mark = " "), "hab.\n")

# Centres de population des communes (moyenne des carrés de 1 km² pondérée par la population)
cp <- g[, .(xp_km = weighted.mean(x, pop) / 1e3, yp_km = weighted.mean(y, pop) / 1e3), by = pcode]
com <- merge(com, cp, by = "pcode", all.x = TRUE)
com$xp_km <- ifelse(is.na(com$xp_km), com$x_km, com$xp_km)
com$yp_km <- ifelse(is.na(com$yp_km), com$y_km, com$yp_km)

# ---- 7. Sauvegardes ---------------------------------------------------------------------------
saveRDS(com, file.path(prep, "communes.rds"))
saveRDS(sec, file.path(prep, "sections.rds"))
saveRDS(panel, file.path(prep, "dtm_panel.rds"))
saveRDS(nat, file.path(prep, "dtm_national.rds"))
saveRDS(loc, file.path(prep, "dtm_localites.rds"))
saveRDS(flux, file.path(prep, "flux_od.rds"))
saveRDS(ev[, .(id, date, mois, categorie, gang, dyad_name, side_a, side_b, type_of_violence,
               where_prec, where_coordinates, latitude, longitude, morts = best, provisoire, pcode_pt)],
        file.path(prep, "ucdp_evenements.rds"))
saveRDS(ucdp_cm, file.path(prep, "ucdp_communes_mois.rds"))
saveRDS(g, file.path(prep, "grille_1km.rds"))
message("Données préparées dans ", prep)
