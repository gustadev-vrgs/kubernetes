<#
  rodar_tudo.ps1 - Executa a atividade prática de Kubernetes do início ao fim
  (etapas 1 a 10 e 13 do roteiro) e grava todas as evidências em evidencias\.

  Como usar (PowerShell, na pasta do projeto, com o Docker Desktop aberto):
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
      .\rodar_tudo.ps1

  Opções:
      -SemPausa    não para para os prints do navegador
      -IncluirV4   também executa a continuação opcional (v4 com 2 réplicas)

  Os comandos são exatamente os do roteiro. Nos registros, ".\scripts\kube.ps1"
  aparece como o comando executado; internamente o script chama o mesmo
  "minikube -p devops-k8s kubectl -- --context=devops-k8s --namespace=aula-k8s"
  que o kube.ps1 chama, para conseguir capturar a saída com segurança.
#>
param(
    [switch]$SemPausa,
    [switch]$IncluirV4
)

$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $PSScriptRoot
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'

$Raiz = $PSScriptRoot
$Build = Join-Path $Raiz 'build'
$Evid = Join-Path $Raiz 'evidencias'
$Utf8 = New-Object System.Text.UTF8Encoding $false
$Perfil = 'devops-k8s'
$KubePrefixo = @('-p', $Perfil, 'kubectl', '--', "--context=$Perfil", '--namespace=aula-k8s')
$ConfigMapArquivo = Join-Path $Raiz 'k8s\configmap.yaml'
$MensagemOriginal = 'Entrega v1 publicada pelo grupo.'
$MensagemNova = 'Entrega configurada pelo grupo.'
$script:Abertos = @()
$script:Resumo = [ordered]@{}

# ------------------------------------------------------------------ utilidades

function Titulo([string]$Texto) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkGreen
    Write-Host "  $Texto" -ForegroundColor Green
    Write-Host ('=' * 72) -ForegroundColor DarkGreen
}

function Aviso([string]$Texto) { Write-Host $Texto -ForegroundColor Yellow }

function Salvar([string]$Nome, $Linhas) {
    $caminho = Join-Path $Evid $Nome
    $texto = (@($Linhas) | ForEach-Object { "$_" }) -join "`r`n"
    [IO.File]::AppendAllText($caminho, $texto + "`r`n", $Utf8)
}

function Gravar([string]$Caminho, [string]$Texto) {
    [IO.File]::WriteAllText($Caminho, $Texto, $Utf8)
}

function Exec {
    param(
        [string]$Arquivo,
        [string]$Exe,
        [string[]]$Argumentos,
        [string]$Exibir,
        [switch]$PodeFalhar
    )
    if (-not $Exibir) { $Exibir = "$Exe $($Argumentos -join ' ')" }
    Write-Host "> $Exibir" -ForegroundColor Cyan
    $saida = & $Exe @Argumentos 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $l = if ($_.TargetObject -is [string]) { $_.TargetObject } else { $_.Exception.Message }
            if ($l -eq 'System.Management.Automation.RemoteException') { $l = '' }
        } else { $l = "$_" }
        Write-Host $l
        $l
    }
    $codigo = $LASTEXITCODE
    if ($Arquivo) {
        Salvar $Arquivo (@("PS> $Exibir") + @($saida) + @("[código de saída: $codigo]", ''))
    }
    $script:UltimoCodigo = $codigo
    if ($codigo -ne 0 -and -not $PodeFalhar) {
        throw "O comando falhou (código $codigo): $Exibir"
    }
}

function Kube {
    param([string]$Arquivo, [string[]]$Argumentos, [switch]$PodeFalhar)
    Exec -Arquivo $Arquivo -Exe $script:Minikube -Argumentos ($KubePrefixo + $Argumentos) `
        -Exibir (".\scripts\kube.ps1 " + ($Argumentos -join ' ')) -PodeFalhar:$PodeFalhar
}

function Mk {
    param([string]$Arquivo, [string[]]$Argumentos)
    Exec -Arquivo $Arquivo -Exe $script:Minikube -Argumentos (@('-p', $Perfil) + $Argumentos) `
        -Exibir ("minikube -p $Perfil " + ($Argumentos -join ' '))
}

function Py {
    param([string]$Arquivo, [string[]]$Argumentos, [switch]$PodeFalhar)
    Exec -Arquivo $Arquivo -Exe 'python' -Argumentos $Argumentos -PodeFalhar:$PodeFalhar
}

function KubeValor { & $script:Minikube @KubePrefixo @args 2>$null }

