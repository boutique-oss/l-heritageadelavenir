#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════
# PIPELINE RAPHAËL HAMACHE — Installation automatique
# ═══════════════════════════════════════════════════════════════

REPO_URL="https://github.com/boutique-oss/l-heritageadelavenir.git"
REPO_DIR="l-heritageadelavenir"
PIPELINE_DIR="$REPO_DIR/pipeline-job-raphael"

echo "🚀 Installation du Pipeline Raphaël Hamache"
echo "══════════════════════════════════════════"

# ─────────────────────────────────────────
# 1. CLONER LE REPO
# ─────────────────────────────────────────
echo ""
echo "📥 Étape 1/4 : Clonage du repo..."

if [ -d "$REPO_DIR" ]; then
    echo "   Repo déjà présent, mise à jour..."
    cd "$REPO_DIR" && git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true
    cd ..
else
    git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"

# ─────────────────────────────────────────
# 2. CRÉER L'ARBORESENCE
# ─────────────────────────────────────────
echo ""
echo "📁 Étape 2/4 : Création de l'arborescence..."

mkdir -p "$PIPELINE_DIR"/{agents,scoring,profile,prompts,notifications,dashboard,scripts,output}
echo "   ✓ Dossiers créés"

# ─────────────────────────────────────────
# 3. CRÉER LES FICHIERS
# ─────────────────────────────────────────
echo ""
echo "📝 Étape 3/4 : Création des fichiers..."

cd "$PIPELINE_DIR"

# ─── package.json ───
cat > package.json << 'ENDPKG'
{
  "name": "pipeline-job-raphael",
  "version": "1.0.0",
  "description": "Pipeline automatisé de recherche d'emploi pour Raphaël Hamache",
  "type": "module",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "scrape": "node index.js scrape",
    "generate": "node index.js generate",
    "recalibrate": "node index.js recalibrate",
    "list": "node index.js list",
    "update": "node index.js update",
    "stats": "node index.js stats"
  },
  "dependencies": {
    "@google/generative-ai": "^0.21.0",
    "@supabase/supabase-js": "^2.45.0",
    "axios": "^1.7.0",
    "cheerio": "^1.0.0",
    "dotenv": "^16.4.0",
    "googleapis": "^140.0.0"
  },
  "engines": { "node": ">=18.0.0" }
}
ENDPKG

# ─── .env.example ───
cat > .env.example << 'ENDENV'
# ===== GOOGLE AI =====
GOOGLE_AI_API_KEY=your_key_here
GOOGLE_AI_MODEL=gemini-2.0-flash

# ===== SUPABASE =====
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key

# ===== FRANCE TRAVAIL =====
FRANCE_TRAVAIL_CLIENT_ID=PAR_jobwatcherv2_2da1e04c8564392a5080eb23a09dc1f9f8e5511e59b5edde02443e248455389d
FRANCE_TRAVAIL_CLIENT_SECRET=ca995393135b5ebf80cef84a4cb3ecc6074961392c6c18cae8caf738a15c984a
FRANCE_TRAVAIL_TOKEN_URL=https://entreprise.pole-emploi.fr/api/oauth2/access_token
FRANCE_TRAVAIL_API_URL=https://api.pole-emploi.io

# ===== GMAIL =====
GMAIL_CLIENT_ID=your_client_id
GMAIL_CLIENT_SECRET=your_client_secret
GMAIL_REFRESH_TOKEN=your_refresh_token
RAPHAEL_EMAIL=raphaelhahamache86@gmail.com

# ===== CONFIG =====
SCORE_SEUIL_NOTIFICATION=45
SCORE_SEUIL_AUTO_VALID=70

# ===== CANVA =====
CANVA_API_KEY=your_canva_api_key
CANVA_APP_ID=AAHAAElIW6U
ENDENV

# ─── .gitignore ───
cat > .gitignore << 'ENDGIT'
.env
node_modules/
*.log
.DS_Store
output/
ENDGIT

# ─── index.js ───
cat > index.js << 'ENDINDEX'
import 'dotenv/config'
import { GoogleGenerativeAI } from '@google/generative-ai'
import { createClient } from '@supabase/supabase-js'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import fs from 'fs'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

