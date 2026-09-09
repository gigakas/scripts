# Reverse Proxy Configuration

If the AI runtime is exposed beyond a private network, place it behind a reverse proxy.

## Nginx example

```nginx
server {
    listen 443 ssl;
    server_name ai.internal.example.com;

    ssl_certificate /etc/ssl/certs/ai-server.crt;
    ssl_certificate_key /etc/ssl/private/ai-server.key;

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }
}
```

## Security Notes

- Keep the runtime bound to `127.0.0.1` when using a reverse proxy.
- Keep `CHATBOT_AI_BEARER_TOKEN` enabled for networked deployments.
- Use TLS for external access.
- Restrict access through firewall rules when possible.
