$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$layout = Get-Content -LiteralPath (Join-Path $projectRoot 'native/octo/config/arm_layout.json') -Raw | ConvertFrom-Json
if ($layout.arms.Count -ne 8) { throw 'Arm layout must contain exactly eight arms' }
$arms = @($layout.arms | Sort-Object index)
$degrees = ($arms | ForEach-Object { $_.home_degrees.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) }) -join ', '
$models = ($arms | ForEach-Object { $_.model_arm }) -join ', '
$extendKeys = ($arms | ForEach-Object { 'KEY_' + $_.extend_key }) -join ', '
$strokeKeys = ($arms | ForEach-Object { 'KEY_' + $_.stroke_key }) -join ', '
$modelYaw = ([double]$layout.model_yaw_degrees * [Math]::PI / 180).ToString('0.0################', [Globalization.CultureInfo]::InvariantCulture)
$gd = @"
# Generated from native/octo/config/arm_layout.json by tools/generate_arm_layout.ps1.
extends RefCounted
const HOME_DEGREES = [$degrees]
const MODEL_ARM_IDS = [$models]
const MODEL_YAW = $modelYaw
const EXTEND_KEYS = [$extendKeys]
const STROKE_KEYS = [$strokeKeys]
"@
$header = @"
// Generated from config/arm_layout.json. Do not edit the duplicated tables.
#pragma once
#include <array>
namespace octo::layout {
inline constexpr double pi=3.14159265358979323846;
inline constexpr std::array<double,8> degrees{{$degrees}};
inline constexpr std::array<unsigned,8> model_arms{{$models}};
inline constexpr double angle(unsigned arm){return degrees[arm]*pi/180.0;}
}
"@
$encoding = New-Object System.Text.UTF8Encoding($false)
foreach ($relative in @('scripts/octopus/arm_layout.gd','native/octo/game/scripts/arm_layout.gd')) {
    [IO.File]::WriteAllText((Join-Path $projectRoot $relative),$gd.Replace("`r`n","`n") + "`n",$encoding)
}
[IO.File]::WriteAllText((Join-Path $projectRoot 'native/octo/include/octo/arm_layout.hpp'),$header.Replace("`r`n","`n") + "`n",$encoding)
