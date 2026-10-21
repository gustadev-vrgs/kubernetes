#!/usr/bin/env bash
# rodar_tudo.sh - Executa a atividade prática de Kubernetes do início ao fim
# (etapas 1 a 10 e 13 do roteiro, caminho Ubuntu/Bash) e grava as evidências
# em evidencias/. Feito para rodar no GitHub Codespaces, mas funciona em
# qualquer Ubuntu com Docker.
#
# Uso, na pasta do projeto:
#     bash rodar_tudo.sh                 # execução completa, com pausas para os prints
#     bash rodar_tudo.sh --sem-pausa     # sem pausas
#     bash rodar_tudo.sh --incluir-v4    # também faz a continuação opcional
#
# Os comandos são os do roteiro (blocos "Ubuntu e Arch (Bash)").

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")"

RAIZ=$(pwd)
BUILD="$RAIZ/build"
EVID="$RAIZ/evidencias"
SEM_PAUSA=0
INCLUIR_V4=0
for arg in "$@"; do
  case "$arg" in
    --sem-pausa) SEM_PAUSA=1 ;;
    --incluir-v4) INCLUIR_V4=1 ;;
  esac
done
MSG_ORIGINAL='Entrega v1 publicada pelo grupo.'
MSG_NOVA='Entrega configurada pelo grupo.'
FUNDO=()
RESUMO=()
ULTIMO=0

# ------------------------------------------------------------------ utilidades

titulo() {
  printf '\n\e[32m%s\n  %s\n%s\e[0m\n' "$(printf '=%.0s' {1..72})" "$1" "$(printf '=%.0s' {1..72})"
}
aviso() { printf '\e[33m%s\e[0m\n' "$*"; }

# Mostra um comando como seria digitado, com aspas onde houver espaço.
exibir() {
  local saida="" a
  for a in "$@"; do
    if [[ "$a" == *" "* ]]; then saida+="\"$a\" "; else saida+="$a "; fi
  done
  printf '%s' "${saida% }"
}

# run ARQUIVO comando...  -> mostra, executa, grava em evidencias/ARQUIVO
run() {
  local arq="$1"; shift
  local cmd; cmd=$(exibir "$@")
  printf '\e[36m$ %s\e[0m\n' "$cmd"
  local tmp; tmp=$(mktemp)
  "$@" 2>&1 | tee "$tmp"
  ULTIMO=${PIPESTATUS[0]}
  if [[ -n "$arq" ]]; then
    { echo "\$ $cmd"; cat "$tmp"; echo "[código de saída: $ULTIMO]"; echo; } >> "$EVID/$arq"
  fi
  rm -f "$tmp"
  return "$ULTIMO"
}

falha() {
  printf '\n\e[31mERRO: %s\e[0m\n' "$*"
  { date '+%F %T'; echo "$*"; } >> "$EVID/ERRO.txt"
  printf '\e[31mOs registros até aqui estão em evidencias/. Mande a pasta para análise.\e[0m\n'
  exit 1
}

# must ARQUIVO comando... -> igual a run, mas interrompe se falhar
must() { run "$@" || falha "O comando falhou (código $ULTIMO): $(exibir "${@:2}")"; }

kube() { ./scripts/kube.sh "$@"; }

encerrar() {
  local pid="$1"
  pkill -P "$pid" 2>/dev/null
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1
}

limpar() {
  local pid
  for pid in "${FUNDO[@]}"; do
    kill -0 "$pid" 2>/dev/null && { pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; }
  done
}
trap limpar EXIT

