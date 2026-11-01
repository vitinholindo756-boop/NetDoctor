# NetDoctor - inteligencia da conexao: notas de qualidade, velocidade x plano (metas da Anatel), historico,
# alertas, rota por salto, assistente e relatorio. Tudo somente leitura (nada altera o PC).
# As leituras lentas rodam em segundo plano; os resultados chegam pela fila $Q.

# ------------------------------------------------------------ biblioteca de testes (processo e segundo plano)
# Usada pelo Diagnostico e pelo Assistente. Os nomes de variaveis evitam colidir com $Q (o PowerShell ignora maiusculas).
$script:NetTestLib = @'
function Fmt($x, [int]$dec = 1) {
    if ($null -eq $x) { return '-' }
    $f = '0'
    if ($dec -gt 0) { $f = '0.' + ('0' * $dec) }
    ([double]$x).ToString($f, [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
}
function Resumo($ms, [int]$perd, [int]$n) {
    $o = [ordered]@{ Enviados = $n; Perdidos = $perd; Pct = [math]::Round($perd / [math]::Max($n, 1) * 100, 1); Min = $null; Media = $null; Max = $null; Jitter = $null }
    if ($ms.Count -gt 0) {
        $o.Min = ($ms | Measure-Object -Minimum).Minimum
        $o.Media = [math]::Round(($ms | Measure-Object -Average).Average, 1)
        $o.Max = ($ms | Measure-Object -Maximum).Maximum
    }
    if ($ms.Count -ge 2) {
        $soma = 0.0
        for ($j = 1; $j -lt $ms.Count; $j++) { $soma += [math]::Abs($ms[$j] - $ms[$j - 1]) }
        $o.Jitter = [math]::Round($soma / ($ms.Count - 1), 1)
    }
    [pscustomobject]$o
}
function PingN([string]$dest, [int]$n, [int]$espera) {
    $p = New-Object System.Net.NetworkInformation.Ping
    $ms = New-Object 'System.Collections.Generic.List[double]'
    $perd = 0
    for ($i = 0; $i -lt $n; $i++) {
        try {
            $r = $p.Send($dest, 2000)
            if ($r.Status -eq 'Success') { $ms.Add($r.RoundtripTime) } else { $perd++ }
        } catch { $perd++ }
        Start-Sleep -Milliseconds $espera
    }
    Resumo $ms $perd $n
}
function TcpN([string]$dest, [int]$porta, [int]$n, [int]$espera) {
    $ms = New-Object 'System.Collections.Generic.List[double]'
    $falhas = 0; $picos = 0
    for ($i = 0; $i -lt $n; $i++) {
        $c = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $t = $c.ConnectAsync($dest, $porta)
            if ($t.Wait(3000) -and $c.Connected) {
                $v = $sw.Elapsed.TotalMilliseconds
                $ms.Add($v)
                if ($v -ge 150) { $picos++ }
            } else { $falhas++ }
        } catch { $falhas++ } finally { $c.Close() }
        Start-Sleep -Milliseconds $espera
    }
    $r = Resumo $ms $falhas $n
    $r | Add-Member -NotePropertyName Picos -NotePropertyValue $picos -PassThru
}
# Transferencia (download/upload) com varias conexoes ao mesmo tempo, medindo o ping durante a carga.
# $mb = megabytes por conexao. Usa a variavel $PingExterno do chamador.
function Carga([string]$tipo, [string]$url, [int]$vezes, [int]$mb) {
    $vel = @()
    $lat = New-Object 'System.Collections.Generic.List[double]'
    $perd = 0; $n = 0
    $pg = New-Object System.Net.NetworkInformation.Ping
    $par = 4; if ($tipo -eq 'up') { $par = 3 }
    $dados = $null
    if ($tipo -eq 'up') { $dados = [byte[]]::new($mb * 1000000) }
    $hc = New-Object System.Net.Http.HttpClient
    $hc.Timeout = [TimeSpan]::FromSeconds(90)
    for ($i = 0; $i -lt $vezes; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tasks = @()
        for ($k = 0; $k -lt $par; $k++) {
            if ($tipo -eq 'down') { $tasks += , $hc.GetByteArrayAsync($url) }
            else {
                $conteudo = New-Object System.Net.Http.ByteArrayContent -ArgumentList (, $dados)
                $tasks += , $hc.PostAsync($url, $conteudo)
            }
        }
        while ($true) {
            $pend = 0
            foreach ($tk in $tasks) { if (-not $tk.IsCompleted) { $pend++ } }
            if ($pend -eq 0) { break }
            if ($sw.Elapsed.TotalSeconds -gt 40) { $hc.CancelPendingRequests(); break }
            $n++
            try {
                $rp = $pg.Send($PingExterno, 2000)
                if ($rp.Status -eq 'Success') { $lat.Add($rp.RoundtripTime) } else { $perd++ }
            } catch { $perd++ }
            Start-Sleep -Milliseconds 30
        }
        $sw.Stop()
        $bytes = 0.0
        foreach ($tk in $tasks) {
            if ($tk.IsCompleted -and -not $tk.IsFaulted -and -not $tk.IsCanceled) {
                if ($tipo -eq 'down') { $bytes += $tk.Result.Length }
                elseif ($tk.Result.IsSuccessStatusCode) { $bytes += $dados.Length }
            }
        }
        if ($bytes -gt 0) { $vel += [math]::Round(($bytes * 8 / 1000000) / $sw.Elapsed.TotalSeconds, 1) } else { $vel += 0 }
    }
    $hc.Dispose()
    $melhor = ($vel | Measure-Object -Maximum).Maximum
    [pscustomobject]@{ Melhor = $melhor; Rodadas = ($vel -join ' / '); Ping = (Resumo $lat $perd ([math]::Max($n, 1))) }
}

# Consulta DNS direta (UDP 53) com tempo limite. Retorna ms ou -1.
function Query-Dns([string]$servidor, [string]$nome, [int]$limiteMs) {
    $idq = Get-Random -Maximum 65535
    $pk = New-Object 'System.Collections.Generic.List[byte]'
    $pk.Add([byte]($idq -shr 8)); $pk.Add([byte]($idq -band 255))
    $pk.AddRange([byte[]](1, 0, 0, 1, 0, 0, 0, 0, 0, 0))
    foreach ($lbl in $nome.Split('.')) {
        $bl = [System.Text.Encoding]::ASCII.GetBytes($lbl)
        $pk.Add([byte]$bl.Length); $pk.AddRange($bl)
    }
    $pk.Add(0)
    $pk.AddRange([byte[]](0, 1, 0, 1))
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = $limiteMs
        $udp.Connect($servidor, 53)
        $cron = [System.Diagnostics.Stopwatch]::StartNew()
        [void]$udp.Send($pk.ToArray(), $pk.Count)
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $udp.Receive([ref]$ep)
        $cron.Stop()
        if ($resp.Length -ge 12 -and $resp[0] -eq $pk[0] -and $resp[1] -eq $pk[1] -and (($resp[3] -band 15) -eq 0) -and ((($resp[6] * 256) + $resp[7]) -gt 0)) { return $cron.Elapsed.TotalMilliseconds }
        return -1.0
    } catch { return -1.0 } finally { $udp.Close() }
}

