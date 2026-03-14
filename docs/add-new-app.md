# Add A New App

This guide shows how to add a new project to this VPS template after the server is already set up.

The idea is simple:

1. Create a new folder for your app
2. Add a `compose.yaml`
3. Connect the app to the shared Docker network
4. Add a route in Caddy
5. Point DNS to the same VPS
6. Start the app

You do **not** need to run the full VPS bootstrap script again just to add a new app.

If you want the full explanation of how domains and per-app Caddy routes work, also read:

- [Domains And Routing](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/domains-and-routing.md)

## Example goal

In this guide, we will pretend you want to add a new app called `crm`.

Its public hostname can be whatever you want, for example:

- `crm.nxt-solutions.com`
- `crm.cheaper.promo`
- `maptoposter.com`

You can replace both the app name and the hostname with your real values.

## Before you start

Make sure:

1. Your VPS is already set up with this template
2. Docker is running
3. Caddy is already running
4. The shared Docker networks `web` and `internal` already exist

If you already ran:

```bash
sudo ./bin/setup-vps.sh --config ./config/server.env
```

then you are ready.

## Step 1. Create a new folder

From the root of this repo, create a new folder for your app:

```bash
mkdir crm
mkdir -p crm/site
```

You can name the folder whatever you want. Usually the folder name should match the app name.

## Step 2. Create the app's compose file

Create:

- `crm/compose.yaml`

Start from this pattern:

```yaml
---
services:
  crm:
    image: nginx:stable-alpine
    restart: unless-stopped
    volumes:
      - ./site:/usr/share/nginx/html:ro
    expose:
      - "80"
    networks:
      web:
        aliases:
          - crm
      internal:

networks:
  web:
    external: true
  internal:
    external: true
```

Important rules:

- Do **not** publish host ports like `3000:3000` or `80:80`
- Use `expose` instead of `ports`
- Attach the app to the shared `web` network
- Give it a stable alias, like `crm`
- If the app needs databases, queues, or internal services, use `internal` too

## Step 3. Add some test content

If you use the example above, create:

- `crm/site/index.html`

Example:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>CRM</title>
  </head>
  <body>
    <h1>CRM is live</h1>
  </body>
</html>
```

Later, replace this with your real app image and files.

## Step 4. Choose the public hostname

You can use:

- a subdomain like `crm.nxt-solutions.com`
- a subdomain on a different base domain like `crm.cheaper.promo`
- a root domain like `maptoposter.com`

This VPS template supports all of those patterns.

For the rest of this guide, we will use:

- `crm.nxt-solutions.com`

## Step 5. Add a DNS record

Go to your DNS provider and create a record for the new app.

Example:

- Type: `A`
- Name: `crm`
- Value: `YOUR_VPS_IP`

That gives you:

- `crm.nxt-solutions.com`

If you use IPv6, also add an `AAAA` record that points to your VPS IPv6 address.

## Step 6. Create a Caddy route file

Create a new file:

```bash
nano caddy/sites/crm.caddy
```

Add:

```caddyfile
crm.nxt-solutions.com {
	encode zstd gzip
	reverse_proxy crm:80
}
```

How this works:

- `crm.nxt-solutions.com` is the public domain
- `crm` is the Docker network alias from `crm/compose.yaml`
- `80` is the port exposed by the app inside Docker

If your app listens on a different internal port, change `80` to the correct port.

The route file can also use a completely different domain, for example:

```caddyfile
crm.cheaper.promo {
	encode zstd gzip
	reverse_proxy crm:80
}
```

or:

```caddyfile
maptoposter.com {
	encode zstd gzip
	reverse_proxy crm:80
}
```

## Step 7. Start the new app

Run:

```bash
cd crm
docker compose up -d
cd ..
```

This starts the new app container.

## Step 8. Reload Caddy

After creating the route file, reload the Caddy stack:

```bash
cd caddy
docker compose --env-file ../config/server.env up -d
cd ..
```

This makes Caddy pick up the new route file.

## Step 9. Open the new app

Open in your browser:

```text
https://crm.nxt-solutions.com
```

If DNS is already pointing correctly, Caddy should automatically create the HTTPS certificate.

## If the app should use basic auth

This template already has shared basic-auth credentials in:

- `BASIC_AUTH_USER`
- `BASIC_AUTH_PASSWORD`

If you want to protect a route with the same shared login, use:

```caddyfile
crm.nxt-solutions.com {
	import shared_basic_auth
	reverse_proxy crm:80
}
```

That reuses the same username and password already used for protected services.

## If your app uses a custom image

Replace the example image:

```yaml
image: nginx:stable-alpine
```

with your real image, for example:

```yaml
image: ghcr.io/your-org/crm:latest
```

If the app listens on port `3000` inside the container, use:

```yaml
expose:
  - "3000"
```

and in `caddy/sites/crm.caddy`:

```caddyfile
crm.nxt-solutions.com {
	reverse_proxy crm:3000
}
```

## If your app needs a database

Keep the public app on the `web` network so Caddy can reach it.

Add the database on `internal` only.

Example pattern:

```yaml
---
services:
  crm:
    image: ghcr.io/your-org/crm:latest
    restart: unless-stopped
    expose:
      - "3000"
    networks:
      web:
        aliases:
          - crm
      internal:

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - ./postgres/data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: crm
      POSTGRES_USER: crm
      POSTGRES_PASSWORD: change-me
    networks:
      - internal

networks:
  web:
    external: true
  internal:
    external: true
```

Do not expose the database with host ports unless you really need external access.

## Useful commands

Start or update the app:

```bash
cd crm
docker compose up -d
```

View app logs:

```bash
cd crm
docker compose logs -f
```

Restart only the app:

```bash
cd crm
docker compose restart
```

Recreate Caddy after Caddyfile changes:

```bash
cd caddy
docker compose --env-file ../config/server.env up -d
```

## Quick checklist

When adding a new app, make sure all of these are true:

1. The app has its own folder
2. The app has a `compose.yaml`
3. The app is attached to `web`
4. The app has a stable network alias
5. DNS points the app subdomain to the VPS IP
6. `caddy/sites/` contains a matching route file
7. The app is started with `docker compose up -d`
8. Caddy is reloaded after the route is added

## Recommended pattern for every new app

- One app = one folder
- One folder = one `compose.yaml`
- One public app = one file in `caddy/sites/`
- Public traffic goes through Caddy
- Internal services stay private on Docker networks
- No direct host ports for normal web apps

That keeps the server consistent and easy to grow later.
