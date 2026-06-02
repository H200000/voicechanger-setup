# 🚀 Entraîner ta voix sur GPU loué (Vast.ai / RunPod)

Ton GPU local suffit pour **utiliser** la voix (VCClient temps réel), mais pour **entraîner** vite, louer un GPU cloud (RTX 4090 24 Go, ~0,30-0,40 $/h) est plus rapide et permet un batch size bien plus gros. Un entraînement de voix RVC tient souvent en **moins d'1 h** → quelques centimes.

> On entraîne sur l'instance **Linux** distante, puis on récupère `.pth` + `.index` pour les charger dans **VCClient** sur ton PC Windows.

---

## 1. Choisir l'instance

- GPU conseillé : **RTX 4090 (24 Go)**. Évite < 12 Go.
- Template : une image **PyTorch / CUDA** (souvent avec Jupyter). Un template « RVC » ou « Applio » tout fait marche aussi.
- À la location, **mappe un port** (ou prévois d'utiliser un tunnel SSH, voir étape 4).
- Mets de quoi tenir : ~25 Go de disque.

> ⚠️ Carte **RTX 5090** (Blackwell) ? Il faut **torch en cu128** (voir note en bas).

---

## 2. Installer Applio sur l'instance

Dans le terminal SSH (ou le terminal Jupyter) de l'instance :

```bash
curl -fsSL https://raw.githubusercontent.com/H200000/voicechanger-setup/main/setup-applio-linux.sh | bash
```

Le script vérifie le GPU, installe git/ffmpeg, clone Applio, monte son environnement et crée `datasets/`. Compte 10-20 min.

---

## 3. Envoyer ton dataset sur l'instance

Dépose tes audios propres dans `/workspace/Applio/datasets/<nom_de_ta_voix>/`.

- **Le plus simple** : le bouton *upload* de l'interface Jupyter de l'instance.
- **En ligne de commande**, depuis ton PC :
  ```bash
  scp -P <PORT> -r ./mavoix root@<IP>:/workspace/Applio/datasets/
  ```
- Rappel dataset : **10-30 min d'audio propre**, zéro bruit/musique, une voix, intonations variées.

---

## 4. Lancer Applio et y accéder depuis ton PC

Sur l'instance :

```bash
cd /workspace/Applio && ./run-applio.sh
```

Note le **port** affiché (souvent `6969`). Pour ouvrir l'interface depuis ton navigateur local, **tunnel SSH** (méthode fiable, marche quel que soit le réseau de l'instance) :

```bash
# Depuis ton PC (Windows : PowerShell ou Git Bash)
ssh -L 6969:localhost:6969 -p <PORT> root@<IP>
```

Puis ouvre **http://localhost:6969**.

> Alternative : si tu as mappé le port à la location, accède direct via `http://<IP>:<port_mappé>`.

---

## 5. Entraîner

Dans l'interface (onglet **Train**) :

1. Nom du modèle + dossier dataset
2. **Preprocess Dataset** → **Extract Features** → **Train Model**
3. **Model version = v2**, **pitch extraction = RMVPE**
4. **Batch size** : 24 Go de VRAM → **16-20** (entraînement bien plus rapide qu'en local 8 Go)
5. Écoute les checkpoints, **arrête quand c'est bon** (trop d'epochs = voix robotique)

---

## 6. Récupérer le modèle — AVANT de détruire l'instance

Les 2 fichiers sont dans `/workspace/Applio/logs/<nom>/` :
- `<nom>.pth`
- `added_*.index`

Télécharge-les (Jupyter *download*, ou `scp` retour) :

```bash
# Depuis ton PC
scp -P <PORT> root@<IP>:/workspace/Applio/logs/<nom>/*.pth   ./
scp -P <PORT> root@<IP>:/workspace/Applio/logs/<nom>/added_*.index ./
```

Puis dans **VCClient** (PC) : **Model = RVC**, charge le `.pth` **et** le `.index`, **Start**, parle.

> 🛑 **Les 2 pièges qui coûtent cher**
> - Instance **éphémère** : si tu détruis sans télécharger, le modèle est **perdu**.
> - **Facturation au temps qui tourne** : **stoppe/détruis** l'instance dès le modèle récupéré.

---

## Note RTX 5090 / Blackwell (`sm_120`)

Si l'entraînement plante (`sm_120 not supported`, `CUDA capability`) sur une carte série 50 :

```bash
cd /workspace/Applio
env/bin/python -m pip install --upgrade --force-reinstall torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
```

(Sur un RTX 4090, pas concerné.)
