# NetDoctor - nucleo (sem janela). Carregado por NetDoctor.ps1.
# Contem: configuracao, estatisticas, veredito, texto para suporte e workers de fundo.

$script:IsWifi = $false

function Fmt($x, [int]$dec = 1) {
    if ($null -eq $x) { return '-' }
    $f = '0'
    if ($dec -gt 0) { $f = '0.' + ('0' * $dec) }
    ([double]$x).ToString($f, [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
}

function Get-AppDir {
    $base = [Environment]::GetFolderPath('ApplicationData')
    if (-not $base) { $base = Join-Path $HOME '.config' }
    $d = Join-Path $base 'NetDoctor'
    if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    $d
}

function Get-ReportDir {
    $base = [Environment]::GetFolderPath('UserProfile')
    if (-not $base) { $base = $HOME }
    $d = Join-Path $base 'roteador'
    if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    $d
}

# Versao instalada e repositorio de onde saem as atualizacoes (GitHub Releases). O Publicar-Versao.ps1 troca a versao.
$script:AppVersion = '1.0.0'
$script:RepoOwner = 'vitinholindo756-boop'
$script:RepoName = 'NetDoctor'

function Log-Error($err) {
    try {
        $msg = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $err)
        Add-Content -Path (Join-Path (Get-AppDir) 'erro.log') -Value $msg
    } catch { }
}

# ------------------------------------------------------------ configuracao
function New-DefaultConfig {
    [pscustomobject]@{
        IntervalS = 2
        SpikeMs   = 150
        TimeoutMs = 3000
        Provedor  = ''
        Plano     = ''
        SomDns    = $true
        Tema      = 'auto'
        Bandeja   = $false
        Alertas   = $true
        AlertaPct = 8
        AutoMonitor = $false
        AutoUpdate = $true
        # Roteador e DNS ficam com Destino vazio de proposito: sao detectados
        # automaticamente na rede de quem estiver usando (Auto = gateway / dns).
        # O usuario adiciona seus proprios destinos (ex.: servidor de jogo) em "+ Destino".
        Targets   = @(
            [pscustomobject]@{ Nome = 'Roteador';  Destino = ''; Porta = 0;   Role = 'local';     Auto = 'gateway' },
            [pscustomobject]@{ Nome = 'DNS em uso'; Destino = ''; Porta = 0;   Role = 'operadora'; Auto = 'dns' },
            [pscustomobject]@{ Nome = 'Controle';  Destino = '1.1.1.1'; Porta = 443; Role = 'controle';  Auto = '' }
        )
    }
}

function Load-Config {
    $p = Join-Path (Get-AppDir) 'config.json'
    $cfg = $null
    if (Test-Path $p) {
        try { $cfg = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
    }
    if (-not $cfg -or -not $cfg.Targets) { $cfg = New-DefaultConfig }
    if (-not $cfg.IntervalS) { $cfg | Add-Member -NotePropertyName IntervalS -NotePropertyValue 2 -Force }
    if (-not $cfg.SpikeMs)   { $cfg | Add-Member -NotePropertyName SpikeMs -NotePropertyValue 150 -Force }
    if (-not $cfg.TimeoutMs) { $cfg | Add-Member -NotePropertyName TimeoutMs -NotePropertyValue 3000 -Force }
    if ($null -eq $cfg.Provedor) { $cfg | Add-Member -NotePropertyName Provedor -NotePropertyValue '' -Force }
    if ($null -eq $cfg.Plano)    { $cfg | Add-Member -NotePropertyName Plano -NotePropertyValue '' -Force }
    # valores antigos que vinham pre-preenchidos: o usuario preenche os dele
    if ([string]$cfg.Provedor -eq 'Online Telecom') { $cfg.Provedor = '' }
    if ([string]$cfg.Plano -eq '300 Mega') { $cfg.Plano = '' }
    # nome antigo do alvo de DNS (agora pode ser Cloudflare, Google etc.)
    foreach ($t in @($cfg.Targets)) { if ([string]$t.Auto -eq 'dns' -and [string]$t.Nome -eq 'DNS da operadora') { $t.Nome = 'DNS em uso' } }
    if ($null -eq $cfg.Bandeja) { $cfg | Add-Member -NotePropertyName Bandeja -NotePropertyValue $false -Force }
    if ($null -eq $cfg.Alertas) { $cfg | Add-Member -NotePropertyName Alertas -NotePropertyValue $true -Force }
    if ($null -eq $cfg.AlertaPct) { $cfg | Add-Member -NotePropertyName AlertaPct -NotePropertyValue 8 -Force }
    if ($null -eq $cfg.AutoUpdate) { $cfg | Add-Member -NotePropertyName AutoUpdate -NotePropertyValue $true -Force }
    if ($null -eq $cfg.AutoMonitor) { $cfg | Add-Member -NotePropertyName AutoMonitor -NotePropertyValue $false -Force }
    if ($null -eq $cfg.Tema) { $cfg | Add-Member -NotePropertyName Tema -NotePropertyValue 'auto' -Force }
    if ($null -eq $cfg.SomDns) { $cfg | Add-Member -NotePropertyName SomDns -NotePropertyValue $true -Force }
    $cfg
}

function Save-Config($cfg) {
    try {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path (Get-AppDir) 'config.json') -Encoding UTF8
    } catch { Log-Error $_ }
}

# ------------------------------------------------------------ estado por destino
function New-TargetState($c) {
    @{
        Nome = [string]$c.Nome; Destino = [string]$c.Destino; Porta = [int]$c.Porta
        Role = [string]$c.Role; Auto = [string]$c.Auto
        Total = 0; Ok = 0; Falhas = 0; Picos = 0; Soma = 0.0
        Min = $null; Max = $null; Last = $null
        Hist = (New-Object 'System.Collections.Generic.List[double]')
    }
}

function Reset-TargetState($t) {
    $t.Total = 0; $t.Ok = 0; $t.Falhas = 0; $t.Picos = 0; $t.Soma = 0.0
    $t.Min = $null; $t.Max = $null; $t.Last = $null
    $t.Hist.Clear()
}

function Get-Pct($t) {
    if ($t.Total -le 0) { return 0.0 }
    [math]::Round(($t.Falhas + $t.Picos) / $t.Total * 100, 1)
}

function Get-Avg($t) {
    if ($t.Ok -le 0) { return $null }
    [math]::Round($t.Soma / $t.Ok, 1)
}

function Get-Endereco($t) {
    if ([string]::IsNullOrWhiteSpace([string]$t.Destino)) { return '(não detectado)' }
    if ($t.Porta -gt 0) { return ('{0}:{1}' -f $t.Destino, $t.Porta) }
    ('{0} (ping)' -f $t.Destino)
}

# Aplica uma amostra vinda de um worker. Retorna OK, PICO ou FALHA.
function Apply-Sample($t, $s) {
    $t.Total = $t.Total + 1
    $status = 'FALHA'
    $msTxt = ''
    if ($s.Status -eq 'OK') {
        $ms = [double]$s.Ms
        $t.Ok = $t.Ok + 1
        $t.Soma = $t.Soma + $ms
        $t.Last = $ms
        if ($null -eq $t.Min -or $ms -lt $t.Min) { $t.Min = $ms }
        if ($null -eq $t.Max -or $ms -gt $t.Max) { $t.Max = $ms }
        $t.Hist.Add($ms)
        $msTxt = ([math]::Round($ms, 1)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        if ($ms -ge $script:SpikeMs) { $t.Picos = $t.Picos + 1; $status = 'PICO' } else { $status = 'OK' }
    } else {
        $t.Falhas = $t.Falhas + 1
        $t.Last = $null
        $t.Hist.Add(-1.0)
    }
    if ($t.Hist.Count -gt 600) { $t.Hist.RemoveAt(0) }
    if ($null -eq $script:SessionStart) { $script:SessionStart = $s.Time }
    $script:LastSample = $s.Time
    if ($script:Csv) {
        $nome = ([string]$t.Nome).Replace(',', ';')
        $script:Csv.WriteLine(('{0},{1},{2},{3}' -f $s.Time.ToString('yyyy-MM-dd HH:mm:ss.fff'), $nome, $msTxt, $status))
    }
    # historico em blocos de 5 min e janela recente para alertas (NetDoctor.insights.ps1)
    Track-Sample $t $s $status
    $status
}

# ------------------------------------------------------------ veredito ao vivo
function Get-Verdict($targets) {
    $ctl = $null; $loc = $null; $ops = $null; $dest = @()
    foreach ($t in $targets) {
        if ($t.Role -eq 'controle' -and -not $ctl) { $ctl = $t }
        elseif ($t.Role -eq 'local' -and -not $loc) { $loc = $t }
        elseif ($t.Role -eq 'operadora' -and -not $ops) { $ops = $t }
        elseif ($t.Role -eq 'destino') { $dest += $t }
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $level = 'info'
    $max = 0
    foreach ($t in $targets) { if ($t.Total -gt $max) { $max = $t.Total } }
    if ($max -lt 20) {
        return @{ Level = 'info'; Lines = @('Coletando dados... em cerca de 1 minuto aparece aqui uma conclusão.') }
    }
    $set = New-Object System.Collections.Generic.List[string]
    if ($loc -and $loc.Total -ge 20 -and (Get-Pct $loc) -ge 1) {
        $dica = 'suspeite de cabo, placa de rede ou roteador.'
        if ($script:IsWifi) { $dica = 'você está no Wi-Fi: sinal fraco, distância ou interferência também causam isso (teste por cabo).' }
        $lines.Add(('Problema até o roteador ({0}%): {1}' -f (Fmt (Get-Pct $loc)), $dica))
        $set.Add('bad')
    }
    if ($ops -and $ops.Total -ge 20 -and (Get-Pct $ops) -ge 1) {
        $lines.Add(('Problemas até o DNS em uso ({0}%): instabilidade na rede até ele (se for o DNS da operadora, o problema começa na rede dela). Teste outro DNS na aba Ferramentas DNS.' -f (Fmt (Get-Pct $ops))))
        $set.Add('warn')
    }
    $ctlPct = 0.0
    if ($ctl -and $ctl.Total -ge 20) {
        $ctlPct = Get-Pct $ctl
        if ($ctlPct -ge 2) {
            $lines.Add(('O destino de controle também perde ({0}%): a perda atinge a internet em geral (linha ou operadora).' -f (Fmt $ctlPct)))
            $set.Add('bad')
        }
    }
    if ($ctl) {
        foreach ($d in $dest) {
            if ($d.Total -ge 30 -and (Get-Pct $d) -ge ($ctlPct + 3)) {
                $lines.Add(('Perda concentrada em {0} ({1}%) com o controle limpo ({2}%): indício de rota ruim até esse destino ou problema nele, não da sua linha. Vale testar com o Cloudflare WARP.' -f $d.Nome, (Fmt (Get-Pct $d)), (Fmt $ctlPct)))
                $set.Add('warn')
            }
        }
    }
    if ($set.Count -gt 0) {
        if ($set.Contains('bad')) { $level = 'bad' } else { $level = 'warn' }
    } elseif ($max -ge 60) {
        $level = 'ok'
        $lines.Add(('Tudo limpo até agora ({0} testes por destino). Problemas raros podem exigir deixar rodando por mais tempo.' -f $max))
    } else {
        $lines.Add(('Sem problemas até agora ({0} testes). Deixe rodando por mais tempo, principalmente durante o jogo.' -f $max))
    }
    @{ Level = $level; Lines = $lines.ToArray() }
}

# ------------------------------------------------------------ texto para suporte
function Build-SupportText([string]$Kind, $targets, $cfg, $verdict, $serverTarget, $meta) {
    $nl = "`r`n"
    $out = New-Object System.Collections.Generic.List[string]
    $dur = ''
    if ($script:SessionStart -and $script:LastSample) {
        $min = [math]::Round(($script:LastSample - $script:SessionStart).TotalMinutes, 0)
        $dur = ' por cerca de {0} minutos' -f $min
    }
    $data = (Get-Date).ToString('dd/MM/yyyy')
    $conn = 'ligado por cabo de rede'
    if ($script:IsWifi) { $conn = 'conectado por Wi-Fi' }
    $stats = New-Object System.Collections.Generic.List[string]
    foreach ($t in $targets) {
        if ($t.Total -gt 0) {
            $stats.Add(('- {0} ({1}): {2}% com problema em {3} testes ({4} falhas, {5} picos acima de {6} ms); latência média {7} ms' -f $t.Nome, (Get-Endereco $t), (Fmt (Get-Pct $t)), $t.Total, $t.Falhas, $t.Picos, $script:SpikeMs, (Fmt (Get-Avg $t))))
        }
    }
    $speed = ''
    if ($meta -and $meta.ContainsKey('Down')) {
        $speed = ('Teste de velocidade (Cloudflare): {0} Mbps de download e {1} Mbps de upload; ping parado {2} ms, sob carga {3} ms (download) e {4} ms (upload).' -f (Fmt $meta['Down']), (Fmt $meta['Up']), (Fmt $meta['Idle']), (Fmt $meta['LoadDown']), (Fmt $meta['LoadUp']))
    }
    if ($Kind -eq 'servidor') {
        $nome = 'o servidor'
        if ($serverTarget) { $nome = $serverTarget.Nome }
        $out.Add(('Olá! Estou com ping alto e picos de lag no {0} e fiz medições para entender se o problema é a minha internet.' -f $nome))
        $out.Add('')
        $out.Add(('Medições de {0}, com um monitor rodando{1}, no mesmo PC {2}, testando ao mesmo tempo um destino de controle e o servidor:' -f $data, $dur, $conn))
        foreach ($l in $stats) { $out.Add($l) }
        if ($verdict) { $out.Add(''); $out.Add('Conclusão:'); foreach ($l in $verdict.Lines) { $out.Add('- ' + $l) } }
        $out.Add('')
        $out.Add('A conexão para o destino de controle não apresenta o mesmo problema, então não parece ser a minha linha. Peço que verifiquem do lado de vocês: firewall ou proteção anti-DDoS descartando conexões, rota/peering até o meu provedor e carga do servidor no horário. Posso enviar o log em CSV com data e hora de cada medição.')
    } else {
        $prov = ([string]$cfg.Provedor).Trim(); $plano = ([string]$cfg.Plano).Trim()
        $quem = 'Sou cliente de vocês'
        if ($prov) { $quem = 'Sou cliente da ' + $prov; if ($plano) { $quem += ' (plano ' + $plano + ')' } }
        $out.Add(('Olá! {0} e estou com perda intermitente de pacotes e picos de latência.' -f $quem))
        $out.Add('')
        $out.Add(('Medições de {0}, com um monitor rodando{1}, no mesmo PC {2}:' -f $data, $dur, $conn))
        foreach ($l in $stats) { $out.Add($l) }
        if ($speed) { $out.Add(''); $out.Add($speed) }
        if ($verdict) { $out.Add(''); $out.Add('O que isso indica:'); foreach ($l in $verdict.Lines) { $out.Add('- ' + $l) } }
        $out.Add('')
        $out.Add('Peço, por favor, que verifiquem a rota até esses destinos, a potência óptica (Rx Power) da ONU e se há congestionamento ou fila no trecho da rede de vocês. Posso enviar o log em CSV com data e hora de cada medição.')
    }
    ($out.ToArray()) -join $nl
}

# ------------------------------------------------------------ workers de fundo
# Um worker por destino: mede em loop (tempo preciso) e joga o resultado na fila $Q.
$script:WorkerCode = {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $sched = [System.Diagnostics.Stopwatch]::StartNew()
    while ($Ctl.Run) {
        $inicio = $sched.ElapsedMilliseconds
        $status = 'OK'
        $ms = 0.0
        try {
            if ($Port -gt 0) {
                $c = New-Object System.Net.Sockets.TcpClient
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $t = $c.ConnectAsync($Dest, $Port)
                    if ($t.Wait($TimeoutMs) -and $c.Connected) { $ms = $sw.Elapsed.TotalMilliseconds } else { $status = 'FALHA' }
                } catch { $status = 'FALHA' } finally { $c.Close() }
            } else {
                $r = $ping.Send($Dest, $TimeoutMs)
                if ($r.Status -eq 'Success') { $ms = [double]$r.RoundtripTime } else { $status = 'FALHA' }
            }
        } catch { $status = 'FALHA' }
        $Q.Enqueue(@{ Idx = $Idx; Time = [DateTime]::Now; Ms = $ms; Status = $status })
        $resto = $IntervalMs - ($sched.ElapsedMilliseconds - $inicio)
        while ($resto -gt 0 -and $Ctl.Run) {
            $passo = [math]::Min(100, $resto)
            Start-Sleep -Milliseconds $passo
            $resto -= $passo
        }
    }
}

function Start-Bg([scriptblock]$Code, [hashtable]$Vars) {
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    foreach ($k in $Vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $Vars[$k]) }
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Code.ToString())
    [pscustomobject]@{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
}

function Stop-Bg($w) { try { [void]$w.PS.BeginStop($null, $null) } catch { } }

function Dispose-Bg($w) {
    try {
        foreach ($e in $w.PS.Streams.Error) { Log-Error ('bg: ' + $e) }
        $w.PS.Dispose()
        $w.RS.Dispose()
    } catch { }
}

function Start-Worker([int]$Idx, $t, $Ctl, $Q, [int]$IntervalMs, [int]$TimeoutMs) {
    Start-Bg $script:WorkerCode @{
        Idx = $Idx; Dest = $t.Destino; Port = [int]$t.Porta
        Ctl = $Ctl; Q = $Q; IntervalMs = $IntervalMs; TimeoutMs = $TimeoutMs
    }
}
