# ECNL Auto Solver

Compiled Termux app for Android aarch64. An active license is required for account status and automation.

This repository is private. Installation requires access to this repository
and an authenticated GitHub CLI session.

Install in Termux:

```sh
pkg install gh tar coreutils
gh auth login
gh release download --repo samperez10/ecnl-bot --pattern install.sh --clobber
bash install.sh --github-auth
```

Run:

```sh
ecnl
ecnl license activate
ecnl status
ecnl run --task math --cycles 10
```

The app gets its own folder at `~/ecnl/`. A new install creates an empty account
list and has no credentials or license activation. Add your accounts in the TUI
or with `ecnl setup`, then activate your license.

```text
~/ecnl/
  releases/            compiled app versions
  current -> releases/.../app
  data/config.json    starts with accounts: []
  data/               your credentials, sessions, logs, and license state
```

The `ecnl` launcher in Termux's `$PREFIX/bin` uses this installation's config.
Re-run the installer to update; it preserves `~/ecnl/data/`. It does not import
accounts or license data from a source checkout or another installation.

Tasks: `colors`, `numbers`, `math`, `bodyparts`. Use `ecnl run --help` for account
selection, cooldowns, cycle limits, and balance targets.

A license does not grant access to this private GitHub repository.