const genAI = new GoogleGenerativeAI(process.env.GOOGLE_AI_API_KEY)
const model = genAI.getGenerativeModel({ model: process.env.GOOGLE_AI_MODEL || 'gemini-2.0-flash' })

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY)

async function callAI(systemPrompt, userContent) {
  try {
    const result = await model.generateContent([
      { text: systemPrompt },
      { text: JSON.stringify(userContent, null, 2) }
    ])
    const text = result.response.text()
    const jsonMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/) || [null, text]
    const jsonStr = jsonMatch[1] || text
    return JSON.parse(jsonStr.trim())
  } catch (e) {
    console.error('Erreur AI:', e.message)
    return null
  }
}

function loadPrompt(name) {
  return fs.readFileSync(join(__dirname, 'prompts', `${name}.md`), 'utf8')
}

function loadProfile() {
  return JSON.parse(fs.readFileSync(join(__dirname, 'profile', 'raphael.json'), 'utf8'))
}

// AGENT 1 : SCRAPER
async function scrape(motsCles, localisation) {
  console.log(`\n🔍 Recherche: "${motsCles}" — ${localisation}`)
  const { franceTravailSearch, getBriefEntreprise } = await import('./agents/scraper.js')
  const calculator = await import('./scoring/calculator.js')
  const memory = await import('./agents/memory.js')

  const offresBrutes = await franceTravailSearch(motsCles, localisation)
  console.log(`   ${offresBrutes.length} offres récupérées`)

  const weights = await memory.chargerPoids(supabase)
  const offres = []

  for (const offre of offresBrutes) {
    const score = calculator.calculerScore(offre, weights)
    const typePoste = calculator.detecterTypePoste(offre.titre)
    const brief = await getBriefEntreprise(offre.entreprise)
    const analyse = calculator.analyserMatch({ ...offre, score }, score)

    offres.push({
      ...offre,
      ...brief,
      score_initial: score,
      type_poste: typePoste,
      raisons_match: analyse.raisonsMatch,
      raisons_decalage: analyse.raisonsDecalage,
      statut: 'detecte'
    })
  }

  offres.sort((a, b) => b.score_initial - a.score_initial)

  for (const offre of offres) {
    const id = await memory.stockerOffre(supabase, offre)
    offre.id = id
    if (offre.score_initial >= 45) {
      await memory.envoyerEmail(offre)
    }
  }

  console.log(`\n✅ ${offres.length} offres analysées`)
  console.log(`   🔥 ${offres.filter(o => o.score_initial >= 70).length} excellentes (≥70)`)
  console.log(`   ✓ ${offres.filter(o => o.score_initial >= 45 && o.score_initial < 70).length} intéressantes (45-70)`)

  return offres
}

// AGENT 2 : GENERATEUR
async function generate(offreId) {
  const memory = await import('./agents/memory.js')
  const { data: offre } = await supabase.from('offres').select('*').eq('id', offreId).single()

  if (!offre) throw new Error(`Offre ${offreId} non trouvée`)

  const profile = loadProfile()
  const promptRedacteur = loadPrompt('redacteur')

  const contenu = await callAI(promptRedacteur, { profil: profile, offre })

  if (!contenu) throw new Error('Échec génération')

  const canva = await import('./agents/canva-generator.js')
  const design = await canva.creerDesign({
    type: offre.type_poste,
    contenu: contenu.cv_contenu,
    lettre: contenu.lettre_motivation,
    titre: offre.titre,
    entreprise: offre.entreprise
  })

  await memory.stockerCandidature(supabase, {
    offre_id: offreId,
    canva_url: design.url,
    score_au_moment: offre.score_initial
  })

  console.log(`\n✅ Design créé: ${design.url}`)
  console.log(`📄 Lettre: `)
  console.log(contenu.lettre_motivation)

  return design
}

