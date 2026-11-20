# Estimations de population de l'IHSI : 2015 (avant la crise) et 2024 (CELADE, ajustées entre départements
# avec les données de l'OIM sur les déplacés).
# Sorties :
#   data/ihsi_communes.rds : par commune, population, ménages, superficie officielle et densité, 2015 et 2024
#   data/ihsi_sections.rds : par section communale (P-code OCHA), population et superficie de 2015
# Nécessite pdftotext (Xpdf ou Poppler ; MiKTeX en fournit un).

suppressPackageStartupMessages(library(data.table))
racine <- if (basename(getwd()) == "scripts") ".." else "."
brut <- file.path(racine, "data", "brut", "ihsi"); dir.create(brut, recursive = TRUE, showWarnings = FALSE)

SOURCES <- c(
  "2024" = "https://ihsi.gouv.ht/public/storage/document-views/March2025/Oan4m17p5LEKtsGEnHgt.pdf",   # site de l'IHSI (copie identique : docs.haitidocs.org/ihsi-2024-disaggregated-estimates.pdf)
  "2015" = "https://web.archive.org/web/20151106110552id_/http://www.ihsi.ht/pdf/projection/Estimat_PopTotal_18ans_Menag2015.pdf")

NB  <- "(\\d{1,3}(?: \\d{3})*|\\d+)"                         # entier, avec ou sans séparateur de milliers
DEC <- "(\\d+[.,]\\d+)"                                      # superficie
DNS <- "(\\d{1,3}(?: \\d{3})*(?:[.,]\\d+)?|\\d+(?:[.,]\\d+)?)" # densité
ENT <- "^\\s*\\d+\\s*[-.]\\s*Comm?unes?\\b"                  # « Comune » : coquille de l'IHSI (Caracol)
RX_COM <- paste0("^\\s*\\d+\\s*[-.]\\s*Comm?unes?\\s+(?:de\\s+|des\\s+|du\\s+|d['’]\\s*)?(.+?)\\s{2,}", NB, "\\s{2,}", NB, "\\s{2,}", DEC, "\\s{2,}", DNS, "\\s*$")
RX_SEC <- paste0("^\\s*(\\d+)\\s*(?:re|ère|er|e|ème)?\\s+(?:Section|Source)\\b(.*?)\\s{2,}(?:(Urbain(?:, Quartier)?|Rural)\\s{2,})?", NB, "\\s{2,}", NB, "\\s{2,}", DEC, "\\s{2,}", DNS, "\\s*$")
num <- function(x) as.numeric(gsub(" ", "", sub(",", ".", x, fixed = TRUE)))

lire_texte <- function(annee) {
  pdf <- file.path(brut, paste0("ihsi_estimations_", annee, ".pdf"))
  if (!file.exists(pdf)) download.file(SOURCES[[annee]], pdf, mode = "wb", quiet = TRUE)
  txt <- tempfile(fileext = ".txt")
  system2("pdftotext", c("-layout", "-enc", "UTF-8", shQuote(pdf), shQuote(txt)))
  l <- readLines(txt, encoding = "UTF-8", warn = FALSE)
  # Noms coupés sur deux lignes (2024) : « 2- Commune de Petit- » / ligne de chiffres / « Gôave » -> une seule ligne
  chif <- "^\\s*[\\d .,]+$"
  for (i in grep(ENT, l)) if (!grepl("\\d", sub(ENT, "", l[i], perl = TRUE)) && i + 2 <= length(l) &&
                             grepl(chif, l[i + 1], perl = TRUE) && !grepl("\\d", l[i + 2])) {
    suite <- trimws(l[i + 2]); debut <- trimws(l[i])
    l[i] <- paste0(debut, if (grepl("-$", debut)) "" else " ", suite, "   ", trimws(l[i + 1]))
  }
  # Fin de nom renvoyée à la ligne suivante, après les chiffres (« Petite Rivière » / « de l'Artibonite »)
  for (i in grep(ENT, l)) if (grepl("\\d+[.,]\\d+", l[i]) && i < length(l) && grepl("^\\s*(de|du|des|d')\\b", l[i + 1]) &&
                             !grepl("\\d", l[i + 1]))
    l[i] <- sub("^(\\s*\\d+\\s*[-.]\\s*Comm?unes?\\s+(?:de\\s+)?.+?)(\\s{2,}\\d)", paste0("\\1 ", trimws(l[i + 1]), "\\2"), l[i], perl = TRUE)
  l
}

# Communes : lignes des tableaux « Population totale, ménages, superficie et densité »
lire_communes <- function(l, annee) {
  m <- regmatches(l, regexec(RX_COM, l, perl = TRUE))
  m <- do.call(rbind, m[lengths(m) == 6])
  d <- unique(data.table(nom = trimws(m[, 2]), pop = num(m[, 3]), menages = num(m[, 4]), km2 = num(m[, 5]), densite = num(m[, 6])))
  stopifnot(all(abs(d$pop / d$km2 - d$densite) / d$densite < 0.02))   # cohérence population / superficie / densité
  d[, annee := as.integer(annee)]
}

