# VPS Docker Template

This README is the documentation index for this repo.

Use the guide that matches the task you want to do.

## What Do You Want To Do?

- [Setup The VPS](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/setup-vps.md)
  Fresh Ubuntu 24.04 server setup, DNS, config, bootstrap script, HTTPS, and first checks.
- [Add A New App](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/add-new-app.md)
  Add a new project or app, wire it into Docker and Caddy, and expose it on its own subdomain.
- [Domains And Routing](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/domains-and-routing.md)
  Use different domains or subdomains per app, understand DNS rules, and manage one Caddy route file per public service.

## Start Here

If this is a brand new server, start with:

- [Setup The VPS](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/setup-vps.md)

If the VPS is already set up and you want to deploy something new, use:

- [Add A New App](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/add-new-app.md)

If you want to understand how multiple domains work on one VPS, use:

- [Domains And Routing](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/domains-and-routing.md)

## Repo References

- `config/server.env.example`: example server config
- `config/runtime/caddy.env.example`: example of the generated runtime auth file
- `bin/setup-vps.sh`: VPS bootstrap script
- `config/server.env`: server-wide settings when you create it locally on a VPS
- `caddy/Caddyfile`: global Caddy config and shared snippets
- `caddy/sites/`: one route file per public app or service
- `example-app/`: starter app pattern for future projects

## CI And Quality Gates

- `.github/workflows/quality.yml`: shell, Markdown, YAML, workflow, and formatting checks
- `.github/workflows/template-validation.yml`: Docker Compose and Caddy configuration validation
- `.github/workflows/security.yml`: secret scanning and misconfiguration scanning
