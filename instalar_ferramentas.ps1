<#
  instalar_ferramentas.ps1 - Instala WSL 2, Docker Desktop, Python e Minikube no Windows 11.

  Execute UMA vez, em um PowerShell aberto como ADMINISTRADOR, na pasta do projeto:
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
      .\instalar_ferramentas.ps1

  Ferramentas que já existirem são mantidas. Ao final, reinicie o computador,
  abra o Docker Desktop uma vez (aceite os termos e espere "Engine running")
  e só então rode o .\rodar_tudo.ps1 em um PowerShell comum.
#>
$ErrorActionPreference = 'Continue'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Abra o PowerShell como administrador (botão direito > Executar como administrador) e rode de novo.' -ForegroundColor Red
    exit 1
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'O winget não foi encontrado. Atualize o "Instalador de Aplicativo" na Microsoft Store ou siga o guia em PDF.' -ForegroundColor Red
    exit 1
}

function Passo([string]$Texto) { Write-Host ''; Write-Host "==> $Texto" -ForegroundColor Green }
$comuns = @('--exact', '--accept-package-agreements', '--accept-source-agreements', '--silent')

Passo 'WSL 2 (necessário para o Docker Desktop)'
wsl --install --no-distribution
wsl --update
wsl --set-default-version 2

Passo 'Docker Desktop'
if (Get-Command docker -ErrorAction SilentlyContinue) { Write-Host 'Já instalado.' }
else { winget install --id Docker.DockerDesktop @comuns }

Passo 'Python 3.12'
& python --version *> $null
if ($LASTEXITCODE -eq 0) { Write-Host "Já instalado: $(& python --version)" }
else {
    winget install --id Python.Python.3.12 --exact --accept-package-agreements --accept-source-agreements `
        --override '/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1'
}

Passo 'Minikube'
if (Get-Command minikube -ErrorAction SilentlyContinue) { Write-Host 'Já instalado.' }
else { winget install --id Kubernetes.minikube @comuns }

Write-Host ''
Write-Host 'Pronto. Agora:' -ForegroundColor Green
Write-Host '  1. Reinicie o computador.'
Write-Host '  2. Abra o Docker Desktop, aceite os termos e espere aparecer "Engine running".'
Write-Host '     Em Settings > General deixe marcado "Use the WSL 2 based engine".'
Write-Host '     NÃO habilite o Kubernetes do Docker Desktop.'
Write-Host '  3. Abra um PowerShell comum na pasta do projeto e rode:'
Write-Host '       Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass'
Write-Host '       .\rodar_tudo.ps1'