// AGENT 3 : RECALIBRAGE
async function recalibrate() {
  const memory = await import('./agents/memory.js')
  const calibrator = await import('./scoring/calibrator.js')

  const poidsActuels = await memory.chargerPoids(supabase)
  const historique = await memory.chargerHistoriqueCandidatures(supabase)

  const nouveauxPoids = calibrator.recalibrerPoids(historique, poidsActuels)
  await memory.sauvegarderPoids(supabase, nouveauxPoids)
  await memory.logLearning(supabase, poidsActuels, nouveauxPoids, null, historique.length)

  console.log('\n📊 Poids recalibrés:')
  for (const [k, v] of Object.entries(nouveauxPoids)) {
    console.log(`   ${k}: ${(v * 100).toFixed(1)}%`)
  }
}

// CLI
function parseArgs(args) {
  const params = {}
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg.startsWith('--')) {
      const [k, ...v] = arg.slice(2).split('=')
      params[k] = v.join('=')
    }
  }
  return params
}

async function main() {
  const args = process.argv.slice(2)
  const cmd = args[0]
  const params = parseArgs(args.slice(1))

  try {
    switch (cmd) {
      case 'scrape':
        await scrape(params.motsCles || 'chef projet agencement design', params.localisation || 'France entière')
        break
      case 'generate':
        if (!params.offreId) { console.error('❌ --offreId requis'); process.exit(1) }
        await generate(params.offreId)
        break
      case 'recalibrate':
        await recalibrate()
        break
      case 'list':
        await import('./agents/memory.js').then(m => m.listerOffres(supabase, { statut: params.statut, limit: parseInt(params.limit) || 20 })
          .then(offres => {
            console.log(`\n📋 ${offres.length} offres:`)
            offres.forEach(o => console.log(`   [${o.score_initial}] ${o.titre} @ ${o.entreprise} (${o.type_poste})`))
          }))
        break
      case 'update':
        if (!params.offreId || !params.resultat) { console.error('❌ --offreId et --resultat requis'); process.exit(1) }
        await import('./agents/memory.js').then(m => m.majCandidatureResultat(supabase, params.offreId, params.resultat, params.notes))
        console.log(`✅ Résultat: ${params.resultat}`)
        break
      case 'stats':
        await import('./agents/memory.js').then(m => m.getStats(supabase).then(s => {
          console.log('\n📈 STATISTIQUES')
          console.log(`   Offres: ${s.total_offres}`)
          console.log(`   Candidatures: ${s.total_candidatures}`)
          console.log(`   Taux réponse: ${s.taux_reponse}%`)
          console.log(`   Taux entretien: ${s.taux_entretien}%`)
        }))
        break
      default:
        console.log(`
🤖 Pipeline Raphaël Hamache

Usage: node index.js <cmd> [options]

CMD:
  scrape      Rechercher des offres
  generate    Générer un design
  list        Lister les offres
  update      Mettre à jour un résultat
  recalibrate Recalculer les poids
  stats       Afficher les stats

Options:
  --motsCles=<val>     Mots-clés
  --localisation=<val>  Ville/région
  --offreId=<uuid>     ID offre
  --resultat=<val>     envoye|reponse|entretien|refus|offre
  --statut=<val>       detecte|valide|ignoré|candidature_envoyee

Exemples:
  node index.js scrape --motsCles="chef projet agencement" --localisation="Nice"
  node index.js list --statut=detecte
  node index.js generate --offreId=<uuid>
  node index.js update --offreId=<uuid> --resultat=entretien
`)
    }
  } catch (e) {
    console.error('❌ Erreur:', e.message)
    process.exit(1)
  }
}

main()
ENDINDEX

# ─── agents/scraper.js ───
cat > agents/scraper.js << 'ENDSCRAPER'
import axios from 'axios'
import * as cheerio from 'cheerio'

const API_BASE = process.env.FRANCE_TRAVAIL_API_URL || 'https://api.pole-emploi.io'
const TOKEN_URL = process.env.FRANCE_TRAVAIL_TOKEN_URL || 'https://entreprise.pole-emploi.fr/api/oauth2/access_token'

let tokenCache = { token: null, expires: 0 }

export async function getAccessToken() {
  if (tokenCache.token && Date.now() < tokenCache.expires) return tokenCache.token

  const response = await axios.post(TOKEN_URL,
    new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: process.env.FRANCE_TRAVAIL_CLIENT_ID,
      client_secret: process.env.FRANCE_TRAVAIL_CLIENT_SECRET,
      scope: 'api_offresdemploiv2 o2dsoffre'
    }),
    { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }
  )

  tokenCache = { token: response.data.access_token, expires: Date.now() + (response.data.expires_in - 60) * 1000 }
  return tokenCache.token
}

