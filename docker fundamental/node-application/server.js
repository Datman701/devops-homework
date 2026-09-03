const http = require('http');

const server = http.createServer((request, response) => {
  response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  response.end(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Hello World</title></head>
<body><h1>Hello World from Node.js</h1></body></html>`);
});

server.listen(80, '0.0.0.0', () => {
  console.log('Node.js app listening on port 80');
});