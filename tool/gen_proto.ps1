# 重新生成 Dart protobuf / gRPC 代码
# 用法: powershell -File tool\gen_proto.ps1
$ErrorActionPreference = 'Stop'

$Root    = Split-Path -Parent $PSScriptRoot
$Protoc  = 'C:\apps\protoc-36.1\bin\protoc.exe'
$Plugin  = "$env:LOCALAPPDATA\Pub\Cache\bin\protoc-gen-dart.bat"
$ProtoIn = Join-Path $Root 'proto'
$OutDir  = Join-Path $Root 'core\lib\src\generated'

if (-not (Test-Path $Protoc))  { throw "protoc not found: $Protoc" }
if (-not (Test-Path $Plugin))  { throw "protoc-gen-dart not found: $Plugin (run: dart pub global activate protoc_plugin)" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $Protoc `
  --proto_path="$ProtoIn" `
  --plugin=protoc-gen-dart="$Plugin" `
  --dart_out=grpc:"$OutDir" `
  littlelaw.proto

if ($LASTEXITCODE -ne 0) { throw "protoc failed with exit code $LASTEXITCODE" }
Write-Host "Generated into $OutDir"
