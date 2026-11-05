param(
    [int]$Port = 0,
    [switch]$NoReload
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$python = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $python)) {
    Write-Host "Создаю виртуальное окружение..."
    python -m venv .venv
    & $python -m pip install --upgrade pip
    & $python -m pip install -r requirements.txt
}

if (-not (Test-Path -LiteralPath ".env")) {
    Write-Host "Создаю .env со случайным SECRET_KEY..."
    $secret = & $python -c "import secrets; print(secrets.token_urlsafe(48))"
    $content = Get-Content -LiteralPath ".env.example" -Raw
    $content = $content.Replace("replace-with-a-long-random-string", $secret)
    Set-Content -LiteralPath ".env" -Value $content -Encoding UTF8 -NoNewline
    Write-Host "Проверьте POSTGRES_PORT и DATABASE_URL в .env."
}

if ($Port -le 0) {
    $Port = 8000
    while (
        $Port -le 8100 -and
        (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    ) {
        $Port++
    }
    if ($Port -gt 8100) {
        throw "Не удалось найти свободный порт в диапазоне 8000-8100."
    }
}

Write-Host ""
Write-Host "API:     http://127.0.0.1:$Port"
Write-Host "Swagger: http://127.0.0.1:$Port/docs"
Write-Host ""

$uvicornArgs = @(
    "-m", "uvicorn", "app.main:app",
    "--host", "127.0.0.1",
    "--port", "$Port"
)
if (-not $NoReload) {
    $uvicornArgs += "--reload"
}

& $python @uvicornArgs
