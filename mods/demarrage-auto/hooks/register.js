// demarrage-auto — lance `/demarrage` comme premier tour d'une session interactive neuve.
// Chargé par `CLAUDE_CODE_PLUGIN_DIRS` dans le bloc `env` de `settings.json` (doc Claude Code,
// « Mods » et « Environment variables » ; mods actifs à partir de la v2.1.287). Les lanceurs
// (`engine/claudeos-boot.sh`, `engine/claudeos-session.sh`) lancent donc `claude` sans argument.
// Un crochet SessionStart ne peut pas faire parler le modèle : il n'ajoute que du contexte, et son
// `initialUserMessage` n'agit qu'en `-p`. Un mod, lui, lance une commande par `$.command.run`.
//
// Quatre gardes :
//  - session.start : session interactive, en terminal ; jamais à /clear (un passage par processus) ;
//  - minuteur : conversation encore vide à 1,5 s, ce qui écarte la reprise et un rechargement du
//    mod — et `$.command.run` refuse un appel dont le démarrage de la session attend la fin ;
//  - BILAN_DEMARRAGE=non dans `reglages/REPONSES` : l'installateur a décliné le bilan d'ouverture
//    de la session principale ; une session de projet (`CLAUDEOS_SESSION_SCOPE=projet`) garde le sien ;
//  - prompt.submit : un prompt d'une autre origine passé avant (`claude "question"`) fait abandonner
//    le bilan quand il se présente, avec une ligne visible.
let promptVu = false

// Le bilan d'ouverture est-il décliné ? `reglages/REPONSES` est à deux dossiers au-dessus du mod
// (`~/.claude/mods/demarrage-auto`). Même lecture que `claudeos_reponse` (engine/config.sh) : la
// première ligne `BILAN_DEMARRAGE=`, valeur exacte. Fichier absent ou illisible : le bilan reste,
// poste non réglé.
async function bilanDecline($) {
  if ((await $.env.get('CLAUDEOS_SESSION_SCOPE')) === 'projet') return false
  try {
    const t = await $.fs.read(`${$.plugin.root}/../../reglages/REPONSES`)
    const ligne = t.split('\n').find((l) => l.startsWith('BILAN_DEMARRAGE='))
    return ligne !== undefined && ligne.slice('BILAN_DEMARRAGE='.length) === 'non'
  } catch {
    return false
  }
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    if (e.isInteractive && e.surface === 'terminal') {
      $.clock.after(1500, async () => {
        const msgs = await $.session.messages()
        if (msgs.length === 0 && !promptVu && !(await bilanDecline($))) {
          void $.command.run({ command: 'demarrage' })
        }
      })
    }
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const kind = e.origin ? e.origin.kind : 'aucune'
    if (kind === 'plugin' && String(e.text).startsWith('/demarrage') && promptVu) {
      return { drop: 'bilan de démarrage sauté : un prompt l\'a précédé' }
    }
    if (kind !== 'plugin') promptVu = true
    return next(e)
  }).catch(($, e, next) => next(e)) // en échec, le prompt passe : un bilan en trop ne coûte rien
}
