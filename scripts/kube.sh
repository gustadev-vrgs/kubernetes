#!/usr/bin/env bash
# Atalho do kubectl fornecido pelo Minikube. Contexto e namespace do laboratorio.
set -euo pipefail
exec minikube -p devops-k8s kubectl -- \
  --context=devops-k8s --namespace=aula-k8s "$@"
