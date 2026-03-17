#!/usr/bin/env bash
set -e

echo "=== Vorbereitung: Variablen setzen ==="

REPO1_URL="https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2FGerolsteiner99%2Fsolr-kafka-platform.git&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832286965919%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=M1duYDny78jarpN%2F5NfB%2FnGfnGhqVs7q1b1KELZYdag%3D&reserved=0"

REPO2_URL="https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2FGerolsteiner99%2Fminikube-solr-config.git&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832286983470%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=Hkxz5TfVicmKtVSk4G5vJKNKL0kGlH29WYCHgRDrhpQ%3D&reserved=0"

WORKDIR="$HOME/solr-migration"
MINIKUBE_CPUS=6
MINIKUBE_MEMORY=16384   # 16 GB
MINIKUBE_DRIVER="docker"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "Arbeitsverzeichnis: $WORKDIR"

echo "=== Minikube prüfen/ starten ==="
if ! minikube status >/dev/null 2>&1; then
  echo "Minikube läuft nicht – starte Minikube..."
  minikube start --driver="$MINIKUBE_DRIVER" --cpus="$MINIKUBE_CPUS" --memory="$MINIKUBE_MEMORY"
else
  echo "Minikube läuft bereits."
fi

echo "=== Namespaces anlegen ==="
kubectl get ns solr >/dev/null 2>&1 || kubectl create namespace solr
kubectl get ns zookeeper >/dev/null 2>&1 || kubectl create namespace zookeeper

echo "=== repo1 klonen ==="
if [ ! -d "repo1" ]; then
    git clone "$REPO1_URL" repo1
else
    cd repo1 && git pull && cd ..
fi

echo "=== repo2 vorbereiten ==="
if [ ! -d "repo2" ]; then
    git clone "$REPO2_URL" repo2
else
    cd repo2 && git pull && cd ..
fi

echo "=== Struktur für repo2 anlegen ==="
mkdir -p repo2/apps/solr/base
mkdir -p repo2/apps/solr/overlays/minikube-dev
mkdir -p repo2/apps/solr/overlays/minikube-ha
mkdir -p repo2/apps/zookeeper/base
mkdir -p repo2/apps/zookeeper/overlays/minikube-dev
mkdir -p repo2/apps/zookeeper/overlays/minikube-ha
mkdir -p repo2/argocd-apps

