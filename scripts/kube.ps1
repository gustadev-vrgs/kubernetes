# Mesmo contexto e namespace de kube.sh. Executar a partir da raiz do projeto.
$ErrorActionPreference = 'Stop'
& minikube -p devops-k8s kubectl -- --context=devops-k8s --namespace=aula-k8s @args
exit $LASTEXITCODE
