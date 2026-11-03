# NetDoctor - analise de Wi-Fi: sua conexao (sinal, canal, tipo) e as redes vizinhas por canal.
# Usa o netsh do Windows (somente leitura). Os rotulos do netsh mudam com o idioma do Windows (portugues, ingles, espanhol);
# em outros idiomas a leitura pode vir incompleta. No Windows 11 recente, listar redes vizinhas exige o servico de Localizacao ligado.

$script:WifiCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    $fila = $Q
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $res = @{ Kind = 'wifi-info'; Ok = $false; Msg = ''; Own = $null; Nets = @() }
    try {
        $txt = (netsh wlan show interfaces 2>&1) | Out-String
        if ([string]::IsNullOrWhiteSpace($txt) -or $txt -match '(?i)no wireless interface|n[aã]o h[aá] nenhuma interface|no hay ninguna interfaz|wlansvc') {
            $res.Msg = 'Este PC não tem adaptador Wi-Fi ativo (ou o serviço WLAN está parado).'
            $fila.Enqueue($res); return
        }
        $own = @{ Ssid = ''; Bssid = ''; Estado = ''; Signal = $null; Channel = $null; Radio = ''; Auth = ''; Rx = $null; Tx = $null; Conectado = $false }
        if ($txt -match '(?m)^\s*SSID\s*:\s*(.+?)\s*$') { $own.Ssid = $Matches[1] }
        if ($txt -match '(?mi)^\s*BSSID\s*:\s*([0-9a-f:\-]{11,17})') { $own.Bssid = $Matches[1].ToLower() }
        if ($txt -match '(?mi)^\s*(State|Estado)\s*:\s*(.+?)\s*$') { $own.Estado = $Matches[2] }
        if ($own.Estado -match '(?i)^(connected|conectad[oa])$') { $own.Conectado = $true }
        if ($txt -match '(?mi)^\s*(Signal|Sinal|Señal)\s*:\s*(\d{1,3})\s*%') { $own.Signal = [int]$Matches[2] }
        if ($txt -match '(?mi)^\s*(Channel|Canal)\s*:\s*(\d+)\s*$') { $own.Channel = [int]$Matches[2] }
        if ($txt -match '(?mi)^\s*(Radio type|Tipo de rádio|Tipo de radio)\s*:\s*(.+?)\s*$') { $own.Radio = $Matches[2] }
        if ($txt -match '(?mi)^\s*(Authentication|Autenticação|Autenticación)\s*:\s*(.+?)\s*$') { $own.Auth = $Matches[2] }
        $taxas = [regex]::Matches($txt, '(?mi)^\s*[^:\r\n]*\(Mbps\)\s*:\s*([\d.,]+)')
        if ($taxas.Count -ge 1) { $own.Rx = [double]::Parse($taxas[0].Groups[1].Value.Replace(',', '.'), $inv) }
        if ($taxas.Count -ge 2) { $own.Tx = [double]::Parse($taxas[1].Groups[1].Value.Replace(',', '.'), $inv) }
        $res.Own = $own

        $txt2 = (netsh wlan show networks mode=bssid 2>&1) | Out-String
        $nets = New-Object System.Collections.ArrayList
        $cur = $null; $ssid = ''
        foreach ($ln in ($txt2 -split "`r?`n")) {
            if ($ln -match '^\s*SSID\s+\d+\s*:\s*(.*)$') { $ssid = $Matches[1].Trim(); continue }
            if ($ln -match '^\s*BSSID\s+\d+\s*:\s*([0-9A-Fa-f:\-]{11,17})') {
                $cur = @{ Ssid = $ssid; Bssid = $Matches[1].ToLower(); Signal = $null; Channel = $null; Radio = '' }
                [void]$nets.Add($cur); continue
            }
            if ($cur) {
                if ($ln -match '(?i)^\s*(Signal|Sinal|Señal)\s*:\s*(\d+)\s*%') { $cur.Signal = [int]$Matches[2] }
                elseif ($ln -match '(?i)^\s*(Channel|Canal)\s*:\s*(\d+)\s*$') { $cur.Channel = [int]$Matches[2] }
                elseif ($ln -match '(?i)^\s*(Radio type|Tipo de rádio|Tipo de radio)\s*:\s*(.+?)\s*$') { $cur.Radio = $Matches[2] }
            }
        }
        $res.Nets = $nets.ToArray()
        $res.Ok = $true
        if ($nets.Count -eq 0) { $res.Msg = 'Não consegui listar as redes vizinhas. No Windows 11 recente, ligue a Localização (Configurações > Privacidade > Localização) e tente de novo.' }
    } catch { $res.Msg = 'Erro ao ler o Wi-Fi: ' + $_.Exception.Message }
    $fila.Enqueue($res)
}

function Get-WifiBand($canal) {
    if ($null -eq $canal) { return '-' }
    if ([int]$canal -le 14) { return '2,4 GHz' }
    '5 GHz ou mais'
}