export async function franceTravailSearch(motsCles, localisation = 'France entière') {
  try {
    const token = await getAccessToken()
    const params = new URLSearchParams({ motsCles, range: '0-49' })

    if (localisation && !localisation.includes('France entière')) {
      params.append('commune', localisation)
      params.append('distance', 100)
    }

    const response = await axios.get(`${API_BASE}/offres/search`, {
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      params,
      timeout: 30000
    })

    return (response.data.resultats || []).map(o => ({
      source: 'france_travail',
      titre: o.intitule || 'Sans titre',
      entreprise: o.entreprise?.nom || 'Entreprise non précisée',
      localisation: o.lieuTravail ? [o.lieuTravail.commune, o.lieuTravail.codePostal].filter(Boolean).join(', ') : 'France',
      secteur: o.secteurActivite?.libelle || 'Non précisé',
      description: o.description || '',
      lien: `https://candidat.pole-emploi.fr/offres/recherche/detail/${o.id}`,
      date_publication: o.dateCreation ? new Date(o.dateCreation).toISOString() : null
    }))
  } catch (error) {
    if (error.response?.status === 401) tokenCache = { token: null, expires: 0 }
    console.error('Erreur API FT:', error.response?.data || error.message)
    return []
  }
}

export async function getBriefEntreprise(nomEntreprise) {
  if (!nomEntreprise || nomEntreprise === 'Entreprise non précisée') return { brief_entreprise: 'Entreprise non identifiée' }

  try {
    const response = await axios.get(
      `https://www.google.com/search?q=${encodeURIComponent(nomEntreprise + ' agencement')}&hl=fr`,
      { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }, timeout: 5000 }
    )
    const $ = cheerio.load(response.data)
    const snippets = []
    $('div.BNeawe').slice(0, 3).each((_, el) => { const t = $(el).text().trim(); if (t.length > 30) snippets.push(t) })
    return { brief_entreprise: snippets.slice(0, 3).join(' | ').substring(0, 300) || 'Infos indisponibles' }
  } catch (e) {
    return { brief_entreprise: 'Analyse web non disponible' }
  }
}
ENDSCRAPER

# ─── agents/canva-generator.js ───
cat > agents/canva-generator.js << 'ENDCANVA'
import fs from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

