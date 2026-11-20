# =============================================================================
#  Carte 3D (rayshader) : densité de population corrigée des déplacements (juillet 2026)
#  et écart de densité associé à la violence des gangs, par commune (modèle de la section 10)
# -----------------------------------------------------------------------------
#  Hauteur des pics : densité corrigée (scénario B, cellules de 1 km², population de
#  référence de l'IHSI répartie à l'intérieur des communes selon WorldPop).
#  Couleur : recul de densité dû à la violence propre de la commune, par rapport à une
#  commune comparable épargnée (effet direct du modèle de Durbin, section 9 de l'article).
#
#  Entrée : data/densite_violence.rds, écrit par l'article (chunk densite-calc)
#  Sortie : figures/carte_3d_violence.png (insérée dans l'article)
#  Usage  : Rscript scripts/03_carte_3d_violence.R [apercu|finale] [refaire]
#  Méthode de rendu et de placement des étiquettes reprise de
#  Cartographie/Population_density_haiti_rayshader.R.
# =============================================================================

options(rgl.useNULL = TRUE)
suppressPackageStartupMessages({
  library(data.table); library(terra); library(sf); library(rayshader); library(png)
  library(ggplot2); library(ragg); library(systemfonts)
})
sf_use_s2(FALSE)
racine <- if (basename(getwd()) == "scripts") ".." else "."
pdf(NULL)

arg <- commandArgs(TRUE)
QUALITE <- if (length(arg) && arg[1] %in% c("apercu", "finale")) arg[1] else "apercu"
REFAIRE <- "refaire" %in% arg
Q <- switch(QUALITE, apercu = list(w = 1300, samples = 16), finale = list(w = 2800, samples = 110))
dir_f <- file.path(racine, "figures"); dir.create(dir_f, showWarnings = FALSE)
dir_r <- file.path(dir_f, "rendus");   dir.create(dir_r, showWarnings = FALSE)

# ---- 1. Données : densité corrigée et recul dû à la violence ------------------------------------
dv <- readRDS(file.path(racine, "data", "densite_violence.rds"))
g  <- merge(dv$grille, dv$communes[, .(pcode, commune, ecart, d26)], by = "pcode", all.x = TRUE)
g[is.na(ecart), ecart := 0]
R  <- rast(as.data.frame(g[, .(x, y, pop_B)]), type = "xyz", crs = "EPSG:32618")   # hab. par km²
RE <- rast(as.data.frame(g[, .(x, y, ecart)]), type = "xyz", crs = "EPSG:32618")   # recul (%), par commune
fmt <- function(x, arrondi = -2) format(round(x, arrondi), big.mark = " ", scientific = FALSE, trim = TRUE)

# chaque cellule -> bloc k x k portant un cône ; Md et Me : densité et recul recopiés sur le bloc
K_CONE <- 5
cones <- function(R, k, p = 1, marge = 0.9) {
  M <- raster_to_matrix(R)
  c0 <- (k + 1) / 2; rayon <- (k - 1) / 2 + marge
  K <- outer(seq_len(k), seq_len(k), function(a, b) pmax(0, 1 - sqrt((a - c0)^2 + (b - c0)^2) / rayon)^p)
  list(M = kronecker(M, K), Md = kronecker(M, matrix(1, k, k)), k = k)
}
C  <- cones(R, K_CONE)
Me <- kronecker(raster_to_matrix(RE), matrix(1, K_CONE, K_CONE))
ij_sommet <- function(x, y) {
  b <- cellFromXY(R, cbind(x, y))
  c(I = (colFromCell(R, b) - 1) * C$k + (C$k + 1) / 2, J = (rowFromCell(R, b) - 1) * C$k + (C$k + 1) / 2)
}

# ---- 2. Couleurs : gris (aucun recul) -> rouge foncé (recul de 45 %) ------------------------------
STOPS <- data.frame(e = c(0, -3, -10, -20, -30, -45),
                    col = c("#A39D93", "#B99388", "#E0735E", "#D0402F", "#A3131B", "#5C0610"))
couleur_e <- function(e) { m <- col2rgb(STOPS$col) / 255
  sapply(1:3, function(k) approx(-STOPS$e, m[k, ], xout = -e, rule = 2)$y) }