# port_forward ALVO PORTAS -> abre em segundo plano e guarda o PID em $PF
port_forward() {
  local alvo="$1" portas="$2" local_port="${2%%:*}"
  local log="$BUILD/port-forward-$local_port.log"
  printf '\e[36m$ ./scripts/kube.sh port-forward %s %s   (em segundo plano)\e[0m\n' "$alvo" "$portas"
  ./scripts/kube.sh port-forward "$alvo" "$portas" > "$log" 2>&1 &
  PF=$!
  FUNDO+=("$PF")
  local i
  for i in $(seq 120); do
    sleep 0.25
    grep -q "Forwarding from 127.0.0.1:$local_port" "$log" 2>/dev/null && return 0
    kill -0 "$PF" 2>/dev/null || break
  done
  encerrar "$PF"
  falha "O port-forward para $alvo não abriu. Veja $log"
}

pods_json() { kube get pods -l app=entrega -o json 2>/dev/null; }

nomes_pods() {
  pods_json | python3 -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    if not p["metadata"].get("deletionTimestamp"):
        print(p["metadata"]["name"])'
}

pod_mais_recente() {
  pods_json | python3 -c '
import json, sys
itens = sorted(json.load(sys.stdin)["items"], key=lambda p: p["metadata"]["creationTimestamp"])
print(itens[-1]["metadata"]["name"])'
}