export async function creerDesign({ type, contenu, lettre, titre, entreprise }) {
  const cv = contenu || {}
  const experiences = cv.experiences || []

  const html = `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Raphaël Hamache — ${titre}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; color: #333; line-height: 1.6; }
    .container { max-width: 800px; margin: 0 auto; padding: 30px; }
    .header { background: linear-gradient(135deg, #1a1a2e, #16213e); color: white; padding: 30px; text-align: center; margin-bottom: 30px; }
    .header h1 { font-size: 28px; margin-bottom: 5px; }
    .header .contact { margin-top: 15px; font-size: 12px; opacity: 0.9; }
    .section { margin-bottom: 25px; }
    .section-title { font-size: 14px; text-transform: uppercase; color: #1a1a2e; border-bottom: 2px solid #1a1a2e; padding-bottom: 5px; margin-bottom: 15px; }
    .resume { background: #f8f9fa; padding: 15px; border-radius: 5px; font-style: italic; }
    .exp { margin-bottom: 15px; padding-left: 15px; border-left: 3px solid #16213e; }
    .exp h3 { font-size: 13px; color: #1a1a2e; }
    .exp .meta { font-size: 10px; color: #666; margin-bottom: 5px; }
    .skills { display: flex; flex-wrap: wrap; gap: 15px; }
    .skill-group { background: #f0f0f0; padding: 15px; border-radius: 5px; min-width: 200px; }
    .skill-group h4 { font-size: 11px; color: #1a1a2e; margin-bottom: 8px; }
    .skill-group ul { list-style: none; font-size: 11px; }
    .skill-group li { margin-bottom: 3px; }
    .lettre { page-break-before: always; padding: 20px; border-top: 1px solid #eee; margin-top: 30px; }
    .lettre p { margin-bottom: 15px; text-align: justify; }
    .footer { text-align: center; font-size: 9px; color: #999; margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Raphaël Hamache</h1>
      <div>${cv.titre_cv || 'Professionnel Agencement & Design d'intérieur'}</div>
      <div class="contact">📍 Nice, France &nbsp;|&nbsp; 📧 raphaelhahamache86@gmail.com</div>
    </div>

    <div class="section">
      <div class="section-title">Profil</div>
      <div class="resume">${cv.resume || 'Professionnel de l\'aménagement intérieur combinant expertise technique 3D et expérience terrain en tapisserie. Capable de concevoir, coordonner et suivre un projet de A à Z.'}</div>
    </div>

    <div class="section">
      <div class="section-title">Expériences</div>
      ${experiences.length > 0 ? experiences.map(e => `
        <div class="exp">
          <h3>${e.poste}</h3>
          <div class="meta">${e.duree}</div>
          <ul>${(e.missions || []).map(m => `<li>${m}</li>`).join('')}</ul>
        </div>`).join('') : `
        <div class="exp">
          <h3>Chef de Projet Aménagement Intérieur</h3>
          <div class="meta">Entreprise familiale — 2.5 ans</div>
          <ul>
            <li>Gestion complète de projets d'aménagement intérieur</li>
            <li>Conception 3D (SketchUp, Enscape, Lumion)</li>
            <li>Coordination artisans et fournisseurs</li>
            <li>Suivi de chantier et réception des travaux</li>
          </ul>
        </div>
        <div class="exp">
          <h3>Tapisserie d'ameublement</h3>
          <div class="meta">4 ans</div>
          <ul><li>Fabrication et pose de rideaux, stores, tentures</li><li>Finitions sur mesure</li></ul>
        </div>`}
    </div>

    <div class="section">
      <div class="section-title">Compétences</div>
      <div class="skills">
        <div class="skill-group"><h4>🔧 3D & CAO</h4><ul>
          <li>Enscape, Lumion, SketchUp (expert)</li><li>V-Ray (avancé)</li><li>AutoCAD, ArchiCAD</li>
        </ul></div>
        <div class="skill-group"><h4>🤖 IA & Code</h4><ul>
          <li>Midjourney (expert)</li><li>Claude, Gemini</li><li>App Electron fonctionnelle</li><li>Mini-ERP Node.js (en cours)</li>
        </ul></div>
        <div class="skill-group"><h4>🎨 Design & PAO</h4><ul>
          <li>Canva, Adobe Express (expert)</li><li>Photoshop, PowerPoint</li>
        </ul></div>
        <div class="skill-group"><h4>🧵 Atelier</h4><ul>
          <li>Tapisserie d'ameublement</li><li>Finitions & reprise sur mesure</li>
        </ul></div>
      </div>
    </div>

    <div class="section">
      <div class="section-title">Formation</div>
      <div class="exp"><h3>Formation Art & Design</h3><div class="meta">3 ans — Dessin, colorisme, composition</div></div>
      <div class="exp"><h3>BAC PRO Tapisserie d'ameublement</h3></div>
    </div>

    <div class="lettre">
      <div class="section-title">Lettre de motivation — ${titre}</div>
      <div>${(lettre || 'Candidature pour le poste de ' + titre + ' chez ' + entreprise).split('\n\n').map(p => `<p>${p}</p>`).join('')}</div>
      <br><br>
      <p>Cordialement,<br><strong>Raphaël Hamache</strong></p>
    </div>

    <div class="footer">Candidature générée automatiquement — Pipeline Raphaël Hamache</div>
  </div>
</body>
</html>`

  const outputDir = join(__dirname, '..', 'output')
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true })

  const filename = `candidature_${Date.now()}.html`
  const filepath = join(outputDir, filename)
  fs.writeFileSync(filepath, html, 'utf8')

  return { id: filename.replace('.html', ''), url: filepath, edit_url: `file://${filepath}`, format: 'html', type }
}
ENDCANVA

# ─── agents/memory.js ───
cat > agents/memory.js << 'ENDMEMORY'
import { google } from 'googleapis'

