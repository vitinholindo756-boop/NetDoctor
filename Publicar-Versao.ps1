# Publicar-Versao.ps1 - SOMENTE PARA O DONO DO PROJETO (nao vai para os usuarios).
#
# Coloque este arquivo na raiz do repositorio, ao lado da pasta NetDoctor, e rode:
#   powershell -ExecutionPolicy Bypass -File .\Publicar-Versao.ps1 -Versao 1.1.0
#
# O que ele faz:
#   1) troca a versao dentro do NetDoctor.engine.ps1;
#   2) gera o NetDoctor.zip com a pasta NetDoctor;
#   3) calcula o SHA256 do zip (o NetDoctor dos usuarios confere esse codigo antes de instalar);
#   4) cria o modelo das notas da versao (notas-v1.1.0.md) ja com a linha do SHA256.
# Depois voce edita as notas (Novidades, Melhorias, Correcoes) e publica a Release no GitHub.
param(
    [Parameter(Mandatory = $true)][string]$Versao,
    [string]$Pasta = 'NetDoctor'
)
$ErrorActionPreference = 'Stop'
if ($Versao -notmatch '^\d+\.\d+\.\d+$') { throw 'Use o formato 1.2.3 (tres numeros).' }
$raiz = $PSScriptRoot
$src = Join-Path $raiz $Pasta
$engine = Join-Path $src 'NetDoctor.engine.ps1'
if (-not (Test-Path $engine)) { throw ('Nao encontrei ' + $engine + '. Coloque este script ao lado da pasta ' + $Pasta + '.') }

# 1) versao no codigo
$txt = [System.IO.File]::ReadAllText($engine)
$padrao = '(\$script:AppVersion\s*=\s*'')[^'']*('')'
if ($txt -notmatch $padrao) { throw 'Nao encontrei $script:AppVersion no NetDoctor.engine.ps1.' }
$txt = [regex]::Replace($txt, $padrao, ('${1}' + $Versao + '${2}'))
[System.IO.File]::WriteAllText($engine, $txt, (New-Object System.Text.UTF8Encoding($true)))

# 2) zip (com a pasta NetDoctor dentro)
$zip = Join-Path $raiz 'NetDoctor.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($src, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)

# 3) SHA256
$hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()

# 4) modelo das notas
$notas = Join-Path $raiz ('notas-v' + $Versao + '.md')
$modelo = @"
## Novidades
- 

## Melhorias
- 

## Correções
- 

SHA256: $hash
"@
[System.IO.File]::WriteAllText($notas, $modelo, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ('Versao {0} preparada.' -f $Versao) -ForegroundColor Green
Write-Host ('  Pacote : ' + $zip)
Write-Host ('  SHA256 : ' + $hash)
Write-Host ('  Notas  : ' + $notas)
Write-Host ''
Write-Host 'Proximos passos:' -ForegroundColor Cyan
Write-Host ('  1. Abra {0} e escreva o que mudou (mantenha a linha SHA256).' -f (Split-Path $notas -Leaf))
Write-Host '  2. Envie o codigo com a nova versao: git add . ; git commit -m "versao" ; git push'
Write-Host ('  3. No GitHub: Releases > Draft a new release > Tag v{0} (alvo: main) > cole as notas > anexe o NetDoctor.zip > Publish release.' -f $Versao)
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host '  (ou, com o GitHub CLI instalado, depois de editar as notas:)'
    Write-Host ('  gh release create v{0} "{1}" --title "NetDoctor v{0}" --notes-file "{2}"' -f $Versao, $zip, $notas)
}
Write-Host ''
Write-Host 'Atencao: se rodar este script de novo, o zip e gerado outra vez e o SHA256 muda; atualize a linha nas notas.' -ForegroundColor Yellow
