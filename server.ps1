$root = 'C:\Users\User\Phuc-Toan-AI'
$apiKey = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY', 'User')
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://localhost:8080/')

try {
    $listener.Start()
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $bytes = [byte[]]@()
    try {
        $requestPath = $context.Request.Url.AbsolutePath
        if ($requestPath -eq '/api/generate' -and $context.Request.HttpMethod -eq 'POST') {
            $reader = [System.IO.StreamReader]::new($context.Request.InputStream, $context.Request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Dispose()
            $request = $body | ConvertFrom-Json
            $model = [string]$request.model
            if ($model -notmatch '^gemini-[a-zA-Z0-9.-]+$') {
                throw [System.ArgumentException]::new('Invalid model')
            }

            $payload = $request.payload | ConvertTo-Json -Depth 100 -Compress
            $url = "https://generativelanguage.googleapis.com/v1beta/models/$model`:generateContent?key=$apiKey"
            try {
                $responseObject = Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 90
                $responseBody = $responseObject | ConvertTo-Json -Depth 100 -Compress
                $context.Response.StatusCode = 200
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            } catch {
                $webException = $_.Exception
                if ($webException.Response) {
                    $context.Response.StatusCode = [int]$webException.Response.StatusCode
                    $responseStream = $webException.Response.GetResponseStream()
                    $errorReader = [System.IO.StreamReader]::new($responseStream)
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($errorReader.ReadToEnd())
                } else {
                    $context.Response.StatusCode = 502
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":{"message":"Google API connection failed"}}')
                }
            }
            $context.Response.ContentType = 'application/json; charset=utf-8'
        } else {
            $relative = if ($requestPath -eq '/') { 'index.html' } else { $requestPath.TrimStart('/') }
            $file = Join-Path $root $relative
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($file)
                $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
                $contentTypes = @{
                    '.html' = 'text/html; charset=utf-8'
                    '.js' = 'application/javascript'
                    '.json' = 'application/json'
                    '.css' = 'text/css'
                    '.png' = 'image/png'
                    '.jpg' = 'image/jpeg'
                    '.svg' = 'image/svg+xml'
                    '.ico' = 'image/x-icon'
                }
                $context.Response.ContentType = if ($contentTypes[$extension]) { $contentTypes[$extension] } else { 'application/octet-stream' }
                $context.Response.StatusCode = 200
            } else {
                $context.Response.StatusCode = 404
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('Not found')
            }
        }
    } catch {
        $context.Response.StatusCode = 500
        $context.Response.ContentType = 'application/json; charset=utf-8'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((@{ error = @{ message = $_.Exception.Message } } | ConvertTo-Json -Compress))
    } finally {
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()
        $context.Response.Close()
    }
}