esperar_prontos() {
  local quantidade="$1" limite=$((SECONDS + 180)) seguidos=0 situacao
  echo "Aguardando $quantidade Pods prontos..."
  while (( SECONDS < limite )); do
    situacao=$(pods_json | python3 -c '
import json, sys
vivos = [p for p in json.load(sys.stdin)["items"] if not p["metadata"].get("deletionTimestamp")]
prontos = [p for p in vivos if (p.get("status", {}).get("containerStatuses") or [{}])[0].get("ready")]
print(len(vivos), len(prontos))')
    if [[ "$situacao" == "$quantidade $quantidade" ]]; then
      seguidos=$((seguidos + 1))
      (( seguidos >= 2 )) && return 0
    else
      seguidos=0
    fi
    sleep 2
  done
  falha "Os Pods não chegaram a $quantidade prontos em 180 s."
}

url_painel() {
  if [[ -n "${CODESPACE_NAME:-}" ]]; then
    echo "https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
  else
    echo "http://127.0.0.1:8080"
  fi
}

pedir_print() {
  local arquivo="$1" descricao="$2"
  (( SEM_PAUSA )) && return 0
  printf '\n\e[35m  >>> PRINT DO NAVEGADOR (%s) <<<\e[0m\n' "$descricao"
  printf '\e[35m  1. Abra este endereço (Ctrl+clique):\e[0m\n'
  printf '       %s\n' "$(url_painel)"
  printf '\e[35m     Se não abrir, use a aba PORTAS, porta 8080, ícone do globo.\e[0m\n'
  printf '\e[35m  2. Tecle Win+Shift+S, capture a página e salve no SEU computador como:\e[0m\n'
  printf '       Desktop\\devops_kubernetes\\evidencias\\%s\n' "$arquivo"
  read -r -p '  3. Depois de salvar, pressione Enter aqui para continuar ' _
}

definir_mensagem() {
  sed -i -E "s|APP_MESSAGE:[[:space:]]*\".*\"|APP_MESSAGE: \"$1\"|" k8s/configmap.yaml
}

# ------------------------------------------------------------------ preparação

mkdir -p "$BUILD" "$EVID"
chmod +x scripts/kube.sh scripts/pipeline_local.sh 2>/dev/null

# Evidências de uma execução anterior vão para uma subpasta.
antigos=$(find "$EVID" -maxdepth 1 -type f ! -name relato.md)
if [[ -n "$antigos" ]]; then
  destino="$EVID/execucao-anterior-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$destino"
  find "$EVID" -maxdepth 1 -type f ! -name relato.md -exec mv {} "$destino"/ \;
fi

# Transcrição completa da sessão.
exec > >(tee -a "$EVID/execucao-completa.txt") 2>&1

titulo 'Preparando o ambiente'
if ! command -v minikube > /dev/null; then
  arq=amd64; [[ "$(uname -m)" == aarch64 ]] && arq=arm64
  echo "Instalando o Minikube ($arq)..."
  curl -fsSLo /tmp/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$arq" \
    || falha 'Não foi possível baixar o Minikube.'
  sudo install /tmp/minikube /usr/local/bin/minikube || falha 'Não foi possível instalar o Minikube.'
fi
for f in python3 docker minikube curl; do
  command -v "$f" > /dev/null || falha "$f não encontrado."
done
for i in $(seq 30); do docker info > /dev/null 2>&1 && break; sleep 2; done
docker info > /dev/null 2>&1 || falha 'O Docker não respondeu.'
definir_mensagem "$MSG_ORIGINAL"
echo OK

# ------------------------------------------------------------------ etapa 1
titulo 'Etapa 1 | Conferência inicial'
must 01-versoes.txt python3 --version
must 01-versoes.txt docker version --format 'Docker cliente {{.Client.Version}} / servidor {{.Server.Version}}'
must 01-versoes.txt minikube version
run  01-versoes.txt bash -c '. /etc/os-release; echo "Sistema: $PRETTY_NAME"'
must 01-minikube-start.txt minikube -p devops-k8s start --driver=docker --cpus=2 --memory=2048
must 01-nodes.txt ./scripts/kube.sh wait --for=condition=Ready node --all --timeout=180s
must 01-nodes.txt ./scripts/kube.sh get nodes -o wide
must 01-versoes.txt ./scripts/kube.sh version
# Limpa uma execução anterior desta atividade, se houver.
must '' ./scripts/kube.sh delete namespace aula-k8s --ignore-not-found=true --wait=true
must 01-testes.txt python3 -m unittest discover -s tests -v

# ------------------------------------------------------------------ etapa 2
titulo 'Etapa 2 | Primeira publicação (v1)'
must 02-build-v1.txt docker build --build-arg APP_VERSION=v1 -t entrega-local:v1 .
must 02-build-v1.txt minikube -p devops-k8s image load entrega-local:v1
must 02-imagens.txt docker image ls entrega-local
must 02-imagens.txt minikube -p devops-k8s image ls
must 02-publicacao-v1.txt ./scripts/kube.sh apply -f k8s/namespace.yaml
must 02-publicacao-v1.txt ./scripts/kube.sh apply -f k8s/configmap.yaml
must 02-publicacao-v1.txt ./scripts/kube.sh apply -f k8s/service.yaml
must 02-publicacao-v1.txt python3 scripts/render.py v1 --replicas 2 --output build/deployment.yaml
must 02-publicacao-v1.txt ./scripts/kube.sh apply --dry-run=server -f build/deployment.yaml
must 02-publicacao-v1.txt ./scripts/kube.sh apply -f build/deployment.yaml
must 02-publicacao-v1.txt ./scripts/kube.sh rollout status deployment/entrega --timeout=120s
must 02-pods-v1.txt ./scripts/kube.sh get pods -l app=entrega -o wide

# ------------------------------------------------------------------ etapa 3
titulo 'Etapa 3 | Acesso e verificação'
port_forward service/entrega 8080:80
must 03-acesso-v1.txt curl -sS http://127.0.0.1:8080/api/status
echo
must 03-acesso-v1.txt curl -i -sS http://127.0.0.1:8080/readyz
echo
must 03-acesso-v1.txt python3 scripts/smoke.py http://127.0.0.1:8080 --version v1 --output evidencias/v1-status.json
must '' curl -sS -o evidencias/pagina-v1.html http://127.0.0.1:8080/
pedir_print print-v1.png 'versão v1'
encerrar "$PF"

# ------------------------------------------------------------------ etapa 4
titulo 'Etapa 4 | Réplicas: de 2 para 3 e exclusão de um Pod'
must 04-escala.txt python3 scripts/render.py v1 --replicas 3 --output build/deployment.yaml
must 04-escala.txt ./scripts/kube.sh apply -f build/deployment.yaml
must 04-escala.txt ./scripts/kube.sh rollout status deployment/entrega --timeout=120s
must 04-escala.txt ./scripts/kube.sh get pods -l app=entrega
mapfile -t ANTES < <(nomes_pods)
./scripts/kube.sh get pods -l app=entrega -w > "$EVID/04-watch-pods.txt" 2>&1 &
WATCH=$!
FUNDO+=("$WATCH")
sleep 3
POD_ANTIGO=$(
  ./scripts/kube.sh get pods -l app=entrega \
    -o jsonpath='{.items[0].metadata.name}'
)
printf '%s\n' "$POD_ANTIGO" > evidencias/pod-excluido.txt
must 04-exclusao.txt ./scripts/kube.sh delete pod "$POD_ANTIGO" --wait=true
esperar_prontos 3
sleep 4
encerrar "$WATCH"
must 04-depois-da-exclusao.txt ./scripts/kube.sh get pods -l app=entrega -o wide
: > evidencias/pod-novo.txt
NOVOS=()
while read -r nome; do
  [[ " ${ANTES[*]} " == *" $nome "* ]] || { NOVOS+=("$nome"); echo "$nome" >> evidencias/pod-novo.txt; }
done < <(nomes_pods)
RESUMO+=("Pod excluído: $POD_ANTIGO" "Pod criado no lugar: ${NOVOS[*]:-}")

# ------------------------------------------------------------------ etapa 5
titulo 'Etapa 5 | ConfigMap: mudar a mensagem sem reconstruir a imagem'
definir_mensagem "$MSG_NOVA"
{ echo 'Conteúdo de k8s/configmap.yaml após a edição:'; cat k8s/configmap.yaml; echo; } >> "$EVID/05-configmap.txt"
cat k8s/configmap.yaml
must 05-configmap.txt ./scripts/kube.sh apply -f k8s/configmap.yaml
port_forward service/entrega 8080:80
must 05-antes-do-reinicio.txt curl -sS http://127.0.0.1:8080/api/status
echo
encerrar "$PF"
must 05-reinicio.txt ./scripts/kube.sh rollout restart deployment/entrega
must 05-reinicio.txt ./scripts/kube.sh rollout status deployment/entrega --timeout=120s
must 05-reinicio.txt ./scripts/kube.sh get pods -l app=entrega
port_forward service/entrega 8080:80
must 05-depois-do-reinicio.txt python3 scripts/smoke.py http://127.0.0.1:8080 --version v1 \
  --message "$MSG_NOVA" --output evidencias/config-status.json
encerrar "$PF"

# ------------------------------------------------------------------ etapa 6
titulo 'Etapa 6 | Nova versão (v2)'
must 06-build-v2.txt docker build --build-arg APP_VERSION=v2 -t entrega-local:v2 .
must 06-build-v2.txt minikube -p devops-k8s image load entrega-local:v2
must 06-publicacao-v2.txt python3 scripts/render.py v2 --replicas 3 --output build/deployment.yaml
must 06-publicacao-v2.txt ./scripts/kube.sh apply -f build/deployment.yaml
must 06-publicacao-v2.txt ./scripts/kube.sh rollout status deployment/entrega --timeout=120s
must 06-publicacao-v2.txt ./scripts/kube.sh get pods -l app=entrega
port_forward service/entrega 8080:80
must 06-smoke-v2.txt python3 scripts/smoke.py http://127.0.0.1:8080 --version v2 \
  --message "$MSG_NOVA" --output evidencias/v2-status.json
encerrar "$PF"
MODELO='{{index .metadata.annotations "deployment.kubernetes.io/revision"}}'
./scripts/kube.sh get deployment entrega -o go-template="$MODELO" \
  > build/revisao-ok.txt || falha 'Não foi possível ler a revisão do Deployment.'
REV_OK=$(cat build/revisao-ok.txt)
[[ -n "$REV_OK" ]] || falha 'A revisão do Deployment veio vazia.'
cp build/revisao-ok.txt evidencias/revisao-ok.txt
echo "Revisão verificada da v2 (deployment.kubernetes.io/revision): $REV_OK" | tee -a "$EVID/06-historico.txt"
must 06-historico.txt ./scripts/kube.sh rollout history deployment/entrega
RESUMO+=("Revisão verificada da v2: $REV_OK")

# ------------------------------------------------------------------ etapa 7
titulo 'Etapa 7 | Publicar a versão com defeito proposital'
must 07-build-quebrada.txt docker build --build-arg APP_VERSION=quebrada -t entrega-local:quebrada .
must 07-build-quebrada.txt minikube -p devops-k8s image load entrega-local:quebrada
must 07-incidente.txt python3 scripts/render.py quebrada --replicas 3 --output build/deployment.yaml
must 07-incidente.txt ./scripts/kube.sh apply -f build/deployment.yaml
INICIO_INCIDENTE=$SECONDS
if run 07-incidente.txt ./scripts/kube.sh rollout status deployment/entrega --timeout=30s; then
  aviso 'Atenção: o rollout da versão quebrada terminou sem erro, o que não era esperado.'
else
  echo 'Resultado previsto: o rollout status terminou com erro/timeout após 30 s.' >> "$EVID/07-incidente.txt"
  aviso 'Resultado previsto: o acompanhamento terminou com timeout. Seguindo para a investigação.'
fi
must 07-pods.txt ./scripts/kube.sh get pods -l app=entrega -o wide
must 07-describe-deployment.txt ./scripts/kube.sh describe deployment entrega
must 07-eventos.txt ./scripts/kube.sh get events --sort-by=.lastTimestamp

# ------------------------------------------------------------------ etapa 8
titulo 'Etapa 8 | Investigar o Pod defeituoso'
POD_NOVO=$(
  ./scripts/kube.sh get pods -l app=entrega \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1].metadata.name}'
)
[[ -n "$POD_NOVO" ]] || POD_NOVO=$(pod_mais_recente)
RESUMO+=("Pod da versão quebrada: $POD_NOVO")
./scripts/kube.sh describe pod "$POD_NOVO" > evidencias/incidente-describe.txt 2>&1
./scripts/kube.sh logs "$POD_NOVO" > evidencias/incidente-logs.txt 2>&1
cat evidencias/incidente-describe.txt | tail -15
port_forward "pod/$POD_NOVO" 8081:8000
must 08-healthz.txt curl -i -sS http://127.0.0.1:8081/healthz
echo
must 08-readyz.txt curl -i -sS http://127.0.0.1:8081/readyz
echo
encerrar "$PF"
FALTA=$((100 - (SECONDS - INICIO_INCIDENTE)))
if (( FALTA > 0 )); then
  echo "Aguardando $FALTA s para o prazo de progresso de 90 s vencer..."
  sleep "$FALTA"