# Nota de bufferbloat pela alta do ping sob carga: A < 5 ms, B < 30, C < 60, D < 200, F a partir de 200.
function Get-BloatGrade($parado, $cargaDown, $cargaUp) {
    if ($null -eq $parado) { return $null }
    $maior = $null
    foreach ($v in @($cargaDown, $cargaUp)) {
        if ($null -ne $v) {
            $dl = [double]$v - [double]$parado
            if ($null -eq $maior -or $dl -gt $maior) { $maior = $dl }
        }
    }
    if ($null -eq $maior) { return $null }
    if ($maior -lt 0) { $maior = 0 }
    $nota = 'F'
    if ($maior -lt 5) { $nota = 'A' } elseif ($maior -lt 30) { $nota = 'B' } elseif ($maior -lt 60) { $nota = 'C' } elseif ($maior -lt 200) { $nota = 'D' }
    @{ Grade = $nota; Delta = [math]::Round($maior, 0) }
}
'@
. ([scriptblock]::Create($script:NetTestLib))

# ------------------------------------------------------------ plano contratado e notas de qualidade
function Convert-PlanToMbps([string]$txt) {
    if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
    $m = [regex]::Match($txt.ToLower(), '(\d+(?:[.,]\d+)?)\s*(giga|gbps|gb|g|mega|mbps|mb|m)?')
    if (-not $m.Success) { return $null }
    $n = [double]::Parse($m.Groups[1].Value.Replace(',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
    if ($m.Groups[2].Value -like 'g*') { $n = $n * 1000 }
    if ($n -le 0) { return $null }
    $n
}

function ToD($s) {
    if ($null -eq $s -or [string]$s -eq '') { return $null }
    $r = 0.0
    if ([double]::TryParse([string]$s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$r)) { return $r }
    $null
}

function NumInv($x) {
    if ($null -eq $x) { return '' }
    ([double]$x).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
}

# nivel 3 = Otimo, 2 = Bom, 1 = Regular, 0 = Ruim (menor e melhor; limites t3 < t2 < t1)
function Get-LvLow($v, $t3, $t2, $t1) {
    if ($null -eq $v) { return $null }
    if ($v -le $t3) { return 3 }
    if ($v -le $t2) { return 2 }
    if ($v -le $t1) { return 1 }
    0
}

# maior e melhor
function Get-LvHigh($v, $t3, $t2, $t1) {
    if ($null -eq $v) { return $null }
    if ($v -ge $t3) { return 3 }
    if ($v -ge $t2) { return 2 }
    if ($v -ge $t1) { return 1 }
    0
}

function Get-LvName($n) {
    switch ($n) { 3 { return 'Ótimo' } 2 { return 'Bom' } 1 { return 'Regular' } 0 { return 'Ruim' } default { return '-' } }
}

# Notas do Diagnostico. Criterios nossos (heuristicas simples e documentadas abaixo), nao um padrao oficial.
function Get-QualityScores($meta, [string]$plano) {
    $r = @{ Bloat = $null; Itens = New-Object System.Collections.ArrayList; PlanMbps = $null; PlanPct = $null; Texto = '' }
    $get = { param($k) if ($meta.ContainsKey($k)) { $meta[$k] } else { $null } }
    $idle = & $get 'Idle'; $ld = & $get 'LoadDown'; $lu = & $get 'LoadUp'
    $jit = & $get 'Jitter'; $loss = & $get 'Loss'; $down = & $get 'Down'; $up = & $get 'Up'
    $bl = Get-BloatGrade $idle $ld $lu
    $r.Bloat = $bl
    $bloatLv = $null
    if ($bl) { $bloatLv = @{ 'A' = 3; 'B' = 3; 'C' = 2; 'D' = 1; 'F' = 0 }[$bl.Grade] }
    $fonte = @{
        'Jogos'      = @((Get-LvLow $idle 40 80 120), (Get-LvLow $jit 8 15 30), (Get-LvLow $loss 0 0.5 2), $bloatLv)
        'Chamadas'   = @((Get-LvLow $idle 100 150 250), (Get-LvLow $jit 15 30 50), (Get-LvLow $loss 0.5 1 3), (Get-LvHigh $up 3 1.5 0.5), $bloatLv)
        'Streaming'  = @((Get-LvHigh $down 25 8 3), (Get-LvLow $loss 0.5 2 5))
        'Navegação'  = @((Get-LvLow $idle 100 200 400), (Get-LvHigh $down 10 3 1), (Get-LvLow $loss 1 3 8))
    }
    foreach ($k in @('Jogos', 'Chamadas', 'Streaming', 'Navegação')) {
        $vals = @($fonte[$k] | Where-Object { $null -ne $_ })
        if ($vals.Count -eq 0) { [void]$r.Itens.Add(@{ Nome = $k; Nivel = $null; Nome2 = '-' }); continue }
        $pior = ($vals | Measure-Object -Minimum).Minimum
        [void]$r.Itens.Add(@{ Nome = $k; Nivel = [int]$pior; Nome2 = (Get-LvName $pior) })
    }
    $pm = Convert-PlanToMbps $plano
    if ($pm -and $null -ne $down) { $r.PlanMbps = $pm; $r.PlanPct = [math]::Round([double]$down / $pm * 100, 0) }
    $t = @()
    if ($bl) { $t += ('Bufferbloat: {0} (+{1} ms sob carga)' -f $bl.Grade, $bl.Delta) }
    foreach ($i in $r.Itens) { if ($null -ne $i.Nivel) { $t += ('{0}: {1}' -f $i.Nome, $i.Nome2) } }
    if ($null -ne $r.PlanPct) { $t += ('Velocidade: {0} de {1} Mbps ({2}% do plano)' -f (NumInv $down), (NumInv $pm), $r.PlanPct) }
    $r.Texto = ($t -join '   |   ')
    $r
}

# ------------------------------------------------------------ historico de velocidade e metas da Anatel
function Get-SpeedHistPath { Join-Path (Get-AppDir) 'historico-velocidade.csv' }

function Add-SpeedHistory($meta, $planMbps) {
    try {
        if (-not $meta.ContainsKey('Down')) { return }
        $p = Get-SpeedHistPath
        $utf = New-Object System.Text.UTF8Encoding($false)
        if (-not (Test-Path $p)) { [System.IO.File]::WriteAllText($p, "DataHora,DownMbps,UpMbps,IdleMs,LoadDownMs,LoadUpMs,PlanoMbps,JitterMs,PerdaPct`r`n", $utf) }
        $g = { param($k) if ($meta.ContainsKey($k)) { NumInv $meta[$k] } else { '' } }
        $linha = ('{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (& $g 'Down'), (& $g 'Up'), (& $g 'Idle'), (& $g 'LoadDown'), (& $g 'LoadUp'), (NumInv $planMbps), (& $g 'Jitter'), (& $g 'Loss'))
        [System.IO.File]::AppendAllText($p, $linha + "`r`n", $utf)
    } catch { Log-Error $_ }
}

function Read-SpeedHistory {
    $p = Get-SpeedHistPath
    if (-not (Test-Path $p)) { return @() }
    try { @(Import-Csv -Path $p -Encoding UTF8) } catch { @() }
}

# Metas citadas pela imprensa para banda larga fixa: media mensal >= 80% do contratado e velocidade instantanea >= 40%.
# Aqui e so um indicativo com a medicao deste PC ate a Cloudflare, nao a medicao oficial da Anatel.
function Get-AnatelSummary($planMbps) {
    $r = @{ N = 0; MediaPct = $null; MinPct = $null; Abaixo40 = 0; Linhas = @() }
    if (-not $planMbps) { return $r }
    $ini = (Get-Date).Date.AddDays(1 - (Get-Date).Day)
    $pcts = @()
    foreach ($row in (Read-SpeedHistory)) {
        $dt = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$row.DataHora, [ref]$dt)) { continue }
        if ($dt -lt $ini) { continue }
        $pl = ToD $row.PlanoMbps; $dn = ToD $row.DownMbps
        if ($null -eq $dn -or $null -eq $pl -or [math]::Abs($pl - $planMbps) -gt 0.5) { continue }
        $pcts += ($dn / $planMbps * 100)
    }
    $r.N = $pcts.Count
    if ($pcts.Count -eq 0) { return $r }
    $r.MediaPct = [math]::Round((($pcts | Measure-Object -Average).Average), 0)
    $r.MinPct = [math]::Round((($pcts | Measure-Object -Minimum).Minimum), 0)
    $r.Abaixo40 = @($pcts | Where-Object { $_ -lt 40 }).Count
    $l = @()
    $l += ('Média do mês: {0}% do plano de {1} Mbps (meta: 80%) em {2} teste(s).' -f $r.MediaPct, (NumInv $planMbps), $r.N)
    $l += ('Menor medição: {0}% (meta instantânea: 40%); {1} medição(ões) abaixo de 40%.' -f $r.MinPct, $r.Abaixo40)
    if ($r.N -lt 10) { $l += 'Poucos testes no mês: a média só fica confiável com muitos testes em dias e horários variados.' }
    $r.Linhas = $l
    $r
}

# ------------------------------------------------------------ historico do monitor (blocos de 5 minutos) e alertas
$script:HistBuckets = @{}
$script:RecentSamples = @{}
$script:AlertState = @{}

function Get-MonHistPath { Join-Path (Get-AppDir) 'historico-monitor.csv' }
function Get-EventsPath { Join-Path (Get-AppDir) 'eventos.csv' }

function Get-BucketStart([datetime]$t) {
    $m = [int]([math]::Floor($t.Minute / 5) * 5)
    [datetime]::new($t.Year, $t.Month, $t.Day, $t.Hour, $m, 0)
}

function Write-HistBucket([string]$name, $b) {
    try {
        $p = Get-MonHistPath
        $utf = New-Object System.Text.UTF8Encoding($false)
        if (-not (Test-Path $p)) { [System.IO.File]::WriteAllText($p, "Inicio,Alvo,Total,Falhas,Picos,SomaMs,OkN,MaxMs`r`n", $utf) }
        $linha = ('{0},{1},{2},{3},{4},{5},{6},{7}' -f $b.Start.ToString('yyyy-MM-dd HH:mm'), $name, $b.Total, $b.Falhas, $b.Picos, (NumInv $b.Soma), $b.OkN, (NumInv $b.Max))
        [System.IO.File]::AppendAllText($p, $linha + "`r`n", $utf)
    } catch { }
}

function Flush-HistBuckets {
    foreach ($k in @($script:HistBuckets.Keys)) { Write-HistBucket $k $script:HistBuckets[$k] }
    $script:HistBuckets = @{}
}

function Write-MonEvent([string]$alvo, [string]$tipo, [string]$detalhe) {
    try {
        $p = Get-EventsPath
        $utf = New-Object System.Text.UTF8Encoding($false)
        if (-not (Test-Path $p)) { [System.IO.File]::WriteAllText($p, "DataHora,Alvo,Tipo,Detalhe`r`n", $utf) }
        $l = ('{0},{1},{2},{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $alvo.Replace(',', ';'), $tipo, $detalhe.Replace(',', ';'))
        [System.IO.File]::AppendAllText($p, $l + "`r`n", $utf)
    } catch { }
}

# Chamada a cada amostra do monitor (ver Apply-Sample).
function Track-Sample($t, $s, [string]$status) {
    try {
        $name = ([string]$t.Nome).Replace(',', ';')
        $time = [datetime]$s.Time
        $bs = Get-BucketStart $time
        $b = $script:HistBuckets[$name]
        if ($b -and $b.Start -ne $bs) { Write-HistBucket $name $b; $b = $null }
        if (-not $b) {
            $b = @{ Start = $bs; Total = 0; Falhas = 0; Picos = 0; Soma = 0.0; OkN = 0; Max = 0.0 }
            $script:HistBuckets[$name] = $b
        }
        $b.Total = $b.Total + 1
        if ($status -eq 'FALHA') { $b.Falhas = $b.Falhas + 1 }
        else {
            $ms = [double]$s.Ms
            $b.OkN = $b.OkN + 1; $b.Soma = $b.Soma + $ms
            if ($ms -gt $b.Max) { $b.Max = $ms }
            if ($status -eq 'PICO') { $b.Picos = $b.Picos + 1 }
        }
        $rq = $script:RecentSamples[$name]
        if (-not $rq) { $rq = New-Object 'System.Collections.Generic.Queue[object]'; $script:RecentSamples[$name] = $rq }
        $rq.Enqueue(@($time.Ticks, ($status -ne 'OK')))
        $cut = $time.AddMinutes(-10).Ticks
        while ($rq.Count -gt 0 -and $rq.Peek()[0] -lt $cut) { [void]$rq.Dequeue() }
    } catch { }
}

# Alerta de degradacao sustentada (ideia dos monitores como o PingPlotter): porcentagem de problemas (falhas e picos)
# na janela recente acima do limite. Re-arma quando cai abaixo da metade do limite e espera 5 min entre alertas.
function Get-MonitorAlerts([double]$limitePct, [int]$janelaMin) {
    $alertas = @()
    $agora = [datetime]::Now
    $corte = $agora.AddMinutes(-$janelaMin).Ticks
    foreach ($k in @($script:RecentSamples.Keys)) {
        $n = 0; $ruins = 0
        foreach ($e in $script:RecentSamples[$k].ToArray()) {
            if ($e[0] -ge $corte) { $n++; if ($e[1]) { $ruins++ } }
        }
        if ($n -lt 20) { continue }
        $pct = $ruins / $n * 100
        $st = $script:AlertState[$k]
        if (-not $st) { $st = @{ Ativo = $false; Ultimo = [datetime]::MinValue }; $script:AlertState[$k] = $st }
        if (-not $st.Ativo -and $pct -ge $limitePct -and (($agora - $st.Ultimo).TotalMinutes -ge 5)) {
            $st.Ativo = $true; $st.Ultimo = $agora
            $alertas += @{ Nome = $k; Pct = [math]::Round($pct, 1); Tipo = 'problema'; Janela = $janelaMin }
        } elseif ($st.Ativo -and $pct -lt ($limitePct / 2)) {
            $st.Ativo = $false
            $alertas += @{ Nome = $k; Pct = [math]::Round($pct, 1); Tipo = 'recuperou'; Janela = $janelaMin }
        }
    }
    $alertas
}

# ------------------------------------------------------------ historico (leitura em segundo plano)
$script:HistCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    $fila = $Q
    $res = @{ Kind = 'hist-done'; Horas = @(); Dias = @(); Total = 0; Falhas = 0; Picos = 0; OkN = 0; Soma = 0.0; Quedas = 0; Msg = ''; Alvos = @() }
    if (-not (Test-Path $Path)) { $res.Msg = 'Ainda não há histórico. Inicie o monitor e deixe rodando.'; $fila.Enqueue($res); return }
    $horas = @()
    for ($h = 0; $h -lt 24; $h++) { $horas += , @{ T = 0; F = 0; P = 0 } }
    $diasMap = @{}
    $alvosSet = @{}
    $quedas = @{}
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $hoje = (Get-Date).Date
    $desde = $hoje.AddDays(-([math]::Max([int]$Dias, 1) - 1))
    foreach ($row in @(Import-Csv -Path $Path -Encoding UTF8)) {
        $dt = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$row.Inicio, 'yyyy-MM-dd HH:mm', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { continue }
        if ($dt -lt $desde) { continue }
        $alvosSet[[string]$row.Alvo] = $true
        if ($Filtro -and [string]$row.Alvo -ne $Filtro) { continue }
        $tot = [int]$row.Total; $fal = [int]$row.Falhas; $pic = [int]$row.Picos
        $hh = $horas[$dt.Hour]
        $hh.T = $hh.T + $tot; $hh.F = $hh.F + $fal; $hh.P = $hh.P + $pic
        $dk = $dt.ToString('yyyy-MM-dd')
        if (-not $diasMap.ContainsKey($dk)) { $diasMap[$dk] = @{ T = 0; F = 0; P = 0 } }
        $dd = $diasMap[$dk]
        $dd.T = $dd.T + $tot; $dd.F = $dd.F + $fal; $dd.P = $dd.P + $pic
        $res.Total = $res.Total + $tot; $res.Falhas = $res.Falhas + $fal; $res.Picos = $res.Picos + $pic
        $res.OkN = $res.OkN + [int]$row.OkN
        if ([string]$row.SomaMs -ne '') { $res.Soma = $res.Soma + [double]::Parse([string]$row.SomaMs, $inv) }
        if ($tot -ge 5 -and $fal -eq $tot) { $quedas[[string]$row.Inicio] = $true }
    }
    $lista = @()
    for ($d = [int]$Dias - 1; $d -ge 0; $d--) {
        $k = $hoje.AddDays(-$d).ToString('yyyy-MM-dd')
        if ($diasMap.ContainsKey($k)) { $lista += , @{ D = $k; T = $diasMap[$k].T; F = $diasMap[$k].F; P = $diasMap[$k].P } }
        else { $lista += , @{ D = $k; T = 0; F = 0; P = 0 } }
    }
    $res.Horas = $horas; $res.Dias = $lista; $res.Quedas = $quedas.Count
    $res.Alvos = @($alvosSet.Keys | Sort-Object)
    if ($res.Total -eq 0) { $res.Msg = 'Sem dados neste período para o destino escolhido.' }
    $fila.Enqueue($res)
}

# ------------------------------------------------------------ rota por salto (estilo MTR / PingPlotter)
$script:RouteCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    $fila = $Q
    $buf = New-Object byte[] 32
    $sonda = New-Object System.Net.NetworkInformation.Ping
    $saltos = New-Object System.Collections.ArrayList
    $fila.Enqueue(@{ Kind = 'route-prog'; Text = 'Descobrindo a rota...' })
    for ($ttl = 1; $ttl -le [int]$MaxSaltos; $ttl++) {
        if (-not $Ctl.Run) { return }
        $op = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
        $rr = $null
        try { $rr = $sonda.Send($Destino, 1500, $buf, $op) } catch { }
        $h = @{ Ttl = $ttl; Addr = ''; Nome = ''; Sent = 0; Lost = 0; Last = $null; Soma = 0.0; Ok = 0; Min = $null; Max = $null; Jit = 0.0; Prev = $null; NomeTent = 0 }
        if ($rr -and $rr.Address) { $h.Addr = $rr.Address.ToString() }
        [void]$saltos.Add($h)
        if ($rr -and $rr.Status -eq 'Success') { break }
    }
    $rodada = 0
    while ($Ctl.Run) {
        $rodada++
        $tarefas = @()
        foreach ($h in $saltos) {
            $p2 = New-Object System.Net.NetworkInformation.Ping
            $o2 = New-Object System.Net.NetworkInformation.PingOptions([int]$h.Ttl, $true)
            $tarefas += , $p2.SendPingAsync($Destino, 1000, $buf, $o2)
        }
        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tarefas, 3000) } catch { }
        for ($i = 0; $i -lt $saltos.Count; $i++) {
            $h = $saltos[$i]; $tk = $tarefas[$i]
            $h.Sent = $h.Sent + 1
            $ok = $false
            if ($tk.IsCompleted -and -not $tk.IsFaulted -and -not $tk.IsCanceled) {
                $rp = $tk.Result
                if ($rp.Address) { $h.Addr = $rp.Address.ToString() }
                if ($rp.Status -eq 'Success' -or $rp.Status -eq 'TtlExpired') {
                    $ok = $true
                    $ms = [double]$rp.RoundtripTime
                    $h.Ok = $h.Ok + 1; $h.Soma = $h.Soma + $ms; $h.Last = $ms
                    if ($null -eq $h.Min -or $ms -lt $h.Min) { $h.Min = $ms }
                    if ($null -eq $h.Max -or $ms -gt $h.Max) { $h.Max = $ms }
                    if ($null -ne $h.Prev) { $h.Jit = $h.Jit + ([math]::Abs($ms - $h.Prev) - $h.Jit) / 16 }
                    $h.Prev = $ms
                }
            }
            if (-not $ok) { $h.Lost = $h.Lost + 1 }
            # nome (DNS reverso) so algumas tentativas por endereco
            if ($h.Addr -and -not $h.Nome -and $h.NomeTent -lt 3 -and $rodada -ge 2) {
                $h.NomeTent = $h.NomeTent + 1
                try {
                    $nt = [System.Net.Dns]::GetHostEntryAsync($h.Addr)
                    if ($nt.Wait(600) -and -not $nt.IsFaulted) { $h.Nome = [string]$nt.Result.HostName }
                } catch { }
            }
        }
        $linhas = @()
        foreach ($h in $saltos) {
            $med = $null; if ($h.Ok -gt 0) { $med = [math]::Round($h.Soma / $h.Ok, 1) }
            $linhas += , @{ Ttl = $h.Ttl; Addr = $h.Addr; Nome = $h.Nome; Sent = $h.Sent; Lost = $h.Lost; Pct = [math]::Round($h.Lost / [math]::Max($h.Sent, 1) * 100, 1); Last = $h.Last; Avg = $med; Min = $h.Min; Max = $h.Max; Jit = [math]::Round($h.Jit, 1) }
        }
        $fila.Enqueue(@{ Kind = 'route-hops'; Rows = $linhas; Round = $rodada })
        for ($w = 0; $w -lt 10 -and $Ctl.Run; $w++) { Start-Sleep -Milliseconds 100 }
    }
    $fila.Enqueue(@{ Kind = 'route-stopped' })
}

