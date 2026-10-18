# Launches a host and N clients of Sinkhole side by side on one machine.
# Usage (from the repo root):
#   .\tools\run_two.ps1            # host + 1 client
#   .\tools\run_two.ps1 -Clients 2 # host + 2 clients
#   .\tools\run_two.ps1 -Godot "C:\Godot\Godot_v4.7.2-stable_win64.exe"
param(
    [int]$Clients = 1,
    [string]$Godot = "C:\Godot\Godot_v4.7.2-stable_win64.exe"
)

$project = Split-Path -Parent $PSScriptRoot
$width = 960
$height = 540

Start-Process -FilePath $Godot -ArgumentList @(
    "--path", "`"$project`"",
    "--resolution", "${width}x${height}",
    "--position", "0,40",
    "--", "--host"
)

Start-Sleep -Milliseconds 1500

for ($i = 1; $i -le $Clients; $i++) {
    $x = ($i % 2) * ($width + 10)
    $y = 40 + [math]::Floor($i / 2) * ($height + 40)
    Start-Process -FilePath $Godot -ArgumentList @(
        "--path", "`"$project`"",
        "--resolution", "${width}x${height}",
        "--position", "$x,$y",
        "--", "--join=127.0.0.1"
    )
    Start-Sleep -Milliseconds 500
}
