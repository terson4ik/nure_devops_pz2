#!/usr/bin/env bash
# Піднімає весь стенд у minikube і перевіряє, що все працює.
set -euo pipefail
cd "$(dirname "$0")"

# build_image <тег> <каталог>: спочатку збираємо в самій ноді,
# при збої запасний шлях: docker build на хості + minikube image load
build_image() {
  minikube image build -t "$1" "$2" \
    || { docker build -t "$1" "$2" && minikube image load "$1"; }
}

# expect "<що перевіряємо>" "<regex>" <команда...>
# повторює команду до 6 разів (пауза 5 с); падає, якщо regex не знайдено у виводі
expect() {
  local title=$1 pattern=$2 out=""
  shift 2
  for i in 1 2 3 4 5 6; do
    if out=$("$@" 2>&1) && grep -Eq -- "$pattern" <<<"$out"; then
      echo "[OK]   $title"
      echo "$out"
      return 0
    fi
    sleep 5
  done
  echo "[FAIL] $title"
  echo "$out"
  exit 1
}

echo "1. Minikube"
if ! minikube status >/dev/null 2>&1; then
  minikube start --driver=docker --container-runtime=containerd
fi

echo "2. Addons"
minikube addons enable ingress
minikube addons enable metrics-server

echo "3. Збірка образів у кластер"
build_image lab-backend:1.0 app/backend
build_image lab-frontend:1.0 app/frontend
minikube image ls | grep lab- || { echo "образи lab-* не знайдено в minikube"; exit 1; }

echo "4. Очікування ingress-контролера"
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s

echo "5. Застосування маніфестів"
ok=0
for i in 1 2 3 4 5; do
  if kubectl apply -f k8s/; then ok=1; break; fi
  echo "apply не вдався (часто webhook ingress ще не готовий), спроба $i/5, чекаємо 10с..."
  sleep 10
done
[ "$ok" = 1 ] || { echo "kubectl apply не вдався"; exit 1; }

echo "6. Очікування готовності"
kubectl wait --for=condition=ready pod/multi-app-pod --timeout=300s
for d in backend frontend log-writer log-reader; do
  kubectl rollout status "deploy/$d" --timeout=300s
done

echo "7. Статус"
kubectl get pods,deploy,rs,svc,ingress,pv,pvc -o wide
kubectl get pods -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
top_ok=0
for i in 1 2 3 4 5 6; do
  if kubectl top pods; then top_ok=1; break; fi
  sleep 10
done
[ "$top_ok" = 1 ] || echo "metrics-server ще не віддав метрики (не критично)"

echo "8. Перевірки"
IP=$(minikube ip)

expect "ClusterIP: frontend -> backend-svc" '"service": "backend"' \
  kubectl exec deploy/frontend -- wget -qO- http://backend-svc:5000
expect "Між Deployment'ами: backend -> frontend-svc -> backend" '"service": "backend"' \
  kubectl exec deploy/backend -- wget -qO- http://frontend-svc
expect "ConfigMap + Secret доступні застосунку" '"color": "blue", "api_key_set": true' \
  kubectl exec deploy/frontend -- wget -qO- http://backend-svc:5000
expect "NodePort 30080" '"service": "backend"' \
  curl -fsS --max-time 5 "http://$IP:30080"
expect "Ingress app.local -> frontend-svc" '"service": "backend"' \
  curl -fsS --max-time 5 -H 'Host: app.local' "http://$IP/"
expect "Ingress api.local -> backend-svc" '"service": "backend"' \
  curl -fsS --max-time 5 -H 'Host: api.local' "http://$IP/"
expect "Один под: frontend -> backend через 127.0.0.1" '"service": "backend"' \
  kubectl exec multi-app-pod -c log-reader -- wget -qO- http://127.0.0.1
expect "emptyDir: log-reader показує access.log nginx" 'GET / HTTP' \
  kubectl logs multi-app-pod -c log-reader --tail=5
expect "hostPath: log-reader читає те, що пише log-writer" 'writer=' \
  kubectl logs deploy/log-reader --tail=3

echo "9. LoadBalancer"
kubectl get svc frontend-lb
echo "EXTERNAL-IP з'являється після 'minikube tunnel' в окремому терміналі (у CI не перевіряється)"

echo "Готово: всі перевірки пройдено"
