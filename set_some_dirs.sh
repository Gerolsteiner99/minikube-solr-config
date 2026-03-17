#!/usr/bin/env bash
set -e

echo "=== Vorbereitung: Variablen setzen ==="

REPO1_URL="https://github.com/Gerolsteiner99/solr-kafka-platform.git"
REPO2_URL="https://github.com/Gerolsteiner99/minikube-solr-config.git"

WORKDIR="$HOME/solr-migration"
MINIKUBE_CPUS=6
MINIKUBE_MEMORY=16384
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

echo "=== repo1 klonen (Quelle) ==="
if [ ! -d "repo1" ]; then
    git clone "$REPO1_URL" repo1
else
    cd repo1 && git pull && cd ..
fi

echo "=== repo2 klonen (Ziel) ==="
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
    repoURL: https://github.com/Gerolsteiner99/minikube-solr-config.git
    path: apps/solr/overlays/minikube-dev
  destination:
    server: https://kubernetes.default.svc
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
    repoURL: https://github.com/Gerolsteiner99/minikube-solr-config.git
    path: apps/zookeeper/overlays/minikube-dev
  destination:
    server: https://kubernetes.default.svc
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
    repoURL: https://github.com/Gerolsteiner99/minikube-solr-config.git
    path: apps/solr/overlays/minikube-ha
  destination:
    server: https://kubernetes.default.svc
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
    repoURL: https://github.com/Gerolsteiner99/minikube-solr-config.git
    path: apps/zookeeper/overlays/minikube-ha
  destination:
    server: https://kubernetes.default.svc
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
