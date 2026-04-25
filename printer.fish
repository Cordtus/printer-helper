function printer -d "Brother HL-3170CDW printer status and info"
        set -l PRINTER_IP 192.168.0.119
        set -l COMMUNITY public
        set -l subcmd $argv[1]

        # OID constants
        set -l OID_MODEL 1.3.6.1.2.1.25.3.2.1.3.1
        set -l OID_SERIAL 1.3.6.1.2.1.43.5.1.1.17.1
        set -l OID_FIRMWARE 1.3.6.1.2.1.1.1.0
        set -l OID_UPTIME 1.3.6.1.2.1.1.3.0
        set -l OID_STATUS 1.3.6.1.2.1.25.3.5.1.1.1
        set -l OID_PAGECOUNT 1.3.6.1.2.1.43.10.2.1.4.1.1
        set -l OID_SUPPLY_NAME 1.3.6.1.2.1.43.11.1.1.6.1
        set -l OID_SUPPLY_MAX 1.3.6.1.2.1.43.11.1.1.8.1
        set -l OID_SUPPLY_CUR 1.3.6.1.2.1.43.11.1.1.9.1
        set -l OID_BR_ALERTS 1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.51.2.1.2
        set -l OID_BR_STATUS 1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.20.0

        # helper: query a single OID, return just the value
        function __printer_get -S
                snmpget -v2c -c $COMMUNITY -Oqv $PRINTER_IP $argv[1] 2>/dev/null
        end

        # helper: walk an OID subtree, return values only
        function __printer_walk -S
                snmpwalk -v2c -c $COMMUNITY -Oqv $PRINTER_IP $argv[1] 2>/dev/null
        end

        # check connectivity
        if not ping -c1 -W1 $PRINTER_IP >/dev/null 2>&1
                echo "Printer at $PRINTER_IP is not reachable"
                return 1
        end

        switch "$subcmd"
                case status info
                        set -l model (string trim -- (__printer_get $OID_MODEL))
                        set -l serial (string trim -c '"' -- (__printer_get $OID_SERIAL))
                        set -l firmware (__printer_get $OID_FIRMWARE)
                        set -l uptime (__printer_get $OID_UPTIME)
                        set -l raw_status (__printer_get $OID_STATUS)
                        set -l pages (__printer_get $OID_PAGECOUNT)

                        set -l status_text
                        switch "$raw_status"
                                case 1; set status_text "Other"
                                case 2; set status_text "Unknown"
                                case 3; set status_text "Idle"
                                case 4; set status_text "Printing"
                                case 5; set status_text "Warmup"
                                case '*'; set status_text "$raw_status"
                        end

                        # extract firmware version from sysDescr
                        set -l fw_ver (string match -r 'Firmware Ver\.([\d.]+)' -- "$firmware")

                        echo "Brother HL-3170CDW"
                        echo "----------------------------"
                        printf "  %-14s %s\n" "Model:" "$model"
                        printf "  %-14s %s\n" "Serial:" "$serial"
                        printf "  %-14s %s\n" "Firmware:" "$fw_ver[2]"
                        printf "  %-14s %s\n" "IP Address:" "$PRINTER_IP"
                        printf "  %-14s %s\n" "Status:" "$status_text"
                        printf "  %-14s %s\n" "Uptime:" (string replace -r '^\((\d+)\)\s*' '' -- "$uptime")
                        printf "  %-14s %s\n" "Total Pages:" "$pages"

                case toner
                        echo "Toner Status"
                        echo "----------------------------"

                        # parse Brother status byte for toner conditions
                        set -l status_hex (__printer_get $OID_BR_STATUS)
                        # extract hex bytes into a flat list
                        set -l bytes (string split ' ' -- (string trim -- "$status_hex"))

                        # Brother status byte layout (tag value pairs):
                        # A1=Cyan, A2=Magenta, A3=Yellow, A4=Black (0=OK, 1=Low, 3=Replace)
                        set -l toner_names "Black" "Cyan" "Magenta" "Yellow"
                        set -l toner_tags "A4" "A1" "A2" "A3"

                        for i in 1 2 3 4
                                set -l tag $toner_tags[$i]
                                set -l name $toner_names[$i]
                                set -l state "OK"

                                # find the tag in the byte array, next byte is 01 (len), then value
                                for j in (seq 1 (count $bytes))
                                        if test (string upper -- "$bytes[$j]") = "$tag"
                                                set -l val_idx (math $j + 2)
                                                if test $val_idx -le (count $bytes)
                                                        set -l val $bytes[$val_idx]
                                                        switch (string upper -- "$val")
                                                                case "00"; set state "OK"
                                                                case "01"; set state "Low"
                                                                case "02"; set state "Very Low"
                                                                case "03"; set state "Replace"
                                                                case '*'; set state "Unknown ($val)"
                                                        end
                                                end
                                                break
                                        end
                                end

                                set -l indicator
                                switch "$state"
                                        case "OK"; set indicator "[OK]"
                                        case "Low"; set indicator "[!!]"
                                        case "Very Low"; set indicator "[!!]"
                                        case "Replace"; set indicator "[XX]"
                                        case '*'; set indicator "[??]"
                                end

                                printf "  %-12s %s %s\n" "$name:" "$indicator" "$state"
                        end

                case supplies drums drum belt
                        echo "Drum & Belt Life"
                        echo "----------------------------"

                        # indices: 6=Belt, 7=Black Drum, 8=Cyan Drum, 9=Magenta Drum, 10=Yellow Drum
                        set -l supply_indices 6 7 8 9 10
                        set -l supply_labels "Belt Unit" "Black Drum" "Cyan Drum" "Magenta Drum" "Yellow Drum"

                        for i in (seq 1 (count $supply_indices))
                                set -l idx $supply_indices[$i]
                                set -l label $supply_labels[$i]
                                set -l max_val (__printer_get "$OID_SUPPLY_MAX.$idx")
                                set -l cur_val (__printer_get "$OID_SUPPLY_CUR.$idx")

                                if test "$max_val" -gt 0 2>/dev/null; and test "$cur_val" -ge 0 2>/dev/null
                                        set -l pct (math -s0 "100 * $cur_val / $max_val")
                                        set -l used (math "$max_val - $cur_val")

                                        # bar graph (20 chars wide)
                                        set -l filled (math -s0 "$pct / 5")
                                        set -l empty (math "20 - $filled")
                                        set -l bar ""
                                        for _j in (seq 1 $filled)
                                                set bar "$bar#"
                                        end
                                        for _j in (seq 1 $empty)
                                                set bar "$bar-"
                                        end

                                        printf "  %-14s [%s] %3d%%\n" "$label:" "$bar" "$pct"
                                        printf "  %14s %s / %s pages remaining\n" "" "$cur_val" "$max_val"
                                else
                                        printf "  %-14s N/A\n" "$label:"
                                end
                        end

                case pages count
                        set -l total (__printer_get $OID_PAGECOUNT)
                        echo "Page Counts"
                        echo "----------------------------"
                        printf "  %-14s %s\n" "Total:" "$total"

                case alerts errors
                        echo "Recent Alerts"
                        echo "----------------------------"
                        set -l alerts (__printer_walk $OID_BR_ALERTS)
                        if test (count $alerts) -eq 0
                                echo "  No alerts"
                        else
                                set -l i 1
                                for alert in $alerts
                                        set -l msg (string trim -c '"' -- "$alert")
                                        printf "  %2d. %s\n" $i "$msg"
                                        set i (math $i + 1)
                                end
                        end

                case reset-toner
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
                        echo "     (while still holding Cancel) to reset that counter"
                        echo "  5. Repeat steps 3-4 for each color that needs resetting"
                        echo "  6. Close the front cover"
                        echo
                        echo "  If the printer is frozen ('standing by on/off to resume'"
                        echo "  with unresponsive buttons), unplug the power cable for"
                        echo "  30 seconds first, then follow the steps above after reboot."

                case cancel flush
                        echo "Sending PJL cancel/reset to printer..."
                        printf '\x1b%%-12345X@PJL\r\n@PJL INITIALIZE\r\n@PJL RESET\r\n\x1b%%-12345X' | nc -w 5 $PRINTER_IP 9100 2>&1
                        sleep 3
                        set -l new_status (__printer_get $OID_STATUS)
                        switch "$new_status"
                                case 3; echo "Printer is now idle."
                                case 4; echo "Printer still reports 'printing' -- may need a power cycle."
                                case '*'; echo "Printer status: $new_status"
                        end

                case '' summary all
                        # show everything
                        printer status
                        echo
                        printer toner
                        echo
                        printer supplies
                        echo
                        printer pages
                        echo
                        printer alerts

                case help '*'
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
                        echo "  (none)       Show all of the above"
                        echo "  help         Show this help"
        end
end

