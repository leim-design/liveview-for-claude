# =====================================================================
#  LiveView for Claude — 실시간 Claude 사용량 위젯  (Windows / PowerShell 5.1+ / WPF)
#  - Claude 계정에 OAuth(공식 인증 방식)로 연결해 사용량을 조회하고
#    항상 위에 떠 있는 작은 창(링 게이지)으로 실시간 표시합니다.
#  - 라이트/다크 테마 전환(◐), 위치 기억, 1분 자동 갱신.
#  - 인증 토큰은 내 컴퓨터(%APPDATA%\ClaudeUsageWidget)에만 저장되고
#    Anthropic 서버(api.anthropic.com) 외에는 어디에도 전송되지 않습니다.
#  - Design by LEIM (www.leim.kr)
# =====================================================================

# --- 단일 실행: 이미 떠 있는 이전 위젯 창은 자동으로 닫기 ---
try {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -like '*ClaudeUsage.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Net.Http

try {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor `
        [System.Net.SecurityProtocolType]::Tls12
} catch { }

# --------------------------- 상수 ---------------------------
$script:AppName     = 'LiveView for Claude'
$script:AppVersion  = '1.0.0'
$script:ClientId    = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'
$script:AuthorizeUrl= 'https://claude.ai/oauth/authorize'
$script:TokenUrl    = 'https://api.anthropic.com/v1/oauth/token'
$script:UsageUrl    = 'https://api.anthropic.com/api/oauth/usage'
$script:ProfileUrl  = 'https://api.anthropic.com/api/oauth/profile'
$script:RedirectUri = 'https://console.anthropic.com/oauth/code/callback'
$script:Scopes      = 'org:create_api_key user:profile user:inference'

# --------------------------- 언어 (시스템 언어 자동 감지) ---------------------------
$script:UiLang = 'en'
try {
    if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ko') { $script:UiLang = 'ko' }
} catch { }
if ($env:LIVEVIEW_LANG -eq 'en' -or $env:LIVEVIEW_LANG -eq 'ko') { $script:UiLang = $env:LIVEVIEW_LANG }

$script:AllStrings = @{
    ko = @{
        title='사용량 라이브뷰'; tipTheme='라이트/다크 전환'; tipRefresh='지금 새로고침'; tipSettings='계정 연결'; tipMinimize='최소화'; tipClose='닫기'
        setTitle='Claude 계정 연결'
        setDesc='아래 버튼을 누르면 브라우저에 Claude 로그인 화면이 열려요. 로그인하고 [허용]을 누르면 나오는 코드를 복사해서 입력칸에 붙여넣은 뒤 [연결]을 누르세요.'
        btnOpenLogin='1. 브라우저에서 로그인 열기'; btnConnect='2. 연결'; btnCloseSet='닫기'
        needConnect='먼저 Claude 계정을 연결해 주세요'; loading='사용량을 불러오는 중…'
        connecting='계정 연결 중…'; connected='계정 연결 완료 — 사용량을 불러오는 중…'
        refreshing='새로고침 중…'; updated='업데이트 {0}'; autoNote='1분마다 자동 갱신'
        authExpired='인증이 만료됐어요 — ⚙에서 다시 연결해 주세요.'
        connFailed='연결 실패({0}) — 코드가 만료됐을 수 있어요. [로그인 열기]부터 다시 해주세요.'
        reconnFailed='재인증 실패 — ⚙에서 다시 연결해 주세요.'
        serverErr='서버 오류({0}) — 잠시 후 다시 시도해요'; netErr='네트워크 오류 — 잠시 후 다시 시도해요'
        reqFailed='요청 실패: {0}'; procErr='오류: {0}'
        rateLimited='요청이 많아 잠시 쉬어가요 — 약 {0}분 후 자동 재시도'
        connectedAs='연결됨 · {0}'; connectedPlain='계정이 연결되어 있어요'; reconnect='다시 연결'; disconnect='연결 해제'
        noItems='사용량 항목을 찾지 못했어요 — debug_log.txt를 확인해 주세요.'
        noToken='연결 실패 — 응답에 토큰이 없어요. 로그를 확인해 주세요.'
        pasteCode='코드를 붙여넣어 주세요.'; pressLoginFirst='먼저 [1. 브라우저에서 로그인 열기]를 눌러 주세요.'
        loginHint='브라우저에서 로그인/허용 후, 표시되는 코드를 붙여넣어 주세요.'
        openLoginFail='로그인 열기 실패: {0}'
        nameSession='세션'; nameWeeklyAll='주간 전체'; sessionPrefix='세션 '
        resetSoon='곧 리셋'; resetDone='리셋됨'; refreshHint='새로고침하면 반영돼요'
        resetTip='{0} 리셋 ({1} 남음)'
        fmtMin='{0}분'; fmtHourMin='{0}시간 {1}분'; fmtDayHour='{0}일 {1}시간'
        dateFmt='M/d HH:mm'
    }
    en = @{
        title='LiveView for Claude'; tipTheme='Toggle light/dark'; tipRefresh='Refresh now'; tipSettings='Connect account'; tipMinimize='Minimize'; tipClose='Close'
        setTitle='Connect your Claude account'
        setDesc='Click the button below to open the Claude sign-in page in your browser. After you sign in and click [Authorize], copy the code shown, paste it into the field, then click [Connect].'
        btnOpenLogin='1. Open sign-in in browser'; btnConnect='2. Connect'; btnCloseSet='Close'
        needConnect='Connect your Claude account to get started'; loading='Loading usage…'
        connecting='Connecting…'; connected='Connected — loading usage…'
        refreshing='Refreshing…'; updated='Updated {0}'; autoNote='Auto-refreshes every minute'
        authExpired='Session expired — reconnect via ⚙.'
        connFailed='Connection failed ({0}) — the code may have expired. Start again from [Open sign-in].'
        reconnFailed='Re-authentication failed — reconnect via ⚙.'
        serverErr='Server error ({0}) — retrying shortly'; netErr='Network error — retrying shortly'
        reqFailed='Request failed: {0}'; procErr='Error: {0}'
        rateLimited='Rate limited — retrying in ~{0} min'
        connectedAs='Connected · {0}'; connectedPlain='Your account is connected'; reconnect='Reconnect'; disconnect='Disconnect'
        noItems='No usage items found — check debug_log.txt.'
        noToken='Connection failed — no token in response. Check the log.'
        pasteCode='Please paste the code.'; pressLoginFirst='Click [1. Open sign-in in browser] first.'
        loginHint='After signing in and authorizing, paste the code shown in the browser.'
        openLoginFail='Could not open sign-in: {0}'
        nameSession='Session'; nameWeeklyAll='Weekly · all'; sessionPrefix='Session '
        resetSoon='Resets soon'; resetDone='Reset'; refreshHint='Refresh to update'
        resetTip='Resets {0} ({1} left)'
        fmtMin='{0}m'; fmtHourMin='{0}h {1}m'; fmtDayHour='{0}d {1}h'
        dateFmt='MMM d HH:mm'
    }
}
$script:S = $script:AllStrings[$script:UiLang]

# --------------------------- 설정/로그 ---------------------------
$script:AppDir     = Join-Path $env:APPDATA 'ClaudeUsageWidget'
$script:ConfigPath = Join-Path $script:AppDir 'config.json'
$script:LogPath    = Join-Path $PSScriptRoot 'debug_log.txt'

function Write-Log([string]$text) {
    try {
        $line = ('[' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $text)
        if ((Test-Path $script:LogPath) -and ((Get-Item $script:LogPath).Length -gt 200KB)) {
            Set-Content -Path $script:LogPath -Value $line -Encoding UTF8
        } else {
            Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
        }
    } catch { }
}

function Load-Config {
    $cfg = @{ accessToken=''; refreshToken=''; expiresAt=0; posX=$null; posY=$null; theme='dark'; email='' }
    if (Test-Path $script:ConfigPath) {
        try {
            $j = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.accessToken)  { $cfg.accessToken  = [string]$j.accessToken }
            if ($j.refreshToken) { $cfg.refreshToken = [string]$j.refreshToken }
            if ($j.expiresAt)    { $cfg.expiresAt    = [double]$j.expiresAt }
            if ($j.posX -ne $null) { $cfg.posX = [double]$j.posX }
            if ($j.posY -ne $null) { $cfg.posY = [double]$j.posY }
            if ($j.theme)        { $cfg.theme = [string]$j.theme }
            if ($j.email)        { $cfg.email = [string]$j.email }
        } catch { }
    }
    return $cfg
}

function Save-Config {
    if (-not (Test-Path $script:AppDir)) {
        New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null
    }
    $script:cfg | ConvertTo-Json | Set-Content -Path $script:ConfigPath -Encoding UTF8
}

$script:cfg = Load-Config

function Get-Epoch { return [double][Math]::Floor(((Get-Date).ToUniversalTime() - (Get-Date '1970-01-01')).TotalSeconds) }

# --------------------------- HTTP ---------------------------
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.UseCookies = $false
$script:http = New-Object System.Net.Http.HttpClient($handler)
$script:http.Timeout = [TimeSpan]::FromSeconds(20)
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
$script:http.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $ua) | Out-Null
$script:http.DefaultRequestHeaders.TryAddWithoutValidation('Accept', 'application/json') | Out-Null

$script:task      = $null
$script:taskKind  = ''
$script:lastFetch = [DateTime]::MinValue
$script:lastData  = $null
$script:refreshTried = $false
$script:FetchIntervalSec = 60
$script:backoffUntil = [DateTime]::MinValue
$script:pkceVerifier = ''

function Start-Get([string]$url, [string]$kind) {
    if ($script:task -ne $null) { return }
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $url)
        $req.Headers.TryAddWithoutValidation('Authorization', ('Bearer ' + $script:cfg.accessToken)) | Out-Null
        $req.Headers.TryAddWithoutValidation('anthropic-beta', 'oauth-2025-04-20') | Out-Null
        $script:task = $script:http.SendAsync($req)
        $script:taskKind = $kind
    } catch {
        $script:task = $null
        Set-Status ($script:S.reqFailed -f $_.Exception.Message) $true
    }
}

function Start-Post([string]$url, $bodyObj, [string]$kind) {
    if ($script:task -ne $null) { return }
    try {
        $json = $bodyObj | ConvertTo-Json -Compress
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $url)
        $req.Content = New-Object System.Net.Http.StringContent($json, [System.Text.Encoding]::UTF8, 'application/json')
        $req.Headers.TryAddWithoutValidation('anthropic-beta', 'oauth-2025-04-20') | Out-Null
        $script:task = $script:http.SendAsync($req)
        $script:taskKind = $kind
    } catch {
        $script:task = $null
        Set-Status ($script:S.reqFailed -f $_.Exception.Message) $true
    }
}

function Begin-Fetch {
    if (-not $script:cfg.accessToken -and -not $script:cfg.refreshToken) { return }
    $script:lastFetch = Get-Date
    if ($script:cfg.refreshToken -and ((Get-Epoch) -ge ($script:cfg.expiresAt - 60))) {
        Start-TokenRefresh
    } else {
        Start-Get $script:UsageUrl 'usage'
    }
}

function Start-TokenRefresh {
    $script:refreshTried = $true
    Start-Post $script:TokenUrl @{ grant_type='refresh_token'; refresh_token=$script:cfg.refreshToken; client_id=$script:ClientId } 'refresh'
}

function Get-PlanLabel([string]$raw) {
    if (-not $raw) { return '' }
    $r = $raw.ToLower()
    if ($r -match '20x')        { return 'Max (20x)' }
    if ($r -match '5x')         { return 'Max (5x)' }
    if ($r -match 'max')        { return 'Max' }
    if ($r -match 'enterprise') { return 'Enterprise' }
    if ($r -match 'team')       { return 'Team' }
    if ($r -match 'pro')        { return 'Pro' }
    if ($r -match 'free')       { return 'Free' }
    return $raw
}

function Apply-Profile($json, [string]$body) {
    if (-not $script:loggedProfileOnce) {
        $script:loggedProfileOnce = $true
        Write-Log ('profile response: ' + $body)
    }
    $raw = ''
    foreach ($cand in @(
        { $json.organization.rate_limit_tier },
        { $json.account.rate_limit_tier },
        { $json.rate_limit_tier },
        { $json.subscriptionType },
        { $json.account.subscriptionType },
        { $json.organization.billing_type },
        { $json.organization.organization_type }
    )) {
        try { $v = & $cand } catch { $v = $null }
        if ($v) { $raw = [string]$v; break }
    }
    $label = Get-PlanLabel $raw
    if ($label) { $script:PlanText.Text = $label }
    try {
        $email = $null
        if ($json.account -ne $null -and $json.account.email_address) { $email = [string]$json.account.email_address }
        elseif ($json.account -ne $null -and $json.account.email) { $email = [string]$json.account.email }
        if ($email) {
            $script:PlanText.ToolTip = $email
            if ($script:cfg.email -ne $email) { $script:cfg.email = $email; Save-Config }
        }
    } catch { }
}

# --------------------------- PKCE ---------------------------
function New-Base64Url([byte[]]$bytes) {
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function Start-Login {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $script:pkceVerifier = New-Base64Url $bytes
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $challenge = New-Base64Url ($sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($script:pkceVerifier)))
    $q = 'code=true' +
         '&client_id=' + $script:ClientId +
         '&response_type=code' +
         '&redirect_uri=' + [Uri]::EscapeDataString($script:RedirectUri) +
         '&scope=' + [Uri]::EscapeDataString($script:Scopes) +
         '&code_challenge=' + $challenge +
         '&code_challenge_method=S256' +
         '&state=' + $script:pkceVerifier
    Start-Process ($script:AuthorizeUrl + '?' + $q)
    Set-Status $script:S.loginHint $false
}

function Connect-WithCode([string]$raw) {
    if (-not $script:pkceVerifier) {
        Set-Status $script:S.pressLoginFirst $true
        return
    }
    $code = $raw.Trim()
    $state = $script:pkceVerifier
    if ($code.Contains('#')) {
        $parts = $code.Split('#')
        $code = $parts[0].Trim()
        if ($parts.Count -gt 1 -and $parts[1]) { $state = $parts[1].Trim() }
    }
    if (-not $code) {
        Set-Status $script:S.pasteCode $true
        return
    }
    Set-Status $script:S.connecting $false
    Start-Post $script:TokenUrl @{
        grant_type='authorization_code'; code=$code; state=$state;
        client_id=$script:ClientId; redirect_uri=$script:RedirectUri;
        code_verifier=$script:pkceVerifier
    } 'token'
}

# --------------------------- 테마 ---------------------------
# 팔레트: Moss / Sage / Ceramic / Acorn / Brown / Clay
# 주간(light) = 그린톤, 야간(dark) = 브라운톤
$script:Themes = @{
    dark = @{
        winBg='#F2332C26'; winBorder='#26FFFFFF'; title='#F2EFE9'; plan='#D9A491'
        btn='#9A9088'; name='#B3A79B'; reset='#948A7E'; pct='#F2EFE9'
        innerFill='Transparent'; track='#1FFFFFFF'; status='#948A7E'; statusErr='#D08B6E'
        setBg='#3E3730'; setFg='#EAE4DC'; setDesc='#B3A79B'; inputBg='#2C2620'; inputFg='#F2EFE9'; inputBorder='#55493F'
        btn2Bg='#4A4139'; okDot='#C9AE93'; connectBg='#B0664A'
        arcNormal='#C9AE93'; arcWarn='#D08B6E'; arcHigh='#C25A3A'
    }
    light = @{
        winBg='#F5F7F5F1'; winBorder='#14000000'; title='#4A5449'; plan='#66755F'
        btn='#8A948A'; name='#7C877B'; reset='#9AA399'; pct='#4A5449'
        innerFill='Transparent'; track='#12000000'; status='#9AA399'; statusErr='#B85C3E'
        setBg='#E7E2CD'; setFg='#4A5449'; setDesc='#7C877B'; inputBg='#FFFFFF'; inputFg='#4A5449'; inputBorder='#C2BCA8'
        btn2Bg='#D8D2BC'; okDot='#66755F'; connectBg='#66755F'
        arcNormal='#A3B9A4'; arcWarn='#66755F'; arcHigh='#C4846B'
    }
}

function Get-ArcBrush([double]$pct) {
    $pal = Get-Pal
    if ($pct -ge 90) { return $pal.arcHigh }
    if ($pct -ge 70) { return $pal.arcWarn }
    return $pal.arcNormal
}

# --------------------------- UI (XAML) ---------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude 사용량" Width="290" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="True">
  <Border x:Name="RootBorder" CornerRadius="22" Background="#F226221F"
          BorderBrush="#26FFFFFF" BorderThickness="1" Padding="16,12,16,12">
    <StackPanel>
      <Grid Margin="2,2,0,10">
        <TextBlock x:Name="TitleText" Text="Claude 사용량" Foreground="#F0EFEA" FontSize="13" FontWeight="SemiBold" HorizontalAlignment="Left" VerticalAlignment="Center"/>
        <TextBlock x:Name="PlanText" Text="" Foreground="#E8B096" FontSize="10.5" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,2,0"/>
        <StackPanel x:Name="BtnPanel" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Visibility="Collapsed">
          <TextBlock x:Name="BtnTheme" Text="&#x25D0;" Foreground="#9A928A" FontSize="13" Margin="0,0,10,0" Cursor="Hand" ToolTip="라이트/다크 전환"/>
          <TextBlock x:Name="BtnRefresh" Text="&#x21BB;" Foreground="#9A928A" FontSize="13" Margin="0,0,10,0" Cursor="Hand" ToolTip="지금 새로고침"/>
          <TextBlock x:Name="BtnSettings" Text="&#x2699;" Foreground="#9A928A" FontSize="13" Margin="0,0,10,0" Cursor="Hand" ToolTip="계정 연결"/>
          <TextBlock x:Name="BtnMinimize" Text="&#x2013;" Background="Transparent" Foreground="#9A928A" FontSize="13" Margin="0,0,10,0" Cursor="Hand" ToolTip="최소화" VerticalAlignment="Center"/>
          <TextBlock x:Name="BtnClose" Text="&#x2715;" Foreground="#9A928A" FontSize="11" Cursor="Hand" ToolTip="닫기" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
      <WrapPanel x:Name="RowsPanel" HorizontalAlignment="Center"/>
      <TextBlock x:Name="StatusText" Foreground="#8D8178" FontSize="9.5" Margin="2,8,0,0" TextWrapping="Wrap" TextAlignment="Center"/>

      <!-- 계정 연결 패널 -->
      <StackPanel x:Name="SettingsPanel" Visibility="Collapsed" Margin="0,10,0,0">
        <Border x:Name="SetCard" Background="#332C29" CornerRadius="12" Padding="12">
          <StackPanel>
            <TextBlock x:Name="SetTitle" Foreground="#E6E0DA" FontSize="11" FontWeight="SemiBold" Text="Claude 계정 연결" Margin="0,0,0,6"/>

            <!-- 이미 연결된 상태 -->
            <StackPanel x:Name="ConnectedView" Visibility="Collapsed">
              <TextBlock x:Name="ConnectedText" Foreground="#B8ACA4" FontSize="10.5" TextWrapping="Wrap"/>
              <Grid Margin="0,10,0,0">
                <TextBlock x:Name="BtnDisconnect" Text="연결 해제" Foreground="#9A928A" FontSize="10.5" HorizontalAlignment="Left" VerticalAlignment="Center" Cursor="Hand"/>
                <Border x:Name="BtnReconnect" Background="#B0664A" CornerRadius="8" Padding="14,5" HorizontalAlignment="Right" Cursor="Hand">
                  <TextBlock x:Name="BtnReconnectText" Text="다시 연결" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                </Border>
              </Grid>
            </StackPanel>

            <!-- 연결 진행 화면 -->
            <StackPanel x:Name="ConnectView">
              <TextBlock x:Name="SetDesc" Foreground="#B8ACA4" FontSize="10.5" TextWrapping="Wrap" LineHeight="16"
                         Text="아래 버튼을 누르면 브라우저에 Claude 로그인 화면이 열려요. 로그인하고 [허용]을 누르면 나오는 코드를 복사해서 입력칸에 붙여넣은 뒤 [연결]을 누르세요."/>
              <Border x:Name="BtnOpenLogin" Background="#403833" CornerRadius="8" Padding="10,6" Margin="0,8,0,0" Cursor="Hand">
                <TextBlock x:Name="BtnOpenLoginText" Text="1. 브라우저에서 로그인 열기" Foreground="#F0EFEA" FontSize="11" HorizontalAlignment="Center"/>
              </Border>
              <TextBox x:Name="CodeBox" Margin="0,8,0,0" Height="26" FontSize="11"
                       Background="#26201E" Foreground="#F0EFEA" BorderBrush="#4A423E"
                       VerticalContentAlignment="Center"/>
              <Grid Margin="0,8,0,0">
                <TextBlock x:Name="BtnCancelSettings" Text="닫기" Foreground="#9A928A" FontSize="11" HorizontalAlignment="Left" VerticalAlignment="Center" Cursor="Hand"/>
                <Border x:Name="BtnConnect" Background="#C96442" CornerRadius="8" Padding="14,5" HorizontalAlignment="Right" Cursor="Hand">
                  <TextBlock x:Name="BtnConnectText" Text="2. 연결" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                </Border>
              </Grid>
            </StackPanel>
          </StackPanel>
        </Border>
        <TextBlock x:Name="VersionText" Text="LiveView for Claude" FontSize="9"
                   Foreground="#8D8178" HorizontalAlignment="Center" Margin="0,8,0,0"/>
        <TextBlock x:Name="CreditText" Text="Designed by LEIM &#183; leim.kr" FontSize="9"
                   Foreground="#8D8178" HorizontalAlignment="Center" Margin="0,2,0,0"
                   Cursor="Hand" ToolTip="www.leim.kr"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:win = [Windows.Markup.XamlReader]::Load($reader)

foreach ($n in @('RootBorder','TitleText','PlanText','BtnPanel','BtnTheme','BtnRefresh','BtnSettings','BtnMinimize','BtnClose',
                 'RowsPanel','StatusText','SettingsPanel','SetCard','SetTitle','SetDesc','BtnOpenLogin','BtnOpenLoginText',
                 'CodeBox','BtnCancelSettings','BtnConnect','BtnConnectText',
                 'ConnectedView','ConnectedText','BtnDisconnect','BtnReconnect','BtnReconnectText','ConnectView','CreditText','VersionText')) {
    Set-Variable -Name $n -Value $script:win.FindName($n) -Scope Script
}

# 작업표시줄/창 아이콘 (위젯 폴더의 widget.ico)
# WindowStyle=None 창은 WPF Icon 속성만으로는 작업표시줄 아이콘이 안 바뀌므로 Win32 WM_SETICON으로 강제 설정
try {
    $script:iconPath = Join-Path $PSScriptRoot 'widget.ico'
    if (Test-Path $script:iconPath) {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.UriSource = New-Object System.Uri $script:iconPath
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.EndInit()
        $script:win.Icon = $bi
        Add-Type -AssemblyName System.Drawing
        if (-not ('Native.IconSetter' -as [type])) {
            Add-Type -Namespace Native -Name IconSetter -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int Msg, System.IntPtr wParam, System.IntPtr lParam);'
        }
        # PowerShell 호스트와 분리된 고유 작업표시줄 ID (안 하면 작업표시줄이 PowerShell 아이콘을 씀)
        if (-not ('Native.Aumid' -as [type])) {
            Add-Type -Namespace Native -Name Aumid -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SetCurrentProcessExplicitAppUserModelID([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPWStr)] string AppID);'
        }
        try { [Native.Aumid]::SetCurrentProcessExplicitAppUserModelID('LEIM.LiveViewForClaude') } catch { }
        $script:win.Add_SourceInitialized({
            try {
                $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($script:win)).Handle
                $script:iconSmall = New-Object System.Drawing.Icon($script:iconPath, 16, 16)
                $script:iconBig   = New-Object System.Drawing.Icon($script:iconPath, 32, 32)
                [Native.IconSetter]::SendMessage($hwnd, 0x80, [System.IntPtr]0, $script:iconSmall.Handle) | Out-Null
                [Native.IconSetter]::SendMessage($hwnd, 0x80, [System.IntPtr]1, $script:iconBig.Handle) | Out-Null
            } catch {
                try { Add-Content -Path $script:LogPath -Value ((Get-Date).ToString('s') + ' ICON WMSET ERR ' + $_.Exception.Message) -Encoding UTF8 } catch { }
            }
        })
    } else {
        try { Add-Content -Path $script:LogPath -Value ((Get-Date).ToString('s') + ' ICON MISSING ' + $script:iconPath) -Encoding UTF8 } catch { }
    }
} catch {
    try { Add-Content -Path $script:LogPath -Value ((Get-Date).ToString('s') + ' ICON ERR ' + $_.Exception.Message) -Encoding UTF8 } catch { }
}

# 언어 적용 (시스템 언어에 따라 자동)
$script:win.Title = $script:S.title
$script:TitleText.Text = $script:S.title
$script:VersionText.Text = ($script:AppName + ' v' + $script:AppVersion)
$script:BtnTheme.ToolTip = $script:S.tipTheme
$script:BtnRefresh.ToolTip = $script:S.tipRefresh
$script:BtnSettings.ToolTip = $script:S.tipSettings
$script:BtnMinimize.ToolTip = $script:S.tipMinimize
$script:BtnClose.ToolTip = $script:S.tipClose
$script:SetTitle.Text = $script:S.setTitle
$script:SetDesc.Text = $script:S.setDesc
$script:BtnOpenLoginText.Text = $script:S.btnOpenLogin
$script:BtnConnectText.Text = $script:S.btnConnect
$script:BtnCancelSettings.Text = $script:S.btnCloseSet
$script:BtnReconnectText.Text = $script:S.reconnect
$script:BtnDisconnect.Text = $script:S.disconnect

if ($script:cfg.posX -ne $null -and $script:cfg.posY -ne $null) {
    $script:win.WindowStartupLocation = 'Manual'
    $script:win.Left = $script:cfg.posX
    $script:win.Top  = $script:cfg.posY
} else {
    $script:win.WindowStartupLocation = 'Manual'
    $wa = [System.Windows.SystemParameters]::WorkArea
    $script:win.Left = $wa.Right - 310
    $script:win.Top  = $wa.Top + 20
}

# --------------------------- 링 게이지 ---------------------------
$script:rows = @{}
$script:lastStatusMsg = ''
$script:lastStatusErr = $false

function Get-Pal {
    $p = $script:Themes[$script:cfg.theme]
    if ($p -eq $null) { $script:cfg.theme = 'dark'; $p = $script:Themes['dark'] }
    return $p
}

function Set-Arc($path, [double]$pct) {
    $cx = 30.0; $cy = 30.0; $r = 27.0
    if ($pct -le 0.2) { $path.Data = $null; return }
    if ($pct -ge 99.8) {
        $path.Data = New-Object System.Windows.Media.EllipseGeometry((New-Object System.Windows.Point($cx,$cy)), $r, $r)
        return
    }
    $ang = 2.0 * [Math]::PI * ($pct / 100.0)
    $sx = $cx; $sy = $cy - $r
    $ex = $cx + $r * [Math]::Sin($ang)
    $ey = $cy - $r * [Math]::Cos($ang)
    $fig = New-Object System.Windows.Media.PathFigure
    $fig.StartPoint = New-Object System.Windows.Point($sx, $sy)
    $arc = New-Object System.Windows.Media.ArcSegment
    $arc.Point = New-Object System.Windows.Point($ex, $ey)
    $arc.Size = New-Object System.Windows.Size($r, $r)
    $arc.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise
    $arc.IsLargeArc = ($pct -gt 50)
    [void]$fig.Segments.Add($arc)
    $geo = New-Object System.Windows.Media.PathGeometry
    [void]$geo.Figures.Add($fig)
    $path.Data = $geo
}

function New-Row([string]$key, [string]$name) {
    $pal = Get-Pal
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Width = 84
    $panel.Margin = New-Object System.Windows.Thickness(0,4,0,4)

    $g = New-Object System.Windows.Controls.Grid
    $g.Width = 60; $g.Height = 60
    $g.HorizontalAlignment = 'Center'

    $ring = New-Object System.Windows.Shapes.Ellipse
    $ring.Width = 54; $ring.Height = 54
    $ring.HorizontalAlignment = 'Center'; $ring.VerticalAlignment = 'Center'
    $ring.Fill = $pal.innerFill
    $ring.Stroke = $pal.track
    $ring.StrokeThickness = 6
    [void]$g.Children.Add($ring)

    $arc = New-Object System.Windows.Shapes.Path
    $arc.Stroke = '#E5A06B'
    $arc.StrokeThickness = 6
    $arc.StrokeStartLineCap = 'Flat'
    $arc.StrokeEndLineCap = 'Flat'
    $arc.Stretch = 'None'
    [void]$g.Children.Add($arc)

    $tbPct = New-Object System.Windows.Controls.TextBlock
    $tbPct.FontSize = 12; $tbPct.FontWeight = 'Bold'
    $tbPct.Foreground = $pal.pct
    $tbPct.HorizontalAlignment = 'Center'; $tbPct.VerticalAlignment = 'Center'
    [void]$g.Children.Add($tbPct)

    $tbName = New-Object System.Windows.Controls.TextBlock
    $tbName.Text = $name
    $tbName.FontSize = 9.5
    $tbName.Foreground = $pal.name
    $tbName.TextAlignment = 'Center'
    $tbName.TextTrimming = 'CharacterEllipsis'
    $tbName.Margin = New-Object System.Windows.Thickness(0,6,0,0)

    $tbReset = New-Object System.Windows.Controls.TextBlock
    $tbReset.FontSize = 8.5
    $tbReset.Foreground = $pal.reset
    $tbReset.TextAlignment = 'Center'
    $tbReset.Margin = New-Object System.Windows.Thickness(0,2,0,0)

    [void]$panel.Children.Add($g)
    [void]$panel.Children.Add($tbName)
    [void]$panel.Children.Add($tbReset)
    [void]$script:RowsPanel.Children.Add($panel)

    $row = @{ panel=$panel; ring=$ring; arc=$arc; pct=$tbPct; name=$tbName; reset=$tbReset }
    $script:rows[$key] = $row
    return $row
}

function Format-Remaining([TimeSpan]$ts) {
    if ($ts.TotalMinutes -lt 1) { return $script:S.resetSoon }
    if ($ts.TotalHours -lt 1)  { return ($script:S.fmtMin -f [int][Math]::Floor($ts.TotalMinutes)) }
    if ($ts.TotalDays -ge 1)   { return ($script:S.fmtDayHour -f [int][Math]::Floor($ts.TotalDays), $ts.Hours) }
    return ($script:S.fmtHourMin -f [int][Math]::Floor($ts.TotalHours), $ts.Minutes)
}

function Get-LimitList {
    # 표시할 항목 목록을 정규화: 신형 limits 배열 우선, 없으면 구형 필드 사용
    $list = New-Object System.Collections.ArrayList
    $d = $script:lastData
    if ($d -eq $null) { return $list }
    $lims = $null
    try { $lims = $d.limits } catch { }
    if ($lims) {
        foreach ($L in @($lims)) {
            if ($L -eq $null -or $L.percent -eq $null) { continue }
            $key = [string]$L.kind
            $name = $null
            if ($L.kind -eq 'session')       { $name = $script:S.nameSession }
            elseif ($L.kind -eq 'weekly_all'){ $name = $script:S.nameWeeklyAll }
            $scopeName = $null
            if ($L.scope -ne $null) {
                try { if ($L.scope.model -ne $null -and $L.scope.model.display_name) { $scopeName = [string]$L.scope.model.display_name } } catch { }
                if (-not $scopeName) { try { if ($L.scope.surface) { $scopeName = [string]$L.scope.surface } } catch { } }
            }
            if ($scopeName) {
                $key = $key + ':' + $scopeName
                if ($L.group -eq 'session') { $name = $script:S.sessionPrefix + $scopeName } else { $name = $scopeName }
            }
            if (-not $name) { $name = $key }
            [void]$list.Add(@{ key=$key; name=$name; pct=[double]$L.percent; resets=$L.resets_at })
        }
    }
    if ($list.Count -eq 0) {
        $legacy = @{ five_hour=$script:S.nameSession; seven_day=$script:S.nameWeeklyAll; seven_day_fable='Fable'; seven_day_sonnet='Sonnet'; seven_day_opus='Opus'; seven_day_haiku='Haiku'; seven_day_cowork='Cowork'; seven_day_oauth_apps='OAuth apps' }
        foreach ($key in @('five_hour','seven_day','seven_day_fable','seven_day_sonnet','seven_day_opus','seven_day_haiku','seven_day_cowork','seven_day_oauth_apps')) {
            $entry = $null
            try { $entry = $d.$key } catch { }
            if ($entry -eq $null -or $entry.utilization -eq $null) { continue }
            [void]$list.Add(@{ key=$key; name=$legacy[$key]; pct=[double]$entry.utilization; resets=$entry.resets_at })
        }
    }
    return $list
}

function Render-Data {
    if ($script:lastData -eq $null) { return }
    $now = Get-Date
    $shown = 0
    foreach ($item in (Get-LimitList)) {
        $shown++
        $key = $item.key
        $row = $script:rows[$key]
        if ($row -eq $null) { $row = New-Row $key $item.name }
        $pct = [double]$item.pct
        if ($pct -lt 0) { $pct = 0 }
        if ($pct -gt 100) { $pct = 100 }
        $row.pct.Text = ('{0}%' -f [Math]::Round($pct))
        $row.arc.Stroke = Get-ArcBrush $pct
        Set-Arc $row.arc $pct
        if ($item.resets) {
            try {
                if ($item.resets -is [DateTime]) {
                    $rt = ([DateTime]$item.resets).ToLocalTime()
                } else {
                    $rt = ([DateTime]::Parse([string]$item.resets, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).ToLocalTime()
                }
                $remain = $rt - $now
                if ($remain.TotalSeconds -le 0) {
                    $row.reset.Text = $script:S.resetDone
                    $row.panel.ToolTip = $script:S.refreshHint
                } else {
                    $row.reset.Text = Format-Remaining $remain
                    $row.panel.ToolTip = ($script:S.resetTip -f $rt.ToString($script:S.dateFmt), (Format-Remaining $remain))
                }
            } catch { $row.reset.Text = '' }
        } else {
            $row.reset.Text = ''
        }
    }
    return $shown
}

function Set-Status([string]$msg, [bool]$isError) {
    $pal = Get-Pal
    $script:lastStatusMsg = $msg
    $script:lastStatusErr = $isError
    $script:StatusText.Text = $msg
    if ($msg) {
        $script:StatusText.Visibility = 'Visible'
    } else {
        $script:StatusText.Visibility = 'Collapsed'
    }
    if ($isError) {
        $script:StatusText.Foreground = $pal.statusErr
    } else {
        $script:StatusText.Foreground = $pal.status
    }
}

function Apply-Theme {
    $pal = Get-Pal
    $script:RootBorder.Background = $pal.winBg
    $script:RootBorder.BorderBrush = $pal.winBorder
    $script:TitleText.Foreground = $pal.title
    $script:PlanText.Foreground = $pal.plan
    foreach ($b in @($script:BtnTheme, $script:BtnRefresh, $script:BtnSettings, $script:BtnClose)) {
        $b.Foreground = $pal.btn
    }
    $script:SetCard.Background = $pal.setBg
    $script:SetTitle.Foreground = $pal.setFg
    $script:SetDesc.Foreground = $pal.setDesc
    $script:BtnOpenLogin.Background = $pal.btn2Bg
    $script:BtnOpenLoginText.Foreground = $pal.setFg
    $script:CodeBox.Background = $pal.inputBg
    $script:CodeBox.Foreground = $pal.inputFg
    $script:CodeBox.BorderBrush = $pal.inputBorder
    $script:BtnCancelSettings.Foreground = $pal.btn
    $script:BtnConnect.Background = $pal.connectBg
    $script:ConnectedText.Foreground = $pal.setDesc
    $script:BtnDisconnect.Foreground = $pal.btn
    $script:BtnReconnect.Background = $pal.connectBg
    $script:CreditText.Foreground = $pal.reset
    $script:VersionText.Foreground = $pal.reset
    # 링들은 다시 그리기
    $script:RowsPanel.Children.Clear()
    $script:rows = @{}
    Render-Data | Out-Null
    Set-Status $script:lastStatusMsg $script:lastStatusErr
}

# --------------------------- 응답 처리 ---------------------------
function Process-Response {
    $t = $script:task
    $kind = $script:taskKind
    $script:task = $null
    try {
        if ($t.IsFaulted -or $t.IsCanceled) {
            Write-Log ("network fail ($kind)")
            Set-Status $script:S.netErr $true
            return
        }
        $resp = $t.Result
        $code = [int]$resp.StatusCode
        $body = $resp.Content.ReadAsStringAsync().Result
        if ($code -ge 400) {
            $snippet = ''
            if ($body) { $snippet = $body.Substring(0, [Math]::Min(1500, $body.Length)) }
            Write-Log ("HTTP $code ($kind) $snippet")
            if ($kind -eq 'profile') { return }   # 플랜 표시는 부가 기능 — 실패해도 조용히 넘어감
            if ($code -eq 429) {
                # 요청 과다 — 서버가 알려준 대기 시간(없으면 5분)만큼 쉬었다가 재시도
                $retrySec = 300.0
                try {
                    $ra = $resp.Headers.RetryAfter
                    if ($ra -ne $null -and $ra.Delta -ne $null) { $retrySec = [Math]::Max(60.0, $ra.Delta.TotalSeconds) }
                } catch { }
                $script:backoffUntil = (Get-Date).AddSeconds($retrySec)
                Set-Status ($script:S.rateLimited -f [int][Math]::Ceiling($retrySec / 60.0)) $true
                return
            }
            if ($kind -eq 'usage' -and ($code -eq 401 -or $code -eq 403)) {
                if ($script:cfg.refreshToken -and -not $script:refreshTried) {
                    Start-TokenRefresh
                    return
                }
                Set-Status $script:S.authExpired $true
                return
            }
            if ($kind -eq 'token') {
                Set-Status ($script:S.connFailed -f $code) $true
                return
            }
            if ($kind -eq 'refresh') {
                Set-Status $script:S.reconnFailed $true
                return
            }
            Set-Status ($script:S.serverErr -f $code) $true
            return
        }
        $json = $body | ConvertFrom-Json
        if ($kind -eq 'token' -or $kind -eq 'refresh') {
            if (-not $json.access_token) {
                Write-Log ("token resp without access_token: $body")
                Set-Status $script:S.noToken $true
                return
            }
            $script:cfg.accessToken = [string]$json.access_token
            if ($json.refresh_token) { $script:cfg.refreshToken = [string]$json.refresh_token }
            $exp = 3600
            if ($json.expires_in) { $exp = [double]$json.expires_in }
            $script:cfg.expiresAt = (Get-Epoch) + $exp - 120
            Save-Config
            if ($kind -eq 'token') {
                $script:SettingsPanel.Visibility = 'Collapsed'
                $script:CodeBox.Text = ''
                Set-Status $script:S.connected $false
            }
            $script:refreshTried = $false
            Start-Get $script:UsageUrl 'usage'
        } elseif ($kind -eq 'usage') {
            $script:refreshTried = $false
            $script:lastData = $json
            if (-not $script:loggedUsageOnce) {
                $script:loggedUsageOnce = $true
                Write-Log ('usage response: ' + $body)
            }
            $shown = Render-Data
            if ($shown -eq 0) {
                Write-Log ("usage resp with no known keys: $body")
                Set-Status $script:S.noItems $true
            } else {
                Set-Status '' $false
                $script:TitleText.ToolTip = ($script:S.updated -f (Get-Date).ToString('HH:mm') + ' · ' + $script:S.autoNote)
            }
            if (-not $script:profileFetched) {
                $script:profileFetched = $true
                Start-Get $script:ProfileUrl 'profile'
            }
        } elseif ($kind -eq 'profile') {
            Apply-Profile $json $body
        }
    } catch {
        Write-Log ('process error: ' + $_.Exception.Message)
        Set-Status ($script:S.procErr -f $_.Exception.Message) $true
    }
}

# --------------------------- 타이머 ---------------------------
$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$script:timer.Add_Tick({
    try {
        if ($script:task -ne $null -and $script:task.IsCompleted) { Process-Response }
        if (($script:cfg.accessToken -or $script:cfg.refreshToken) -and $script:task -eq $null -and (Get-Date) -ge $script:backoffUntil) {
            $elapsed = (Get-Date) - $script:lastFetch
            if ($elapsed.TotalSeconds -ge $script:FetchIntervalSec) { Begin-Fetch }
        }
        Render-Data | Out-Null
    } catch { }
})

# --------------------------- 이벤트 ---------------------------
function Test-Interactive($element) {
    $interactive = @($script:BtnClose, $script:BtnMinimize, $script:BtnRefresh, $script:BtnSettings, $script:BtnTheme,
                     $script:BtnCancelSettings, $script:BtnConnect, $script:BtnOpenLogin, $script:CodeBox,
                     $script:BtnReconnect, $script:BtnDisconnect, $script:CreditText)
    $node = $element
    while ($node -ne $null) {
        foreach ($it in $interactive) {
            if ([object]::ReferenceEquals($node, $it)) { return $true }
        }
        if ($node -is [System.Windows.Media.Visual]) {
            $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
        } else {
            break
        }
    }
    return $false
}

$script:RootBorder.Add_MouseLeftButtonDown({
    param($s, $e)
    if (Test-Interactive $e.OriginalSource) { return }
    try { $script:win.DragMove() } catch { }
})

# 마우스를 올렸을 때만 버튼 표시 (평소엔 플랜명만)
$script:win.Add_MouseEnter({
    $script:BtnPanel.Visibility = 'Visible'
    $script:PlanText.Visibility = 'Collapsed'
})
$script:win.Add_MouseLeave({
    $script:BtnPanel.Visibility = 'Collapsed'
    $script:PlanText.Visibility = 'Visible'
})

$script:BtnClose.Add_MouseLeftButtonUp({
    $script:win.Close()
})

$script:BtnMinimize.Add_MouseLeftButtonUp({
    param($s, $e)
    $script:win.WindowState = [System.Windows.WindowState]::Minimized
    if ($e) { $e.Handled = $true }
})

$script:BtnTheme.Add_MouseLeftButtonUp({
    if ($script:cfg.theme -eq 'dark') { $script:cfg.theme = 'light' } else { $script:cfg.theme = 'dark' }
    Save-Config
    Apply-Theme
})

$script:BtnRefresh.Add_MouseLeftButtonUp({
    if (-not $script:cfg.accessToken -and -not $script:cfg.refreshToken) {
        Show-SettingsPanel
        return
    }
    Set-Status $script:S.refreshing $false
    $script:lastFetch = [DateTime]::MinValue
    $script:backoffUntil = [DateTime]::MinValue
})

function Show-SettingsPanel {
    if ($script:cfg.accessToken -or $script:cfg.refreshToken) {
        if ($script:cfg.email) {
            $script:ConnectedText.Text = ($script:S.connectedAs -f $script:cfg.email)
        } else {
            $script:ConnectedText.Text = $script:S.connectedPlain
        }
        $script:ConnectedView.Visibility = 'Visible'
        $script:ConnectView.Visibility = 'Collapsed'
    } else {
        $script:ConnectedView.Visibility = 'Collapsed'
        $script:ConnectView.Visibility = 'Visible'
    }
    $script:SettingsPanel.Visibility = 'Visible'
}

$script:BtnSettings.Add_MouseLeftButtonUp({
    if ($script:SettingsPanel.Visibility -eq 'Visible') {
        $script:SettingsPanel.Visibility = 'Collapsed'
    } else {
        Show-SettingsPanel
    }
})

$script:BtnReconnect.Add_MouseLeftButtonUp({
    $script:ConnectedView.Visibility = 'Collapsed'
    $script:ConnectView.Visibility = 'Visible'
})

$script:BtnDisconnect.Add_MouseLeftButtonUp({
    $script:cfg.accessToken = ''
    $script:cfg.refreshToken = ''
    $script:cfg.expiresAt = 0
    $script:cfg.email = ''
    Save-Config
    $script:lastData = $null
    $script:RowsPanel.Children.Clear()
    $script:rows = @{}
    $script:PlanText.Text = ''
    $script:PlanText.ToolTip = $null
    $script:profileFetched = $false
    $script:ConnectedView.Visibility = 'Collapsed'
    $script:ConnectView.Visibility = 'Visible'
    Set-Status $script:S.needConnect $false
})

$script:BtnCancelSettings.Add_MouseLeftButtonUp({
    $script:SettingsPanel.Visibility = 'Collapsed'
})

$script:BtnOpenLogin.Add_MouseLeftButtonUp({
    try { Start-Login } catch {
        Write-Log ('login open error: ' + $_.Exception.Message)
        Set-Status ($script:S.openLoginFail -f $_.Exception.Message) $true
    }
})

$script:BtnConnect.Add_MouseLeftButtonUp({
    Connect-WithCode $script:CodeBox.Text
})

$script:CreditText.Add_MouseLeftButtonUp({
    try { Start-Process 'https://www.leim.kr' } catch { }
})

$script:win.Add_Closing({
    try {
        $script:cfg.posX = $script:win.Left
        $script:cfg.posY = $script:win.Top
        Save-Config
    } catch { }
})

# --------------------------- 시작 ---------------------------
Apply-Theme
if (-not $script:cfg.accessToken -and -not $script:cfg.refreshToken) {
    Set-Status $script:S.needConnect $false
    Show-SettingsPanel
} else {
    Set-Status $script:S.loading $false
}

$script:timer.Start()
[void]$script:win.ShowDialog()
