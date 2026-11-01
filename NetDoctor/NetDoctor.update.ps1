# NetDoctor - atualizacoes pelo GitHub Releases: verificar, ver novidades/melhorias/correcoes, baixar e instalar.
# Seguranca: a instalacao so acontece com clique do usuario, confere o SHA256 publicado na versao, guarda backup dos
# arquivos atuais e restaura tudo se a copia falhar. Nada baixado e executado: so arquivos do proprio NetDoctor sao trocados.

function ConvertTo-VersionObj([string]$tag) {
    $t = ([string]$tag).Trim().TrimStart('v', 'V')
    $m = [regex]::Match($t, '^\d+(\.\d+){1,3}')
    if (-not $m.Success) { return $null }
    try { return [version]$m.Value } catch { return $null }
}

# Le as ultimas versoes publicadas (sem login; o GitHub limita consultas anonimas por hora).
$script:UpdCheckCode = {
    $ErrorActionPreference = 'Stop'
    $fila = $Q
    $r = @{ Kind = 'upd-info'; Ok = $false; Msg = ''; Releases = @() }
    try {
        Add-Type -AssemblyName System.Net.Http
        $hc = New-Object System.Net.Http.HttpClient
        $hc.Timeout = [TimeSpan]::FromSeconds(15)
        $hc.DefaultRequestHeaders.UserAgent.ParseAdd('NetDoctor-Updater')
        $hc.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
        $resp = $hc.GetAsync($Url).Result
        $codigo = [int]$resp.StatusCode
        $corpo = $resp.Content.ReadAsStringAsync().Result
        $hc.Dispose()
        if ($codigo -eq 404) { $r.Msg = 'Nenhuma versão publicada no GitHub ainda (ou o repositório é privado).' }
        elseif ($codigo -eq 403) { $r.Msg = 'O GitHub limitou as consultas por agora. Tente de novo mais tarde.' }
        elseif ($codigo -ne 200) { $r.Msg = ('O GitHub respondeu com o código {0}.' -f $codigo) }
        else {
            $lista = @()
            foreach ($x in @($corpo | ConvertFrom-Json)) {
                if ($x.draft -or $x.prerelease) { continue }
                $zip = $null
                foreach ($a in @($x.assets)) { if ([string]$a.name -like '*.zip') { $zip = $a; break } }
                $sha = ''
                if ([string]$x.body -match '(?i)sha-?256\s*[:=]\s*([0-9a-f]{64})') { $sha = $Matches[1].ToLower() }
                elseif ($zip -and [string]$zip.digest -match '^sha256:([0-9a-fA-F]{64})$') { $sha = $Matches[1].ToLower() }
                $dt = ''
                try { $dt = ([datetime]$x.published_at).ToString('dd/MM/yyyy') } catch { }
                $zu = ''; if ($zip) { $zu = [string]$zip.browser_download_url }
                $lista += , @{ Tag = [string]$x.tag_name; Nome = [string]$x.name; Body = [string]$x.body; Url = [string]$x.html_url; Data = $dt; ZipUrl = $zu; Sha = $sha; Ver = $null }
            }
            $r.Releases = $lista; $r.Ok = $true
            if ($lista.Count -eq 0) { $r.Msg = 'Nenhuma versão publicada ainda.' }
        }
    } catch { $r.Msg = 'Não foi possível consultar o GitHub: ' + $_.Exception.Message }
    $fila.Enqueue($r)
}

