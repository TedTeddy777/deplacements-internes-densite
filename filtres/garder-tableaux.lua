-- PDF : évite qu'un tableau court soit coupé par un saut de page.
-- \gardertableau (défini dans l'en-tête de l'article) remplace \needspace : needspace laisse une pénalité de -100
-- que TeX, avec \raggedbottom, préfère ensuite à toute autre coupure, ce qui repoussait des tableaux qui tenaient.
-- Avant chaque cellule de code qui produit un tableau de 25 lignes au plus, \gardertableau réserve la place
-- du tableau (en \small), de sa légende et du début de la note qui le suit ; s'il en manque, le tableau
-- commence page suivante. Si le tableau suit directement un intertitre, la réserve est placée avant
-- l'intertitre, qui part avec lui. Les tableaux plus longs (sigles, populations par commune) restent
-- libres de se poursuivre sur plusieurs pages.

local function nb_lignes(div)
  local n, tab = 0, false
  div:walk({ Table = function(t)
    tab = true
    for _, b in ipairs(t.bodies) do n = n + #b.body end
    n = n + #t.head.rows
  end })
  return tab and n or nil
end

function Pandoc(doc)
  if not FORMAT:match("latex") then return nil end
  local out = pandoc.List()
  for _, b in ipairs(doc.blocks) do
    if b.t == "Div" and b.classes:includes("cell") then
      local n = nb_lignes(b)
      if n and n <= 25 then
        local h = math.ceil(n * 0.95) + 5
        local prec = out[#out]
        if prec and prec.t == "Header" then
          out:insert(#out, pandoc.RawBlock("latex", "\\gardertableau{" .. (h + 3) .. "\\baselineskip}"))
        else
          out:insert(pandoc.RawBlock("latex", "\\gardertableau{" .. h .. "\\baselineskip}"))
        end
      end
    end
    out:insert(b)
  end
  doc.blocks = out
  return doc
end
