# =============================================================================
#  Cartes 3D (rayshader) des départements de l'Ouest et de l'Artibonite :
#  communes qui ont perdu ou gagné de la densité avec les déplacements (juillet 2026)
# -----------------------------------------------------------------------------
#  Hauteur des pics : densité corrigée des déplacements (scénario B, cellules de 1 km²).
#  Couleur : variation de la population de la commune due aux déplacements, par rapport
#  à la population de référence (IHSI) : rouge = perte de densité, bleu = gain.
#
#  Entrée : data/densite_violence.rds, écrit par l'article (chunk densite-calc)
#  Sorties : figures/carte_3d_ouest.png, figures/carte_3d_artibonite.png
#  Usage  : Rscript scripts/04_cartes_3d_departements.R [apercu|finale] [refaire]
#  Rendu et placement des étiquettes repris de scripts/03_carte_3d_violence.R.
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
Q <- switch(QUALITE, apercu = list(w = 1200, samples = 16), finale = list(w = 2400, samples = 100))
dir_f <- file.path(racine, "figures"); dir.create(dir_f, showWarnings = FALSE)
dir_r <- file.path(dir_f, "rendus");   dir.create(dir_r, showWarnings = FALSE)

# ---- 1. Données ---------------------------------------------------------------------------------
dv <- readRDS(file.path(racine, "data", "densite_violence.rds"))
cm <- dv$communes
g  <- merge(dv$grille, cm[, .(pcode, commune, departement, var_B)], by = "pcode")
COURT <- c("Petite Rivière de l'Artibonite" = "Petite-Rivière", "Saint-Michel de l'Attalaye" = "Saint-Michel",
           "Cornillon / Grand Bois" = "Cornillon", "Croix-Des-Bouquets" = "Croix-des-Bouquets",
           "Pointe à Raquette" = "Pointe-à-Raquette", "Anse à Galets" = "Anse-à-Galets")
court <- function(x) unname(ifelse(x %in% names(COURT), COURT[x], x))
fmt <- function(x, arrondi = -2) format(round(x, arrondi), big.mark = " ", scientific = FALSE, trim = TRUE)
pct <- function(v) { r <- round(v); ifelse(r > 0, paste0("+", r, " %"), ifelse(r < 0, paste0("−", -r, " %"), "0 %")) }

# ---- 2. Couleurs : rouge (perte) - gris (aucune variation) - bleu (gain) -------------------------
STOPS <- data.frame(v = c(-60, -25, -8, 0, 8, 20, 40),
                    col = c("#8E1B1E", "#D03B35", "#E8897D", "#ADA79D", "#7FAEE8", "#3D87DF", "#174E92"))
couleur_v <- function(v) { m <- col2rgb(STOPS$col) / 255
  sapply(1:3, function(k) approx(STOPS$v, m[k, ], xout = v, rule = 2)$y) }
# les cellules peu peuplées tirent vers la couleur du sol (pierre claire), et non vers le blanc du fond
SOL <- "#B9B1A3"
texture <- function(Mv, Md) {
  cc <- couleur_v(as.vector(Mv))
  a  <- pmin(1, pmax(0.40, (log10(pmax(as.vector(Md), 1)) - 1.5) / (log10(3000) - 1.5)))
  s  <- matrix(col2rgb(SOL) / 255, nrow(cc), 3, byrow = TRUE)
  cc <- s + (cc - s) * a
  cc[is.na(cc)] <- 1
  aperm(array(cc, dim = c(nrow(Mv), ncol(Mv), 3)), c(2, 1, 3))
}

# ---- 3. Outils de rendu (voir 03_carte_3d_violence.R) ---------------------------------------------
cones <- function(R, k, p = 1, marge = 0.9) {
  M <- raster_to_matrix(R)
  c0 <- (k + 1) / 2; rayon <- (k - 1) / 2 + marge
  K <- outer(seq_len(k), seq_len(k), function(a, b) pmax(0, 1 - sqrt((a - c0)^2 + (b - c0)^2) / rayon)^p)
  list(M = kronecker(M, K), Md = kronecker(M, matrix(1, k, k)), k = k)
}
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
  list(im = readPNG(f, native = TRUE), x0 = (bx0 + bx1) / 2 - wpx * s / 2, y0 = (by0 + by1) / 2 - hpx * s / 2, wmm = wpx * s, hmm = hpx * s,
       wpx = wpx, hpx = hpx, cx = cc[1] - 1, cy = rr[1] - 1)
}
mm <- function(PL, px, py) data.frame(X = unname(PL$x0 + (px - PL$cx) / PL$wpx * PL$wmm),
                                      Y = unname(PL$y0 + (1 - (py - PL$cy) / PL$hpx) * PL$hmm))