# Analise: redes por canal, interferencia, canal sugerido e leitura do sinal. Criterios simples e explicados na tela.
function Get-WifiAnalysis($own, $nets) {
    $r = @{ Canais = @(); Linhas = @(); Nivel = 'ok' }
    $outras = @()
    foreach ($n in @($nets)) {
        if ($null -eq $n.Channel) { continue }
        if ($own -and $own.Bssid -and [string]$n.Bssid -eq [string]$own.Bssid) { continue }
        $outras += $n
    }
    $score = @{}
    for ($c = 1; $c -le 13; $c++) {
        $s = 0.0
        foreach ($n in $outras) {
            if ([int]$n.Channel -le 14) {
                $d = [math]::Abs([int]$n.Channel - $c)
                if ($d -le 4) { $s += ([double]$n.Signal / 100.0) * (1.0 - $d / 5.0) }
            }
        }
        $score[$c] = [math]::Round($s, 2)
    }
    $porCanal = @{}
    foreach ($n in $outras) {
        $c = [int]$n.Channel
        if (-not $porCanal.ContainsKey($c)) { $porCanal[$c] = @{ N = 0; Max = 0 } }
        $porCanal[$c].N = $porCanal[$c].N + 1
        if ([int]$n.Signal -gt $porCanal[$c].Max) { $porCanal[$c].Max = [int]$n.Signal }
    }
    foreach ($c in @(1, 6, 11)) { if (-not $porCanal.ContainsKey($c)) { $porCanal[$c] = @{ N = 0; Max = 0 } } }
    $linhas = @()
    foreach ($c in @($porCanal.Keys | Sort-Object)) {
        $n = $porCanal[$c].N
        $nivel = 'baixa'
        if ($c -le 13) {
            if ($score[$c] -ge 2.0) { $nivel = 'alta' } elseif ($score[$c] -ge 0.8) { $nivel = 'média' }
        } else {
            if ($n -ge 4) { $nivel = 'alta' } elseif ($n -ge 2) { $nivel = 'média' }
        }
        $obs = ''
        if ($own -and $own.Channel -eq $c) { $obs = 'seu canal' }
        elseif ($c -in @(1, 6, 11)) { $obs = 'canal sem sobreposição (2,4 GHz)' }
        $linhas += @{ Canal = $c; Faixa = (Get-WifiBand $c); Redes = $n; Max = $porCanal[$c].Max; Nivel = $nivel; Obs = $obs }
    }
    $r.Canais = $linhas
    $t = @()
    if ($own -and $own.Conectado -and $null -ne $own.Signal) {
        $sig = [int]$own.Signal
        $q = 'muito fraco'; $r.Nivel = 'bad'
        if ($sig -ge 70) { $q = 'ótimo'; $r.Nivel = 'ok' } elseif ($sig -ge 50) { $q = 'bom'; $r.Nivel = 'ok' } elseif ($sig -ge 30) { $q = 'fraco'; $r.Nivel = 'warn' }
        $t += ('Sinal da sua rede: {0}% ({1}).' -f $sig, $q)
        if ($sig -lt 50) { $t += 'Aproxime-se do roteador, tire obstáculos (paredes, espelhos, micro-ondas) ou teste por cabo para comparar.' }
        if ($null -ne $own.Channel) {
            if ([int]$own.Channel -le 14) {
                $melhor = 1; foreach ($c in @(6, 11)) { if ($score[$c] -lt $score[$melhor]) { $melhor = $c } }
                $meu = $score[[int]$own.Channel]
                if ($melhor -ne [int]$own.Channel -and ($score[$melhor] + 0.5) -lt $meu) {
                    $t += ('Seu canal {0} (2,4 GHz) tem interferência {1}. Sugestão: troque para o canal {2} no painel do roteador.' -f $own.Channel, $(if ($meu -ge 2.0) { 'alta' } else { 'média' }), $melhor)
                    if ($r.Nivel -eq 'ok') { $r.Nivel = 'warn' }
                } else { $t += ('Seu canal {0} (2,4 GHz) está numa situação aceitável em relação às redes vizinhas.' -f $own.Channel) }
                $t += 'Se o roteador tem 5 GHz, use essa rede quando estiver perto dele: é mais rápida e menos congestionada.'
            } else {
                $mesmo = 0; if ($porCanal.ContainsKey([int]$own.Channel)) { $mesmo = $porCanal[[int]$own.Channel].N }
                $melhor = $null; $melhorN = 999
                foreach ($c in @(36, 40, 44, 48, 149, 153, 157, 161)) {
                    $nn = 0; if ($porCanal.ContainsKey($c)) { $nn = $porCanal[$c].N }
                    if ($nn -lt $melhorN) { $melhorN = $nn; $melhor = $c }
                }
                if ($mesmo -ge 3 -and $melhor) { $t += ('Há {0} outras redes no seu canal {1} (5 GHz). Sugestão: canal {2}, que está mais livre.' -f $mesmo, $own.Channel, $melhor); if ($r.Nivel -eq 'ok') { $r.Nivel = 'warn' } }
                else { $t += ('Seu canal {0} (5 GHz) tem pouca concorrência.' -f $own.Channel) }
            }
        }
    } else { $t += 'Você não está conectado a uma rede Wi-Fi neste momento.' }
    $r.Linhas = $t
    $r
}