function KubeJson {
    $texto = (KubeValor @args) -join "`n"
    if ($texto) { $texto | ConvertFrom-Json }
}

function Nomes-Pods {
    $lista = KubeJson get pods -l app=entrega -o json
    @($lista.items | Where-Object { -not $_.metadata.deletionTimestamp } |
        ForEach-Object { $_.metadata.name })
}

function Esperar-PodsProntos([int]$Quantidade, [int]$Segundos = 180) {
    Write-Host "Aguardando $Quantidade Pods prontos..." -ForegroundColor DarkGray
    $limite = (Get-Date).AddSeconds($Segundos)
    $seguidos = 0
    while ((Get-Date) -lt $limite) {
        $lista = KubeJson get pods -l app=entrega -o json
        $vivos = @($lista.items | Where-Object { -not $_.metadata.deletionTimestamp })
        $prontos = @($vivos | Where-Object {
            $_.status.containerStatuses -and $_.status.containerStatuses[0].ready -eq $true })
        if ($vivos.Count -eq $Quantidade -and $prontos.Count -eq $Quantidade) {
            $seguidos++
            if ($seguidos -ge 2) { return }
        } else { $seguidos = 0 }
        Start-Sleep -Seconds 2
    }
    throw "Os Pods não chegaram a $Quantidade prontos em $Segundos s."
}

function LerTexto([string]$Caminho) {
    if (-not (Test-Path $Caminho)) { return '' }
    $fs = [IO.File]::Open($Caminho, 'Open', 'Read', 'ReadWrite')
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}

