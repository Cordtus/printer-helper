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

## Usage

Run directly:

```bash
./printer.bash status
./printer.bash toner
./printer.bash supplies
```

Or source it into your current Bash session:

```bash
source ./printer.bash
printer status
```

To make it available in every Bash shell, copy it somewhere stable and source it from `~/.bashrc`:

```bash
mkdir -p ~/.local/share/printer-helper
cp printer.bash ~/.local/share/printer-helper/printer.bash
printf '\nsource ~/.local/share/printer-helper/printer.bash\n' >> ~/.bashrc
source ~/.bashrc
```

## Subcommands

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

## Configure another IP or SNMP community

Set environment variables before running the command:

```bash
PRINTER_IP=192.168.0.119 PRINTER_COMMUNITY=public ./printer.bash status
```

When sourced:

```bash
export PRINTER_IP=192.168.0.119
export PRINTER_COMMUNITY=public
printer status
```

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