# les cellules peu peuplées prennent la couleur du sol de l'île (pierre claire, visible sur le fond blanc) ;
# les pics portent la couleur du recul
SOL <- "#B9B1A3"
texture <- function(Me, Md) {
  cc <- couleur_e(as.vector(Me))
  a  <- pmin(1, pmax(0.06, (log10(pmax(as.vector(Md), 1)) - 1.5) / (log10(3000) - 1.5)))
  s  <- matrix(col2rgb(SOL) / 255, nrow(cc), 3, byrow = TRUE)
  cc <- s + (cc - s) * a
  cc[is.na(cc)] <- 1
  aperm(array(cc, dim = c(nrow(Me), ncol(Me), 3)), c(2, 1, 3))
}

# ---- 3. Rendu 3D et passes de localisation -----------------------------------------------------
GAP <- 1.2
rendre <- function(nom, M, tex, haut, w, h, cam) {
  f_img <- file.path(dir_r, sprintf("%s_%s.png", nom, QUALITE)); f_loc <- sub("\\.png$", "_loc.rds", f_img)
  if (!REFAIRE && file.exists(f_img) && file.exists(f_loc)) return(list(img = f_img, loc = readRDS(f_loc)))
  zs <- max(M, na.rm = TRUE) / (haut * nrow(M))
  t0 <- Sys.time()
  plot_3d(tex, M, zscale = zs, solid = FALSE, shadow = TRUE, shadowdepth = -(GAP + 0.2) * zs,
          windowsize = round(c(1200, 1200 * h / w)), background = "white")
  render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = cam$fov)
  base <- list(width = w, height = h, camera_lookat = cam$lookat,
               lightdirection = c(315, 135), lightaltitude = c(38, 65), lightintensity = c(900, 300),
               lightcolor = c("#FFF4E8", "#EAF1FF"), ground_material = rayrender::diffuse(color = "#FFFFFF"))
  do.call(render_highquality, c(list(filename = f_img, plot = FALSE, samples = Q$samples), base))
  message(sprintf("Rendu %s (%d x %d, %d échantillons) : %s", nom, w, h, Q$samples, format(Sys.time() - t0, digits = 3)))
  k <- 1200 / w
  dbg <- modifyList(base, list(width = 1200, height = round(h * k), light = FALSE, samples = 1, filename = NA, plot = TRUE))
  uv  <- do.call(render_highquality, c(dbg, list(debug_channel = "uv")))
  pos <- do.call(render_highquality, c(dbg, list(debug_channel = "position")))
  y <- pos[, , 2] - min(pos[, , 2], na.rm = TRUE)
  loc <- list(u = uv[, , 1], v = uv[, , 2], y = y, terrain = y > (GAP + 0.2) / 2, k = k, w = w, h = h,
              nI = nrow(M), nJ = ncol(M))
  saveRDS(loc, f_loc); rgl::close3d()
  im <- readPNG(f_img)[, , 1:3]
  gg <- apply(im[seq_len(round(0.04 * h)), , , drop = FALSE], 3, median)
  for (ch in 1:3) im[, , ch] <- pmin(im[, , ch] / gg[ch], 1)
  writePNG(im, f_img)
  list(img = f_img, loc = loc)
}
sommet_px <- function(loc, I, J) {
  tu <- (I - 0.5) / loc$nI; tv <- 1 - (J - 0.5) / loc$nJ
  for (tol in c(0.75, 1.5, 3, 6, 12)) {
    ok <- loc$terrain & abs(loc$u - tu) <= tol / loc$nI & abs(loc$v - tv) <= tol / loc$nJ
    if (any(ok, na.rm = TRUE)) break
  }
  ij <- which(ok, arr.ind = TRUE)
  if (!nrow(ij)) return(c(px = NA, py = NA))
  b <- unname(ij[which.min(ij[, 1]), ])
  c(px = (b[2] - 0.5) / loc$k, py = (b[1] - 0.5) / loc$k)
}

H_REND <- round(Q$w * 2436 / 3600)
REND <- rendre("haiti_violence", C$M, texture(Me, C$Md), haut = 0.24, w = Q$w, h = H_REND,
               cam = list(theta = 0, phi = 42, zoom = 0.53, fov = 22, lookat = c(0, -30, 25)))

