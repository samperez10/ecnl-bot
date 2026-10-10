# ECNL Auto Solver

**Created by xnote12**

ECNL Auto Solver automates supported challenges on
[ECNL Media Market](https://ecnlmediamarket.com/) through an interactive terminal
interface or CLI. Available for **Android Termux ARM64** and **Ubuntu 22.04 ARMHF**
(including Orange Pi PC).

## Features

- Solve Colors, Numbers, Math, and Body Parts tasks.
- Run multiple enabled accounts concurrently.
- Monitor wallets, earnings, and task progress.
- Pause or stop individual accounts or all accounts.
- Set cooldowns and per-account wallet targets.

## Sneak peek

| Main menu | Live account monitor |
| --- | --- |
| <img src="docs/images/main-menu.jpg" alt="ECNL main menu" width="340"> | <img src="docs/images/account-monitor.jpg" alt="ECNL running Body Parts tasks across four accounts" width="340"> |

## Install

Termux:

```sh
pkg install curl tar coreutils util-linux
```

Ubuntu / Armbian ARMHF:

```sh
sudo apt update
sudo apt install -y curl tar coreutils util-linux
```

Install on either platform:

```sh
curl -fsSL https://github.com/samperez10/ecnl-bot/releases/latest/download/install.sh -o install-ecnl.sh
bash install-ecnl.sh
```

The app installs in `~/ecnl/` with a fresh, empty account configuration.
On Linux, the launcher is installed in `~/.local/bin/`. If `ecnl` is not
found in your current shell, run `export PATH="$HOME/.local/bin:$PATH"`.

## Use

```sh
ecnl
```

Add and enable your accounts in **Manage Accounts**, activate your license in
**Settings**, then select a task and choose **Start Auto Solver**.

For CLI usage:

```sh
ecnl setup
ecnl status
ecnl run
ecnl run --task math
ecnl --help
```
