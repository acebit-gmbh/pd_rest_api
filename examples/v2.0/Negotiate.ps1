# Negotiate (Windows SSO / gMSA) login — no password needed.
# -UseDefaultCredentials tells Invoke-RestMethod to use the current process
# identity's Kerberos ticket when the server replies with
# `WWW-Authenticate: Negotiate`.

param(
    [Parameter(Mandatory)] [string] $Server,
    [int] $Port = 8714
)

$response = Invoke-RestMethod `
    -Uri "https://${Server}:${Port}/v2.0/auth/login" `
    -Method POST `
    -Body '{"auth":"negotiate"}' `
    -ContentType "application/json" `
    -UseDefaultCredentials

$token = $response.access_token

Write-Host "Login successful!" -ForegroundColor Green
Write-Host "  Access Token: $($token.Substring(0, 20))..."
