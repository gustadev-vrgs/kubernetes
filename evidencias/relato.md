# Relato do grupo

Integrantes: ⟪nomes⟫
Data: ⟪data da execução⟫
Sistema: Ubuntu em GitHub Codespaces (terminal Bash), Docker e Minikube com driver Docker. O computador do grupo (Windows 11) não tem virtualização de hardware habilitada no firmware, o que impediu o Docker Desktop de iniciar; por isso seguimos os blocos "Ubuntu e Arch (Bash)" do roteiro em um Codespace.
Python / Docker / Minikube / Kubernetes: ⟪copiar de 01-versoes.txt⟫

Todas as saídas citadas estão na pasta `evidencias/`. Cada arquivo começa com o comando que a produziu (linha `$`) e termina com o código de saída. O arquivo `execucao-completa.txt` contém a transcrição completa da sessão.

## Etapas

| Etapa | Comando e evidência | Resultado esperado | Resultado observado e explicação |
|---|---|---|---|
| Testes | `python3 -m unittest discover -s tests -v` → `01-testes.txt` | 8 testes OK | ⟪8 testes, OK⟫. Os testes sobem servidores locais temporários e não dependem do cluster. |
| Publicação v1 | `docker build`, `minikube image load`, `apply` e `rollout status` → `02-publicacao-v1.txt`, `02-pods-v1.txt`, `v1-status.json`, `print-v1.png` | 2 Pods prontos; API v1 | Dois Pods `1/1 Running` (⟪nomes⟫). A página mostrou v1, a mensagem do ConfigMap e o nome ⟪pod⟫, que é um dos dois Pods listados. O smoke test imprimiu `SMOKE OK`. |
| Escala | `render.py v1 --replicas 3` + `apply` → `04-escala.txt` | 3 Pods prontos | Um terceiro Pod foi criado. A imagem não mudou, portanto o modelo também não mudou e não houve nova revisão. |
| Exclusão e recuperação | `delete pod` → `pod-excluido.txt`, `pod-novo.txt`, `04-watch-pods.txt`, `04-depois-da-exclusao.txt` | Nome antigo removido; novo Pod criado | ⟪pod excluído⟫ entrou em `Terminating` e desapareceu. O ReplicaSet criou ⟪pod novo⟫, com nome e IP novos, e voltou a 3 prontos. |
| ConfigMap | `apply -f k8s/configmap.yaml` → `05-antes-do-reinicio.txt`; `rollout restart` → `05-reinicio.txt`, `config-status.json` | Mensagem muda após recriar Pods | Logo após o apply, a API ainda mostrava "Entrega v1 publicada pelo grupo.". Depois do restart, mostrou "Entrega configurada pelo grupo." com a versão ainda v1. |
| Atualização v2 | build/load v2 + `apply` → `06-publicacao-v2.txt`, `v2-status.json`, `06-historico.txt` | 3 Pods v2 prontos | 3 Pods v2 prontos e smoke OK. Revisão salva: ⟪n.º de revisao-ok.txt⟫. |
| Incidente | build/load quebrada + `apply` + `rollout status --timeout=30s` → `07-*.txt`, `incidente-describe.txt`, `incidente-logs.txt`, `08-healthz.txt`, `08-readyz.txt` | Novo Running 0/1; healthz 200, readyz 503 | O rollout terminou com timeout. Havia 3 Pods v2 `1/1` e o Pod ⟪pod quebrado⟫ em `Running 0/1`, com 0 reinícios. Nos eventos: `Readiness probe failed ... 503`. `/healthz` respondeu 200 e `/readyz` respondeu 503. Depois de 90 s, o Deployment marcou `ProgressDeadlineExceeded` (`08-deployment-apos-prazo.txt`) e não fez rollback sozinho. |
| Rollback | `rollout undo --to-revision=⟪n⟫` → `09-rollback.txt`, `09-alinhamento.txt`, `rollback-status.json`, `print-rollback.png` | v2 restaurada | A imagem voltou a `entrega-local:v2` e o Deployment estabilizou com 3 réplicas prontas. A mensagem continuou a nova. `build/deployment.yaml` ainda pedia `quebrada` e foi regenerado como v2. |
| Pipeline v3 | `python3 scripts/pipeline_local.py v3 3` → `10-pipeline.txt`, `status-v3.json`, `pods-v3.txt`, `imagem-v3.txt`, `print-v3.png` | Smoke OK e estado final v3 | Testes, build, load, apply, rollout e smoke concluídos: "Pipeline concluida: v3, replicas=3". O estado final está em `final-pods.txt` e `final-deployment.yaml`. |

