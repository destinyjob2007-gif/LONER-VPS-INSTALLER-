# LONER VPS INSTALLER

Installs a full **Pterodactyl panel + Wings + Docker** on a fresh Ubuntu VPS in one run.
It also sets up **ngrok**, so you get a public `https` address without buying a domain.
Made for people who have never set up a server before.

## What you need

| Thing | Notes |
|---|---|
| A VPS | Ubuntu **22.04 or 24.04**, at least **2 GB RAM** (4 GB+ is better) and 20 GB disk |
| Root access | You log in as `root` |
| A free ngrok account | The script walks you through making one |
| A terminal app | **Termux** or **ConnectBot** on Android, **Termius** on iPhone, or PuTTY / Windows Terminal on PC |

## 1. Connect to your VPS

Your VPS provider gives you an **IP address**, a **username** (usually `root`) and a **password**.

From a PC or a phone terminal:

```
ssh root@YOUR_VPS_IP
```

Type `yes` when asked, then your password. Typing the password shows nothing on screen, that is normal.
Some hosts give a web console instead. Open it from their dashboard; it works the same way.

## 2. Download and run the installer

Copy one line, paste it, press Enter:

```
curl -fsSL https://raw.githubusercontent.com/destinyjob2007-gif/LONER-VPS-INSTALLER/main/ptero-install.sh -o ptero-install.sh && bash ptero-install.sh
```

Replace `YOUR_GITHUB_NAME` and `YOUR_REPO_NAME` with this repo's names.

If `curl` is missing: `apt update && apt install -y curl`, then try again.

## 3. Follow the screen

1. You see the red **LONER VPS INSTALLER** banner.
2. If you have no ngrok account, answer `N`. The script shows three steps: sign up, copy your free domain, copy your authtoken.
3. Paste the domain and token, then choose your admin email, username, password, node name and timezone (for example `Africa/Lagos`).
4. Wait. It installs everything and prints **OK** or **FAIL** checks at the end. It takes about 10 to 20 minutes.

If a step fails, it stops and tells you. Run `bash ptero-install.sh` again. Finished steps are skipped, and your answers are remembered.

## 4. Do these by hand after it finishes

Open `https://YOUR-NGROK-DOMAIN` and log in with the admin email and password you chose.
If ngrok shows a "Visit Site" warning page, press **Visit Site**.

1. **Node heart:** Admin > Nodes. The heart should turn green within a minute.
2. **Eggs:** Admin > Nests > Create a nest (for example `Bots`), then **Import Egg** and add:
   - Node.js: `https://raw.githubusercontent.com/pterodactyl/generic-eggs/main/nodejs/egg-node-js-generic.json`
   - Python: `https://raw.githubusercontent.com/pterodactyl/generic-eggs/main/python/egg-python-generic.json`
3. **API key** (if you use a reseller bot): Admin > Application API > Create, Read & Write on everything. Copy the `ptla_` key. It is shown only once.

Startup commands you can use on the eggs:

```
if [ -f package.json ]; then npm install --omit=dev --no-audit --no-fund; fi; node index.js
```
```
if [ -f requirements.txt ]; then pip install --user -r requirements.txt; fi; python3 main.py
```

## After a restart

Containers and VPS machines without systemd do not start things by themselves. Run:

```
bash /data/start-ptero.sh
```

(If your VPS has no `/data` disk, it is `/var/lib/ptero-data/start-ptero.sh`.)

## Keep these safe

- Your **ngrok authtoken**, **admin password** and **API keys**. Never post them or share screenshots of them.
- `/data/.ptero-install/config.env` holds your saved answers and database password.

## Troubleshooting

| Problem | Fix |
|---|---|
| Node heart is red | `bash /data/start-ptero.sh`, wait a minute, refresh |
| Script stopped | Read the line after `STOPPED:`, fix it, run the script again |
| Need the details | `tail -40 /root/ptero-install.log` |
| Wrong ngrok token | `rm /data/.ptero-install/config.env` and run the script again |

## Credits

Made by **LONER**. Uses [Pterodactyl](https://pterodactyl.io), Docker and ngrok.
