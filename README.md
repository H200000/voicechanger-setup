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