## Respostas

**1. Por que carregar a imagem no Minikube depois de construir no Docker?**
O `docker build` grava a imagem no armazenamento do Docker Desktop do computador. O nó do Minikube é outro ambiente, um contêiner com o próprio runtime e o próprio armazenamento de imagens. O Deployment usa `imagePullPolicy: Never`, então o kubelet só usa uma imagem que já esteja no nó e nunca tenta baixá-la. Sem o `minikube image load`, o Pod ficaria em `ErrImageNeverPull`. O arquivo `02-imagens.txt` mostra a imagem nos dois lugares.

**2. Qual a função das portas 8000, 80, 30080 e 8080?**
- 8000 é a porta em que a aplicação escuta dentro do contêiner (`containerPort` e `targetPort: http`).
- 80 é a porta do Service dentro do cluster.
- 30080 é o NodePort, que publica o Service em uma porta do nó. Não usamos essa porta porque, com o driver Docker, o nó fica em uma rede interna do Docker e não é alcançável diretamente pelo navegador.
- 8080 é a porta local do computador, aberta pelo `port-forward`. É o endereço que o navegador acessa.
- Também usamos 8081, para a inspeção direta do Pod quebrado, e 18080, que a pipeline abre temporariamente.

**3. Por que o Pod excluído foi substituído?**
O Deployment declara 3 réplicas e o ReplicaSet reconcilia continuamente: compara o estado observado com o desejado. Quando um Pod sumiu, a contagem caiu para 2 e o controlador criou outro a partir do mesmo modelo. O novo Pod não tem a mesma identidade do anterior: ele tem nome, IP e UID novos (⟪pod excluído⟫ → ⟪pod novo⟫). O objetivo é recuperar a quantidade, não o objeto.

**4. Por que três Pods no mesmo nó não protegem contra a perda da máquina?**
O Minikube tem um único nó. Se esse nó (ou o computador) parar, os três Pods param juntos, e não existe outro nó onde o controlador possa recriá-los. Réplicas protegem contra a falha de uma instância. A falha de uma máquina exige réplicas distribuídas em vários nós, e a perda de dados exige backup.

**5. Por que a mensagem não mudou imediatamente após aplicar o ConfigMap?**
A aplicação recebe `APP_MESSAGE` por `envFrom`, como variável de ambiente. Variáveis de ambiente são fixadas quando o contêiner inicia, e a aplicação lê a mensagem apenas na inicialização. Atualizar o objeto ConfigMap não altera o ambiente de processos que já estão rodando. O `rollout restart` adiciona uma anotação de data ao modelo dos Pods, o que gera uma nova revisão. Os Pods novos leem o valor atual. Não foi preciso construir outra imagem, porque a mensagem é configuração externa à imagem.

**6. Tag de imagem e revisão do Deployment são a mesma coisa?**
Não. A tag (`v1`, `v2`, `v3`) identifica o pacote construído. A revisão é um contador do Deployment que aumenta sempre que o modelo dos Pods muda, inclusive sem troca de imagem. No nosso caso, o restart da etapa 5 criou uma revisão nova, por isso a v2 ficou na revisão ⟪n⟫, e não na 2. Mudar só `replicas` não cria revisão, porque a quantidade não faz parte do modelo. Depois do rollback, a revisão restaurada ganhou um número novo (`09-historico.txt`).

