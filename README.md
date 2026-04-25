# Printer Helper

Bash-based printer helper for querying a Brother HL-3170CDW over SNMP and sending a raw PJL reset to the printer when needed.

The helper can be used from either:

- **Bash** as a sourced shell function.
- **Fish** as a Fish wrapper function that calls the Bash helper.

## Files

- `printer.bash` — Bash helper script. Can be sourced as a Bash function or run directly.
- `README.md` — Setup, usage, compatibility, and dependency notes.

## What it provides

```text
printer status       Device info, uptime, and current status
printer toner        Toner cartridge status: OK / Low / Very Low / Replace
printer supplies     Drum and belt life remaining with bar graphs
printer pages        Total page count
printer alerts       Recent printer alert/error messages
printer cancel       Send a PJL reset to cancel a stuck print job
printer reset-toner  Print the manual toner counter reset procedure
printer summary      Show status, toner, supplies, pages, and alerts
printer help         Show help text
```

Running `printer` with no subcommand is the same as:

```bash
printer summary
```

## Requirements

The printer must be reachable on the network and must allow SNMP v2c reads with the configured community string.

Default configuration:

```bash
PRINTER_IP=192.168.0.119
PRINTER_COMMUNITY=public
```

Required commands:

- `bash`
- `ping`
- `snmpget`
- `snmpwalk`
- `nc` / netcat, only required for `printer cancel`

## Install dependencies

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install bash iputils-ping snmp netcat-openbsd
```

### Arch / Garuda

```bash
sudo pacman -S bash iputils net-snmp openbsd-netcat
```

### Fedora

```bash
sudo dnf install bash iputils net-snmp-utils nmap-ncat
```

---

# Setup path 1: Bash

Use this path on Debian, Ubuntu, and most Linux systems where Bash is the default interactive shell.

## Bash per-user function install

This installs the helper only for the current user.

Run from the directory containing `printer.bash`:

```bash
mkdir -p ~/.local/lib/printer-helper
cp printer.bash ~/.local/lib/printer-helper/printer.bash
chmod 644 ~/.local/lib/printer-helper/printer.bash
```

Add the helper to `~/.bashrc`:

```bash
cat >> ~/.bashrc <<'BASHRC'

# Printer helper
if [ -r "$HOME/.local/lib/printer-helper/printer.bash" ]; then
  . "$HOME/.local/lib/printer-helper/printer.bash"
fi
BASHRC
```

Reload Bash:

```bash
source ~/.bashrc
```

Verify that Bash sees `printer` as a function:

```bash
type printer
printer help
```

Expected `type printer` result:

```text
printer is a function
```

Use it normally:

```bash
printer status
printer toner
printer supplies
printer pages
printer alerts
```

## Bash persistent defaults

Use this if your printer IP or SNMP community differs from the script defaults.

Add these lines above the printer helper source block in `~/.bashrc`:

```bash
export PRINTER_IP=192.168.0.119
export PRINTER_COMMUNITY=public
```

Example `~/.bashrc` block:

```bash
export PRINTER_IP=192.168.0.119
export PRINTER_COMMUNITY=public

# Printer helper
if [ -r "$HOME/.local/lib/printer-helper/printer.bash" ]; then
  . "$HOME/.local/lib/printer-helper/printer.bash"
fi
```

Reload Bash:

```bash
source ~/.bashrc
```

## Bash one-off override

Use environment variables before the command:

```bash
PRINTER_IP=192.168.0.119 PRINTER_COMMUNITY=public printer status
```

## Bash system-wide function install

Use this only if every interactive Bash user on the machine should get the `printer` function.

Install the helper:

```bash
sudo install -D -m 0644 printer.bash /usr/local/lib/printer-helper/printer.bash
```

On Debian/Ubuntu, interactive Bash shells read `/etc/bash.bashrc`. Add a guarded source block there:

```bash
sudo tee -a /etc/bash.bashrc >/dev/null <<'BASHRC'

# Printer helper
if [ -r /usr/local/lib/printer-helper/printer.bash ]; then
  . /usr/local/lib/printer-helper/printer.bash
fi
BASHRC
```

Open a new terminal, or reload Bash:

```bash
source /etc/bash.bashrc
```

Verify:

```bash
type printer
printer help
```

## Bash alternative: standalone executable

This does not install a shell function. It installs the helper as a normal command in your `PATH`.

```bash
sudo install -D -m 0755 printer.bash /usr/local/bin/printer
```

Then run:

```bash
printer status
printer toner
```

This works because `printer.bash` calls its internal `printer` function when executed directly.

---

# Setup path 2: Fish

Fish cannot source Bash functions directly. Use this path if Fish is your interactive shell.

The Fish setup creates a Fish function named `printer` that calls the Bash helper script.

## Fish per-user function install

This installs the helper only for the current user.

Run from the directory containing `printer.bash`:

```fish
mkdir -p ~/.local/lib/printer-helper ~/.config/fish/functions
cp printer.bash ~/.local/lib/printer-helper/printer.bash
chmod 755 ~/.local/lib/printer-helper/printer.bash
```

Create `~/.config/fish/functions/printer.fish`:

```fish
cat > ~/.config/fish/functions/printer.fish <<'FISH'
function printer --description "Printer helper"
    bash "$HOME/.local/lib/printer-helper/printer.bash" $argv
end
FISH
```

Reload Fish:

```fish
exec fish
```

Verify that Fish sees `printer` as a function:

```fish
type printer
printer help
```

Expected `type printer` result:

```text
printer is a function with definition
```

Use it normally:

```fish
printer status
printer toner
printer supplies
printer pages
printer alerts
```

## Fish persistent defaults

Use exported universal variables if your printer IP or SNMP community differs from the script defaults:

```fish
set -Ux PRINTER_IP 192.168.0.119
set -Ux PRINTER_COMMUNITY public
```

These variables are inherited by the Bash helper when the Fish wrapper calls it.

## Fish one-off override

Use `env` before the command:

```fish
env PRINTER_IP=192.168.0.119 PRINTER_COMMUNITY=public printer status
```

## Fish system-wide function install

Use this only if every Fish user on the machine should get the `printer` function.

Install the Bash helper:

```fish
sudo install -D -m 0755 printer.bash /usr/local/lib/printer-helper/printer.bash
```

Create the system-wide Fish wrapper:

```fish
sudo mkdir -p /etc/fish/functions
sudo tee /etc/fish/functions/printer.fish >/dev/null <<'FISH'
function printer --description "Printer helper"
    bash /usr/local/lib/printer-helper/printer.bash $argv
end
FISH
```

Open a new Fish shell, or reload Fish:

```fish
exec fish
```

Verify:

```fish
type printer
printer help
```

---

# Compatibility

Target environment:

- Linux
- Bash 4+
- Brother HL-3170CDW
- SNMP v2c using the printer's configured community string

The standard printer MIB OIDs may work on other Brother printers and some non-Brother network printers. The Brother-specific toner status bytes, drum/belt supply indexes, and reset procedure are model-specific and may need adjustment.

`printer cancel` uses PJL over TCP port `9100`. This is intended for printers with raw socket printing enabled. If the printer does not accept raw socket printing, the command may fail or do nothing.

# Notes

- The helper only reads SNMP data except for `printer cancel`, which sends a PJL initialize/reset command to port `9100`.
- `printer reset-toner` only prints manual reset instructions. It does not send a toner reset command to the printer.
- If `printer toner` returns incorrect values, verify that the Brother status OID exists on the printer model and that `snmpget` returns a hex byte sequence.