function Iniciar-Fundo([string[]]$Argumentos, [string]$Saida, [string]$Erro) {
    Remove-Item $Saida, $Erro -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $script:Minikube -ArgumentList ($KubePrefixo + $Argumentos) `
        -NoNewWindow -PassThru -RedirectStandardOutput $Saida -RedirectStandardError $Erro
    $script:Abertos += $p
    return $p
}

function Encerrar($Processo) {
    if ($Processo -and -not $Processo.HasExited) {
        & taskkill /PID $Processo.Id /T /F *> $null
    }
    Start-Sleep -Seconds 1
}

function Abrir-PortForward([string]$Alvo, [string]$Portas) {
    $local = $Portas.Split(':')[0]
    $log = Join-Path $Build "port-forward-$local.log"
    $err = Join-Path $Build "port-forward-$local.err.log"
    Write-Host "> .\scripts\kube.ps1 port-forward $Alvo $Portas   (em segundo plano)" -ForegroundColor Cyan
    $p = Iniciar-Fundo @('port-forward', $Alvo, $Portas) $log $err
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 250
        if ((LerTexto $log) -match "Forwarding from 127\.0\.0\.1:$local") { return $p }
        if ($p.HasExited) { break }
    }
    Encerrar $p
    throw "O port-forward para $Alvo não abriu. Veja $log e $err"
}

function Pedir-Print([string]$Arquivo, [string]$Descricao) {
    if ($SemPausa) { return }
    Start-Process 'http://127.0.0.1:8080'
    Write-Host ''
    Write-Host '  >>> PRINT DO NAVEGADOR <<<' -ForegroundColor Magenta
    Write-Host "  O navegador foi aberto em http://127.0.0.1:8080 ($Descricao)." -ForegroundColor Magenta
    Write-Host '  Tecle Win+Shift+S, capture a janela e salve como:' -ForegroundColor Magenta
    Write-Host "      $(Join-Path $Evid $Arquivo)" -ForegroundColor White
    Read-Host '  Depois de salvar, pressione Enter para continuar'
}

function Definir-Mensagem([string]$Mensagem) {
    $conteudo = [IO.File]::ReadAllText($ConfigMapArquivo)
    $novo = $conteudo -replace 'APP_MESSAGE:\s*".*"', ('APP_MESSAGE: "' + $Mensagem + '"')
    Gravar $ConfigMapArquivo $novo
}

# ------------------------------------------------------------------ execução

$inicio = Get-Date
New-Item -ItemType Directory -Force $Build, $Evid | Out-Null

# Execução anterior: guarda as evidências antigas em uma subpasta.
$antigos = Get-ChildItem $Evid -File | Where-Object { $_.Name -ne 'relato.md' }
if ($antigos) {
    $destino = Join-Path $Evid ('execucao-anterior-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $destino | Out-Null
    $antigos | Move-Item -Destination $destino
}

Start-Transcript -Path (Join-Path $Evid 'execucao-completa.txt') | Out-Null

try {
    Titulo 'Verificando as ferramentas'
    foreach ($ferramenta in 'python', 'docker', 'minikube', 'curl.exe') {
        if (-not (Get-Command $ferramenta -ErrorAction SilentlyContinue)) {
            throw "$ferramenta não foi encontrado no PATH. Rode o instalar_ferramentas.ps1 e reabra o PowerShell."
        }
    }
    $script:Minikube = (Get-Command minikube).Source
    & python --version *> $null
    if ($LASTEXITCODE -ne 0) { throw 'O comando python não funciona (talvez seja o atalho da Microsoft Store).' }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw 'O Docker não respondeu. Abra o Docker Desktop, espere "Engine running" e rode de novo.' }
    Write-Host 'OK' -ForegroundColor Green

    # Garante que a mensagem comece com o valor original do ZIP; a etapa 5 a altera.
    Definir-Mensagem $MensagemOriginal

    # ---------------------------------------------------------------- etapa 1
    Titulo 'Etapa 1 | Conferência inicial'
    Py  '01-versoes.txt' @('--version')
    Exec '01-versoes.txt' 'docker' @('version', '--format', 'Docker cliente {{.Client.Version}} / servidor {{.Server.Version}}')
    Mk  '01-versoes.txt' @('version')
    Mk  '01-minikube-start.txt' @('start', '--driver=docker', '--cpus=2', '--memory=2048')
    Kube '01-nodes.txt' @('wait', '--for=condition=Ready', 'node', '--all', '--timeout=180s')
    Kube '01-nodes.txt' @('get', 'nodes', '-o', 'wide')
    Kube '01-versoes.txt' @('version')
    # Limpa uma execução anterior desta mesma atividade, se houver.
    Kube '' @('delete', 'namespace', 'aula-k8s', '--ignore-not-found=true', '--wait=true')
    Py  '01-testes.txt' @('-m', 'unittest', 'discover', '-s', 'tests', '-v')

    # ---------------------------------------------------------------- etapa 2
    Titulo 'Etapa 2 | Primeira publicação (v1)'
    Exec '02-build-v1.txt' 'docker' @('build', '--build-arg', 'APP_VERSION=v1', '-t', 'entrega-local:v1', '.')
    Mk  '02-build-v1.txt' @('image', 'load', 'entrega-local:v1')
    Exec '02-imagens.txt' 'docker' @('image', 'ls', 'entrega-local')
    Mk  '02-imagens.txt' @('image', 'ls')
    Kube '02-publicacao-v1.txt' @('apply', '-f', 'k8s/namespace.yaml')
    Kube '02-publicacao-v1.txt' @('apply', '-f', 'k8s/configmap.yaml')
    Kube '02-publicacao-v1.txt' @('apply', '-f', 'k8s/service.yaml')
    Py  '02-publicacao-v1.txt' @('scripts/render.py', 'v1', '--replicas', '2', '--output', 'build/deployment.yaml')
    Kube '02-publicacao-v1.txt' @('apply', '--dry-run=server', '-f', 'build/deployment.yaml')
    Kube '02-publicacao-v1.txt' @('apply', '-f', 'build/deployment.yaml')
    Kube '02-publicacao-v1.txt' @('rollout', 'status', 'deployment/entrega', '--timeout=120s')
    Kube '02-pods-v1.txt' @('get', 'pods', '-l', 'app=entrega', '-o', 'wide')

    # ---------------------------------------------------------------- etapa 3
    Titulo 'Etapa 3 | Acesso e verificação'
    $pf = Abrir-PortForward 'service/entrega' '8080:80'
    Exec '03-acesso-v1.txt' 'curl.exe' @('-sS', 'http://127.0.0.1:8080/api/status')
    Exec '03-acesso-v1.txt' 'curl.exe' @('-i', '-sS', 'http://127.0.0.1:8080/readyz')
    Py  '03-acesso-v1.txt' @('scripts/smoke.py', 'http://127.0.0.1:8080', '--version', 'v1', '--output', 'evidencias/v1-status.json')
    Exec '' 'curl.exe' @('-sS', '-o', 'evidencias/pagina-v1.html', 'http://127.0.0.1:8080/')
    Pedir-Print 'print-v1.png' 'versão v1'
    Encerrar $pf

    # ---------------------------------------------------------------- etapa 4
    Titulo 'Etapa 4 | Réplicas: de 2 para 3 e exclusão de um Pod'
    Py  '04-escala.txt' @('scripts/render.py', 'v1', '--replicas', '3', '--output', 'build/deployment.yaml')
    Kube '04-escala.txt' @('apply', '-f', 'build/deployment.yaml')
    Kube '04-escala.txt' @('rollout', 'status', 'deployment/entrega', '--timeout=120s')
    Kube '04-escala.txt' @('get', 'pods', '-l', 'app=entrega')
    $antes = Nomes-Pods
    $watch = Iniciar-Fundo @('get', 'pods', '-l', 'app=entrega', '-w') (Join-Path $Evid '04-watch-pods.txt') (Join-Path $Build 'watch.err.log')
    Start-Sleep -Seconds 3
    $podAntigo = (KubeJson get pods -l app=entrega -o json).items[0].metadata.name
    Gravar (Join-Path $Evid 'pod-excluido.txt') "$podAntigo`r`n"
    Kube '04-exclusao.txt' @('delete', 'pod', $podAntigo, '--wait=true')
    Esperar-PodsProntos 3
    Start-Sleep -Seconds 4
    Encerrar $watch
    Kube '04-depois-da-exclusao.txt' @('get', 'pods', '-l', 'app=entrega', '-o', 'wide')
    $novos = @(Nomes-Pods | Where-Object { $antes -notcontains $_ })
    Gravar (Join-Path $Evid 'pod-novo.txt') (($novos -join "`r`n") + "`r`n")
    $script:Resumo['Pod excluído'] = $podAntigo
    $script:Resumo['Pod criado no lugar'] = ($novos -join ', ')

    # ---------------------------------------------------------------- etapa 5
    Titulo 'Etapa 5 | ConfigMap: mudar a mensagem sem reconstruir a imagem'
    Definir-Mensagem $MensagemNova
    Salvar '05-configmap.txt' (@('Conteúdo de k8s/configmap.yaml após a edição:') + (Get-Content $ConfigMapArquivo) + '')
    Kube '05-configmap.txt' @('apply', '-f', 'k8s/configmap.yaml')
    $pf = Abrir-PortForward 'service/entrega' '8080:80'
    Exec '05-antes-do-reinicio.txt' 'curl.exe' @('-sS', 'http://127.0.0.1:8080/api/status')
    Encerrar $pf
    Kube '05-reinicio.txt' @('rollout', 'restart', 'deployment/entrega')
    Kube '05-reinicio.txt' @('rollout', 'status', 'deployment/entrega', '--timeout=120s')
    Kube '05-reinicio.txt' @('get', 'pods', '-l', 'app=entrega')
    $pf = Abrir-PortForward 'service/entrega' '8080:80'
    Py  '05-depois-do-reinicio.txt' @('scripts/smoke.py', 'http://127.0.0.1:8080', '--version', 'v1',
        '--message', $MensagemNova, '--output', 'evidencias/config-status.json')
    Encerrar $pf

    # ---------------------------------------------------------------- etapa 6
    Titulo 'Etapa 6 | Nova versão (v2)'
    Exec '06-build-v2.txt' 'docker' @('build', '--build-arg', 'APP_VERSION=v2', '-t', 'entrega-local:v2', '.')
    Mk  '06-build-v2.txt' @('image', 'load', 'entrega-local:v2')
    Py  '06-publicacao-v2.txt' @('scripts/render.py', 'v2', '--replicas', '3', '--output', 'build/deployment.yaml')
    Kube '06-publicacao-v2.txt' @('apply', '-f', 'build/deployment.yaml')
    Kube '06-publicacao-v2.txt' @('rollout', 'status', 'deployment/entrega', '--timeout=120s')
    Kube '06-publicacao-v2.txt' @('get', 'pods', '-l', 'app=entrega')
    $pf = Abrir-PortForward 'service/entrega' '8080:80'
    Py  '06-smoke-v2.txt' @('scripts/smoke.py', 'http://127.0.0.1:8080', '--version', 'v2',
        '--message', $MensagemNova, '--output', 'evidencias/v2-status.json')
    Encerrar $pf
    $d = KubeJson get deployment entrega -o json
    $revOk = "$($d.metadata.annotations.'deployment.kubernetes.io/revision')".Trim()
    if (-not $revOk) { throw 'Não foi possível ler a revisão do Deployment.' }
    Gravar (Join-Path $Build 'revisao-ok.txt') "$revOk`r`n"
    Gravar (Join-Path $Evid 'revisao-ok.txt') "$revOk`r`n"
    Salvar '06-historico.txt' "Revisão verificada da v2 (anotação deployment.kubernetes.io/revision): $revOk"
    Kube '06-historico.txt' @('rollout', 'history', 'deployment/entrega')
    $script:Resumo['Revisão verificada da v2'] = $revOk

    # ---------------------------------------------------------------- etapa 7
    Titulo 'Etapa 7 | Publicar a versão com defeito proposital'
    Exec '07-build-quebrada.txt' 'docker' @('build', '--build-arg', 'APP_VERSION=quebrada', '-t', 'entrega-local:quebrada', '.')
    Mk  '07-build-quebrada.txt' @('image', 'load', 'entrega-local:quebrada')
    Py  '07-incidente.txt' @('scripts/render.py', 'quebrada', '--replicas', '3', '--output', 'build/deployment.yaml')
    Kube '07-incidente.txt' @('apply', '-f', 'build/deployment.yaml')
    $inicioIncidente = Get-Date
    Kube '07-incidente.txt' @('rollout', 'status', 'deployment/entrega', '--timeout=30s') -PodeFalhar
    if ($script:UltimoCodigo -ne 0) {
        Salvar '07-incidente.txt' 'Resultado previsto: o rollout status terminou com erro/timeout após 30 s.'
        Aviso 'Resultado previsto: o acompanhamento terminou com timeout. Seguindo para a investigação.'
    } else {
        Aviso 'Atenção: o rollout da versão quebrada terminou sem erro, o que não era esperado.'
    }
    Kube '07-pods.txt' @('get', 'pods', '-l', 'app=entrega', '-o', 'wide')
    Kube '07-describe-deployment.txt' @('describe', 'deployment', 'entrega')
    Kube '07-eventos.txt' @('get', 'events', '--sort-by=.lastTimestamp')

    # ---------------------------------------------------------------- etapa 8
    Titulo 'Etapa 8 | Investigar o Pod defeituoso'
    $lista = KubeJson get pods -l app=entrega -o json
    $podNovo = ($lista.items | Sort-Object { $_.metadata.creationTimestamp } | Select-Object -Last 1).metadata.name
    $script:Resumo['Pod da versão quebrada'] = $podNovo
    Kube 'incidente-describe.txt' @('describe', 'pod', $podNovo)
    Kube 'incidente-logs.txt' @('logs', $podNovo)
    $pf = Abrir-PortForward "pod/$podNovo" '8081:8000'
    Exec '08-healthz.txt' 'curl.exe' @('-i', '-sS', 'http://127.0.0.1:8081/healthz')
    Exec '08-readyz.txt' 'curl.exe' @('-i', '-sS', 'http://127.0.0.1:8081/readyz')
    Encerrar $pf
    # Espera o prazo de progresso (90 s) passar para registrar a condição do Deployment.
    $falta = 100 - ((Get-Date) - $inicioIncidente).TotalSeconds
    if ($falta -gt 0) {
        Write-Host "Aguardando $([int]$falta) s para o prazo de progresso de 90 s vencer..." -ForegroundColor DarkGray
        Start-Sleep -Seconds ([int]$falta)
    }
    Kube '08-deployment-apos-prazo.txt' @('get', 'pods', '-l', 'app=entrega', '-o', 'wide')
    Kube '08-deployment-apos-prazo.txt' @('describe', 'deployment', 'entrega')

    # ---------------------------------------------------------------- etapa 9
    Titulo 'Etapa 9 | Rollback para a revisão verificada'
    $revOk = (Get-Content (Join-Path $Build 'revisao-ok.txt') -Raw).Trim()
    Kube '09-rollback.txt' @('rollout', 'undo', 'deployment/entrega', "--to-revision=$revOk")
    Kube '09-rollback.txt' @('rollout', 'status', 'deployment/entrega', '--timeout=120s')
    Kube '09-rollback.txt' @('get', 'pods', '-l', 'app=entrega')
    Kube '09-rollback.txt' @('get', 'deployment', 'entrega', '-o', 'jsonpath={.spec.template.spec.containers[0].image}')
    $img = (KubeJson get deployment entrega -o json).spec.template.spec.containers[0].image
    $script:Resumo['Imagem após o rollback'] = $img
    Salvar '09-rollback.txt' @('', "Imagem do Deployment após o rollback: $img",
        ('build/deployment.yaml ainda pede: ' + (Select-String -Path 'build/deployment.yaml' -Pattern 'image:').Line.Trim()), '')
    Py  '09-alinhamento.txt' @('scripts/render.py', 'v2', '--replicas', '3', '--output', 'build/deployment.yaml')
    Kube '09-alinhamento.txt' @('apply', '-f', 'build/deployment.yaml')
    Kube '09-alinhamento.txt' @('rollout', 'status', 'deployment/entrega', '--timeout=120s')
    Kube '09-historico.txt' @('rollout', 'history', 'deployment/entrega')
    Kube '09-configmap-apos-rollback.txt' @('get', 'configmap', 'entrega-config', '-o', 'yaml')
    $pf = Abrir-PortForward 'service/entrega' '8080:80'
    Py  '09-smoke-rollback.txt' @('scripts/smoke.py', 'http://127.0.0.1:8080', '--version', 'v2',
        '--message', $MensagemNova, '--output', 'evidencias/rollback-status.json')
    Exec '' 'curl.exe' @('-sS', '-o', 'evidencias/pagina-rollback.html', 'http://127.0.0.1:8080/')
    Pedir-Print 'print-rollback.png' 'versão v2 recuperada'
    Encerrar $pf

    # ---------------------------------------------------------------- etapa 10
    Titulo 'Etapa 10 | Pipeline local'
    $n = 3
    while ($true) {
        & docker image inspect "entrega-local:v$n" *> $null
        if ($LASTEXITCODE -ne 0) { break }
        Aviso "A tag entrega-local:v$n já existe (execução anterior); usando a próxima versão."
        $n++
    }
    $versaoPipeline = "v$n"
    Py  '10-pipeline.txt' @('scripts/pipeline_local.py', $versaoPipeline, '3')
    $script:Resumo['Versão publicada pela pipeline'] = "$versaoPipeline com 3 réplicas"
    $pf = Abrir-PortForward 'service/entrega' '8080:80'
    Exec '10-status-final.txt' 'curl.exe' @('-sS', 'http://127.0.0.1:8080/api/status')
    Exec '' 'curl.exe' @('-sS', '-o', "evidencias/pagina-$versaoPipeline.html", 'http://127.0.0.1:8080/')
    Pedir-Print "print-$versaoPipeline.png" "versão $versaoPipeline publicada pela pipeline"
    Encerrar $pf

    if ($IncluirV4) {
        Titulo 'Continuação opcional | próxima versão com 2 réplicas'
        $versaoOpc = 'v' + ($n + 1)
        Py  '11-opcional.txt' @('scripts/pipeline_local.py', $versaoOpc, '2')
        Salvar '11-opcional.txt' (@('', 'build/deployment.yaml gerado:') + (Get-Content 'build/deployment.yaml'))
        $script:Resumo['Continuação opcional'] = "$versaoOpc com 2 réplicas"
    }

    # ---------------------------------------------------------------- etapa 13
    Titulo 'Etapa 13 | Estado final'
    Gravar (Join-Path $Evid 'final-pods.txt') (((KubeValor get pods -l app=entrega -o wide) -join "`r`n") + "`r`n")
    Gravar (Join-Path $Evid 'final-deployment.yaml') (((KubeValor get deployment entrega -o yaml) -join "`r`n") + "`r`n")
    Get-Content (Join-Path $Evid 'final-pods.txt') | Write-Host

    $duracao = (Get-Date) - $inicio
    $linhas = @("Resumo da execução - $(Get-Date -Format 'dd/MM/yyyy HH:mm')",
        "Duração: $([int]$duracao.TotalMinutes) min", '')
    foreach ($k in $script:Resumo.Keys) { $linhas += "${k}: $($script:Resumo[$k])" }
    Gravar (Join-Path $Evid '00-resumo.txt') (($linhas -join "`r`n") + "`r`n")

    Titulo 'CONCLUÍDO'
    $linhas | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host 'Todas as evidências estão na pasta evidencias\.' -ForegroundColor Green
    Write-Host 'O cluster continua ligado. Para desligar depois:' -ForegroundColor Green
    Write-Host '   .\scripts\kube.ps1 delete namespace aula-k8s'
    Write-Host '   minikube -p devops-k8s stop'
}
catch {
    Write-Host ''
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
    Salvar 'ERRO.txt' @((Get-Date).ToString('s'), $_.Exception.Message, $_.InvocationInfo.PositionMessage)
    Write-Host 'Os registros até aqui estão em evidencias\. Envie a pasta para análise.' -ForegroundColor Red
}
finally {
    foreach ($p in $script:Abertos) { if ($p -and -not $p.HasExited) { & taskkill /PID $p.Id /T /F *> $null } }
    Stop-Transcript | Out-Null
}