# ------------------------------------------------------------ assistente "qual o problema?"
$script:AssistCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    Add-Type -AssemblyName System.Net.Http
    . ([scriptblock]::Create($Lib))
    $fila = $Q
    $S = @{ Nivel = 'ok' }
    $dicas = New-Object System.Collections.ArrayList
    $achei = New-Object System.Collections.ArrayList
    function Emit([string]$t, [string]$c = 'Gray') { $fila.Enqueue(@{ Kind = 'assist-line'; Text = $t; Color = $c }) }
    function Prog([string]$t) { $fila.Enqueue(@{ Kind = 'assist-prog'; Text = $t }) }
    function Head([string]$t) { Emit ''; Emit ('=== ' + $t + ' ===') 'Cyan' }
    function Marca([string]$g) {
        if ($g -eq 'bad') { $S.Nivel = 'bad' } elseif ($g -eq 'warn' -and $S.Nivel -eq 'ok') { $S.Nivel = 'warn' }
    }
    function Acha([string]$t, [string]$g) { [void]$achei.Add($t); Marca $g }
    function Dica([string]$t) { if (-not $dicas.Contains($t)) { [void]$dicas.Add($t) } }
    function Linha([string]$rot, $r) {
        if ($null -eq $r.Media) { Emit ('{0,-22} SEM RESPOSTA ({1} de {2} perdidos)' -f $rot, $r.Perdidos, $r.Enviados) 'Red'; return }
        Emit ('{0,-22} perda {1}% | média {2} ms | máx {3} ms | jitter {4} ms' -f $rot, (Fmt $r.Pct), (Fmt $r.Media), (Fmt $r.Max 0), (Fmt $r.Jitter))
    }
    function Info-Wifi {
        $w = (netsh wlan show interfaces) | Out-String
        $sig = $null; $canal = $null
        if ($w -match '(?m)^\s*[^:\r\n]+:\s*(\d{1,3})%\s*$') { $sig = [int]$Matches[1] }
        if ($w -match '(?m)^\s*(Channel|Canal)\s*:\s*(\d+)\s*$') { $canal = [int]$Matches[2] }
        if ($null -eq $sig) { Emit 'Não consegui ler o sinal do Wi-Fi (o Windows não informou).' 'DarkGray'; return }
        $cor = 'Green'; if ($sig -lt 60) { $cor = 'Yellow' }; if ($sig -lt 40) { $cor = 'Red' }
        Emit ('Sinal do Wi-Fi: {0}%' -f $sig) $cor
        if ($sig -lt 60) { Acha ('Sinal do Wi-Fi fraco ({0}%).' -f $sig) 'warn'; Dica 'Aproxime-se do roteador, tire obstáculos (paredes, espelhos, micro-ondas) ou teste por cabo para comparar.' }
        if ($canal) {
            $faixa = '2,4 GHz'; if ($canal -gt 14) { $faixa = '5 GHz ou mais' }
            Emit ('Canal {0} ({1})' -f $canal, $faixa)
            if ($canal -le 14) { Dica 'Você está na faixa de 2,4 GHz (alcance maior, mas mais lenta e congestionada). Se o roteador tem 5 GHz, use essa rede quando estiver perto.' }
            $viz = (netsh wlan show networks mode=bssid) | Out-String
            $mesmo = 0
            foreach ($mm in [regex]::Matches($viz, '(?m)^\s*(Channel|Canal)\s*:\s*(\d+)\s*$')) { if ([int]$mm.Groups[2].Value -eq $canal) { $mesmo++ } }
            if ($mesmo -gt 1) {
                Emit ('Redes visíveis no mesmo canal: {0} (contando a sua).' -f $mesmo) 'Yellow'
                Acha ('Há {0} redes no mesmo canal do seu Wi-Fi: interferência provável.' -f ($mesmo - 1)) 'warn'
                Dica 'Troque o canal do Wi-Fi no painel do roteador (em 2,4 GHz, prefira 1, 6 ou 11).'
            }
        }
    }
    try {
        Prog 'Verificando a conexão...'
        $rota = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if (-not $rota) { Emit 'Sem conexão de rede ativa. Verifique o cabo, o Wi-Fi e o roteador.' 'Red'; $S.Nivel = 'bad'; throw 'sem rede' }
        $gw = [string]$rota.NextHop
        $ad = Get-NetAdapter -InterfaceIndex $rota.InterfaceIndex
        $wifi = ([string]$ad.PhysicalMediaType -match '802\.11|Wireless')
        $tipoCon = 'cabo'; if ($wifi) { $tipoCon = 'Wi-Fi' }
        Head 'Sua conexão'
        Emit ('Adaptador: {0} ({1})   Link: {2}' -f $ad.Name, $tipoCon, $ad.LinkSpeed)
        if (-not $wifi -and $ad.Speed -and $ad.Speed -lt 1000000000) { Acha ('O cabo negociou menos de 1 Gbps ({0}).' -f $ad.LinkSpeed) 'warn'; Dica 'Troque o cabo de rede por um de boa qualidade (Cat5e ou superior) e teste outra porta do roteador.' }
        $pm = Get-NetAdapterPowerManagement -Name $ad.Name
        if ($pm -and [string]$pm.AllowComputerToTurnOffDevice -eq 'Enabled') { Acha 'O Windows pode desligar a placa de rede para economizar energia.' 'warn'; Dica 'Gerenciador de Dispositivos > placa de rede > Gerenciamento de Energia: desmarque "Permitir que o computador desligue este dispositivo".' }

        if ($Problema -eq 'queda') {
            Head 'Teste de estabilidade (cerca de 30 segundos)'
            $pg = New-Object System.Net.NetworkInformation.Ping
            $mg = New-Object 'System.Collections.Generic.List[double]'; $me = New-Object 'System.Collections.Generic.List[double]'
            $pg_loss = 0; $pe_loss = 0; $seqG = 0; $maxSeqG = 0; $seqE = 0; $maxSeqE = 0
            for ($i = 0; $i -lt 60; $i++) {
                if (($i % 6) -eq 0) { Prog ('Testando estabilidade... {0}%' -f [int]($i / 60 * 100)) }
                try { $a = $pg.Send($gw, 1000); if ($a.Status -eq 'Success') { $mg.Add($a.RoundtripTime); $seqG = 0 } else { $pg_loss++; $seqG++; if ($seqG -gt $maxSeqG) { $maxSeqG = $seqG } } } catch { $pg_loss++ }
                try { $b2 = $pg.Send($PingExterno, 1000); if ($b2.Status -eq 'Success') { $me.Add($b2.RoundtripTime); $seqE = 0 } else { $pe_loss++; $seqE++; if ($seqE -gt $maxSeqE) { $maxSeqE = $seqE } } } catch { $pe_loss++ }
                Start-Sleep -Milliseconds 300
            }
            $rg = Resumo $mg $pg_loss 60; $re = Resumo $me $pe_loss 60
            Linha 'Roteador' $rg; Linha 'Internet' $re
            if ($rg.Pct -gt 0) { Acha ('Perdas até o próprio roteador ({0}%): o problema está dentro da sua casa (cabo, Wi-Fi, placa ou roteador).' -f (Fmt $rg.Pct)) 'bad'; Dica 'Teste por cabo direto no roteador e troque o cabo. Se for Wi-Fi, aproxime-se. Reinicie o roteador.' }
            elseif ($re.Pct -gt 0) { Acha ('O roteador respondeu bem, mas houve perdas até a internet ({0}%): o problema está do roteador para fora (operadora).' -f (Fmt $re.Pct)) 'bad'; Dica 'Deixe o Monitor rodando 15 a 30 minutos e gere o relatório para a operadora; anote data e hora das quedas.' }
            else { Emit 'Nenhuma queda nestes 30 segundos. Quedas ocasionais podem não aparecer num teste curto.' 'Green'; Dica 'Deixe a aba Monitor com alertas ligados por algumas horas (de preferência minimizado na bandeja) e depois veja a aba Histórico.' }
            if ($maxSeqE -ge 3) { Acha ('Sequência de {0} perdas seguidas até a internet: indício de queda real, não só oscilação.' -f $maxSeqE) 'bad' }
        }

        if ($Problema -eq 'lag' -or $Problema -eq 'lenta') {
            Prog 'Medindo o roteador e a internet...'
            Head 'Atraso e estabilidade'
            $rg = PingN $gw 25 100; Linha 'Roteador' $rg
            $re = PingN $PingExterno 25 100; Linha 'Internet' $re
            if ($rg.Pct -gt 0 -or ($null -ne $rg.Jitter -and $rg.Jitter -gt 8) -or ($null -ne $rg.Max -and $rg.Max -gt 30)) {
                Acha 'Já há instabilidade até o roteador: o problema começa na sua rede local.' 'bad'
                if ($wifi) { Dica 'Você está no Wi-Fi: teste por cabo. Se melhorar, o problema é o sinal.' } else { Dica 'Troque o cabo, teste outra porta do roteador e reinicie o roteador.' }
            }
            if ($re.Pct -gt 0) { Acha ('Perda de {0}% até a internet.' -f (Fmt $re.Pct)) 'bad' }
            if ($null -ne $re.Media -and $re.Media -gt 80) { Acha ('Ping até a internet alto ({0} ms).' -f (Fmt $re.Media 0)) 'warn' }
            if ($null -ne $re.Jitter -and $re.Jitter -gt 15) { Acha ('Jitter alto ({0} ms): o ping oscila bastante.' -f (Fmt $re.Jitter)) 'warn' }
        }

        if ($Problema -eq 'lag') {
            Head 'Seus destinos (TCP)'
            foreach ($a in @($Alvos)) {
                if ([int]$a.Porta -le 0 -or -not $a.Destino) { continue }
                Prog ('Medindo ' + $a.Nome + '...')
                $r = TcpN ([string]$a.Destino) ([int]$a.Porta) 20 200
                if ($null -eq $r.Media) { Emit ('{0,-22} SEM RESPOSTA' -f $a.Nome) 'Red'; Acha ('Sem resposta de {0}.' -f $a.Nome) 'warn' }
                else {
                    $pr = [math]::Round(($r.Perdidos + $r.Picos) / $r.Enviados * 100, 1)
                    Emit ('{0,-22} problemas {1}% | média {2} ms | máx {3} ms' -f $a.Nome, (Fmt $pr), (Fmt $r.Media), (Fmt $r.Max 0))
                    if ($a.Role -eq 'destino' -and $pr -ge 5) { Acha ('{0} tem {1}% de problemas: pode ser o servidor ou a rota até ele.' -f $a.Nome, (Fmt $pr)) 'warn'; Dica 'Se o controle estiver limpo e só esse destino ruim, o problema não é sua linha: tente outro servidor/região do jogo.' }
                }
            }
        }

        if ($Problema -eq 'lag' -or $Problema -eq 'lenta') {
            Head 'Atraso sob carga (bufferbloat)'
            Prog 'Medindo o ping com a linha cheia...'
            $base = PingN $PingExterno 10 100
            $dn = Carga 'down' 'https://speed.cloudflare.com/__down?bytes=10000000' 1 10
            $bl = Get-BloatGrade $base.Media $dn.Ping.Media $null
            Emit ('Ping parado: {0} ms | durante o download: {1} ms' -f (Fmt $base.Media 0), (Fmt $dn.Ping.Media 0))
            if ($bl) {
                $cg = 'Green'; if ($bl.Grade -eq 'C') { $cg = 'Yellow' }; if ($bl.Grade -eq 'D' -or $bl.Grade -eq 'F') { $cg = 'Red' }
                Emit ('Nota de bufferbloat: {0} (+{1} ms)' -f $bl.Grade, $bl.Delta) $cg
                if ($bl.Grade -eq 'C') { Acha ('Bufferbloat moderado (+{0} ms): o ping sobe quando alguém baixa algo.' -f $bl.Delta) 'warn' }
                if ($bl.Grade -eq 'D' -or $bl.Grade -eq 'F') {
                    Acha ('Bufferbloat alto (+{0} ms): o ping explode quando a linha está ocupada.' -f $bl.Delta) 'bad'
                    Dica 'Peça para ninguém baixar/transmitir durante o jogo. Se o roteador tem SQM/QoS inteligente, ligue-o limitando a velocidade a cerca de 90% do plano.'
                }
            }
        }

        if ($Problema -eq 'lenta') {
            Head 'Velocidade'
            Prog 'Medindo o download...'
            $mbd = 15; if ($PlanoMbps) { $mbd = [math]::Max(5, [math]::Min(40, [int]($PlanoMbps * 0.1875))) }
            $d2 = Carga 'down' ('https://speed.cloudflare.com/__down?bytes=' + ($mbd * 1000000)) 2 $mbd
            Emit ('Download: melhor {0} Mbps (rodadas: {1}; 4 conexões)' -f (Fmt $d2.Melhor), $d2.Rodadas)
            if ($PlanoMbps -and $d2.Melhor -gt 0) {
                $pc = [math]::Round($d2.Melhor / $PlanoMbps * 100, 0)
                Emit ('Isso é {0}% do plano de {1} Mbps.' -f $pc, (Fmt $PlanoMbps 0))
                if ($pc -lt 40) { Acha ('Velocidade medida abaixo de 40% do plano ({0}%).' -f $pc) 'bad'; Dica 'Teste por cabo, sem outros aparelhos usando a rede. Se continuar baixo, registre vários testes (aba Diagnóstico) e gere o relatório para a operadora.' }
                elseif ($pc -lt 80) { Acha ('Velocidade em {0}% do plano.' -f $pc) 'warn'; Dica 'A meta de média mensal é 80%: repita em horários diferentes e acompanhe o histórico.' }
            } elseif (-not $PlanoMbps) { Emit 'Preencha o plano na aba Texto para o suporte para comparar com a velocidade contratada.' 'DarkGray' }
            if ($d2.Melhor -le 0) { Acha 'O teste de velocidade não conseguiu medir (sem acesso à Cloudflare?).' 'warn' }
            Head 'DNS'
            $alvosDns = @()
            $atual = @(Get-DnsClientServerAddress -InterfaceIndex $rota.InterfaceIndex -AddressFamily IPv4 | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ -and $_ -notlike '127.*' })
            if ($atual.Count -gt 0) { $alvosDns += @{ N = 'DNS atual'; I = $atual[0] } }
            $alvosDns += @{ N = 'Cloudflare'; I = '1.1.1.1' }; $alvosDns += @{ N = 'Google'; I = '8.8.8.8' }
            $melhorDns = $null; $atualMs = $null
            foreach ($x in $alvosDns) {
                $ts = @()
                foreach ($dom in 'google.com', 'youtube.com', 'wikipedia.org') { [void](Query-Dns $x.I $dom 1500); $v = Query-Dns $x.I $dom 1500; if ($v -ge 0) { $ts += $v } }
                if ($ts.Count -gt 0) {
                    $mdns = [math]::Round(($ts | Measure-Object -Average).Average, 1)
                    Emit ('{0,-12} {1,-16} {2} ms' -f $x.N, $x.I, (Fmt $mdns))
                    if ($x.N -eq 'DNS atual') { $atualMs = $mdns } elseif ($null -eq $melhorDns -or $mdns -lt $melhorDns.Ms) { $melhorDns = @{ N = $x.N; Ms = $mdns } }
                } else { Emit ('{0,-12} {1,-16} sem resposta' -f $x.N, $x.I) 'DarkGray' }
            }
            if ($null -ne $atualMs -and $melhorDns -and $atualMs -gt ($melhorDns.Ms + 25)) { Acha ('O DNS atual responde mais devagar ({0} ms) que o {1} ({2} ms).' -f (Fmt $atualMs 0), $melhorDns.N, (Fmt $melhorDns.Ms 0)) 'warn'; Dica 'Experimente trocar o DNS na aba Ferramentas DNS (há um teste de velocidade e backup automático).' }
        }

        if ($Problema -eq 'wifi' -or $wifi) {
            Head 'Wi-Fi'
            if (-not $wifi) { Emit 'Você está conectado por cabo: o Wi-Fi não está em uso neste PC.' 'Gray'; Dica 'Para avaliar o Wi-Fi, desconecte o cabo e rode o assistente de novo.' }
            else {
                Info-Wifi
                if ($Problema -eq 'wifi') {
                    $rg = PingN $gw 30 100; Linha 'Roteador (Wi-Fi)' $rg
                    if ($rg.Pct -gt 0) { Acha ('Perda de {0}% até o roteador pelo Wi-Fi.' -f (Fmt $rg.Pct)) 'bad' }
                    if ($null -ne $rg.Jitter -and $rg.Jitter -gt 8) { Acha ('Oscilação alta até o roteador pelo Wi-Fi (jitter {0} ms).' -f (Fmt $rg.Jitter)) 'warn'; Dica 'Wi-Fi costuma oscilar mais que cabo. Para jogos e chamadas, o cabo é o mais estável.' }
                }
            }
        }

        Head 'Conclusão'
        if ($achei.Count -eq 0) { Emit 'Não encontrei problema nos testes desta rodada.' 'Green'; if ($dicas.Count -eq 0) { Dica 'Se o problema acontece só às vezes, deixe o Monitor rodando e veja o Histórico depois.' } }
        else { foreach ($x in $achei) { Emit ('- ' + $x) 'Yellow' } }
        if ($dicas.Count -gt 0) { Head 'O que fazer'; $n = 0; foreach ($x in $dicas) { $n++; Emit ('{0}. {1}' -f $n, $x) } }
        Emit ''
        Emit 'São indícios feitos neste momento, não prova: repita em outro horário para confirmar.' 'DarkGray'
    } catch {
        if ($_.Exception.Message -ne 'sem rede') { Emit ('Erro durante o teste: ' + $_.Exception.Message) 'Red'; $S.Nivel = 'warn' }
    }
    $fila.Enqueue(@{ Kind = 'assist-done'; Nivel = $S.Nivel })
}

