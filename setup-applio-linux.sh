#!/usr/bin/env bash
# ============================================================
#  Setup Applio sur une instance GPU Linux (Vast.ai, RunPod...)
#  pour entrainer une voix RVC v2.
#
#  Usage (dans le terminal SSH ou Jupyter de l'instance) :
#    curl -fsSL https://raw.githubusercontent.com/H200000/voicechanger-setup/main/setup-applio-linux.sh | bash
#  ou, si tu as copie le fichier sur l'instance :
#    bash setup-applio-linux.sh [WORKDIR]
#
#  WORKDIR par defaut : /workspace (persiste sur la plupart des instances)
# ============================================================
set -euo pipefail

WORKDIR="${1:-/workspace}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "==> Verification GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
else
    echo "[!] nvidia-smi introuvable : pas de GPU NVIDIA visible dans cette instance ?"
fi

echo "==> Dependances systeme (git, ffmpeg)"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || sudo apt-get update -y
    apt-get install -y git ffmpeg >/dev/null 2>&1 || sudo apt-get install -y git ffmpeg
fi

echo "==> Clone d'Applio"
if [ ! -d "$WORKDIR/Applio" ]; then
    git clone https://github.com/IAHispano/Applio.git
fi
cd "$WORKDIR/Applio"

echo "==> Installation de l'environnement Applio (long : deps + torch)"
chmod +x run-install.sh run-applio.sh 2>/dev/null || true
./run-install.sh

mkdir -p "$WORKDIR/Applio/datasets"

cat <<EOF

==================================================================
  APPLIO PRET dans $WORKDIR/Applio
==================================================================

  1) DEPOSE TON DATASET :
       $WORKDIR/Applio/datasets/<nom_de_ta_voix>/
     (via le file-upload Jupyter, ou : scp -P <PORT> -r ./mavoix root@<IP>:$WORKDIR/Applio/datasets/)

  2) LANCE APPLIO :
       cd $WORKDIR/Applio && ./run-applio.sh
     Note le port affiche (en general 6969).

  3) ACCEDE A L'INTERFACE depuis ton PC (tunnel SSH, methode fiable) :
       ssh -L 6969:localhost:6969 -p <PORT> root@<IP>
     puis ouvre http://localhost:6969 dans ton navigateur.

  4) ENTRAINE (onglet Train) : version=v2, pitch=RMVPE, batch 16-20 si 24 Go VRAM.

  5) RECUPERE LE MODELE (avant de DETRUIRE l'instance !) :
       $WORKDIR/Applio/logs/<nom>/<nom>.pth
       $WORKDIR/Applio/logs/<nom>/added_*.index
     Telecharge-les sur ton PC, puis charge-les dans VCClient (Model = RVC).

  /!\ DETRUIS l'instance une fois le modele telecharge (facturation au temps qui tourne).
EOF