fi
must 08-deployment-apos-prazo.txt ./scripts/kube.sh get pods -l app=entrega -o wide
must 08-deployment-apos-prazo.txt ./scripts/kube.sh describe deployment entrega

# ------------------------------------------------------------------ etapa 9
titulo 'Etapa 9 | Rollback para a revisão verificada'
REV_OK=$(cat build/revisao-ok.txt)
must 09-rollback.txt ./scripts/kube.sh rollout undo deployment/entrega --to-revision="$REV_OK"
must 09-rollback.txt ./scripts/kube.sh rollout status deployment/entrega --timeout=120s
must 09-rollback.txt ./scripts/kube.sh get pods -l app=entrega
must 09-rollback.txt ./scripts/kube.sh get deployment entrega \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
printf '\n'
IMG=$(./scripts/kube.sh get deployment entrega -o jsonpath='{.spec.template.spec.containers[0].image}')
RESUMO+=("Imagem após o rollback: $IMG")
{
  echo
  echo "Imagem do Deployment após o rollback: $IMG"
  echo "build/deployment.yaml ainda pede: $(grep -m1 'image:' build/deployment.yaml | xargs)"
  echo
} | tee -a "$EVID/09-rollback.txt"
must 09-alinhamento.txt python3 scripts/render.py v2 --replicas 3 --output build/deployment.yaml
must 09-alinhamento.txt ./scripts/kube.sh apply -f build/deployment.yaml
must 09-alinhamento.txt ./scripts/kube.sh rollout status deployment/entrega --timeout=120s
must 09-historico.txt ./scripts/kube.sh rollout history deployment/entrega
must 09-configmap-apos-rollback.txt ./scripts/kube.sh get configmap entrega-config -o yaml
port_forward service/entrega 8080:80
must 09-smoke-rollback.txt python3 scripts/smoke.py http://127.0.0.1:8080 --version v2 \
  --message "$MSG_NOVA" --output evidencias/rollback-status.json