# ------------------------------------------------------------ conclusao da rota por salto (lado da janela)
# Perda so conta quando continua ate o destino: equipamentos do caminho costumam limitar respostas ICMP e parecer que perdem.
function Get-RouteConclusion($rows) {
    $r = @{ Nivel = 'ok'; Texto = ''; Ttl = $null }
    $rows = @($rows)
    if ($rows.Count -eq 0) { $r.Texto = 'Aguardando medições...'; return $r }
    $min = ($rows | ForEach-Object { $_.Sent } | Measure-Object -Minimum).Minimum
    if ($min -lt 20) { $r.Texto = ('Coletando dados... ({0} de 20 rodadas para uma conclusão confiável)' -f $min); return $r }
    $dest = $rows[$rows.Count - 1]
    $limiar = 3.0
    $inicio = $null
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ($rows[$i].Pct -lt $limiar) { continue }
        $continua = $true
        for ($j = $i + 1; $j -lt $rows.Count; $j++) { if ($rows[$j].Pct -lt ($rows[$i].Pct * 0.5)) { $continua = $false; break } }
        if ($continua) { $inicio = $rows[$i]; break }
    }
    if ($null -eq $inicio) {
        $perdeu = @($rows | Where-Object { $_.Pct -ge $limiar -and $_.Ttl -lt $dest.Ttl })
        if ($perdeu.Count -gt 0) { $r.Texto = 'Alguns saltos do caminho mostram perda, mas ela não continua até o destino: é limitação de resposta desses equipamentos, sem efeito real na sua conexão.' }
        elseif ($dest.Pct -ge $limiar) { $r.Nivel = 'bad'; $r.Texto = ('O destino perde {0}% das respostas, mas o caminho não mostra onde começa (saltos sem resposta).' -f $dest.Pct) }
        else { $r.Texto = 'Nenhuma perda persistente no caminho até o destino nesta medição.' }
        return $r
    }
    $onde = 'na internet, depois da sua operadora'
    if ($inicio.Ttl -le 1) { $onde = 'no primeiro salto (seu roteador): problema na sua rede local' }
    elseif ($inicio.Ttl -le 3) { $onde = 'nos primeiros saltos depois do roteador (rede da operadora)' }
    $ender = $inicio.Addr; if (-not $ender) { $ender = '(sem resposta)' }
    $r.Nivel = 'bad'; $r.Ttl = $inicio.Ttl
    $r.Texto = ('A perda de {0}% começa no salto {1} ({2}) e continua até o destino: {3}.' -f $inicio.Pct, $inicio.Ttl, $ender, $onde)
    $r
}

