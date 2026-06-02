# 🎙️ Voice Changer Setup

**Installe un voice changer temps réel sur Windows en un seul double-clic.**

Tu parles dans ton micro → ta voix ressort transformée (autre voix, personnage, voix anonyme) **en direct**, et tu peux l'envoyer dans Discord, OBS, un jeu, n'importe quelle app.

Ce repo automatise l'installation de toute la stack :

| Composant | Rôle | Source |
|---|---|---|
| **VCClient** (w-okada) | le moteur de transformation de voix temps réel | [HuggingFace](https://huggingface.co/wok000/vcclient000) / [GitHub](https://github.com/w-okada/voice-changer) |
| **VB-CABLE** | câble audio virtuel pour router la voix vers tes apps | [VB-Audio](https://vb-audio.com/Cable/) |
| **Pilote NVIDIA** | calcul GPU (vérifié, pas installé automatiquement) | [NVIDIA](https://www.nvidia.com/Download/index.aspx) |

---

## ⚡ Installation rapide

### Prérequis
- **Windows 10 / 11 (64 bits)**
- **GPU NVIDIA** (RTX 3060+ confortable, GTX 1080 minimum) avec **pilote à jour** → [télécharger ici](https://www.nvidia.com/Download/index.aspx)
- ~10 Go d'espace disque libre

> Pas de GPU NVIDIA ? Le script bascule automatiquement sur un build DirectML (AMD/Intel), mais le temps réel sera moins confortable.

### En 3 étapes

1. **Télécharge ce repo** (bouton vert `Code` → `Download ZIP`, puis dézippe) ou clone-le :
   ```bash
   git clone https://github.com/<ton-compte>/voicechanger-setup.git
   ```

2. **Double-clic sur `INSTALL.bat`**
   Windows va demander les droits administrateur → accepte.
   Le script fait tout :
   - vérifie le système et le GPU
   - installe VB-CABLE
   - télécharge et installe VCClient (build CUDA si NVIDIA)
   - crée un raccourci **« Voice Changer »** sur le Bureau

3. **Lance le voice changer**
   Double-clic sur le raccourci **Voice Changer** du Bureau (ou sur `Start-VoiceChanger.bat`).
   Une interface s'ouvre dans ton navigateur.

> ⚠️ Si l'installeur dit qu'un **redémarrage** est nécessaire (activation de VB-CABLE), redémarre avant le premier lancement.

---

## 🎛️ Configuration (dans l'interface VCClient)

1. **Input** (micro) = ton micro réel
2. **Output** (sortie) = `CABLE Input (VB-Audio Virtual Cable)`
3. **Model** = charge une voix :
   - **Seed-VC** → *zero-shot* : tu donnes juste un échantillon (~15 s), pas d'entraînement. **Commence par ça.**
   - **RVC** → un fichier `.pth` (+ `.index`) : qualité maximale. Modèles tout faits sur [huggingface.co/models?search=rvc](https://huggingface.co/models?search=rvc), [weights.gg](https://weights.gg), [voice-models.com](https://voice-models.com)
4. **Chunk** : petit = moins de latence mais plus de charge GPU. Ajuste jusqu'à trouver l'équilibre.
5. **Pitch / F0** : transpose en demi-tons si tu passes voix homme ↔ femme.
6. Clique **Start** et parle.

---

## 🔀 Router la voix vers tes apps

Une fois VCClient en marche, ta voix transformée sort sur **CABLE Input**. Pour l'utiliser ailleurs, choisis **CABLE Output** comme micro dans l'app cible :

| App | Où régler |
|---|---|
| **Discord** | Paramètres → Voix et vidéo → Périphérique d'entrée → `CABLE Output` |
| **OBS** | Source audio → `CABLE Output` |
| **Jeu / autre** | Micro = `CABLE Output` |

```
Micro réel ──▶ VCClient (transforme) ──▶ CABLE Input
                                              │
                                         CABLE Output ──▶ Discord / OBS / jeu
```

> Pour t'entendre toi-même pendant que tu parles, active l'option **monitor** dans VCClient (sortie vers ton casque).

---

## 🎓 Entraîner ta propre voix (Applio)

VCClient **transforme** la voix mais n'**entraîne** pas de modèle. Pour créer ta propre voix RVC (qualité maximale, réutilisable en temps réel dans VCClient), on installe **[Applio](https://github.com/IAHispano/Applio)** — l'outil d'entraînement RVC de référence en 2026 (maintenu, GUI, installeur one-click).

### Installation

**Double-clic sur `INSTALL-TRAINING.bat`** (⚠️ **pas** en administrateur — Applio le refuse, le script tourne en utilisateur normal).
Il télécharge Applio, installe son propre Miniconda + dépendances (aucun Python à installer toi-même, compte 10-25 min), et crée un raccourci **« Applio (Training) »** sur le Bureau.

> Installé par défaut dans `C:\Applio`. Pour un autre dossier (ASCII, sans espaces) :
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\install-applio.ps1 -InstallDir D:\Applio
> ```

### Préparer le dataset (l'étape qui détermine tout)

La **propreté** de l'audio compte plus que la durée. Un dataset court mais nickel bat un long dataset bruité.

| Durée d'audio propre | Résultat |
|---|---|
| < 5 min | Trop court pour entraîner → préfère le **zero-shot Seed-VC** (voir plus bas) |
| **5 min** | Plancher. OK si la voix est très distinctive et l'audio impeccable |
| **10-30 min** | ✅ **La zone idéale.** Meilleur rapport qualité/effort |
| 30-50 min | Voix plus robuste, rendements décroissants au-delà |

Règles pour un audio « propre » :
- **Zéro bruit de fond** (ventilo, clavier, écho de pièce), zéro musique, **une seule personne**
- **Varie les intonations** (aigu/grave, quelques émotions) → sinon la voix sort robotique
- Si l'audio est sale, nettoie/sépare la voix d'abord (ex. **UVR – Ultimate Vocal Remover**)

> **Trop peu d'audio (≈ 2 min) ?** N'entraîne pas (sur-apprentissage garanti). Utilise le **zero-shot Seed-VC** directement dans VCClient : tu donnes juste l'échantillon, pas d'entraînement. Avec peu d'audio, le zero-shot bat un RVC mal entraîné.

### Entraîner

1. Lance Applio → onglet **Train**
2. Nomme le modèle, pointe vers ton dossier de dataset
3. **Preprocess Dataset** → **Extract Features** → **Train Model**
4. **Batch size** : avec **8 Go de VRAM**, mets **6-8** (pas plus)
5. **Écoute les checkpoints** sauvegardés et **arrête quand c'est bon** : trop d'epochs = voix robotique (mauvaise généralisation), pas l'inverse

### Charger ta voix dans VCClient (temps réel)

Après l'entraînement, récupère **2 fichiers** dans `C:\Applio\logs\<nom_du_modele>\` :
- `<nom>.pth` (le modèle)
- `added_*.index` (l'index — améliore la ressemblance)

Dans VCClient : **Model = RVC**, charge le `.pth` **et** le `.index`, clique **Start** et parle.

### RTX série 50 (Blackwell)

Les cartes **RTX 50xx** (architecture Blackwell, `sm_120`) exigent **CUDA 12.8+ / PyTorch récent**. Si l'entraînement plante avec une erreur du type `sm_120 not supported` ou `CUDA capability` :

```bat
REM Depuis le dossier Applio (ex C:\Applio), réinstalle torch en cu128 dans l'env Applio :
env\python.exe -m pip install --upgrade --force-reinstall torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
```

> ⚖️ **Légal / éthique** (rappel) : n'entraîne une voix réelle qu'avec l'accord de la personne. Générer un dataset via une voix TTS commerciale (ElevenLabs, etc.) peut violer leurs CGU. Usage perso/créatif/consenti uniquement.

---

## 🧰 Options avancées

Le script accepte des paramètres (via PowerShell) :

```powershell
# Forcer un dossier d'installation (doit rester ASCII, sans accents/espaces)
powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir C:\vcclient

# Forcer un build precis : cuda (NVIDIA) | dml (AMD/Intel) | cpu
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Edition cuda

# Sauter VB-CABLE (si deja installe ou si tu utilises VoiceMeeter)
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipVBCable
```

Le script est **idempotent** : tu peux le relancer sans risque, il saute ce qui est déjà installé.

---

## 🩹 Dépannage

| Problème | Cause probable | Solution |
|---|---|---|
| Latence trop haute | chunk trop grand | réduis le chunk |
| Ça grésille / coupe | GPU saturé ou chunk trop petit | augmente le chunk, ferme les apps lourdes |
| Voix robotique | mauvais modèle / pas de `.index` | utilise le `.index` (RVC) ou un meilleur échantillon |
| Pas de son en sortie | mauvais routage VB-CABLE | Output = `CABLE Input`, app cible = `CABLE Output` |
| « CUDA not available » | build CPU/DML installé par erreur | relance avec `-Edition cuda` |
| VCClient ne démarre pas | chemin avec accents/espaces | installe dans `C:\vcclient` |
| VB-CABLE absent après install | activation différée | **redémarre** le PC |

---

## 📦 Ce que fait le script en détail

`install.ps1` (orchestrateur) :

1. **Auto-élévation** administrateur
2. **Vérif système** : Windows 64 bits, espace disque, chemin ASCII
3. **Détection GPU** : NVIDIA → CUDA, sinon DirectML, sinon CPU
4. **VB-CABLE** : récupère le `.zip` officiel, installe en silencieux, détecte le besoin de reboot
5. **VCClient** : interroge l'**API HuggingFace** pour trouver le dernier build Windows correspondant (pas de version figée en dur), télécharge via BITS (reprise sur gros fichier), extrait dans `C:\vcclient`
6. **Raccourci** de lancement sur le Bureau
7. **Instructions** de configuration finales

---

## ⚠️ Notes importantes

- **Ce repo n'héberge aucun binaire.** Il télécharge VCClient et VB-CABLE depuis leurs sources officielles au moment de l'install.
- **Statut de test** : le script a été écrit et relu avec soin mais **n'a pas encore été exécuté sur une machine Windows réelle**. Si tu rencontres une erreur au premier lancement, ouvre une issue avec le message exact — c'est rapide à corriger.
- **Légal / éthique** : n'usurpe pas l'identité de quelqu'un sans son accord. Le clonage de voix est encadré par la loi (droit à l'image vocale, RGPD). Usage perso/créatif/consenti uniquement.
- **Crédits** : [w-okada](https://github.com/w-okada/voice-changer) (VCClient), [VB-Audio](https://vb-audio.com) (VB-CABLE), [Plachtaa](https://github.com/Plachtaa/seed-vc) (Seed-VC), [RVC-Project](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI) (RVC).

---

## 🔗 Alternatives (si tu veux comparer)

- **Applio** — installeur RVC moderne tout-en-un : [github.com/IAHispano/Applio](https://github.com/IAHispano/Applio)
- **ElevenLabs Conversational Voice Changer** — solution cloud payante, zéro install : [elevenlabs.io/voice-changer](https://elevenlabs.io/voice-changer/conversational)
- **Seed-VC** (direct) — [github.com/Plachtaa/seed-vc](https://github.com/Plachtaa/seed-vc)

---

*Licence MIT — voir [LICENSE](LICENSE).*
