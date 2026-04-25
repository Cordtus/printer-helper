#!/usr/bin/env bash
# Brother HL-3170CDW printer helper commands.
# Source this file to add the `printer` function, or run it directly.

printer() {
  local PRINTER_IP="${PRINTER_IP:-192.168.0.119}"
  local COMMUNITY="${PRINTER_COMMUNITY:-${COMMUNITY:-public}}"
  local subcmd="${1:-summary}"

  # OID constants
  local OID_MODEL="1.3.6.1.2.1.25.3.2.1.3.1"
  local OID_SERIAL="1.3.6.1.2.1.43.5.1.1.17.1"
  local OID_FIRMWARE="1.3.6.1.2.1.1.1.0"
  local OID_UPTIME="1.3.6.1.2.1.1.3.0"
  local OID_STATUS="1.3.6.1.2.1.25.3.5.1.1.1"
  local OID_PAGECOUNT="1.3.6.1.2.1.43.10.2.1.4.1.1"
  local OID_SUPPLY_MAX="1.3.6.1.2.1.43.11.1.1.8.1"
  local OID_SUPPLY_CUR="1.3.6.1.2.1.43.11.1.1.9.1"
  local OID_BR_ALERTS="1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.51.2.1.2"
  local OID_BR_STATUS="1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.20.0"

  __printer_need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
      printf 'Missing dependency: %s\n' "$1" >&2
      return 1
    }
  }

  __printer_clean() {
    sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"//; s/"$//'
  }

  __printer_get() {
    snmpget -v2c -c "$COMMUNITY" -Oqv "$PRINTER_IP" "$1" 2>/dev/null | sed 's/\r$//'
  }

  __printer_walk() {
    snmpwalk -v2c -c "$COMMUNITY" -Oqv "$PRINTER_IP" "$1" 2>/dev/null | sed 's/\r$//'
  }

  __printer_require_network() {
    __printer_need_cmd ping || return 1

    if ! ping -c 1 -W 1 "$PRINTER_IP" >/dev/null 2>&1; then
      printf 'Printer at %s is not reachable\n' "$PRINTER_IP"
      return 1
    fi
  }

  __printer_require_snmp() {
    __printer_need_cmd snmpget || return 1
    __printer_require_network || return 1
  }

  __printer_bar() {
    local pct="$1"
    local filled=$((pct / 5))
    local empty
    local bar=""
    local i

    ((filled < 0)) && filled=0
    ((filled > 20)) && filled=20
    empty=$((20 - filled))

    for ((i = 0; i < filled; i++)); do bar+="#"; done
    for ((i = 0; i < empty; i++)); do bar+="-"; done

    printf '%s' "$bar"
  }

  case "$subcmd" in
    status|info)
      __printer_require_snmp || return 1

      local model serial firmware uptime raw_status pages status_text fw_ver uptime_text
      model="$(__printer_get "$OID_MODEL" | __printer_clean)"
      serial="$(__printer_get "$OID_SERIAL" | __printer_clean)"
      firmware="$(__printer_get "$OID_FIRMWARE")"
      uptime="$(__printer_get "$OID_UPTIME")"
      raw_status="$(__printer_get "$OID_STATUS" | __printer_clean)"
      pages="$(__printer_get "$OID_PAGECOUNT" | __printer_clean)"

      case "$raw_status" in
        1) status_text="Other" ;;
        2) status_text="Unknown" ;;
        3) status_text="Idle" ;;
        4) status_text="Printing" ;;
        5) status_text="Warmup" ;;
        *) status_text="$raw_status" ;;
      esac

      fw_ver=""
      if [[ "$firmware" =~ Firmware[[:space:]]Ver\.([0-9.]+) ]]; then
        fw_ver="${BASH_REMATCH[1]}"
      else
        fw_ver="$(printf '%s' "$firmware" | __printer_clean)"
      fi

      uptime_text="$(printf '%s' "$uptime" | sed -E 's/^\([0-9]+\)[[:space:]]*//' | __printer_clean)"

      echo "Brother HL-3170CDW"
      echo "----------------------------"
      printf "  %-14s %s\n" "Model:" "$model"
      printf "  %-14s %s\n" "Serial:" "$serial"
      printf "  %-14s %s\n" "Firmware:" "$fw_ver"
      printf "  %-14s %s\n" "IP Address:" "$PRINTER_IP"
      printf "  %-14s %s\n" "Status:" "$status_text"
      printf "  %-14s %s\n" "Uptime:" "$uptime_text"
      printf "  %-14s %s\n" "Total Pages:" "$pages"
      ;;

    toner)
      __printer_require_snmp || return 1

      echo "Toner Status"
      echo "----------------------------"

      local status_hex bytes toner_names toner_tags idx tag name state j val_idx val indicator
      status_hex="$(__printer_get "$OID_BR_STATUS")"
      status_hex="$(printf '%s' "$status_hex" | sed -E 's/^Hex-STRING:[[:space:]]*//I; s/"//g; s/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:lower:]' '[:upper:]')"
      read -r -a bytes <<< "$status_hex"

      # Brother status byte layout: A1=Cyan, A2=Magenta, A3=Yellow, A4=Black.
      # Values: 00=OK, 01=Low, 02=Very Low, 03=Replace.
      toner_names=("Black" "Cyan" "Magenta" "Yellow")
      toner_tags=("A4" "A1" "A2" "A3")

      for idx in "${!toner_names[@]}"; do
        tag="${toner_tags[$idx]}"
        name="${toner_names[$idx]}"
        state="OK"

        for ((j = 0; j < ${#bytes[@]}; j++)); do
          if [[ "${bytes[$j]}" == "$tag" ]]; then
            val_idx=$((j + 2))
            if ((val_idx < ${#bytes[@]})); then
              val="${bytes[$val_idx]}"
              case "$val" in
                00) state="OK" ;;
                01) state="Low" ;;
                02) state="Very Low" ;;
                03) state="Replace" ;;
                *) state="Unknown ($val)" ;;
              esac
            fi
            break
          fi
        done

        case "$state" in
          OK) indicator="[OK]" ;;
          Low|"Very Low") indicator="[!!]" ;;
          Replace) indicator="[XX]" ;;
          *) indicator="[??]" ;;
        esac

        printf "  %-12s %s %s\n" "$name:" "$indicator" "$state"
      done
      ;;

    supplies|drums|drum|belt)
      __printer_require_snmp || return 1

      echo "Drum & Belt Life"
      echo "----------------------------"

      local supply_indices supply_labels i supply_idx label max_val cur_val pct bar
      supply_indices=(6 7 8 9 10)
      supply_labels=("Belt Unit" "Black Drum" "Cyan Drum" "Magenta Drum" "Yellow Drum")

      for i in "${!supply_indices[@]}"; do
        supply_idx="${supply_indices[$i]}"
        label="${supply_labels[$i]}"
        max_val="$(__printer_get "$OID_SUPPLY_MAX.$supply_idx" | __printer_clean)"
        cur_val="$(__printer_get "$OID_SUPPLY_CUR.$supply_idx" | __printer_clean)"

        if [[ "$max_val" =~ ^-?[0-9]+$ ]] && [[ "$cur_val" =~ ^-?[0-9]+$ ]] && ((max_val > 0 && cur_val >= 0)); then
          pct=$((100 * cur_val / max_val))
          bar="$(__printer_bar "$pct")"
          printf "  %-14s [%s] %3d%%\n" "$label:" "$bar" "$pct"
          printf "  %14s %s / %s pages remaining\n" "" "$cur_val" "$max_val"
        else
          printf "  %-14s N/A\n" "$label:"
        fi
      done
      ;;

    pages|count)
      __printer_require_snmp || return 1

      local total
      total="$(__printer_get "$OID_PAGECOUNT" | __printer_clean)"
      echo "Page Counts"
      echo "----------------------------"
      printf "  %-14s %s\n" "Total:" "$total"
      ;;

    alerts|errors)
      __printer_need_cmd snmpwalk || return 1
      __printer_require_network || return 1

      echo "Recent Alerts"
      echo "----------------------------"

      local alerts alert i msg
      mapfile -t alerts < <(__printer_walk "$OID_BR_ALERTS" | sed '/^[[:space:]]*$/d')

      if ((${#alerts[@]} == 0)); then
        echo "  No alerts"
      else
        i=1
        for alert in "${alerts[@]}"; do
          msg="$(printf '%s' "$alert" | __printer_clean)"
          printf "  %2d. %s\n" "$i" "$msg"
          i=$((i + 1))
        done
      fi
      ;;

    reset-toner)
      echo "Toner Counter Reset Procedure"
      echo "----------------------------"
      echo
      echo "  Use this when aftermarket cartridges trigger false"
      echo "  'Replace Toner' errors (counter-based, not actual level)."
      echo
      echo "  1. Open the front cover"
      echo "  2. Press and hold the Cancel button"
      echo "  3. While holding Cancel, press Secure (up arrow)"
      echo "     to cycle through toners:"
      echo "       TN-K = Black"
      echo "       TN-C = Cyan"
      echo "       TN-M = Magenta"
      echo "       TN-Y = Yellow"
      echo "  4. When the desired toner is shown, press Start"
      echo "     while still holding Cancel to reset that counter"
      echo "  5. Repeat steps 3-4 for each color that needs resetting"
      echo "  6. Close the front cover"
      echo
      echo "  If the printer is frozen ('standing by on/off to resume'"
      echo "  with unresponsive buttons), unplug the power cable for"
      echo "  30 seconds first, then follow the steps above after reboot."
      ;;

    cancel|flush)
      __printer_need_cmd nc || return 1
      __printer_require_snmp || return 1

      echo "Sending PJL cancel/reset to printer..."
      printf '\033%%-12345X@PJL\r\n@PJL INITIALIZE\r\n@PJL RESET\r\n\033%%-12345X' | nc -w 5 "$PRINTER_IP" 9100 2>&1
      sleep 3

      local new_status
      new_status="$(__printer_get "$OID_STATUS" | __printer_clean)"
      case "$new_status" in
        3) echo "Printer is now idle." ;;
        4) echo "Printer still reports 'printing' -- may need a power cycle." ;;
        *) echo "Printer status: $new_status" ;;
      esac
      ;;

    summary|all|"")
      printer status || return 1
      echo
      printer toner || return 1
      echo
      printer supplies || return 1
      echo
      printer pages || return 1
      echo
      printer alerts || return 1
      ;;

    help|-h|--help|*)
      echo "Usage: printer [subcommand]"
      echo
      echo "Subcommands:"
      echo "  status       Device info, uptime, and current status"
      echo "  toner        Toner cartridge status (OK / Low / Replace)"
      echo "  supplies     Drum and belt life remaining with bar graphs"
      echo "  pages        Page count statistics"
      echo "  alerts       Recent alert/error messages from the printer"
      echo "  cancel       Send PJL reset to cancel a stuck print job"
      echo "  reset-toner  Show toner counter reset procedure"
      echo "  summary      Show status, toner, supplies, pages, and alerts"
      echo "  help         Show this help"
      echo
      echo "Environment overrides:"
      echo "  PRINTER_IP=192.168.0.119"
      echo "  PRINTER_COMMUNITY=public"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printer "$@"
fi
