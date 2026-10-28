# CUBE - ClaudeHub

Une petite app Mac qui affiche tes sessions [Claude Code](https://claude.com/claude-code) en cours sous forme de cartes, avec un cube de glace animé qui montre l'état du projet actif.

<p align="center"><img src="docs/widget.png" width="400" alt="Le widget : la carte du projet actif avec son cube orange, et deux petites cartes en dessous"></p>

> **Projet perso, non officiel.** CubeWidget n'est ni fait, ni soutenu par Anthropic.

## Ce que fait l'app

- **Le widget** : une carte pour le projet actif (nom, tâche en cours, statut, durée, tokens) et jusqu'à 2 petites cartes en dessous pour les autres sessions. Il reste toujours au-dessus des autres fenêtres, sur tous les bureaux.
- **Le cube** montre l'état du projet actif :
  - bleu qui regarde à gauche et à droite : Claude bosse ;
  - orange qui sautille : Claude attend ta réponse (permission, question, plan à valider) ;
  - vert dont les yeux suivent la souris : tâche ou réponse terminée ;
  - endormi : aucune session.
- **Un halo** autour de la carte : un trait bleu qui tourne quand Claude bosse, un halo orange fixe quand il attend, vert quand c'est fini.
- **Le Claude Hub** : une fenêtre qui regroupe toutes les sessions, rangées par thèmes, avec un vrai terminal par projet ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) où tourne Claude Code.
- **Un mini cube dans la barre des menus**, avec la liste de toutes les sessions.
- **Telegram (facultatif)** :
  - des notifications sur ton téléphone quand tu n'es pas devant le Mac : tâche finie, Claude attend, réponse terminée ;
  - des réponses depuis Telegram : écrire à une session, répondre Oui / Non à une permission, choisir une réponse à une question de Claude ;
  - tout est désactivé par défaut et protégé : code à 6 chiffres (TOTP), autorisation projet par projet, journal.
- **Sons** : un son court pour chaque changement d'état, réglables dans les Réglages.

L'interface est en français.

## Prérequis

- macOS 14 (Sonoma) ou plus récent
- Les outils de développement Swift : Xcode ou `xcode-select --install` (Swift 5.10+)
- [Claude Code](https://claude.com/claude-code)

## Installation

```bash
git clone https://github.com/Harlo9/CUBE-ClaudeHub.git
cd CUBE-ClaudeHub
./build.sh
```

`build.sh` compile l'app dans `build/CubeWidget.app`, installe le petit programme `cube-hook` dans `~/.cube-widget/bin/`, puis lance l'app (`./build.sh --no-run` pour compiler seulement).

### Brancher Claude Code : les hooks

L'app connaît l'état de tes sessions grâce aux [hooks de Claude Code](https://code.claude.com/docs/en/hooks). À chaque événement, Claude Code lance `cube-hook`, qui écrit un petit fichier par session dans `~/.cube-widget/sessions/`.

Ajoute ceci dans `~/.claude/settings.json`. **Fais d'abord une copie du fichier**, et fusionne ce bloc avec tes hooks existants si tu en as déjà :

```json
{
  "hooks": {
    "SessionStart":       [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "UserPromptSubmit":   [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "PreToolUse":         [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "PostToolUse":        [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "PostToolUseFailure": [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "PermissionRequest":  [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "Notification":       [{ "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
                             "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "Stop":               [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "StopFailure":        [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "TaskCreated":        [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "TaskCompleted":      [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }],
    "SessionEnd":         [{ "hooks": [{ "type": "command", "command": "$HOME/.cube-widget/bin/cube-hook" }] }]
  }
}
```

`cube-hook` n'affiche jamais rien, ne bloque jamais Claude Code (il finit toujours sans erreur, en ~13 ms) et ignore ce qu'il ne comprend pas. Les sessions déjà ouvertes apparaissent à leur prochain événement.

### Autorisations macOS

- **« CubeWidget souhaite contrôler Terminal »** (bouton « Afficher dans Terminal » du Hub) : OK. Réglable dans Réglages Système → Confidentialité et sécurité → Automatisation.
- **« CubeWidget souhaite vous envoyer des notifications »** (seulement si tu allumes les commandes Telegram) : Autoriser.
- La première fois, macOS peut demander si `codesign` peut utiliser la clé du trousseau : « Toujours autoriser ». `build.sh` signe avec ton certificat « Apple Development » s'il existe, sinon avec une signature locale.

### Sons

Trois sons sont ceux de macOS (Glass, Purr, Bottle) : `build.sh` les copie depuis ton Mac. Pour le son « Claude commence à bosser », ou pour remplacer les autres, mets tes propres fichiers dans un dossier `Sons/` à la racine : `bosse`, `fini`, `attente`, `dodo` (`.aiff`, `.wav`, `.mp3` ou `.m4a`). Un son manquant ne joue simplement rien.

## Telegram (facultatif)

Tout se règle dans **Réglages → Telegram** (menu du cube dans la barre des menus) :

1. **Connexion** : crée un bot avec [@BotFather](https://t.me/BotFather) (`/newbot`), colle son token (rangé dans le trousseau macOS, jamais dans un fichier), puis envoie un message à ton bot : l'app trouve ta conversation toute seule.
2. **Notifications** : interrupteur général, puis la cloche 🔔 sur chaque projet. Par défaut, les messages partent seulement si tu es absent du Mac depuis 3 minutes.
3. **Commandes** (pour répondre depuis le téléphone) : configure un code de déverrouillage (QR code à scanner dans ton app de codes), autorise les projets un par un, puis envoie `/unlock` à ton bot. `/lock` reverrouille, `/sessions` liste tes sessions, `/aide` explique le reste.

## Organisation du code

```
Sources/
  CubeWidget/     l'app (SwiftUI + AppKit)
    App/          démarrage, Constants.swift (toutes les tailles, couleurs et durées)
    Widget/       les cartes et le halo
    Mascot/       le cube animé
    Hub/          la fenêtre Claude Hub et ses thèmes
    Terminal/     le lien avec l'app Terminal (AppleScript)
    MenuBar/      le mini cube de la barre des menus
    Telegram/     notifications et commandes
    Settings/     la fenêtre Réglages
    Sessions/     lecture des fichiers de session
    Sound/        les sons
  CubeHook/       le programme lancé par les hooks de Claude Code
  SessionFile/    le format des fichiers de session, partagé par les deux
Assets/           les images d'origine du cube (réduites par Scripts/make_frames.swift)
Resources/        images réduites, icône, Info.plist
```

Toutes les durées d'animation, tailles et couleurs sont dans `Sources/CubeWidget/App/Constants.swift`.

## Licence

[MIT](LICENSE)
