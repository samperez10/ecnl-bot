# ECNL Auto Solver

**Created by xnote12 · v1.0.0**

ECNL Auto Solver is a compiled Android Termux app for automating supported
challenges on [ECNL Media Market](https://ecnlmediamarket.com/). It includes an
interactive terminal interface and a CLI for running multiple accounts,
tracking task progress, and stopping each account at a chosen wallet balance.

This repository distributes the installer and compiled app through
[GitHub Releases](https://github.com/samperez10/ecnl-bot/releases). Python,
Textual, Pillow, NumPy, and the required Termux libraries are bundled with the
app. Users do not need to install Python packages or compile the application.

## Supported tasks

| Task | CLI name |
| --- | --- |
| Solving Colors | `colors` |
| Solving Numbers | `numbers` |
| Solving Math | `math` |
| Solving Body Parts | `bodyparts` |

Both the TUI and CLI support these tasks. Enabled accounts run concurrently,
with separate credentials and saved sessions for each account.

## Installation

Requires **Android Termux on aarch64 / ARM64**. This release is not a desktop
Linux, Windows, or macOS executable.

Run in Termux:

```sh
pkg install curl tar coreutils util-linux
curl -fL https://github.com/samperez10/ecnl-bot/releases/latest/download/install.sh -o install-ecnl.sh
bash install-ecnl.sh
```

The installer downloads the compiled app, verifies its SHA-256 checksum,
checks startup and TUI navigation, and creates the `ecnl` launcher in
Termux's `$PREFIX/bin`.

A fresh installation has **no accounts, passwords, saved sessions, or activated
license**. It creates its own `~/ecnl/` folder and does not import data from
another installation or a source checkout.

## First launch

```sh
ecnl
```

1. Open **Manage Accounts** and add your ECNL username and password.
2. Enable the accounts you want to run.
3. Open **Settings → Manage License** and activate your issued license key.
4. Select a task on the main menu and choose **Start Auto Solver**.

The runner displays each account's wallet, earnings during the current run,
task progress, solve result, and cooldown. You can pause or stop individual
accounts, pause or stop all accounts, or hide the monitor while the run
continues. **View Logs** opens the application's local logs.

Settings include solve and failure cooldowns, an optional per-account balance
target, and a wake-lock option when the Termux wake-lock commands are available.

## CLI commands

Running `ecnl` without a command opens the TUI. CLI commands use the same
account configuration and license as the TUI.

```sh
# Add or update an account interactively
ecnl setup

# Activate a license; the key is entered through a private prompt
ecnl license activate

# Show wallets and selected-task progress for all enabled accounts
ecnl status
ecnl status --task math

# Run all enabled accounts using the configured task
ecnl run

# Select a task and limit attempted cycles per account
ecnl run --task numbers --cycles 10

# Select specific enabled accounts
ecnl run --task colors --account alice --account bob

# Set a successful-solve cooldown and a per-account wallet target
ecnl run --task bodyparts --cooldown 10 --target-balance 50

# Verify the license online, or inspect its saved status
ecnl license refresh
ecnl license status

# Clear an account's session
ecnl logout --account alice
```

| Option | Behavior |
| --- | --- |
| `--task` | `colors`, `numbers`, `math`, or `bodyparts`; defaults to the configured task. |
| `--account USERNAME` | Select an enabled account; repeat for multiple accounts. Defaults to all enabled accounts. |
| `--cycles N` | Limit attempted cycles per account, including failed attempts. Available on `run`. |
| `--cooldown SECONDS` | Override the delay after successful solves for this run. |
| `--target-balance AMOUNT` | Stop each account independently when its task wallet reaches this amount; `0` disables the target. |
| `--config PATH` | Use an alternate configuration file. |
| `--verbose` | Show diagnostic logs. |

Runtime account selections and overrides are not saved. Reaching a balance
target stops that account for the current run without disabling it in account
management. Other accounts continue running.

Without `--cycles`, automation continues until stopped, the daily task limit
is reached, or an account reaches its balance target. Press **Ctrl+C** to stop
CLI automation and close its connections.

Status output shows one row per account. Run output reports solves, claims,
limits, errors, and a final summary without login chatter or countdown spam.

```sh
ecnl --help
ecnl run --help
ecnl status --help
```

## License verification

An active license is required for `status` and automation in both modes.
The app verifies the license online before account requests and checks it
again every **15 minutes** during automation. Verification failure, including
an unreachable license server, stops all workers. Known license failure or
local expiry blocks further automation requests.

Revocation is detected at the next online verification. Requests already
sent cannot be recalled. The saved `active` label alone does not authorize a
run; `ecnl license status` displays saved metadata, while
`ecnl license refresh` verifies it online.

Account setup, session logout, help, and license management remain available
without an active license.

## Application folder and data

```text
~/ecnl/
├── releases/                 Compiled application versions
├── current -> releases/.../app
└── data/
    ├── config.json           Account list and settings; initially accounts: []
    ├── credentials.json      Local account passwords, created when saved
    ├── sessions/             Per-account saved sessions
    ├── logs/                 Application logs
    └── license_installation_key.json
```

License activation metadata is stored in the configuration, and the installation
private key stays in the local data folder. The `ecnl` launcher explicitly uses
`~/ecnl/data/config.json`, so running it from another directory uses the same
installation data.

## Updates

Every time you launch `ecnl`, the launcher checks the latest GitHub Release.
When it finds a newer version, it downloads and installs it **without asking**,
then opens the updated app with your original command and arguments. Running
sessions continue using their existing version.

Updates preserve `~/ecnl/data/`, including your accounts, settings, saved
sessions, and license identity. The installer verifies the archive checksum and
checks CLI and TUI startup before switching versions. If the check or update
fails, the launcher opens the installed app. It never automatically downgrades.
An offline update check times out after eight seconds for public releases.

**Existing installations:** run the updated installer once to enable automatic
updates. No app rebuild is needed to add the launcher updater:

```sh
curl -fL https://github.com/samperez10/ecnl-bot/releases/latest/download/install.sh -o install-ecnl.sh
bash install-ecnl.sh
```

Future releases must use version tags such as `v1.0.1` and include
`install.sh`, `ecnl-termux-aarch64.tar.gz`, and `SHA256SUMS`. Publish a new
version tag for each app update; replacing files under the same tag does not
trigger an automatic update.

To install a specific release:

```sh
bash install-ecnl.sh --version v1.0.0
```

## Uninstall

```sh
ecnl uninstall
```

The launcher asks for confirmation before deleting **the entire installation**:
the app versions, launcher, accounts, passwords, sessions, logs, and local
license identity. Enter `y` to remove everything; Enter, `n`, or no input
cancels. There are no extra uninstall flags.

Removing the local license identity does not release its server-side
installation binding. Stop any running ECNL sessions before uninstalling.

If you installed an earlier installer, run the updated installer once to add
this command. Your accounts and license data are preserved during that update.

## Troubleshooting

- **No enabled accounts:** add an account through the TUI or `ecnl setup`, then enable it in Manage Accounts.
- **License inactive:** use `ecnl license activate` or `ecnl license refresh` and check the reported reason.
- **Login failed:** check the account credentials in Manage Accounts and verify that the account can sign in to ECNL.
- **Unsupported architecture:** this release requires aarch64 / ARM64 Termux.
- **Missing installer tools:** run `pkg install curl tar coreutils util-linux`.
- **Need diagnostic output:** add `--verbose` to the CLI command or open View Logs in the TUI.

If the repository is made private again, users with repository access can
install through an authenticated GitHub CLI session:

```sh
pkg install gh tar coreutils util-linux
gh auth login
gh release download --repo samperez10/ecnl-bot --pattern install.sh --clobber
bash install.sh --github-auth
```