# ------------------------------------------------------------ relatorio HTML (arquivo unico, sem internet)
$script:ReportCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    $fila = $Q
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    function Esc-Html($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }
    function Svg-Barras($vals, $rotulos, [double]$escalaMin) {
        $max = $escalaMin
        foreach ($v in $vals) { if ($v -gt $max) { $max = $v } }
        $n = $vals.Count; $w = 8 * $n + 4
        $sb2 = New-Object System.Text.StringBuilder
        [void]$sb2.Append(('<svg viewBox="0 0 {0} 64" width="{0}" height="64" role="img">' -f $w))
        for ($i = 0; $i -lt $n; $i++) {
            $alt = [math]::Round(52 * $vals[$i] / $max, 1)
            $cor = '#3b82f6'; if ($vals[$i] -ge 5) { $cor = '#ef4444' } elseif ($vals[$i] -ge 1) { $cor = '#f59e0b' }
            [void]$sb2.Append(('<rect x="{0}" y="{1}" width="6" height="{2}" fill="{3}"><title>{4}: {5}%</title></rect>' -f (2 + 8 * $i), (56 - $alt).ToString($inv), $alt.ToString($inv), $cor, (Esc-Html $rotulos[$i]), ([math]::Round($vals[$i], 1)).ToString($inv)))
        }
        [void]$sb2.Append('</svg>')
        $sb2.ToString()
    }
    $sb = New-Object System.Text.StringBuilder
    function L([string]$t) { [void]$sb.AppendLine($t) }
    $css = @'
