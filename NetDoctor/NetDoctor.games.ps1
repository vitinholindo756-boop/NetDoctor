# NetDoctor - otimizacoes para jogos (todas reversiveis). Carregado por NetDoctor.ps1.
# Antes de mudar qualquer valor, o original e guardado em jogos-backup.json (modelo de "desfazer"
# usado pelo winutil, de Chris Titus Tech). Valores e chaves seguem a documentacao da Microsoft
# (MMCSS, Windows Error Reporting, HAGS). Nada aqui altera servicos do Windows.

function New-RegOp([string]$P, [string]$N, $V, [string]$T = 'DWord', [bool]$NeedExisting = $false) {
    [pscustomobject]@{ P = $P; N = $N; V = $V; T = $T; NeedExisting = $NeedExisting }
}

$script:HighPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:GameStates = @{}
$script:IsLaptop = $null

$script:GameTweaks = @(
    [pscustomobject]@{
        Id = 'gamemode'; Nome = 'Modo de Jogo do Windows'; Cat = 'Jogos'; Risco = 'Baixo'; Rec = $true; Admin = $false; Tipo = 'reg'
        Desc = 'Liga o Modo de Jogo: durante o jogo, o Windows evita instalar drivers e atualizações e reduz tarefas em segundo plano. O ganho costuma ser pequeno, mas não tem custo.'
        Reg = @((New-RegOp 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1), (New-RegOp 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1)); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'gamebar'; Nome = 'Desativar Xbox Game Bar e gravação em segundo plano'; Cat = 'Jogos'; Risco = 'Baixo'; Rec = $true; Admin = $false; Tipo = 'reg'
        Desc = 'Desliga a gravação em segundo plano (Game DVR) e o painel do Game Bar. Reduz uso de CPU/GPU e quedas de FPS em alguns PCs. Você perde clipes automáticos e o atalho Win+G.'
        Reg = @((New-RegOp 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0), (New-RegOp 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0), (New-RegOp 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0), (New-RegOp 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0)); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'power'; Nome = 'Plano de energia: Alto desempenho'; Cat = 'Energia'; Risco = 'Baixo'; Rec = $true; Admin = $true; Tipo = 'power'
        Desc = 'Ativa o plano Alto desempenho (cria o plano se ele não existir). Mantém o processador em frequência alta. Em notebook gasta mais bateria: use ligado na tomada. Ao reverter, volta o plano anterior.'
        Reg = @(); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'mmcss'; Nome = 'Priorizar jogos no agendador multimídia (MMCSS)'; Cat = 'Jogos'; Risco = 'Baixo'; Rec = $false; Admin = $true; Tipo = 'reg'
        Desc = 'Marca a tarefa Games como prioridade alta no agendador multimídia. A Microsoft documenta esses valores, mas só afeta jogos que usam o MMCSS e o efeito costuma ser pequeno. O valor GPU Priority não é alterado porque a documentação diz que o Windows não o usa.'
        Reg = @((New-RegOp 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'String'), (New-RegOp 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'SFIO Priority' 'High' 'String')); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'hags'; Nome = 'Agendamento de GPU acelerado por hardware (HAGS)'; Cat = 'Jogos'; Risco = 'Médio'; Rec = $false; Admin = $true; Tipo = 'reg'
        Desc = 'Liga o HAGS. Só aparece como compatível se o Windows já mostra essa configuração para a sua placa de vídeo. O efeito varia: alguns jogos melhoram, outros engasgam. Precisa reiniciar o PC. Teste jogo a jogo.'
        Reg = @((New-RegOp 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord' $true)); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'mouse'; Nome = 'Desativar aceleração do mouse'; Cat = 'Jogos'; Risco = 'Baixo'; Rec = $false; Admin = $false; Tipo = 'reg'
        Desc = 'Desliga o Aprimorar precisão do ponteiro, útil em jogos de mira. Muda a sensação do mouse também na área de trabalho. Aplica ao sair e entrar no Windows de novo.'
        Reg = @((New-RegOp 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'), (New-RegOp 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'), (New-RegOp 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String')); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'visual'; Nome = 'Reduzir animações e transparência'; Cat = 'Sistema'; Risco = 'Baixo'; Rec = $false; Admin = $false; Tipo = 'reg'
        Desc = 'Desliga animações de janelas e da barra de tarefas, Aero Peek e transparência. Libera um pouco de CPU/GPU em PCs fracos; o visual fica mais simples. Parte só aparece ao sair e entrar no Windows.'
        Reg = @((New-RegOp 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0), (New-RegOp 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0), (New-RegOp 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'), (New-RegOp 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0)); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'alttab'; Nome = 'Alt+Tab só com janelas abertas'; Cat = 'Sistema'; Risco = 'Baixo'; Rec = $false; Admin = $false; Tipo = 'reg'
        Desc = 'No Windows 11, o Alt+Tab passa a mostrar só as janelas abertas, sem abas do navegador. Mais limpo e rápido para alternar entre jogo e outros programas. No Windows 10 não faz diferença.'
        Reg = @((New-RegOp 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'MultiTaskingAltTabFilter' 3)); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'tasks'; Nome = 'Desativar tarefas agendadas de telemetria'; Cat = 'Sistema'; Risco = 'Baixo'; Rec = $false; Admin = $true; Tipo = 'tasks'
        Desc = 'Desativa 4 tarefas agendadas de telemetria (Compatibility Appraiser, ProgramDataUpdater, Consolidator e UsbCeip). Evita picos de disco e CPU em segundo plano. Não afeta o Windows Update comum. Ao reverter, elas voltam como estavam.'
        Reg = @()
        Tasks = @(
            [pscustomobject]@{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' },
            [pscustomobject]@{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' },
            [pscustomobject]@{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' },
            [pscustomobject]@{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
        )
    },
    [pscustomobject]@{
        Id = 'privacy'; Nome = 'Privacidade: anúncios e sugestões'; Cat = 'Privacidade'; Risco = 'Baixo'; Rec = $false; Admin = $false; Tipo = 'reg'
        Desc = 'Desliga o ID de publicidade, as experiências personalizadas com dados de diagnóstico e as sugestões no menu Iniciar. Não muda o desempenho em jogos, só a privacidade.'
        Reg = @((New-RegOp 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0), (New-RegOp 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0), (New-RegOp 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0)); Tasks = @()
    },
    [pscustomobject]@{
        Id = 'wer'; Nome = 'Privacidade: relatórios de erro do Windows'; Cat = 'Privacidade'; Risco = 'Baixo'; Rec = $false; Admin = $false; Tipo = 'reg'
        Desc = 'Desativa o envio de relatórios de erro (Windows Error Reporting) para a sua conta de usuário. Evita a janela de procurar solução quando um programa fecha. Dificulta diagnosticar travamentos com a Microsoft.'
        Reg = @((New-RegOp 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1)); Tasks = @()
    }
)

# ------------------------------------------------------------ estado atual
# Biblioteca definida uma vez e executada aqui e em segundo plano (Get-ScheduledTask/powercfg/CIM sao lentos).
$script:GameStateLib = @'
$script:HighPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
function Get-RegState([string]$P, [string]$N) {
    try {
        $v = (Get-ItemProperty -Path $P -Name $N -ErrorAction Stop).$N
        return @{ Exists = $true; Value = $v }
    } catch { return @{ Exists = $false; Value = $null } }
}

function Get-ActivePowerGuid {
    $o = (powercfg /getactivescheme 2>$null) | Out-String
    if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1].ToLower() }
    ''
}

function Test-HighPowerActive {
    $o = (powercfg /getactivescheme 2>$null) | Out-String
    if ($o -match $script:HighPerfGuid) { return $true }
    ($o -match 'Alto desempenho|High performance|Desempenho M[aá]ximo|Ultimate Performance')
}

function Test-IsLaptop {
    try { return [bool](Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue) } catch { return $false }
}

# Ativa / Inativa / Parcial / Incompatível
function Get-TweakState($t) {
    try {
        if ($t.Tipo -eq 'power') { if (Test-HighPowerActive) { return 'Ativa' } else { return 'Inativa' } }
        if ($t.Tipo -eq 'tasks') {
            $tot = 0; $dis = 0
            foreach ($k in $t.Tasks) {
                $x = Get-ScheduledTask -TaskPath $k.Path -TaskName $k.Name -ErrorAction SilentlyContinue
                if ($x) { $tot++; if ([string]$x.State -eq 'Disabled') { $dis++ } }
            }
            if ($tot -eq 0) { return 'Incompatível' }
            if ($dis -eq $tot) { return 'Ativa' }
            if ($dis -eq 0) { return 'Inativa' }
            return 'Parcial'
        }
        $tot = 0; $ok = 0
        foreach ($op in $t.Reg) {
            $cur = Get-RegState $op.P $op.N
            if ($op.NeedExisting -and -not $cur.Exists) { return 'Incompatível' }
            $tot++
            if ($cur.Exists -and ([string]$cur.Value -eq [string]$op.V)) { $ok++ }
        }
        if ($tot -gt 0 -and $ok -eq $tot) { return 'Ativa' }
        if ($ok -eq 0) { return 'Inativa' }
        return 'Parcial'
    } catch { return 'Inativa' }
}
'@
. ([scriptblock]::Create($script:GameStateLib))

$script:GameStatesCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    . ([scriptblock]::Create($Lib))
    $res = @{}
    foreach ($t in $Tweaks) { $res[[string]$t.Id] = Get-TweakState $t }
    $lap = Test-IsLaptop
    $Q.Enqueue(@{ Kind = 'game-states'; States = $res; Laptop = $lap })
}

function Get-GameStateCached([string]$Id) {
    if ($script:GameStates.ContainsKey($Id)) { return [string]$script:GameStates[$Id] }
    Get-TweakState (Get-TweakById $Id)
}

function Test-GameRecomendada($t) {
    if ($t.Tipo -eq 'power') {
        if ($null -eq $script:IsLaptop) { $script:IsLaptop = Test-IsLaptop }
        return (-not $script:IsLaptop)
    }
    [bool]$t.Rec
}

# ------------------------------------------------------------ backup (valores originais)
function Get-GameBackupPath { Join-Path (Get-AppDir) 'jogos-backup.json' }

function Read-GameBackup {
    $bk = [pscustomobject]@{ Regs = @(); PowerPrev = ''; Tasks = @(); Data = '' }
    $p = Get-GameBackupPath
    if (Test-Path $p) {
        try {
            $o = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($o) {
                $bk.Regs = @($o.Regs | Where-Object { $_ })
                $bk.PowerPrev = [string]$o.PowerPrev
                $bk.Tasks = @($o.Tasks | Where-Object { $_ })
                $bk.Data = [string]$o.Data
            }
        } catch { Log-Error $_ }
    }
    $bk
}

function Save-GameBackup($bk) {
    try {
        $bk.Data = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        ConvertTo-Json -InputObject $bk -Depth 5 | Set-Content -Path (Get-GameBackupPath) -Encoding UTF8
    } catch { Log-Error $_ }
}

# Somente chaves/valores definidos acima podem ser restaurados (o arquivo de backup nao e confiavel).
function Get-AllowedRegKeys {
    $h = @{}
    foreach ($t in $script:GameTweaks) { foreach ($op in $t.Reg) { $h[($op.P + '|' + $op.N)] = $op } }
    $h
}

function Quote-Ps([string]$s) { "'" + ($s -replace "'", "''") + "'" }

function New-RegSetLine([string]$P, [string]$N, $V, [string]$T) {
    if ($T -eq 'String') { $val = Quote-Ps ([string]$V) } else { $val = [string][int]$V }
    ('if (-not (Test-Path {0})) {{ New-Item -Path {0} -Force | Out-Null }}; Set-ItemProperty -Path {0} -Name {1} -Value {2} -Type {3}' -f (Quote-Ps $P), (Quote-Ps $N), $val, $T)
}

function New-RegRemoveLine([string]$P, [string]$N) {
    ('Remove-ItemProperty -Path {0} -Name {1} -ErrorAction SilentlyContinue' -f (Quote-Ps $P), (Quote-Ps $N))
}

function Set-RegOpLocal([string]$P, [string]$N, $V, [string]$T) {
    if (-not (Test-Path $P)) { New-Item -Path $P -Force | Out-Null }
    if ($T -eq 'String') { Set-ItemProperty -Path $P -Name $N -Value ([string]$V) -Type String }
    else { Set-ItemProperty -Path $P -Name $N -Value ([int]$V) -Type DWord }
}

$script:PowerSetLine = @'
$hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; powercfg /setactive $hp 2>$null; if ($LASTEXITCODE -ne 0) { $o = powercfg /duplicatescheme $hp | Out-String; if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { powercfg /setactive $Matches[1] } else { throw 'plano' } }
'@

function Get-TweakById([string]$Id) { $script:GameTweaks | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }

# ------------------------------------------------------------ aplicar
function Invoke-GameApply([string[]]$Ids) {
    $res = @{ Ok = @(); Fail = @(); Skip = @(); Cancelado = $false }
    $bk = Read-GameBackup
    $elev = New-Object System.Collections.ArrayList
    $local = New-Object System.Collections.ArrayList
    foreach ($id in $Ids) {
        $t = Get-TweakById $id
        if (-not $t) { continue }
        if ((Get-GameStateCached $id) -eq 'Incompatível') { $res.Skip += $t.Nome; continue }
        if ($t.Tipo -eq 'reg') {
            foreach ($op in $t.Reg) {
                $k = $op.P + '|' + $op.N
                $ja = @($bk.Regs) | Where-Object { ($_.P + '|' + $_.N) -eq $k }
                if (-not $ja) {
                    $cur = Get-RegState $op.P $op.N
                    $bk.Regs = @($bk.Regs) + [pscustomobject]@{ Id = $t.Id; P = $op.P; N = $op.N; Exists = $cur.Exists; Value = $cur.Value; T = $op.T }
                }
                if ($op.P -like 'HKLM:*') { [void]$elev.Add((New-RegSetLine $op.P $op.N $op.V $op.T)) }
                else { [void]$local.Add([pscustomobject]@{ Id = $t.Id; P = $op.P; N = $op.N; V = $op.V; T = $op.T }) }
            }
        } elseif ($t.Tipo -eq 'power') {
            if (-not $bk.PowerPrev) {
                $g = Get-ActivePowerGuid
                if ($g -and -not (Test-HighPowerActive)) { $bk.PowerPrev = $g }
            }
            [void]$elev.Add($script:PowerSetLine)
        } elseif ($t.Tipo -eq 'tasks') {
            foreach ($k in $t.Tasks) {
                $x = Get-ScheduledTask -TaskPath $k.Path -TaskName $k.Name -ErrorAction SilentlyContinue
                if (-not $x) { continue }
                $ja = @($bk.Tasks) | Where-Object { $_.Path -eq $k.Path -and $_.Name -eq $k.Name }
                if (-not $ja) { $bk.Tasks = @($bk.Tasks) + [pscustomobject]@{ Path = $k.Path; Name = $k.Name; WasEnabled = ([string]$x.State -ne 'Disabled') } }
                [void]$elev.Add(('Disable-ScheduledTask -TaskPath {0} -TaskName {1} -ErrorAction SilentlyContinue | Out-Null' -f (Quote-Ps $k.Path), (Quote-Ps $k.Name)))
            }
        }
    }
    Save-GameBackup $bk
    foreach ($op in $local) {
        try { Set-RegOpLocal $op.P $op.N $op.V $op.T } catch { Log-Error $_ }
    }
    $elevOk = $true
    if ($elev.Count -gt 0) {
        $script2 = '$ErrorActionPreference = ''Stop''; try { ' + ($elev -join '; ') + '; exit 0 } catch { exit 1 }'
        $code = Invoke-Elevated $script2
        if ($null -eq $code) { $res.Cancelado = $true; $elevOk = $false }
        elseif ($code -ne 0) { $elevOk = $false }
    }
    foreach ($id in $Ids) {
        $t = Get-TweakById $id
        if (-not $t -or $res.Skip -contains $t.Nome) { continue }
        # tarefas agendadas: confia no codigo de saida (Get-ScheduledTask e lento); a lista confirma em segundo plano
        if ($t.Tipo -eq 'tasks') { $ok = $elevOk } else { $ok = ((Get-TweakState $t) -eq 'Ativa') }
        if ($ok) { $res.Ok += $t.Nome; $script:GameStates[$id] = 'Ativa' } else { $res.Fail += $t.Nome }
    }
    $res
}

# ------------------------------------------------------------ reverter
function Invoke-GameRevert([string[]]$Ids) {
    $res = @{ Feitos = 0; Cancelado = $false; Falhou = $false }
    $bk = Read-GameBackup
    $allowed = Get-AllowedRegKeys
    $elev = New-Object System.Collections.ArrayList
    $dropLocal = New-Object System.Collections.ArrayList
    $dropElev = New-Object System.Collections.ArrayList
    $dropPower = $false; $dropTasks = New-Object System.Collections.ArrayList

    foreach ($e in @($bk.Regs)) {
        if ($Ids -notcontains [string]$e.Id) { continue }
        $k = [string]$e.P + '|' + [string]$e.N
        if (-not $allowed.ContainsKey($k)) { continue }
        $op = $allowed[$k]
        $isHklm = ($op.P -like 'HKLM:*')
        if (-not [bool]$e.Exists) {
            if ($isHklm) { [void]$elev.Add((New-RegRemoveLine $op.P $op.N)); [void]$dropElev.Add($k) }
            else { try { Remove-ItemProperty -Path $op.P -Name $op.N -ErrorAction SilentlyContinue; [void]$dropLocal.Add($k) } catch { Log-Error $_ } }
            continue
        }
        $val = $null
        if ($op.T -eq 'String') {
            $s = [string]$e.Value
            if ($s -notmatch '^[\w .\-]{0,60}$') { continue }
            $val = $s
        } else {
            try { $val = [int]$e.Value } catch { continue }
        }
        if ($isHklm) { [void]$elev.Add((New-RegSetLine $op.P $op.N $val $op.T)); [void]$dropElev.Add($k) }
        else { try { Set-RegOpLocal $op.P $op.N $val $op.T; [void]$dropLocal.Add($k) } catch { Log-Error $_ } }
    }

    if ($Ids -contains 'power' -and $bk.PowerPrev -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        [void]$elev.Add(('powercfg /setactive {0}; if ($LASTEXITCODE -ne 0) {{ throw ''plano'' }}' -f $bk.PowerPrev))
        $dropPower = $true
    }
    if ($Ids -contains 'tasks') {
        $tw = Get-TweakById 'tasks'
        foreach ($e in @($bk.Tasks)) {
            $permitida = $tw.Tasks | Where-Object { $_.Path -eq [string]$e.Path -and $_.Name -eq [string]$e.Name }
            if (-not $permitida) { continue }
            if ([bool]$e.WasEnabled) {
                [void]$elev.Add(('Enable-ScheduledTask -TaskPath {0} -TaskName {1} -ErrorAction SilentlyContinue | Out-Null' -f (Quote-Ps ([string]$e.Path)), (Quote-Ps ([string]$e.Name))))
            }
            [void]$dropTasks.Add(([string]$e.Path + '|' + [string]$e.Name))
        }
    }

    $elevOk = $true
    if ($elev.Count -gt 0) {
        $script2 = '$ErrorActionPreference = ''Stop''; try { ' + ($elev -join '; ') + '; exit 0 } catch { exit 1 }'
        $code = Invoke-Elevated $script2
        if ($null -eq $code) { $res.Cancelado = $true; $elevOk = $false }
        elseif ($code -ne 0) { $res.Falhou = $true; $elevOk = $false }
    }

    $drop = New-Object System.Collections.ArrayList
    foreach ($k in $dropLocal) { [void]$drop.Add($k) }
    if ($elevOk) { foreach ($k in $dropElev) { [void]$drop.Add($k) } }
    $bk.Regs = @(@($bk.Regs) | Where-Object { $drop -notcontains ([string]$_.P + '|' + [string]$_.N) })
    if ($elevOk -and $dropPower) { $bk.PowerPrev = '' }
    if ($elevOk) { $bk.Tasks = @(@($bk.Tasks) | Where-Object { $dropTasks -notcontains ([string]$_.Path + '|' + [string]$_.Name) }) }
    $res.Feitos = $drop.Count + $(if ($elevOk -and $dropPower) { 1 } else { 0 }) + $(if ($elevOk) { $dropTasks.Count } else { 0 })
    Save-GameBackup $bk
    $res
}

# ------------------------------------------------------------ utilitarios
# 0 = criado, 2 = ja existe um recente (limite de 24 h do Windows), 1 = falhou, $null = permissao recusada
function Invoke-RestorePoint {
    $s = '$ErrorActionPreference = ''Stop''; try { Enable-ComputerRestore -Drive ($env:SystemDrive + ''\''); $w = $null; Checkpoint-Computer -Description ''NetDoctor'' -RestorePointType MODIFY_SETTINGS -WarningVariable w -WarningAction SilentlyContinue; if ($w) { exit 2 } else { exit 0 } } catch { exit 1 }'
    Invoke-Elevated $s
}

# Ferramentas demoradas abrem uma janela propria (administrador) para voce acompanhar.
function Start-GameTool([string]$Tool) {
    $fim = "Write-Host ''; Read-Host 'Pressione Enter para fechar'"
    switch ($Tool) {
        'temp' {
            $a = Quote-Ps $env:TEMP; $b = Quote-Ps (Join-Path $env:SystemRoot 'Temp')
            $s = '$ErrorActionPreference = ''SilentlyContinue''; $dirs = @(' + $a + ', ' + $b + '); ' +
                'Write-Host ''NetDoctor - limpando arquivos temporários...'' -ForegroundColor Cyan; ' +
                '$antes = 0.0; foreach ($d in $dirs) { if ($d.Length -ge 8 -and (Test-Path -LiteralPath $d)) { $antes += [double](Get-ChildItem -LiteralPath $d -Force -Recurse -File | Measure-Object Length -Sum).Sum } }; ' +
                'foreach ($d in $dirs) { if ($d.Length -ge 8 -and (Test-Path -LiteralPath $d)) { Get-ChildItem -LiteralPath $d -Force | Remove-Item -Recurse -Force } }; ' +
                '$depois = 0.0; foreach ($d in $dirs) { if ($d.Length -ge 8 -and (Test-Path -LiteralPath $d)) { $depois += [double](Get-ChildItem -LiteralPath $d -Force -Recurse -File | Measure-Object Length -Sum).Sum } }; ' +
                'Write-Host (''Liberado: {0:N1} MB (arquivos em uso são mantidos).'' -f (($antes - $depois) / 1MB)) -ForegroundColor Green; ' + $fim
        }
        'disks' {
            $s = '$ErrorActionPreference = ''Continue''; Write-Host ''NetDoctor - otimizando discos (SSD: TRIM, HDD: desfragmentar)'' -ForegroundColor Cyan; ' +
                'Get-Volume | Where-Object { $_.DriveType -eq ''Fixed'' -and $_.DriveLetter } | ForEach-Object { $l = $_.DriveLetter; $tipo = ''Desconhecido''; ' +
                'try { $pd = Get-Partition -DriveLetter $l | Get-Disk | Get-PhysicalDisk; $tipo = [string]$pd.MediaType } catch { }; ' +
                'if ($tipo -eq ''SSD'') { Write-Host ("Unidade ${l}: SSD -> TRIM") -ForegroundColor Yellow; Optimize-Volume -DriveLetter $l -ReTrim -Verbose } ' +
                'elseif ($tipo -eq ''HDD'') { Write-Host ("Unidade ${l}: HDD -> desfragmentar") -ForegroundColor Yellow; Optimize-Volume -DriveLetter $l -Defrag -Verbose } ' +
                'else { Write-Host ("Unidade ${l}: tipo não identificado, ignorada") -ForegroundColor DarkGray } }; ' + $fim
        }
        'sfc' {
            $s = 'Write-Host ''NetDoctor - verificando arquivos do Windows (pode levar 10 a 20 minutos)'' -ForegroundColor Cyan; sfc /scannow; ' + $fim
        }
        default { return $null }
    }
    Invoke-Elevated $s -NoWait -Visible
}