const EMAIL = process.env.RAPHAEL_EMAIL || 'raphaelhahamache86@gmail.com'

export async function stockerOffre(supabase, offre) {
  const { data: existante } = await supabase.from('offres').select('id').eq('lien', offre.lien).single()

  if (existante) {
    await supabase.from('offres').update({ score_initial: offre.score_initial, updated_at: new Date().toISOString() }).eq('id', existante.id)
    return existante.id
  }

  const { data, error } = await supabase.from('offres').insert({
    source: offre.source || 'france_travail',
    titre: offre.titre,
    entreprise: offre.entreprise,
    localisation: offre.localisation,
    secteur: offre.secteur,
    description: offre.description?.substring(0, 5000),
    lien: offre.lien,
    date_publication: offre.date_publication,
    score_initial: offre.score_initial,
    brief_entreprise: offre.brief_entreprise,
    type_poste: offre.type_poste,
    statut: 'detecte'
  }).select('id').single()

  if (error) { console.error('Erreur stockage:', error); return null }
  return data?.id
}

export async function listerOffres(supabase, { statut = null, limit = 20 } = {}) {
  let q = supabase.from('offres').select('*').order('score_initial', { ascending: false }).limit(limit)
  if (statut) q = q.eq('statut', statut)
  const { data } = await q
  return data || []
}

export async function stockerCandidature(supabase, c) {
  await supabase.from('offres').update({ statut: 'candidature_envoyee' }).eq('id', c.offre_id)
  const { data } = await supabase.from('candidatures').insert({
    offre_id: c.offre_id, canva_url: c.canva_url, score_au_moment: c.score_au_moment, resultat: c.resultat || 'envoye'
  }).select('id').single()
  return data?.id
}

export async function majCandidatureResultat(supabase, offreId, resultat, notes = null) {
  const { data: existante } = await supabase.from('candidatures').select('id').eq('offre_id', offreId).order('date_envoi', { ascending: false }).limit(1).single()
  if (existante) {
    await supabase.from('candidatures').update({ resultat, date_resultat: new Date().toISOString(), notes }).eq('id', existante.id)
  } else {
    await supabase.from('candidatures').insert({ offre_id: offreId, resultat, score_resultat: { envoye: 1, reponse: 3, entretien: 5, refus: 1, offre: 10 }[resultat] || 0 })
  }
}

export async function chargerPoids(supabase) {
  const { data } = await supabase.from('scoring_weights').select('*').eq('id', 1).single()
  if (!data) return { titre_match: 0.25, secteur_match: 0.20, taille: 0.15, frescura: 0.10, sante: 0.15, geo: 0.15 }
  return { titre_match: data.titre_match, secteur_match: data.secteur_match, taille: data.taille, frescura: data.fraicheur, sante: data.sante, geo: data.geo }
}

export async function sauvegarderPoids(supabase, poids) {
  await supabase.from('scoring_weights').upsert({ id: 1, ...poids, dermiere_maj: new Date().toISOString() })
}

export async function chargerHistoriqueCandidatures(supabase) {
  const { data } = await supabase.from('candidatures').select('*, offres(score_titre_match, score_secteur_match, score_taille, score_fraicheur, score_sante, score_geo)').not('resultat', 'is', null)
  if (!data) return []
  return data.map(c => ({ ...c, scores: { titre_match: c.offres?.score_titre_match, secteur_match: c.offres?.score_secteur_match, taille: c.offres?.score_taille, frescura: c.offres?.score_fraicheur, sante: c.offres?.score_sante, geo: c.offres?.score_geo } }))
}

export async function logLearning(supabase, avant, apres, declencheur, nb) {
  const ajust = {}
  for (const k of Object.keys(apres)) ajust[k] = ((apres[k] - avant[k]) > 0 ? '+' : '') + (apres[k] - avant[k]).toFixed(4)
  await supabase.from('learning_log').insert({ poids_avant: avant, poids_apres: apres, declencheur, nb_candidatures_calculees: nb, ajustements: ajust })
}