must '' curl -sS -o evidencias/pagina-rollback.html http://127.0.0.1:8080/
pedir_print print-rollback.png 'versão v2 recuperada'
encerrar "$PF"

# ------------------------------------------------------------------ etapa 10
titulo 'Etapa 10 | Pipeline local'
N=3
while docker image inspect "entrega-local:v$N" > /dev/null 2>&1; do
  aviso "A tag entrega-local:v$N já existe (execução anterior); usando a próxima versão."
  N=$((N + 1))
done
VERSAO="v$N"
must 10-pipeline.txt python3 scripts/pipeline_local.py "$VERSAO" 3
RESUMO+=("Versão publicada pela pipeline: $VERSAO com 3 réplicas")
port_forward service/entrega 8080:80
must 10-status-final.txt curl -sS http://127.0.0.1:8080/api/status
echo
must '' curl -sS -o "evidencias/pagina-$VERSAO.html" http://127.0.0.1:8080/
pedir_print "print-$VERSAO.png" "versão $VERSAO publicada pela pipeline"
encerrar "$PF"

if (( INCLUIR_V4 )); then
  titulo 'Continuação opcional | próxima versão com 2 réplicas'
  OPC="v$((N + 1))"
  must 11-opcional.txt python3 scripts/pipeline_local.py "$OPC" 2
  { echo; echo 'build/deployment.yaml gerado:'; cat build/deployment.yaml; } >> "$EVID/11-opcional.txt"
  RESUMO+=("Continuação opcional: $OPC com 2 réplicas")
