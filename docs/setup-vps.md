# Setup The VPS

This guide walks you through setting up a fresh Ubuntu 24.04 VPS with this template.

At the end, you will have:

- Docker installed
- Caddy running with automatic HTTPS
- Dozzle running behind shared basic auth
- The sample app running
- Firewall and SSH hardening applied

## Before you start

You need these 4 things:

1. A fresh Ubuntu 24.04 VPS
2. One or more domains you control, for example `nxt-solutions.com`, `cheaper.promo`, or `maptoposter.com`
3. Access to that domain's DNS settings
4. SSH access to the server with a sudo user

## Very important: domain names vs server IP

Public hostnames now live in the files under:

- `caddy/sites/`

Those hostnames do **not** need to be on the same base domain.

Examples:

- `dozzle.nxt-solutions.com`
- `maptoposter.com`

Then in DNS, you point those names to your server IP:

- `dozzle.nxt-solutions.com` -> `YOUR_SERVER_IP`
- `maptoposter.com` -> `YOUR_SERVER_IP`

So the rule is:

- Put **hostnames** in `caddy/sites/*.caddy`
- Put **server-wide settings** in `config/server.env`
- Point the hostnames to your VPS **IP address** in DNS

Do **not** put the raw IP directly in the Caddy route files.

For the full routing model, including multiple domains and per-app route files, see:

- [Domains And Routing](/Users/noahgillard/rqc.icu/projects/VPS-Docker-Template/docs/domains-and-routing.md)

## Step 1. Create your VPS

Create a new server with:

- Ubuntu `24.04`
- Your SSH key added during setup if possible

Once it is created, note the public IP address. You will need it for DNS.

## Step 2. Connect to the server

From your own computer, SSH into the VPS:

```bash
ssh your-user@YOUR_SERVER_IP
```

If you can log in, continue.

## Step 3. Install Git if needed

Some fresh servers do not have Git yet. Run:

```bash
sudo apt update
sudo apt install -y git
```

## Step 4. Clone this repo onto the VPS

Choose where you want the repo to live, then clone it:

```bash
git clone <YOUR-REPO-URL>
cd VPS-Docker-Template
```

If this repo is private, use the Git URL that works for your account.

## Step 5. Edit the starter Caddy route files

Before running the setup, choose the public hostnames you want to use for the starter services.

Open the Dozzle route file:

```bash
nano caddy/sites/dozzle.caddy
```

Replace the placeholder hostname with your real one.

Example:

```caddyfile
dozzle.nxt-solutions.com {
  import shared_basic_auth

  reverse_proxy dozzle:8080 {
    flush_interval -1
  }
}
```

Then open the example app route file:

```bash
nano caddy/sites/example-app.caddy
```

Replace the placeholder hostname with your real one.

Example:

```caddyfile
maptoposter.com {
  encode zstd gzip
  reverse_proxy example-app:80
}
```

You can use different base domains for each file.

## Step 6. Create your DNS records

After choosing the hostnames in the route files, create DNS records that point them to the VPS.

Example if you configured:

- `dozzle.nxt-solutions.com`
- `maptoposter.com`

and your server IP is `1.2.3.4`:

- Type: `A`
- Name: `dozzle`
- Value: `1.2.3.4`

- Type: `A`
- Name: `@`
- Value: `1.2.3.4`

That creates:

- `dozzle.nxt-solutions.com`
- `maptoposter.com`

If your provider also gives you IPv6 and you use it, you can also add matching `AAAA` records.

## Step 7. Copy the example config

Run:

```bash
cp config/server.env.example config/server.env
```

About the config files:

- `config/server.env.example` is the file you copy and edit yourself
- `config/runtime/caddy.env.example` shows the shape of the runtime file
- `config/runtime/caddy.env` is generated automatically by the setup script

## Step 8. Edit the config file

Open the config file:

```bash
nano config/server.env
```

Replace the example values with your own.

Example:

```env
ACME_EMAIL=ops@nxt-solutions.com
BASIC_AUTH_USER=admin
BASIC_AUTH_PASSWORD=use-a-long-random-password-here

TZ=Europe/Brussels
SSH_DISABLE_PASSWORD_AUTH=true
ENABLE_UFW=true
ENABLE_FAIL2BAN=true
```

What each value means:

- `ACME_EMAIL`: email used by Caddy for HTTPS certificate registration
- `BASIC_AUTH_USER`: shared username for any service routes protected with basic auth
- `BASIC_AUTH_PASSWORD`: shared password for any service routes protected with basic auth
- `TZ`: server timezone
- `SSH_DISABLE_PASSWORD_AUTH`: disables SSH password login after checking your SSH key exists
- `ENABLE_UFW`: enables the firewall
- `ENABLE_FAIL2BAN`: enables fail2ban for SSH protection

The public hostnames are **not** configured here anymore. They live in the files under `caddy/sites/`.

## Step 9. Make sure SSH key login works

This script can disable SSH password login for safety.

That is good, but only if your SSH key already works.

If you are already logging in with your SSH key, keep:

```env
SSH_DISABLE_PASSWORD_AUTH=true
```

If you are not sure, or you still rely on a password to SSH into the server, temporarily use:

```env
SSH_DISABLE_PASSWORD_AUTH=false
```

You can harden SSH later after your key setup is confirmed.

## Step 10. Run the setup script

Run:

```bash
sudo ./bin/setup-vps.sh --config ./config/server.env
```

The script will:

1. Check that the server is Ubuntu 24.04
2. Install Docker Engine and Docker Compose
3. Add your user to the `docker` group
4. Enable the firewall for ports `22`, `80`, and `443`
5. Enable fail2ban for SSH
6. Optionally disable SSH password login
7. Create the shared Docker networks
8. Start `example-app`, `dozzle`, and `caddy`
9. Run smoke checks

## Step 11. Wait for DNS and HTTPS

If your DNS was just created, HTTPS may take a little time to become fully ready.

This is normal. Caddy needs the domain to point to the server so it can request the certificate.

## Step 12. Open the URLs in your browser

Open:

- the hostname you put in `caddy/sites/example-app.caddy`, for example `https://maptoposter.com`
- the hostname you put in `caddy/sites/dozzle.caddy`, for example `https://dozzle.nxt-solutions.com`

Expected result:

- The example app page loads on the app domain
- Dozzle asks for the shared basic auth username and password you put in `config/server.env`

## What the script changes on the server

This is helpful to know before you run it:

- Installs Docker from Docker's official Ubuntu repository
- Enables Docker as a system service
- Creates Docker networks named `web` and `internal`
- Enables UFW with inbound access for SSH, HTTP, and HTTPS
- Enables fail2ban for SSH
- Can disable SSH password authentication
- Starts the Caddy, Dozzle, and example app stacks

## If something does not work

### The domain does not open

Check that:

- the hostname in the matching file under `caddy/sites/` is correct
- the DNS record points to the correct VPS IP
- you waited long enough for DNS to propagate

### HTTPS is not ready yet

Usually this means one of these:

- DNS is still propagating
- the hostname does not point to the VPS yet
- port `80` or `443` is blocked somewhere outside the server

### SSH hardening worries you

Set this before running the script:

```env
SSH_DISABLE_PASSWORD_AUTH=false
```

Then rerun later with it set to `true` after your SSH key login is confirmed.

### I changed the config and want to run setup again

That is fine. The setup script is designed to be rerun:

```bash
sudo ./bin/setup-vps.sh --config ./config/server.env
```

## Quick recap

One valid setup is:

- `caddy/sites/dozzle.caddy` -> `dozzle.nxt-solutions.com`
- `caddy/sites/example-app.caddy` -> `maptoposter.com`

And in DNS:

- `dozzle.nxt-solutions.com` -> your VPS IP
- `maptoposter.com` -> your VPS IP

After the VPS is up, you can add more apps on other domains like:

- `crm.cheaper.promo`
- `api.maptoposter.com`

using separate route files in `caddy/sites/`.

Then run:

```bash
sudo ./bin/setup-vps.sh --config ./config/server.env
```
