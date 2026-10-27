# Shared by the server blocks in nginx.prod.conf and nginx.prod.http.conf

client_max_body_size 6m;

# Internal endpoints are for the API and Match Engine only
location /internal/ {
    return 404;
}

location = /internal {
    return 404;
}

location /api/ {
    proxy_pass http://api:3000;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
