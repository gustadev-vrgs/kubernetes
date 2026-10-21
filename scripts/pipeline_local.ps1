# Execucao nativa no PowerShell. A implementacao compartilhada esta em Python.
$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'pipeline_local.py') @args
exit $LASTEXITCODE