fi

# ------------------------------------------------------------------ etapa 13
titulo 'Etapa 13 | Estado final'
./scripts/kube.sh get pods -l app=entrega -o wide \
  > evidencias/final-pods.txt
./scripts/kube.sh get deployment entrega -o yaml \
  > evidencias/final-deployment.yaml
cat evidencias/final-pods.txt

{
  echo "Resumo da execução - $(date '+%d/%m/%Y %H:%M')"
  echo "Duração: $((SECONDS / 60)) min"
  echo
  printf '%s\n' "${RESUMO[@]}"
} > evidencias/00-resumo.txt

# Pacote para baixar: projeto inteiro sem .git e sem o próprio zip.
python3 - <<'EOF'
import os, zipfile
nome = 'entrega-atividade-kubernetes.zip'
with zipfile.ZipFile(nome, 'w', zipfile.ZIP_DEFLATED) as z:
    for raiz, pastas, arquivos in os.walk('.'):
        pastas[:] = [p for p in pastas if p not in ('.git', '.devcontainer', '__pycache__')]
        for a in arquivos:
            if a == nome:
                continue
            caminho = os.path.join(raiz, a)
            z.write(caminho, os.path.join('devops_kubernetes', os.path.relpath(caminho, '.')))
EOF

titulo 'CONCLUÍDO'
cat evidencias/00-resumo.txt
echo
printf '\e[32mTodas as evidências estão em evidencias/.\e[0m\n'
printf '\e[32mPacote para baixar: entrega-atividade-kubernetes.zip\e[0m\n'
printf '  (no painel de arquivos à esquerda: botão direito > Download)\n'