body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:24px;background:#f5f7fa;color:#1f2933;line-height:1.45}
.w{max-width:960px;margin:auto}
h1{margin:0 0 4px;font-size:26px} h2{margin:28px 0 8px;font-size:18px;border-bottom:2px solid #d5dbe3;padding-bottom:4px}
.card{background:#fff;border:1px solid #d5dbe3;border-radius:8px;padding:12px 16px;margin:8px 0}
table{border-collapse:collapse;width:100%;font-size:14px} th,td{text-align:left;padding:5px 8px;border-bottom:1px solid #e4e8ee} th{background:#eef2f7}
pre{white-space:pre-wrap;background:#0f172a;color:#e2e8f0;padding:12px;border-radius:8px;font-size:13px}
.m{color:#64748b;font-size:13px} .bad{color:#b91c1c;font-weight:600} .ok{color:#15803d;font-weight:600} .warn{color:#b45309;font-weight:600}
@media (prefers-color-scheme:dark){body{background:#111827;color:#e5e7eb}.card{background:#1f2937;border-color:#374151}th{background:#273449}td,th{border-color:#374151}h2{border-color:#374151}.m{color:#9ca3af}}
'@
    L '<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Relatório NetDoctor</title><style>'
    L $css
    L '</style></head><body><div class="w">'
    L ('<h1>Relatório de conexão - NetDoctor</h1><div class="m">Gerado em {0}. Operadora: {1}. Plano: {2}.</div>' -f (Esc-Html $Dados.DataHora), (Esc-Html $(if ($Dados.Provedor) { $Dados.Provedor } else { 'não informada' })), (Esc-Html $(if ($Dados.Plano) { $Dados.Plano } else { 'não informado' })))
    L '<div class="card m">Medições feitas por este PC com o NetDoctor. São indícios técnicos para conversar com a operadora, não a medição oficial da Anatel. Revise antes de compartilhar: o relatório contém IP local e o nome da sua operadora.</div>'

    # --- resumo
    L '<h2>Resumo</h2><div class="card">'
    if ($Dados.Scores) { L ('<p>{0}</p>' -f (Esc-Html $Dados.Scores)) } else { L '<p class="m">Rode o Diagnóstico com o teste de velocidade ligado para ver as notas.</p>' }
    foreach ($l in @($Dados.Anatel)) { L ('<p>{0}</p>' -f (Esc-Html $l)) }
    L '</div>'

    # --- alvos desta sessao
    if (@($Dados.Alvos).Count -gt 0) {
        L '<h2>Monitor (sessão atual)</h2><div class="card"><table><tr><th>Destino</th><th>Endereço</th><th>Testes</th><th>Falhas</th><th>Picos</th><th>Média (ms)</th><th>Problemas</th></tr>'
        foreach ($a in @($Dados.Alvos)) {
            $cl = 'ok'; if ($a.Pct -ge 3) { $cl = 'bad' } elseif ($a.Pct -ge 1) { $cl = 'warn' }
            L ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td class="{6}">{7}%</td></tr>' -f (Esc-Html $a.Nome), (Esc-Html $a.Destino), $a.Total, $a.Falhas, $a.Picos, (Esc-Html $a.Media), $cl, $a.Pct)
        }
        L '</table></div>'
    }

    # --- historico (30 dias)
    L '<h2>Histórico do monitor (últimos 30 dias)</h2>'
    if ((Test-Path $HistPath)) {
        $desde = (Get-Date).Date.AddDays(-29)
        $porAlvo = @{}
        foreach ($row in @(Import-Csv -Path $HistPath -Encoding UTF8)) {
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParseExact([string]$row.Inicio, 'yyyy-MM-dd HH:mm', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { continue }
            if ($dt -lt $desde) { continue }
            $k = [string]$row.Alvo
            if (-not $porAlvo.ContainsKey($k)) {
                $hs = @(); for ($h = 0; $h -lt 24; $h++) { $hs += , @{ T = 0; B = 0 } }
                $porAlvo[$k] = @{ T = 0; F = 0; B = 0; Quedas = 0; Horas = $hs; Soma = 0.0; OkN = 0 }
            }
            $g = $porAlvo[$k]
            $tot = [int]$row.Total; $fal = [int]$row.Falhas; $pic = [int]$row.Picos
            $g.T = $g.T + $tot; $g.F = $g.F + $fal; $g.B = $g.B + $fal + $pic
            $g.Horas[$dt.Hour].T = $g.Horas[$dt.Hour].T + $tot; $g.Horas[$dt.Hour].B = $g.Horas[$dt.Hour].B + $fal + $pic
            $g.OkN = $g.OkN + [int]$row.OkN
            if ([string]$row.SomaMs -ne '') { $g.Soma = $g.Soma + [double]::Parse([string]$row.SomaMs, $inv) }
            if ($tot -ge 5 -and $fal -eq $tot) { $g.Quedas = $g.Quedas + 1 }
        }
        if ($porAlvo.Count -eq 0) { L '<div class="card m">Ainda sem dados no período.</div>' }
        foreach ($k in @($porAlvo.Keys | Sort-Object)) {
            $g = $porAlvo[$k]
            $disp = 100.0; if ($g.T -gt 0) { $disp = 100.0 * (1 - $g.F / $g.T) }
            $prob = 0.0; if ($g.T -gt 0) { $prob = 100.0 * $g.B / $g.T }
            $pcts = @(); $rot = @(); $pior = -1; $piorV = -1.0
            for ($h = 0; $h -lt 24; $h++) {
                $v = 0.0; if ($g.Horas[$h].T -gt 0) { $v = 100.0 * $g.Horas[$h].B / $g.Horas[$h].T }
                $pcts += $v; $rot += ('{0:00}h' -f $h)
                if ($g.Horas[$h].T -ge 20 -and $v -gt $piorV) { $piorV = $v; $pior = $h }
            }
            $txtPior = 'sem destaque'
            if ($pior -ge 0 -and $piorV -gt 0) { $txtPior = ('{0:00}h às {1:00}h ({2}% de problemas)' -f $pior, (($pior + 1) % 24), [math]::Round($piorV, 1)) }
            $mediaMs = '-'; if ($g.OkN -gt 0) { $mediaMs = [math]::Round($g.Soma / $g.OkN, 1).ToString($inv) }
            L ('<div class="card"><b>{0}</b><br>Disponibilidade: {1}% &nbsp; Problemas (falhas e picos): {2}% &nbsp; Latência média: {3} ms &nbsp; Blocos de 5 min sem resposta: {4}<br>Pior horário: {5}<br><span class="m">Problemas por hora do dia (0h a 23h):</span><br>{6}</div>' -f (Esc-Html $k), [math]::Round($disp, 2).ToString($inv), [math]::Round($prob, 1).ToString($inv), $mediaMs, $g.Quedas, (Esc-Html $txtPior), (Svg-Barras $pcts $rot 5))
        }
    } else { L '<div class="card m">Ainda não há histórico do monitor. Deixe o Monitor rodando para acumular dados.</div>' }

    # --- velocidade
    L '<h2>Testes de velocidade</h2>'
    if ((Test-Path $SpeedPath)) {
        $vs = @(Import-Csv -Path $SpeedPath -Encoding UTF8)
        $ult = @($vs | Select-Object -Last 15)
        L '<div class="card"><table><tr><th>Data</th><th>Download</th><th>Upload</th><th>Ping parado</th><th>Ping no download</th><th>% do plano</th></tr>'
        foreach ($v in $ult) {
            $pc = '-'
            if ([string]$v.PlanoMbps -ne '' -and [string]$v.DownMbps -ne '' -and [double]::Parse([string]$v.PlanoMbps, $inv) -gt 0) { $pc = ('{0}%' -f [math]::Round(100 * [double]::Parse([string]$v.DownMbps, $inv) / [double]::Parse([string]$v.PlanoMbps, $inv), 0)) }
            L ('<tr><td>{0}</td><td>{1} Mbps</td><td>{2} Mbps</td><td>{3} ms</td><td>{4} ms</td><td>{5}</td></tr>' -f (Esc-Html $v.DataHora), (Esc-Html $v.DownMbps), (Esc-Html $v.UpMbps), (Esc-Html $v.IdleMs), (Esc-Html $v.LoadDownMs), $pc)
        }
        L '</table></div>'
    } else { L '<div class="card m">Nenhum teste de velocidade registrado ainda. Rode o Diagnóstico com o teste de velocidade ligado.</div>' }

    # --- eventos
    if ((Test-Path $EvPath)) {
        $ev = @(Import-Csv -Path $EvPath -Encoding UTF8 | Select-Object -Last 20)
        if ($ev.Count -gt 0) {
            L '<h2>Alertas recentes</h2><div class="card"><table><tr><th>Data</th><th>Destino</th><th>Tipo</th><th>Detalhe</th></tr>'
            foreach ($e in $ev) { L ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>' -f (Esc-Html $e.DataHora), (Esc-Html $e.Alvo), (Esc-Html $e.Tipo), (Esc-Html $e.Detalhe)) }
            L '</table></div>'
        }
    }

    # --- achados e texto
    if (@($Dados.Achados).Count -gt 0) {
        L '<h2>O que o Diagnóstico encontrou</h2><div class="card"><ul>'
        foreach ($a in @($Dados.Achados)) { L ('<li>{0}</li>' -f (Esc-Html $a)) }
        L '</ul></div>'
    }
    if ($Dados.Rede) { L ('<h2>Rede deste PC</h2><pre>{0}</pre>' -f (Esc-Html $Dados.Rede)) }
    if ($Dados.Suporte) { L ('<h2>Texto para enviar ao suporte</h2><pre>{0}</pre>' -f (Esc-Html $Dados.Suporte)) }
    L '</div></body></html>'
    $ok = $true; $msg = ''
    try { [System.IO.File]::WriteAllText($Saida, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true))) } catch { $ok = $false; $msg = $_.Exception.Message }
    $fila.Enqueue(@{ Kind = 'report-done'; Ok = $ok; Path = $Saida; Msg = $msg })
}