echo "=== Konfiguration aus repo1 übernehmen ==="
cp -r repo1/solr/* repo2/apps/solr/base/ 2>/dev/null || true
cp -r repo1/zookeeper/* repo2/apps/zookeeper/base/ 2>/dev/null || true

echo "=== DEV Overlay erzeugen ==="

cat > repo2/apps/solr/overlays/minikube-dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: StatefulSet
      name: solr
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
      - op: replace
        path: /spec/template/spec/containers/0/resources
        value:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
EOF

cat > repo2/apps/zookeeper/overlays/minikube-dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: StatefulSet
      name: zookeeper
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
      - op: replace
        path: /spec/template/spec/containers/0/resources
        value:
          requests:
            cpu: "100m"
            memory: "512Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
EOF

echo "=== HA Overlay erzeugen ==="

cat > repo2/apps/solr/overlays/minikube-ha/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: StatefulSet
      name: solr
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
      - op: replace
        path: /spec/template/spec/containers/0/resources
        value:
          requests:
            cpu: "500m"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
EOF

cat > repo2/apps/zookeeper/overlays/minikube-ha/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: StatefulSet
      name: zookeeper
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
      - op: replace
        path: /spec/template/spec/containers/0/resources
        value:
          requests:
            cpu: "200m"
            memory: "1Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
EOF

echo "=== ArgoCD App-Definitionen erzeugen ==="

cat > repo2/argocd-apps/solr-minikube-dev.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: solr-minikube-dev
spec:
  project: default
  source:
    repoURL: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2FGerolsteiner99%2Frepo2.git&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832286994521%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=vvaCVTQaERU5Bd%2Bk8kVxRiYIBXXTLc6AGKEWm1b7w8w%3D&reserved=0
    path: apps/solr/overlays/minikube-dev
  destination:
    server: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fkubernetes.default.svc%2F&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832287003987%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=wsNXO%2Bbb5Bf6EvdY0gPjqUGUpO%2BNuSaBCfimeUnoixo%3D&reserved=0
    namespace: solr
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

cat > repo2/argocd-apps/zookeeper-minikube-dev.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: zookeeper-minikube-dev
spec:
  project: default
  source:
    repoURL: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2FGerolsteiner99%2Frepo2.git&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832287012045%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=WeXan7iQhjGjaUKDl9qjoZOoRoPy9HksPHnyXBspzy4%3D&reserved=0
    path: apps/zookeeper/overlays/minikube-dev
  destination:
    server: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fkubernetes.default.svc%2F&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832287020595%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=R7r%2BZsiLsVqvsIBSLgKUDPaKiwObFKdhUgZ%2B%2FVeK%2B%2F0%3D&reserved=0
    namespace: zookeeper
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

cat > repo2/argocd-apps/solr-minikube-ha.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: solr-minikube-ha
spec:
  project: default
  source:
    repoURL: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2FGerolsteiner99%2Frepo2.git&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832287028814%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=D0vH02C9GYh%2BwMQmOA385lySoZdE5ab4XapzFzCW%2F0o%3D&reserved=0
    path: apps/solr/overlays/minikube-ha
  destination:
    server: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fkubernetes.default.svc%2F&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832287037560%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=Np32sPtE5NEvzXR1D0ANGU96dbMt%2FOZwKlr7nxLEJ6c%3D&reserved=0
    namespace: solr
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

cat > repo2/argocd-apps/zookeeper-minikube-ha.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: zookeeper-minikube-ha
spec:
  project: default
  source:
    repoURL: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2FGerolsteiner99%2Frepo2.git&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832287045462%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=%2B6iy%2B8zMfRsP7XxHgGGmHEDXbN0xGiskdT06aMkq%2Bn8%3D&reserved=0
    path: apps/zookeeper/overlays/minikube-ha
  destination:
    server: https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fkubernetes.default.svc%2F&data=05%7C02%7Crainer.medack%40finastra.com%7C204b8675df2844bb6f0608de838b7b8d%7C0b9b90da3fe1457ab340f1b67e1024fb%7C0%7C0%7C639092832287053145%7CUnknown%7CTWFpbGZsb3d8eyJFbXB0eU1hcGkiOnRydWUsIlYiOiIwLjAuMDAwMCIsIlAiOiJXaW4zMiIsIkFOIjoiTWFpbCIsIldUIjoyfQ%3D%3D%7C0%7C%7C%7C&sdata=V5LMGZHRCZWisDdJVE3o%2B%2B3SUWSx7yKfBf%2FEeYjdXms%3D&reserved=0
    namespace: zookeeper
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo "=== repo2 committen ==="
cd repo2
git add .
git commit -m "DEV + HA Overlays + ArgoCD Apps" || true
git push || true

echo "=== Auswahlmenü ==="
echo "Bitte Modus wählen:"
echo "1 = Entwicklungsmodus (1× Solr, 1× ZK)"
echo "2 = HA-Modus (3× Solr, 3× ZK)"
read -p "Auswahl: " MODE

if [ "$MODE" = "1" ]; then
  echo "DEV-Modus ausgewählt."
  argocd app create -f argocd-apps/solr-minikube-dev.yaml || true
  argocd app create -f argocd-apps/zookeeper-minikube-dev.yaml || true
  argocd app sync solr-minikube-dev
  argocd app sync zookeeper-minikube-dev
elif [ "$MODE" = "2" ]; then
  echo "HA-Modus ausgewählt."
  argocd app create -f argocd-apps/solr-minikube-ha.yaml || true
  argocd app create -f argocd-apps/zookeeper-minikube-ha.yaml || true
  argocd app sync solr-minikube-ha
  argocd app sync zookeeper-minikube-ha
else
  echo "Ungültige Auswahl."
fi

echo "=== Fertig! ==="