# ---- 4. Toile (mm) ------------------------------------------------------------------------------
W <- 170; H <- 122
placer <- function(REND, bx0, by0, bx1, by1, marge = 0.01) {
  im <- readPNG(REND$img)[, , 1:3]
  fonce <- pmin(im[, , 1], im[, , 2], im[, , 3]) < 0.95
  rr <- range(which(rowSums(fonce) > 0.004 * ncol(im))); cc <- range(which(colSums(fonce) > 0.004 * nrow(im)))
  m <- round(marge * ncol(im))
  rr <- c(max(1, rr[1] - m), min(nrow(im), rr[2] + m)); cc <- c(max(1, cc[1] - m), min(ncol(im), cc[2] + m))
  imc <- im[rr[1]:rr[2], cc[1]:cc[2], ]
  f <- tempfile(fileext = ".png"); writePNG(imc, f)
  wpx <- ncol(imc); hpx <- nrow(imc)
  s <- min((bx1 - bx0) / wpx, (by1 - by0) / hpx)
  list(im = readPNG(f, native = TRUE), x0 = (bx0 + bx1) / 2 - wpx * s / 2, y0 = by0, wmm = wpx * s, hmm = hpx * s,
       wpx = wpx, hpx = hpx, cx = cc[1] - 1, cy = rr[1] - 1)
}
mm <- function(PL, px, py) data.frame(X = unname(PL$x0 + (px - PL$cx) / PL$wpx * PL$wmm),
                                      Y = unname(PL$y0 + (1 - (py - PL$cy) / PL$hpx) * PL$hmm))
PL <- placer(REND, 2, 7, 168, 112)

# sommet (mm) du pic le plus dense d'une commune
sommet_commune <- function(pc) {
  z <- g[pcode == pc][which.max(pop_B)]
  ij <- ij_sommet(z$x, z$y); p <- sommet_px(REND$loc, ij["I"], ij["J"]); mm(PL, p["px"], p["py"])
}

# ---- 5. Habillage --------------------------------------------------------------------------------
FONT <- "Segoe UI"; pt2mm <- 0.3528
INK <- "#0b0b0b"; INK2 <- "#52514e"; MUET <- "#898781"; ROUGE_F <- "#7E0A12"
largeur <- function(s, pt, weight = "normal") string_width(s, family = FONT, size = pt, weight = weight) * pt2mm
texte <- function(x, y, lab, pt, face = "plain", col = INK, hjust = 0.5, vjust = 0.5, lh = 1.1)
  annotate("text", x = x, y = y, label = lab, size = pt / .pt, fontface = face, colour = col,
           family = FONT, hjust = hjust, vjust = vjust, lineheight = lh)
trait <- function(x, y, xend, yend, col = INK2)
  list(annotate("segment", x = x, y = y, xend = xend, yend = yend, colour = col, linewidth = 0.25),
       annotate("point", x = xend, y = yend, size = 0.5, colour = col))
encadre <- function(cx, cy, l1, l2, l3, cible, p = c(7, 9.5, 6)) {
  pad <- 1.4
  w  <- max(largeur(l1, p[1], "bold"), largeur(l2, p[2], "bold"), largeur(l3, p[3])) + 2 * pad
  hl <- p * pt2mm * 1.3; h <- sum(hl) + 2 * pad - 0.4; y1 <- cy + h / 2 - pad
  c(trait(cx, cy, cible$X, cible$Y),
    list(annotate("rect", xmin = cx - w / 2, xmax = cx + w / 2, ymin = cy - h / 2, ymax = cy + h / 2,
                  fill = "#FFFFFF", colour = "#A3131B", linewidth = 0.35),
         texte(cx, y1, l1, p[1], "bold", INK, vjust = 1),
         texte(cx, y1 - hl[1], l2, p[2], "bold", ROUGE_F, vjust = 1),
         texte(cx, y1 - hl[1] - hl[2], l3, p[3], "plain", INK2, vjust = 1)))
}

cm <- dv$communes
# encadrés : Port-au-Prince et les trois communes où la violence a le plus réduit la densité
BOITES <- data.table(pcode = unique(c("HT0111", cm[commune %in% dv$top3, pcode])))
BOITES <- merge(BOITES, cm[, .(pcode, commune, ecart, d26)], by = "pcode")
# positions absolues des encadrés (mm) : Port-au-Prince en haut à droite, les trois autres en colonne dans le golfe,
# du recul le plus fort au moins fort
autres <- cm[pcode %in% setdiff(BOITES$pcode, "HT0111")][order(ecart), pcode]
POS <- c(list(HT0111 = c(146, 103)), setNames(list(c(31, 83), c(31, 68), c(31, 53))[seq_along(autres)], autres))
# villes de repère (petites étiquettes)
VILLES <- data.table(pcode = c("HT0311", "HT0511", "HT0711", "HT0211", "HT0811", "HT0611", "HT0911", "HT0621"),
                     dx = c(-4, -4, -4, 4, -4, 4, -4, 4), dy = c(4, 4, 4, -4, 4, 4, 4, 4))
