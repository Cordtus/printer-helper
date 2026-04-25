# Printer Bash Helper

Bash port of the original Fish `printer` helper function for a Brother HL-3170CDW on the local network.

The helper queries printer status over SNMP and can send a PJL reset over the printer's raw TCP print port.

## Files

- `printer.bash` — Bash function and standalone executable script.
- `README.md` — Basic usage, compatibility, and dependency notes.

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

## Setup as a Bash function

To use commands like this directly:

```bash
printer status
printer toner
printer supplies
```

Bash must `source` the file into your shell session. Executing the script works too, but that is not the same as installing the `printer` function into your shell.

### Per-user install: recommended

Run from the directory containing `printer.bash`:

```bash
mkdir -p ~/.local/lib/printer-helper
cp printer.bash ~/.local/lib/printer-helper/printer.bash
chmod 644 ~/.local/lib/printer-helper/printer.bash
```

Add this block to `~/.bashrc`:

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

Verify that Bash sees the function:

```bash
type printer
printer help
```

Expected result from `type printer`:

```text
printer is a function
```

After that, use it normally:

```bash
printer status
printer toner
printer supplies
printer pages
printer alerts
```

### System-wide install for all users

Use this only if multiple shell users on the machine should get the `printer` function.

Install the file under `/usr/local/lib`:

```bash
sudo install -D -m 0644 printer.bash /usr/local/lib/printer-helper/printer.bash
```

On Debian/Ubuntu, interactive Bash shells read `/etc/bash.bashrc`, so add a guarded source block there:

```bash
sudo tee -a /etc/bash.bashrc >/dev/null <<'BASHRC'

# Printer helper
if [ -r /usr/local/lib/printer-helper/printer.bash ]; then
  . /usr/local/lib/printer-helper/printer.bash
fi
BASHRC
```

Then open a new terminal or run:

```bash
source /etc/bash.bashrc
```

Verify:

```bash
type printer
printer help
```

### Alternative: standalone executable

This does not install a shell function, but it lets you run the helper as a normal command if the script is in your `PATH`.

```bash
sudo install -D -m 0755 printer.bash /usr/local/bin/printer
```

Then run:

```bash
printer status
printer toner
```

This works because `printer.bash` calls the `printer` function internally when executed directly.


## Setup as a Fish function

Fish cannot source Bash functions directly. To use the same helper from Fish with commands like `printer status`, create a Fish wrapper function that calls the Bash script.

### Per-user Fish install

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

Reload Fish, or open a new terminal:

```fish
exec fish
```

Verify:

```fish
type printer
printer help
```

Expected result from `type printer`:

```text
printer is a function with definition
```

After that, use it normally:

```fish
printer status
printer toner
printer supplies
printer pages
printer alerts
```

### Persistent Fish defaults

Set exported universal variables if your printer IP or SNMP community differs from the script defaults:

```fish
set -Ux PRINTER_IP 192.168.0.119
set -Ux PRINTER_COMMUNITY public
```

These exported variables are inherited by the Bash script called from the Fish wrapper.

### System-wide Fish install

For all Fish users on the machine, install the script and function under system paths:

```fish
sudo install -D -m 0755 printer.bash /usr/local/lib/printer-helper/printer.bash
sudo mkdir -p /etc/fish/functions
```

Create `/etc/fish/functions/printer.fish`:

```fish
sudo tee /etc/fish/functions/printer.fish >/dev/null <<'FISH'
function printer --description "Printer helper"
    bash /usr/local/lib/printer-helper/printer.bash $argv
end
FISH
```

Then open a new Fish shell or run:

```fish
exec fish
```

## Configure printer IP or SNMP community

### One-off command

```bash
PRINTER_IP=192.168.0.119 PRINTER_COMMUNITY=public printer status
```

### Persistent per-user defaults

Add these above the source block in `~/.bashrc`:

```bash
export PRINTER_IP=192.168.0.119
export PRINTER_COMMUNITY=public
```

Example:

```bash
export PRINTER_IP=192.168.0.119
export PRINTER_COMMUNITY=public

# Printer helper
if [ -r "$HOME/.local/lib/printer-helper/printer.bash" ]; then
  . "$HOME/.local/lib/printer-helper/printer.bash"
fi
```

Reload:

```bash
source ~/.bashrc
```

## Usage

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

`printer` with no subcommand is the same as `printer summary`.

## Compatibility

Target environment:

- Linux
- Bash 4+
- Brother HL-3170CDW
- SNMP v2c using the printer's public community string

The standard printer MIB OIDs may work on other Brother printers, but the Brother-specific toner status bytes, drum/belt supply indexes, and reset procedure are model-specific and may need adjustment.

`printer cancel` uses PJL over TCP port `9100`. This is intended for printers with raw socket printing enabled. If the printer does not accept raw socket printing, the command will fail or do nothing.

## Notes

- The helper only reads SNMP data except for `printer cancel`, which sends a PJL initialize/reset command to port `9100`.
- The toner reset subcommand only prints manual instructions. It does not send any reset command to the printer.
- If `printer toner` returns incorrect values, verify that the Brother status OID exists on the printer model and that `snmpget` returns a hex byte sequence.