# Sections communales : lignes « 1re Section X  Urbain|Rural  population  ménages  superficie  densité »,
# rattachées à la dernière commune rencontrée dans les mêmes tableaux
lire_sections <- function(l) {
  # Rang en exposant sur la ligne des chiffres, nom de la section sur la ligne suivante :
  # «  e   Urbain, Quartier   21 406 ... » / « 3 Section Bellevue » -> « 3 Section Bellevue   Urbain, Quartier   21 406 ... »
  for (i in grep("^\\s*(re|ère|er|e|ème)\\s{2,}\\S.*\\d+[.,]\\d+", l, perl = TRUE))
    if (i < length(l) && grepl("^\\s*\\d+\\s*(re|e)?\\s+(Section|Source)\\b", l[i + 1], perl = TRUE) && !grepl("\\d+[.,]\\d+", l[i + 1]))
      l[i + 1] <- paste0(trimws(l[i + 1]), "   ", sub("^\\s*(re|ère|er|e|ème)\\s{2,}", "", l[i], perl = TRUE))
  com <- NA_character_; out <- list()
  for (i in seq_along(l)) {
    mc <- regmatches(l[i], regexec(RX_COM, l[i], perl = TRUE))[[1]]
    if (length(mc) == 6) { com <- trimws(mc[2]); next }
    ms <- regmatches(l[i], regexec(RX_SEC, l[i], perl = TRUE))[[1]]
    if (length(ms) == 8 && !is.na(com))
      out[[length(out) + 1]] <- data.table(nom_commune = com, rang = as.integer(ms[2]), nom_section = trimws(ms[3]),
                                           milieu = ms[4], pop = num(ms[5]), km2 = num(ms[7]))
  }
  unique(rbindlist(out))
}

# Appariement aux P-codes OCHA : noms normalisés, puis corrections manuelles
norm <- function(x) {
  x <- iconv(tolower(trimws(x)), "UTF-8", "ASCII//TRANSLIT")
  x <- sub("^(les |le |la |l'|l )", "", x)
  gsub("[^a-z]", "", x)
}
CORR <- c(cornillon = "cornillongrandbois", chansolme = "chamsolme", ranquite = "ranquitte", valleedejacmel = "vallee")   # graphies différentes
com <- readRDS(file.path(racine, "data", "communes.rds"))
ref <- data.table(pcode = com$pcode, commune = com$commune, departement = com$departement, cle = norm(com$commune))
cle_commune <- function(x) { k <- norm(x); k[k %in% names(CORR)] <- CORR[k[k %in% names(CORR)]]; k }

txt <- list("2015" = lire_texte("2015"), "2024" = lire_texte("2024"))
ihsi <- rbind(lire_communes(txt[["2015"]], "2015"), lire_communes(txt[["2024"]], "2024"))
ihsi[, cle := cle_commune(nom)]
ihsi <- merge(ihsi, ref, by = "cle", all.x = TRUE)
non_app <- unique(ihsi[is.na(pcode), .(annee, nom)])
if (nrow(non_app)) { print(non_app); print(setdiff(ref$commune, ihsi$commune)) }
cat("Communes appariées :", ihsi[!is.na(pcode), uniqueN(pcode), by = annee][, paste(annee, V1, collapse = " ; ")], "\n")
out <- dcast(ihsi[!is.na(pcode)], pcode + commune + departement ~ annee, value.var = c("pop", "menages", "km2", "densite"))
saveRDS(out, file.path(racine, "data", "ihsi_communes.rds"))
cat("Écrit :", nrow(out), "communes\n")

# Sections communales de 2015 -> P-code OCHA (commune + rang de la section)
sec <- lire_sections(txt[["2015"]])
sec[, cle := cle_commune(nom_commune)]
sec <- merge(sec, ref[, .(cle, pcode)], by = "cle", all.x = TRUE)
stopifnot(!anyNA(sec$pcode))
# Coquilles de l'IHSI : « 2e Source Beauvoir » (Chansolme, prise en compte par le motif) ;
# « 2e Section Fond Melon Michineau » (Cayes-Jacmel) est la 4e section (HT0213-04 chez OCHA)
sec[pcode == "HT0213" & grepl("Fond Melon", nom_section), rang := 4L]
s15 <- sec[, .(pop_2015 = sum(pop), km2_2015 = sum(km2), nom_ihsi = nom_section[1]), by = .(pcode, rang)]
s15[, section := sprintf("%s-%02d", pcode, rang)]
# contrôle : la somme des sections reproduit la population de la commune
ctl <- merge(s15[, .(somme = sum(pop_2015)), by = pcode], out[, .(pcode, pop_2015)], by = "pcode")
cat("Sections IHSI 2015 :", nrow(s15), "; communes dont la somme des sections diffère de plus de 1 % :",
    ctl[abs(somme / pop_2015 - 1) > 0.01, .N], "\n")
if (ctl[abs(somme / pop_2015 - 1) > 0.01, .N]) print(ctl[abs(somme / pop_2015 - 1) > 0.01])
oc <- sf::st_drop_geometry(readRDS(file.path(racine, "data", "sections.rds")))
cat("Sections OCHA :", nrow(oc), "; appariées :", sum(oc$section %in% s15$section),
    "; IHSI sans équivalent OCHA :", sum(!s15$section %in% oc$section), "\n")
print(head(merge(s15, data.table(oc)[, .(section, nom_ocha = nom_section)], by = "section")[, .(section, nom_ihsi, nom_ocha, pop_2015)], 12))
saveRDS(s15[, .(section, pcode, rang, nom_ihsi, pop_2015, km2_2015)], file.path(racine, "data", "ihsi_sections.rds"))