export async function getStats(supabase) {
  const [{ count: total_offres }, { count: total_cand }, { data: resultats }] = await Promise.all([
    supabase.from('offres').select('*', { count: 'exact', head: true }),
    supabase.from('candidatures').select('*', { count: 'exact', head: true }),
    supabase.from('candidatures').select('resultat').not('resultat', 'is', null)
  ])
  const nb = resultats?.length || 0
  const nbRep = resultats?.filter(r => ['reponse', 'entretien', 'offre'].includes(r.resultat)).length || 0
  const nbEnt = resultats?.filter(r => ['entretien', 'offre'].includes(r.resultat)).length || 0
  return { total_offres: total_offres || 0, total_candidatures: total_cand || 0, taux_reponse: nb > 0 ? Math.round(nbRep / nb * 100) : 0, taux_entretien: nb > 0 ? Math.round(nbEnt / nb * 100) : 0 }
}

export async function envoyerEmail(offre) {
  if (!process.env.GMAIL_CLIENT_ID || !process.env.GMAIL_REFRESH_TOKEN) {
    console.log(`\n📧 [EMAIL] ${offre.titre} @ ${offre.entreprise} — Score ${offre.score_initial}/100`)
    return { sent: false, mode: 'simulation' }
  }

  const oauth2 = new google.auth.OAuth2(process.env.GMAIL_CLIENT_ID, process.env.GMAIL_CLIENT_SECRET)
  oauth2.setCredentials({ refresh_token: process.env.GMAIL_REFRESH_TOKEN })
  const gmail = google.gmail({ version: 'v1', auth: oauth2 })

  const stars = '⭐'.repeat(Math.min(Math.floor(offre.score_initial / 20), 5))
  const sujet = `[PIPELINE] ${offre.titre} @ ${offre.entreprise} — ${offre.score_initial}/100`
  const corps = `
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
POSTE : ${offre.titre}
LOCALISATION : ${offre.localisation}
SCORE : ${offre.score_initial}/100 ${stars}
TYPE : ${offre.type_poste}

ENTREPRISE : ${offre.brief_entreprise || 'À analyser'}

LIEN : ${offre.lien}

ACTIONS :
1. node index.js generate --offreId=${offre.id}
2. node index.js update --offreId=${offre.id} --resultat=<val>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`.trim()

  const message = Buffer.from(`To: ${EMAIL}\r\nSubject: ${sujet}\r\n\r\n${corps}`).toString('base64url')

  try {
    await gmail.users.messages.send({ userId: 'me', requestBody: { raw: message } })
    console.log(`✅ Email envoyé: ${offre.titre}`)
    return { sent: true }
  } catch (e) {
    console.error('Erreur email:', e.message)
    return { sent: false, error: e.message }
  }
}
ENDMEMORY

# ─── scoring/calculator.js ───
cat > scoring/calculator.js << 'ENDCALC'

const SECTEURS = ['agencement', 'mobilier', 'design', 'scénographie', 'aménagement', 'ébénisterie', 'menuiserie']
const MOTS_CLES = ['agencement', 'mobilier', 'design', 'intérieur', 'scénographie', 'tapisserie', 'chef projet', 'dessinateur', 'projeteur', 'aménagement', 'atelier', '3D', 'BE', 'conducteur']
const GRANDES_VILLES = ['Paris', 'Lyon', 'Marseille', 'Toulouse', 'Nice', 'Nantes', 'Montpellier', 'Strasbourg', 'Bordeaux', 'Lille', 'Rennes', 'Grenoble', 'Cannes', 'Antibes']

export function matchMotsCles(titre) {
  if (!titre) return 0
  const t = titre.toLowerCase()
  let n = 0
  for (const m of MOTS_CLES) if (t.includes(m)) n++
  return Math.min(n / 3, 1)
}

export function scoreSecteur(secteur) {
  if (!secteur) return 20
  const s = secteur.toLowerCase()
  for (const c of SECTEURS) if (s.includes(c)) return 100
  return 20
}

export function scoreTaille(nb) {
  if (!nb) return 50
  if (nb <= 50) return 100
  if (nb <= 250) return 70
  if (nb <= 1000) return 40
  return 20
}

export function scoreFraicheur(date) {
  if (!date) return 30
  const h = (Date.now() - new Date(date)) / 3600000
  if (h <= 24) return 100
  if (h <= 72) return 70
ENDCALC
