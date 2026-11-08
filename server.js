const http = require('http');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const port = Number(process.env.PORT || 8080);
const apiKey = process.env.GEMINI_API_KEY;
const types = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon'
};

function sendJson(response, status, value) {
    response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
    response.end(JSON.stringify(value));
}

async function handleGenerate(request, response) {
    if (!apiKey) {
        sendJson(response, 503, { error: { message: 'Server chưa cấu hình GEMINI_API_KEY' } });
        return;
    }

    let body = '';
    request.on('data', chunk => {
        body += chunk;
        if (body.length > 10 * 1024 * 1024) {
            request.destroy();
        }
    });
    request.on('end', async () => {
        try {
            const { model, payload } = JSON.parse(body || '{}');
            if (!/^gemini-[a-zA-Z0-9.-]+$/.test(model || '')) {
                sendJson(response, 400, { error: { message: 'Model không hợp lệ' } });
                return;
            }

            const upstream = await fetch(
                `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                }
            );
            const data = await upstream.text();
            response.writeHead(upstream.status, { 'Content-Type': 'application/json; charset=utf-8' });
            response.end(data);
        } catch (error) {
            sendJson(response, 500, { error: { message: error.message || 'Lỗi máy chủ' } });
        }
    });
}

const server = http.createServer((request, response) => {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    if (pathname === '/api/generate' && request.method === 'POST') {
        handleGenerate(request, response);
        return;
    }

    const relativePath = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
    const filePath = path.resolve(root, relativePath);
    if (!filePath.startsWith(root + path.sep)) {
        sendJson(response, 403, { error: { message: 'Không cho phép truy cập' } });
        return;
    }

    fs.readFile(filePath, (error, data) => {
        if (error) {
            response.writeHead(error.code === 'ENOENT' ? 404 : 500);
            response.end(error.code === 'ENOENT' ? 'Not found' : 'Server error');
            return;
        }
        response.writeHead(200, { 'Content-Type': types[path.extname(filePath).toLower()] || 'application/octet-stream' });
        response.end(data);
    });
});

server.listen(port, () => {
    console.log(`PHUC BT server listening on port ${port}`);
});
