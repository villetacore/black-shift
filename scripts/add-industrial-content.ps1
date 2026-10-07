# Original content placements, reproducible and shared with the map builder.
$ErrorActionPreference='Stop'
$mapPath=Join-Path $PSScriptRoot '../server/priv/maps/foundry.json'
$m=Get-Content $mapPath -Raw | ConvertFrom-Json
$m.objects=@($m.objects | Where-Object { $_.id -notlike 'exp-*' })
function Add-Prop($id,$model,$position,$size,$yaw=0,$collision=$true) {
    $m.objects+= [pscustomobject]@{id="exp-$id";shape='box';model=$model;position=$position;size=$size;yaw=[double]$yaw;material=6;uv_scale=0.7;collision=$collision}
}
Add-Prop 'console-west' 'console' @(10,1.4,0.7) @(1.4,0.9,1.4)
Add-Prop 'console-pump' 'console' @(40,9.8,1.9) @(1.6,0.9,1.4) 180
Add-Prop 'console-generator' 'console' @(58.5,17,0.8) @(1.6,1,1.6) 90
Add-Prop 'generator-a' 'generator' @(54,13.8,0.8) @(2.8,1.6,1.6)
Add-Prop 'generator-b' 'generator' @(57,13.8,0.8) @(2.2,1.6,1.6)
Add-Prop 'tank-a' 'tank' @(32,9.7,1.4) @(1.8,1.8,2.8)
Add-Prop 'tank-b' 'tank' @(34.2,9.7,1.4) @(1.8,1.8,2.8)
Add-Prop 'pump-a' 'pump' @(40,2.4,0.55) @(2.2,1.3,1.1)
Add-Prop 'pump-b' 'pump' @(44,2.4,0.55) @(2.2,1.3,1.1)
Add-Prop 'spool-a' 'cable-spool' @(44,29,0.7) @(1.5,1.4,1.4)
Add-Prop 'spool-b' 'cable-spool' @(10,41.8,0.6) @(1.2,1.2,1.2) 90
Add-Prop 'pallet-a' 'pallet' @(55,41.5,1.35) @(2.5,1.3,0.3)
Add-Prop 'pallet-b' 'pallet' @(55,41.5,1.65) @(2.5,1.3,0.3) 8
Add-Prop 'pallet-c' 'pallet' @(5,28,0.15) @(2.5,1.3,0.3)
Add-Prop 'barrier-a' 'barricade' @(32,28,0.6) @(3,0.8,1.2) 15
Add-Prop 'barrier-b' 'barricade' @(46,15,0.6) @(3,0.8,1.2) -15
foreach($x in @(51,54,57)) { Add-Prop "bollard-$x" 'bollard' @($x,42.8,0.5) @(0.5,0.5,1) }
foreach($x in @(5,14,25,40)) { Add-Prop "fan-$x" 'fan' @($x,43.3,2.7) @(1.3,0.45,1.3) 180 $false }
foreach($x in @(31,39,47)) {
 Add-Prop "lamp-$x" 'lamp' @($x,12.35,3.4) @(0.6,0.45,0.8) 0 $false
}
# Contained cooling basin with steps on both sides of the east rim.
Add-Prop 'basin-west' '' @(30.9,1.9,1) @(0.2,2,2)
Add-Prop 'basin-north' '' @(33.5,0.9,1) @(5.4,0.2,2)
Add-Prop 'basin-south' '' @(33.5,2.9,1) @(5.4,0.2,2)
Add-Prop 'basin-east' '' @(36.1,1.9,1) @(0.2,2,2)
for($i=0;$i -lt 6;$i++) {
 $h=0.3*($i+1)
 Add-Prop "basin-inner-step-$i" '' @((33.8+0.4*$i),1.9,($h/2)) @(0.4,1,$h)
 Add-Prop "basin-outer-step-$i" '' @((38.4-0.4*$i),1.9,($h/2)) @(0.4,1,$h)
}
$m | Add-Member -Force NoteProperty liquids @(
 @{id='cooling-water';rect=@(31,1,36,2.8);bottom=0;surface=1.9;current=@(0.35,0);color=@(0.13,0.30,0.29)},
 @{id='service-flood';rect=@(35,38,45,42.8);bottom=0;surface=0.32;current=@(-0.25,0.08);color=@(0.28,0.27,0.12)}
)
$m | ConvertTo-Json -Depth 30 -Compress | Set-Content $mapPath
# Store the expansion so the Elixir map generator reproduces it on all platforms.
@{objects=@($m.objects | Where-Object { $_.id -like 'exp-*' });liquids=$m.liquids} | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $PSScriptRoot '../server/priv/maps/industrial-expansion.json')


