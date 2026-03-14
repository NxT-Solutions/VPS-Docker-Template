# Domains And Routing

This guide explains how domains work in this template and how to route any domain or subdomain to any app.

The important idea is:

- every public app gets its own Caddy route file
- every route file can use a completely different domain
- Caddy does not care whether the hostname is on `nxt-solutions.com`, `cheaper.promo`, `maptoposter.com`, or something else

As long as the hostname points to this VPS, Caddy can serve it.

## What is supported

You can use:

- a subdomain like `app.nxt-solutions.com`
- a subdomain on a different domain like `admin.cheaper.promo`
- a root domain like `maptoposter.com`
- an API subdomain like `api.maptoposter.com`

All of these can live on the same VPS at the same time.

Example:

- `dozzle.nxt-solutions.com`
- `crm.cheaper.promo`
- `maptoposter.com`
- `api.maptoposter.com`

## The DNS rule

For every public hostname you want to use, create a DNS record that points to this VPS.

Examples:

- `dozzle.nxt-solutions.com` -> `YOUR_VPS_IP`
- `crm.cheaper.promo` -> `YOUR_VPS_IP`
- `maptoposter.com` -> `YOUR_VPS_IP`
- `api.maptoposter.com` -> `YOUR_VPS_IP`

If the hostname does not point to the VPS, Caddy cannot serve it and cannot request HTTPS certificates for it.

## How routing works in this repo

The routing setup is:

- `config/server.env`: server-wide settings such as ACME email and shared auth
- `caddy/Caddyfile`: global Caddy config and shared snippets
- `caddy/sites/*.caddy`: one route file per public app or service

This means:

- server-wide settings stay in one place
- you do not need to keep editing one giant Caddy config
- every app can have its own small route file
- different projects can use totally different domains

## Current examples in this repo

This repo already ships with:

- `caddy/sites/dozzle.caddy`
- `caddy/sites/example-app.caddy`

Those are just starter examples. You should edit their placeholder hostnames before first deployment.

## Route file pattern

Create one file per public app inside:

```text
caddy/sites/
```

Example:

- `caddy/sites/crm.caddy`
- `caddy/sites/maptoposter-api.caddy`
- `caddy/sites/shop.caddy`

### Example: subdomain on `nxt-solutions.com`

```caddyfile
crm.nxt-solutions.com {
  encode zstd gzip
  reverse_proxy crm:80
}
```

### Example: subdomain on `cheaper.promo`

```caddyfile
admin.cheaper.promo {
  encode zstd gzip
  reverse_proxy admin:3000
}
```

### Example: root domain

```caddyfile
maptoposter.com {
  encode zstd gzip
  reverse_proxy maptoposter:8080
}
```

### Example: API subdomain

```caddyfile
api.maptoposter.com {
  encode zstd gzip
  reverse_proxy maptoposter-api:8080
}
```

## How the upstream name works

In a route like this:

```caddyfile
crm.nxt-solutions.com {
  reverse_proxy crm:80
}
```

the `crm` part is the Docker network alias of the app container.

That alias must exist in the app's `compose.yaml`.

Example:

```yaml
services:
  crm:
    image: ghcr.io/example/crm:latest
    expose:
      - "80"
    networks:
      web:
        aliases:
          - crm
      internal:
```

So the rule is:

- Caddy hostname = public domain
- Docker alias = container name Caddy should reach
- internal port = the app port inside Docker

## Shared basic auth

This repo provides shared basic auth through:

- `BASIC_AUTH_USER`
- `BASIC_AUTH_PASSWORD`

The main `Caddyfile` defines a reusable snippet called:

```text
shared_basic_auth
```

If you want to protect a route, use:

```caddyfile
admin.cheaper.promo {
  import shared_basic_auth
  reverse_proxy admin:3000
}
```

That reuses the same basic-auth login across any protected routes.

## What belongs where

Use `config/server.env` for:

- `ACME_EMAIL`
- `BASIC_AUTH_USER`
- `BASIC_AUTH_PASSWORD`
- timezone and server-hardening toggles

Use `caddy/sites/*.caddy` for:

- public hostnames
- which upstream container a hostname should reach
- whether a route should use shared basic auth

This keeps server-wide settings separate from app-specific routing.

## How to add a new hostname

When you want to add a new domain or subdomain, do these steps:

1. Create the DNS record pointing to this VPS
2. Create or update the app's `compose.yaml`
3. Give the app a stable alias on the `web` network
4. Create a new file in `caddy/sites/`
5. Reload Caddy

## Reload Caddy after route changes

After adding or changing a file in `caddy/sites/`, run:

```bash
cd caddy
docker compose --env-file ../config/server.env up -d
```

That makes sure Caddy picks up the new route configuration.

## Good examples

These are all valid combinations on one VPS:

- `app.nxt-solutions.com` -> `next-app:3000`
- `crm.cheaper.promo` -> `crm:80`
- `maptoposter.com` -> `maptoposter:8080`
- `api.maptoposter.com` -> `maptoposter-api:8080`

You are not limited to one “main domain”.

## Common mistakes

### Putting the raw IP in Caddy hostnames

Do not do this:

```caddyfile
1.2.3.4 {
  reverse_proxy crm:80
}
```

Use a real hostname instead.

### Forgetting DNS

If `crm.cheaper.promo` does not point to your VPS, Caddy cannot make it live.

### Using `ports` on normal web apps

Do not expose web apps directly on the host unless you have a special reason.

Let Caddy be the public entrypoint.

## Related guides

- [Setup The VPS](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/setup-vps.md)
- [Add A New App](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/add-new-app.md)