VILLES <- merge(VILLES, cm[, .(pcode, commune)], by = "pcode")

carte <- function() {
  # légende : recul de densité (dégradé)
  lx0 <- 6; lx1 <- 56; ly <- 106; emax <- 45
  lv <- seq(0, emax, length.out = 100)
  lb <- data.frame(x0 = lx0 + lv / emax * (lx1 - lx0), e = -lv)
  lb$x1 <- lb$x0 + (lx1 - lx0) / 100 + 0.05; lb$fill <- rgb(couleur_e(lb$e))
  tk <- c(0, 10, 20, 30, 40)
  p <- ggplot() +
    annotation_raster(PL$im, xmin = PL$x0, xmax = PL$x0 + PL$wmm, ymin = PL$y0, ymax = PL$y0 + PL$hmm, interpolate = TRUE) +
    texte(lx0, ly + 9.5, "Écart de densité associé à la violence des gangs (modèle)", 7.5, "bold", INK, hjust = 0) +
    texte(lx0, ly + 5.5, "par rapport à la population prédite sans violence locale (couleur)", 6.2, "plain", INK2, hjust = 0) +
    geom_rect(data = lb, aes(xmin = x0, xmax = x1, ymin = ly - 1.4, ymax = ly + 1.4, fill = fill), colour = NA) +
    scale_fill_identity() +
    annotate("segment", x = lx0 + tk / emax * (lx1 - lx0), xend = lx0 + tk / emax * (lx1 - lx0), y = ly - 1.4, yend = ly - 2.4,
             colour = INK2, linewidth = 0.2) +
    annotate("text", x = lx0 + tk / emax * (lx1 - lx0), y = ly - 4, label = ifelse(tk == 0, "0", paste0("−", tk, " %")),
             size = 6 / .pt, family = FONT, colour = INK2) +
    texte(lx0, ly - 9, "Hauteur des pics : densité corrigée des déplacements,\njuillet 2026 (cellules de 1 km²)", 6.2, "plain", INK2,
          hjust = 0, vjust = 1, lh = 1.2) +
    texte(2, 2, paste0("Sources : OIM, Matrice de suivi des déplacements (round 14, juillet 2026) ; IHSI ; UCDP ; WorldPop R2025A ",
                       "(répartition à l'intérieur des communes). Calculs des auteurs."),
          5.4, "plain", MUET, hjust = 0, vjust = 0)
  for (k in seq_len(nrow(VILLES))) {
    s <- sommet_commune(VILLES$pcode[k]); if (is.na(s$X)) next
    dx <- VILLES$dx[k]; dy <- VILLES$dy[k]
    p <- p + trait(s$X + dx - sign(dx) * 0.6, s$Y + dy, s$X, s$Y, col = MUET) +
      texte(s$X + dx, s$Y + dy, VILLES$commune[k], 6.2, "plain", INK2, hjust = if (dx < 0) 1 else 0)
  }
  for (k in seq_len(nrow(BOITES))) {
    b <- BOITES[k]; s <- sommet_commune(b$pcode); d <- POS[[b$pcode]]; if (is.null(d)) d <- c(s$X + 30, s$Y + 10)
    p <- p + encadre(d[1], d[2], b$commune, paste0("−", format(round(-b$ecart), trim = TRUE), " %"),
                     paste0(fmt(b$d26), " hab./km² en juillet 2026"), s)
  }
  p + coord_fixed(xlim = c(0, W), ylim = c(0, H), expand = FALSE, clip = "on") +
    theme_void() + theme(plot.margin = margin(0, 0, 0, 0), plot.background = element_rect(fill = "white", colour = NA))
}

f_out <- file.path(dir_f, if (QUALITE == "finale") "carte_3d_violence.png" else "carte_3d_violence_apercu.png")
ggsave(f_out, carte(), device = agg_png, width = W, height = H, units = "mm", dpi = if (QUALITE == "finale") 300 else 150, bg = "white")
message("Carte écrite : ", f_out)