# Baixa o pacote com progresso e calcula o SHA256.
$script:UpdDownloadCode = {
    $ErrorActionPreference = 'Stop'
    $fila = $Q
    $r = @{ Kind = 'upd-downloaded'; Ok = $false; Msg = ''; Path = $Dest; Sha = '' }
    try {
        Add-Type -AssemblyName System.Net.Http
        $hc = New-Object System.Net.Http.HttpClient
        $hc.Timeout = [TimeSpan]::FromMinutes(5)
        $hc.DefaultRequestHeaders.UserAgent.ParseAdd('NetDoctor-Updater')
        $resp = $hc.GetAsync($ZipUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        if (-not $resp.IsSuccessStatusCode) { throw ('HTTP ' + [int]$resp.StatusCode) }
        $total = $resp.Content.Headers.ContentLength
        $entrada = $resp.Content.ReadAsStreamAsync().Result
        $saida = [System.IO.File]::Create($Dest)
        $buf = New-Object byte[] 65536
        $lido = 0L; $ult = [datetime]::Now
        while (($n = $entrada.Read($buf, 0, $buf.Length)) -gt 0) {
            $saida.Write($buf, 0, $n); $lido += $n
            if (([datetime]::Now - $ult).TotalMilliseconds -gt 300) {
                $ult = [datetime]::Now
                $pct = 0; if ($total) { $pct = [int](100 * $lido / $total) }
                $fila.Enqueue(@{ Kind = 'upd-prog'; Pct = $pct; Bytes = $lido })
            }
        }
        $saida.Close(); $entrada.Close(); $hc.Dispose()
        $alg = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($Dest)
        $r.Sha = (($alg.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) -join '')
        $fs.Close()
        $r.Ok = $true
    } catch { $r.Msg = $_.Exception.Message }
    $fila.Enqueue($r)
}

# Converte as notas da versao (markdown simples) em linhas coloridas para a tela.
function Convert-NotesToLines([string]$body) {
    $out = @()
    $vazio = $false
    foreach ($ln in ([string]$body -split "`r?`n")) {
        if ($ln -match '(?i)sha-?256\s*[:=]') { continue }
        $t = $ln.TrimEnd()
        if ($t -match '^\s*#+\s*(.+)$') {
            $h = $Matches[1].Trim()
            $cor = 'Cyan'
            if ($h -match '(?i)corre|bug') { $cor = 'Yellow' } elseif ($h -match '(?i)novidade') { $cor = 'Green' }
            $out += @{ T = $h; C = $cor }; $vazio = $false; continue
        }
        if ($t -match '^\s*[-*]\s+(.*)$') { $t = '  • ' + $Matches[1] }
        $t = $t -replace '\*\*', ''
        if ($t.Trim() -eq '') { if (-not $vazio) { $out += @{ T = ''; C = 'Gray' } }; $vazio = $true; continue }
        $vazio = $false
        $out += @{ T = $t; C = 'Gray' }
    }
    $out
}

# Instala o pacote ja conferido: extrai, guarda backup, copia e restaura se algo falhar.
function Install-Update([string]$zip) {
    $res = @{ Ok = $false; Msg = ''; Backup = '' }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('NetDoctor-upd-' + [guid]::NewGuid().ToString('N'))
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
        $alvo = Get-ChildItem -Path $tmp -Filter 'NetDoctor.ps1' -Recurse -File | Select-Object -First 1
        if (-not $alvo) { $res.Msg = 'O pacote baixado não contém o NetDoctor.ps1.'; return $res }
        $pacote = $alvo.DirectoryName
        foreach ($f in @('NetDoctor.ps1', 'NetDoctor.engine.ps1', 'NetDoctor.bg.ps1')) {
            if (-not (Test-Path (Join-Path $pacote $f))) { $res.Msg = ('Arquivo ausente no pacote: ' + $f); return $res }
        }
        $backup = Join-Path (Get-AppDir) ('backup-v' + $script:AppVersion + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        $feitos = @()
        try {
            foreach ($a in @(Get-ChildItem -Path $pacote -Recurse -File)) {
                $rel = $a.FullName.Substring($pacote.Length).TrimStart('\', '/')
                $dest = Join-Path $PSScriptRoot $rel
                $dir = Split-Path $dest -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                if (Test-Path $dest) {
                    $b = Join-Path $backup $rel
                    $bd = Split-Path $b -Parent
                    if (-not (Test-Path $bd)) { New-Item -ItemType Directory -Path $bd -Force | Out-Null }
                    Copy-Item -Path $dest -Destination $b -Force
                }
                Copy-Item -Path $a.FullName -Destination $dest -Force
                $feitos += $rel
            }
        } catch {
            foreach ($rel in $feitos) {
                $b = Join-Path $backup $rel
                if (Test-Path $b) { Copy-Item -Path $b -Destination (Join-Path $PSScriptRoot $rel) -Force }
            }
            $res.Msg = 'Falha ao copiar os arquivos: ' + $_.Exception.Message + ' (os arquivos anteriores foram restaurados)'
            return $res
        }
        $res.Ok = $true; $res.Backup = $backup
        try { Get-ChildItem -Path (Get-AppDir) -Directory -Filter 'backup-v*' | Sort-Object CreationTime -Descending | Select-Object -Skip 3 | Remove-Item -Recurse -Force } catch { }
    } catch { $res.Msg = $_.Exception.Message }
    finally { try { Remove-Item -Path $tmp -Recurse -Force } catch { } }
    $res
}
