@echo off
set "PSSCRIPT=%TEMP%\synclock_float.ps1"

(
echo Add-Type -AssemblyName System.Windows.Forms
echo Add-Type -AssemblyName System.Drawing
echo.
echo # === Sync state (matches JS implementation exactly) ===
echo $script:baseServerTime = 0        # server epoch ms at sync point
echo $script:anchorTick = 0            # Stopwatch.ElapsedMilliseconds at sync point
echo $script:isSynced = $false
echo $script:isSyncing = $false
echo $script:lastTickTime = [Environment]::TickCount
echo $script:perfWatch = [System.Diagnostics.Stopwatch]::StartNew^(^)
echo.
echo # === syncTime(reason) — faithful port of JS syncTime ===
echo function Sync-Time ^{
echo     param^([string]$reason = "AUTO"^)
echo     if ^($script:isSyncing^) ^{ return ^}
echo     $script:isSyncing = $true
echo     try ^{
echo         $start = $script:perfWatch.ElapsedMilliseconds
echo         $wc = New-Object System.Net.WebClient
echo         $wc.Headers.Add^("Cache-Control", "no-store"^)
echo         $task = $wc.DownloadStringTaskAsync^("https://1.1.1.1/cdn-cgi/trace"^)
echo         if ^(-not $task.Wait^(4000^)^) ^{ throw "Timeout" ^}
echo         $text = $task.Result
echo         $tsLine = ^($text -split "`n"^) ^| Where-Object ^{ $_ -match "^ts=" ^}
echo         $tsValue = [double]^($tsLine -replace "ts=", ""^)
echo         $tsMs = $tsValue * 1000
echo         $elapsed = $script:perfWatch.ElapsedMilliseconds - $start
echo         $script:baseServerTime = $tsMs + $elapsed / 2
echo         $script:anchorTick = $script:perfWatch.ElapsedMilliseconds
echo         $script:isSynced = $true
echo         # Sync flash
echo         $script:syncIndicator.BackColor = [System.Drawing.Color]::FromArgb^(255, 230, 0^)
echo         $script:flashTimer.Start^(^)
echo     ^} catch ^{
echo         if ^(-not $script:isSynced^) ^{
echo             $script:syncIndicator.BackColor = [System.Drawing.Color]::Gray
echo         ^}
echo     ^} finally ^{
echo         $script:isSyncing = $false
echo     ^}
echo ^}
echo.
echo # === getNow() — equivalent of JS: isSynced ? new Date(baseServerTime + (perf - anchor)) : new Date() ===
echo function Get-SyncedNow ^{
echo     if ^($script:isSynced^) ^{
echo         $elapsedSinceAnchor = $script:perfWatch.ElapsedMilliseconds - $script:anchorTick
echo         $epochMs = $script:baseServerTime + $elapsedSinceAnchor
echo         $epoch = [DateTimeOffset]::FromUnixTimeMilliseconds^([long]$epochMs^)
echo         return $epoch.LocalDateTime
echo     ^} else ^{
echo         return [DateTime]::Now
echo     ^}
echo ^}
echo.
echo # === UI Setup ===
echo $form = New-Object System.Windows.Forms.Form
echo $form.FormBorderStyle = "None"
echo $form.StartPosition = "Manual"
echo $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
echo $form.Size = New-Object System.Drawing.Size^(200, 36^)
echo $form.Location = New-Object System.Drawing.Point^(^($screen.Right - 210^), ^($screen.Bottom - 46^)^)
echo $form.TopMost = $true
echo $form.BackColor = [System.Drawing.Color]::FromArgb^(26, 26, 26^)
echo $form.ShowInTaskbar = $false
echo $form.Opacity = 0.92
echo.
echo # Clock label
echo $label = New-Object System.Windows.Forms.Label
echo $label.Dock = "Fill"
echo $label.ForeColor = [System.Drawing.Color]::White
echo $label.Font = New-Object System.Drawing.Font^("Segoe UI", 12, [System.Drawing.FontStyle]::Bold^)
echo $label.TextAlign = "MiddleCenter"
echo $form.Controls.Add^($label^)
echo.
echo # Sync indicator dot (top-left)
echo $script:syncIndicator = New-Object System.Windows.Forms.Label
echo $script:syncIndicator.Size = New-Object System.Drawing.Size^(8, 8^)
echo $script:syncIndicator.Location = New-Object System.Drawing.Point^(4, 4^)
echo $script:syncIndicator.BackColor = [System.Drawing.Color]::Gray
echo $form.Controls.Add^($script:syncIndicator^)
echo $script:syncIndicator.BringToFront^(^)
echo.
echo # Flash timer (sync feedback — equivalent of JS sync-flash animation)
echo $script:flashTimer = New-Object System.Windows.Forms.Timer
echo $script:flashTimer.Interval = 800
echo $script:flashTimer.Add_Tick^(^{
echo     $script:flashTimer.Stop^(^)
echo     if ^($script:isSynced^) ^{
echo         $script:syncIndicator.BackColor = [System.Drawing.Color]::FromArgb^(255, 230, 0^)
echo     ^}
echo ^}^)
echo.
echo # Drag support
echo $script:dragging = $false
echo $script:dragStart = [System.Drawing.Point]::Empty
echo $label.Add_MouseDown^(^{ param^($s,$e^)
echo     if ^($e.Button -eq "Left"^) ^{ $script:dragging = $true; $script:dragStart = $e.Location ^}
echo ^}^)
echo $label.Add_MouseMove^(^{ param^($s,$e^)
echo     if ^($script:dragging^) ^{
echo         $form.Location = New-Object System.Drawing.Point^(^($form.Left + $e.X - $script:dragStart.X^), ^($form.Top + $e.Y - $script:dragStart.Y^)^)
echo     ^}
echo ^}^)
echo $label.Add_MouseUp^(^{ $script:dragging = $false ^}^)
echo.
echo # Right-click context menu: Manual Sync + Close
echo $menu = New-Object System.Windows.Forms.ContextMenuStrip
echo $syncItem = $menu.Items.Add^("Sync"^)
echo $syncItem.Add_Click^(^{ Sync-Time "MANUAL" ^}^)
echo $closeItem = $menu.Items.Add^("Close"^)
echo $closeItem.Add_Click^(^{ $form.Close^(^) ^}^)
echo $label.ContextMenuStrip = $menu
echo.
echo # === Main tick timer (500ms interval) ===
echo $days = @^("日","月","火","水","木","金","土"^)
echo $script:autoSyncCount = 0
echo $timer = New-Object System.Windows.Forms.Timer
echo $timer.Interval = 500
echo $timer.Add_Tick^(^{
echo     # Wake-up detection: if gap ^> 3000ms, re-sync (matches JS: nowSystem - lastTick ^> 3000)
echo     $nowTick = [Environment]::TickCount
echo     $gap = $nowTick - $script:lastTickTime
echo     if ^($gap -lt 0^) ^{ $gap = $gap + [int]::MaxValue ^}
echo     if ^($gap -gt 3000^) ^{ Sync-Time "WAKE_UP" ^}
echo     $script:lastTickTime = $nowTick
echo.
echo     # Get synced time
echo     $now = Get-SyncedNow
echo     $d = $days[[int]$now.DayOfWeek]
echo     $label.Text = ^("{0}/{1} ({2})  {3}" -f $now.Month, $now.Day, $d, $now.ToString^("HH:mm"^)^)
echo.
echo     # Auto sync every 600 seconds (= 1200 ticks at 500ms) — matches JS: setInterval 600000
echo     $script:autoSyncCount++
echo     if ^($script:autoSyncCount %% 1200 -eq 0^) ^{ Sync-Time "AUTO" ^}
echo ^}^)
echo $timer.Start^(^)
echo.
echo # === Initial sync (matches JS: syncTime("INITIAL")) ===
echo Sync-Time "INITIAL"
echo.
echo [System.Windows.Forms.Application]::Run^($form^)
) > "%PSSCRIPT%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PSSCRIPT%"
del "%PSSCRIPT%" 2>nul