etaler <- function(y, gap, ymin = -Inf, ymax = Inf) {
  o <- order(y); z <- y[o]
  for (k in seq_along(z)[-1]) z[k] <- max(z[k], z[k - 1] + gap)
  z <- z - (mean(z) - mean(y[o]))
  if (max(z) > ymax) z <- z - (max(z) - ymax)
  if (min(z) < ymin) z <- z + (ymin - min(z))
  out <- y; out[o] <- z; out
}

FONT <- "Segoe UI"; pt2mm <- 0.3528
INK <- "#0b0b0b"; INK2 <- "#52514e"; MUET <- "#898781"
largeur <- function(s, pt, weight = "normal") string_width(s, family = FONT, size = pt, weight = weight) * pt2mm
texte <- function(x, y, lab, pt, face = "plain", col = INK, hjust = 0.5, vjust = 0.5, lh = 1.1)
  annotate("text", x = x, y = y, label = lab, size = pt / .pt, fontface = face, colour = col,
           family = FONT, hjust = hjust, vjust = vjust, lineheight = lh)

# ---- 4. Carte d'un département ----------------------------------------------------------------------
carte_departement <- function(dep, nom, titre, cam, haut, k = 7, H = 128, boite = c(34, 8, 136, 106)) {
  gd <- g[departement == dep]
  R  <- rast(as.data.frame(gd[, .(x, y, pop_B)]), type = "xyz", crs = "EPSG:32618")
  RV <- rast(as.data.frame(gd[, .(x, y, var_B)]), type = "xyz", crs = "EPSG:32618")
  C  <- cones(R, k)
  Mv <- kronecker(raster_to_matrix(RV), matrix(1, k, k))
  REND <- rendre(nom, C$M, texture(Mv, C$Md), haut = haut, w = Q$w, h = round(Q$w * 0.72), cam = cam)
  W <- 170
  PL <- placer(REND, boite[1], boite[2], boite[3], boite[4])
  # sommet du pic le plus dense de chaque commune
  cd_ <- cm[departement == dep]
  L <- rbindlist(lapply(cd_$pcode, function(pc) {
    z <- gd[pcode == pc][which.max(pop_B)]
    b <- cellFromXY(R, cbind(z$x, z$y))
    I <- (colFromCell(R, b) - 1) * C$k + (C$k + 1) / 2; J <- (rowFromCell(R, b) - 1) * C$k + (C$k + 1) / 2
    p <- sommet_px(REND$loc, I, J); s <- mm(PL, p["px"], p["py"])
    data.table(pcode = pc, X = s$X, Y = s$Y)
  }))
  L <- merge(L, cd_[, .(pcode, commune, var_B)], by = "pcode")[!is.na(X)]
  L[, `:=`(nom = court(commune), val = pct(var_B), cote = ifelse(X < PL$x0 + PL$wmm / 2, "g", "d"))]
  L[, `:=`(wn = largeur(nom, 6.6), wv = largeur(val, 6.6, "bold"))]
  L[, ly := NA_real_]
  for (ct in c("g", "d")) { k2 <- L$cote == ct; if (any(k2)) L$ly[k2] <- etaler(L$Y[k2], 4.6, ymin = boite[2] + 2, ymax = boite[4] - 2) }
  XG <- 32; XD <- 138
  # légende divergente
  lx0 <- 6; lx1 <- 66; ly <- H - 11; vmin <- -60; vmax <- 40
  lv <- seq(vmin, vmax, length.out = 120)
  lb <- data.frame(x0 = lx0 + (lv - vmin) / (vmax - vmin) * (lx1 - lx0), v = lv)
  lb$x1 <- lb$x0 + (lx1 - lx0) / 120 + 0.05; lb$fill <- rgb(couleur_v(lb$v))
  tk <- c(-60, -40, -20, 0, 20, 40)
  p <- ggplot() +
    annotation_raster(PL$im, xmin = PL$x0, xmax = PL$x0 + PL$wmm, ymin = PL$y0, ymax = PL$y0 + PL$hmm, interpolate = TRUE) +
    texte(lx0, ly + 8.5, "Variation de la densité due aux déplacements (couleur)", 7.5, "bold", INK, hjust = 0) +
    texte(lx0, ly + 4.8, "juillet 2026, par rapport à la population de référence (scénario B)", 6.2, "plain", INK2, hjust = 0) +
    geom_rect(data = lb, aes(xmin = x0, xmax = x1, ymin = ly - 1.3, ymax = ly + 1.3, fill = fill), colour = NA) +
    scale_fill_identity() +
    annotate("segment", x = lx0 + (tk - vmin) / (vmax - vmin) * (lx1 - lx0), xend = lx0 + (tk - vmin) / (vmax - vmin) * (lx1 - lx0),
             y = ly - 1.3, yend = ly - 2.3, colour = INK2, linewidth = 0.2) +
    annotate("text", x = lx0 + (tk - vmin) / (vmax - vmin) * (lx1 - lx0), y = ly - 3.9, label = pct(tk),
             size = 5.8 / .pt, family = FONT, colour = INK2) +
    texte(lx1 + 4, ly + 1, "Rouge : perte de densité\nBleu : gain de densité\nHauteur des pics : densité corrigée\n(échelle propre à la carte)",
          6, "plain", INK2, hjust = 0, vjust = 0.5, lh = 1.15) +
    texte(2, 2, paste0("Sources : OIM, Matrice de suivi des déplacements (round 14, juillet 2026) ; IHSI ; WorldPop R2025A ",
                       "(répartition à l'intérieur des communes). Calculs des auteurs."),
          5.3, "plain", MUET, hjust = 0, vjust = 0)
  for (i in seq_len(nrow(L))) {
    l <- L[i]; colv <- if (l$var_B < -0.5) "#A3131B" else if (l$var_B > 0.5) "#1F5FB0" else INK2
    if (l$cote == "g") {
      p <- p + annotate("segment", x = XG + 0.8, y = l$ly, xend = l$X, yend = l$Y, colour = "#7a7975", linewidth = 0.22) +
        annotate("point", x = l$X, y = l$Y, size = 0.45, colour = "#555555") +
        texte(XG, l$ly, l$val, 6.6, "bold", colv, hjust = 1) +
        texte(XG - l$wv - 1, l$ly, l$nom, 6.6, "plain", INK, hjust = 1)
    } else {
      p <- p + annotate("segment", x = XD - 0.8, y = l$ly, xend = l$X, yend = l$Y, colour = "#7a7975", linewidth = 0.22) +
        annotate("point", x = l$X, y = l$Y, size = 0.45, colour = "#555555") +
        texte(XD, l$ly, l$nom, 6.6, "plain", INK, hjust = 0) +
        texte(XD + l$wn + 1, l$ly, l$val, 6.6, "bold", colv, hjust = 0)
    }
  }
  p <- p + coord_fixed(xlim = c(0, W), ylim = c(0, H), expand = FALSE, clip = "on") +
    theme_void() + theme(plot.margin = margin(0, 0, 0, 0), plot.background = element_rect(fill = "white", colour = NA))
  f_out <- file.path(dir_f, sprintf("carte_3d_%s%s.png", nom, if (QUALITE == "finale") "" else "_apercu"))
  ggsave(f_out, p, device = agg_png, width = W, height = H, units = "mm", dpi = if (QUALITE == "finale") 300 else 150, bg = "white")
  message("Carte écrite : ", f_out)
}

carte_departement("Ouest", "ouest", "Département de l'Ouest",
                  cam = list(theta = 0, phi = 50, zoom = 0.56, fov = 22, lookat = c(0, -10, 0)), haut = 0.40,
                  H = 104, boite = c(30, 7, 140, 86))
carte_departement("Artibonite", "artibonite", "Département de l'Artibonite",
                  cam = list(theta = 0, phi = 52, zoom = 0.56, fov = 22, lookat = c(0, -10, 0)), haut = 0.40)