**7. Que sinais mostram que a versão quebrada está viva, mas não pronta?**
- O Pod aparecia como `Running` com `READY 0/1` e 0 reinícios.
- A liveness, em `/healthz`, respondia 200. Por isso o contêiner não era reiniciado.
- A readiness, em `/readyz`, respondia 503. Os eventos mostram `Readiness probe failed: HTTP probe failed with statuscode: 503`.
- Os logs mostram as requisições das probes chegando ao processo.
- O Pod não entrou no Service, os 3 Pods v2 continuaram atendendo (`maxUnavailable: 0`) e o rollout não terminou.

O sinal que justifica abandonar a entrega é o conjunto de três evidências: readiness falhando de forma persistente, o rollout sem progresso e o Deployment com `ProgressDeadlineExceeded`.

**8. O que o timeout fez? O que o rollback restaurou e o que não restaurou?**
O `--timeout=30s` apenas encerrou a espera do comando `rollout status`. Nada foi revertido por ele, e o prazo de 90 s do Deployment também só marca a condição de falha. Quem iniciou a reversão foi o comando `rollout undo deployment/entrega --to-revision=⟪n⟫`. O rollback restaurou o modelo dos Pods daquela revisão (imagem `entrega-local:v2`, probes, ambiente). Ele não restaurou:
- o ConfigMap, que continuou com a mensagem nova;
- a quantidade de réplicas, que continuou 3, porque não faz parte do modelo;
- os arquivos locais: `build/deployment.yaml` continuou pedindo `quebrada` e `k8s/configmap.yaml` continuou editado.

**9. Por que alinhar o arquivo gerado após a reversão?**
O arquivo é a descrição do estado desejado. Se ele continuasse pedindo `entrega-local:quebrada`, o próximo `apply`, feito por alguém do grupo ou por uma automação, publicaria de novo a versão defeituosa e desfaria o rollback. Por isso o arquivo foi regenerado com `render.py v2 --replicas 3` e reaplicado. O cluster e o arquivo voltaram a descrever a mesma coisa.

**10. Quais verificações a pipeline realiza? Qual é seu limite?**
A pipeline faz, em ordem:
1. confere o Docker (`docker info`) e o Minikube (`minikube status`);
2. roda os 8 testes unitários;
3. recusa uma tag que já exista;
4. constrói e carrega a imagem;
5. gera e aplica os manifestos;
6. espera o `rollout status`, o que garante que as readiness passaram;
7. faz um smoke test HTTP pelo Service, conferindo versão e `ready: true`;
8. registra os Pods e o ID da imagem.

Ela para no primeiro erro e não faz rollback automático.

Os limites são vários:
- O smoke test não confere a mensagem e consulta um só Pod pelo port-forward.
- Não há testes de integração, carga ou segurança.
- Problemas que surgem depois do deploy não são detectados, como vazamento de memória, falhas intermitentes ou erros com dados reais. Também não existe monitoramento contínuo.
- O cluster tem um único nó.

Ela é uma pipeline local porque roda na máquina de trabalho do grupo (aqui, o Codespace), é acionada manualmente pelo terminal e publica em um cluster local, sem repositório remoto nem registry. Para virar integração e entrega contínuas, faltariam:
- um repositório Git com gatilho por push ou pull request;
- um servidor de CI (GitHub Actions, GitLab CI ou Jenkins);
- envio da imagem a um registry com tag imutável (por exemplo, o hash do commit);
- credenciais seguras para o cluster de destino;
- ambientes separados (homologação e produção) e aprovação antes da produção;
- notificações, monitoramento e rollback automatizado a partir de métricas.

## Divergências e correções

⟪Descrever aqui qualquer diferença em relação ao roteiro, com hipótese, comando de diagnóstico, sinal observado e correção. Se não houve nenhuma, escrever "Nenhuma divergência: todas as etapas produziram o resultado esperado".⟫

Observação: o grupo usou o script `rodar_tudo.sh`, que executa em sequência exatamente os comandos do roteiro (etapas 1 a 10 e 13). Ele grava cada saída com o comando correspondente e para nos pontos em que o roteiro pede captura de tela. A etapa 7 termina em timeout de propósito, e o script trata esse resultado como esperado.
