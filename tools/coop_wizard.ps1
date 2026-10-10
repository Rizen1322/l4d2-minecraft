# Co-op menu: host creates one invite code (IP + room token), teammate pastes it.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root
$config=Join-Path $root 'l4d2mc.coop.json'
Write-Host ''
Write-Host '  1 - Я хост (создать комнату и код приглашения)'
Write-Host '  2 - Подключиться к другу по коду'
Write-Host '  3 - Выключить кооп (играть одному)'
$choice=Read-Host 'Выбор'
if($choice -eq '1'){
    & python passthrough/configure_coop.py host | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Не удалось создать комнату.'}
    $token=(Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).token
    # Radmin VPN (26.x), Tailscale/ZeroTier (100.x, 10.x) and home LAN addresses.
    $ips=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Sort-Object InterfaceAlias)
    if(!$ips){throw 'Не найдено ни одной сети.'}
    for($i=0;$i -lt $ips.Count;$i++){ Write-Host ("  {0} - {1}  ({2})" -f ($i+1),$ips[$i].IPAddress,$ips[$i].InterfaceAlias) }
    $pick=Read-Host 'Какой адрес дать другу (Radmin/Tailscale, если вы не в одной сети)'
    $ip=$ips[[int]$pick-1].IPAddress
    $code=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("L4D2MC1|$ip|$token"))
    Set-Clipboard -Value $code
    Write-Host ''
    Write-Host 'Код приглашения скопирован в буфер обмена. Отправь его другу ЛИЧНО:'
    Write-Host $code
    Write-Host 'Потом запускай Launch-L4D2MC-2K.bat как обычно.'
} elseif($choice -eq '2'){
    $code=(Read-Host 'Вставь код приглашения от хоста').Trim()
    $parts=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($code)).Split('|')
    if($parts.Count -ne 3 -or $parts[0] -ne 'L4D2MC1'){throw 'Неверный код приглашения.'}
    $nick=Read-Host 'Твой ник в Steam/L4D2 (точно как в игре)'
    $env:L4D2MC_ROOM_TOKEN=$parts[2]
    try{ & python passthrough/configure_coop.py join --server $parts[1] --player $nick }
    finally{ Remove-Item Env:L4D2MC_ROOM_TOKEN -ErrorAction SilentlyContinue }
    if($LASTEXITCODE -ne 0){throw 'Не удалось сохранить настройки подключения.'}
    Write-Host 'Готово. Запусти Minecraft, потом Launch-L4D2MC-2K.bat (после того как хост загрузил карту).'
} elseif($choice -eq '3'){
    & python passthrough/configure_coop.py off
} else { Write-Host 'Ничего не выбрано.' }
