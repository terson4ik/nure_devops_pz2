# k8s-lab
Backend (Python) + frontend (nginx) в Docker Compose и Kubernetes (minikube).

- Локально: `docker compose up -d --build`, затем `curl http://localhost:8080`
- Kubernetes: `./deploy-all.sh` (minikube, аддоны, образы, манифесты и проверки)
- CI: `.github/workflows/deploy.yml` запускает `deploy-all.sh` на каждый push
