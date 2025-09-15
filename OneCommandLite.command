#!/bin/bash

#   ___            ___                              _ 
#  / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
# | (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
#  \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|

# Version: 1.0 (Lite)
# by Ryan Summer
# https://shop.ryansummer.com/p/onecommand

# === COLOR DEFINITIONS ===
NC=$'\033[0m'
BO=$'\033[1m'
GY=$'\033[2m'
RE=$'\033[1;31m'
GR=$'\033[1;32m'
YE=$'\033[1;33m'
BL=$'\033[1;34m'
MA=$'\033[1;35m'
CY=$'\033[1;36m'

# navigation codes
NAV_BACK=0
NAV_CONT=1
NAV_QUIT=2

return_to_menu=false
interrupted=false

# Global Retry
global_retry() {
    echo
    for i in 3 2 1; do
        echo -ne "\rRetrying in $i... "
        # read one char, timeout after 1s
        read -t 1 -n 1 key

        if [[ $? -eq 0 ]]; then
            # user pressed something - check for nav  
            handle_navigation_input "$key"
            nav=$?
            if   [[ $nav -eq $NAV_QUIT ]]; then 
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                # pop one level: return to caller  
                echo    # clean up newline
                return $NAV_BACK
            else
                # any other key (including Enter) breaks out and retries now  
                echo    # clean up newline
                return $NAV_CONT
            fi
        fi
    done
    # countdown expired, so retry normally
    echo -ne "\r                    \r"  # clear countdown line
    return $NAV_CONT
}

# Global Navigation handler
handle_navigation_input() {
    local choice="$1"
    case "$choice" in
        "q"|"Q"|"quit"|"QUIT"|"exit"|"EXIT")
            return_to_menu=false
            interrupted=false
            return $NAV_QUIT
            ;;
        "b"|"B"|"back"|"BACK")
            return_to_menu=false
            interrupted=false
            return $NAV_BACK
            ;;
        *)
            return_to_menu=false
            interrupted=false
            return $NAV_CONT
            ;;
    esac
}

# Resize Terminal window taller via osascript
function set_terminal_height_to_1200p(){
    osascript <<'EOF'
    tell application "Terminal"
        set b to bounds of front window
        set leftEdge to item 1 of b
        set topEdge to item 2 of b
        set rightEdge to item 3 of b
        set bottomEdge to item 4 of b
        
        -- Keep left/top, keep width same (right - left)
        set newBottomEdge to topEdge + 1200 -- increase height by 1200 pixels (adjust as needed)
        set bounds of front window to {leftEdge, topEdge, rightEdge, newBottomEdge}
    end tell
EOF
}

# Resize Terminal window smaller via osascript
function set_terminal_height_to_500p(){
    osascript <<'EOF'
    tell application "Terminal"
        set b to bounds of front window
        set leftEdge to item 1 of b
        set topEdge to item 2 of b
        set rightEdge to item 3 of b
        set bottomEdge to item 4 of b
        
        -- Keep left/top, keep width same (right - left)
        set newBottomEdge to topEdge + 500 -- set height to 500 pixels (adjust as needed)
        set bounds of front window to {leftEdge, topEdge, rightEdge, newBottomEdge}
    end tell
EOF
}

# Resize Terminal window wider via osascript
function set_terminal_width_to_1120p(){
    osascript <<'EOF'
    tell application "Terminal"
        set b to bounds of front window
        set leftEdge to item 1 of b
        set topEdge to item 2 of b
        set rightEdge to item 3 of b
        set bottomEdge to item 4 of b
        -- Keep left/top/bottom, adjust width by changing right edge
        set newRightEdge to leftEdge + 1120 -- set width to 1120 pixels (adjust as needed)
        set bounds of front window to {leftEdge, topEdge, newRightEdge, bottomEdge}
    end tell
EOF
}

# Resize Terminal window narrower via osascript
function set_terminal_width_to_760p(){
    osascript <<'EOF'
    tell application "Terminal"
        set b to bounds of front window
        set leftEdge to item 1 of b
        set topEdge to item 2 of b
        set rightEdge to item 3 of b
        set bottomEdge to item 4 of b
        -- Keep left/top/bottom, adjust width by changing right edge
        set newRightEdge to leftEdge + 760 -- set width to 760 pixels (adjust as needed)
        set bounds of front window to {leftEdge, topEdge, newRightEdge, bottomEdge}
    end tell
EOF
}

# Global Navigation menu
show_navigation_prompt() {
    echo
    echo "${BL}Navigation${NC}: ${GR}⮑${NC}  Continue | ${GR}B${NC} Back | ${GR}^C${NC} Interrupt/Exit | ${GR}Q${NC} Main Menu "
    echo 
}

# Function to get menu item by index (simulates array access)
get_menu_item() {
    local index=$1
    case $index in
        0) echo " 1) 📡 ${BO}${GR}Speed Test${NC}" ;;
        1) echo " 2) 📊 ${BO}${GR}Activity Monitor (Top)${NC}" ;;
        2) echo " 3) ℹ️  ${BO}${GR}System Information${NC}" ;;
        3) echo " 4) 🔄 ${BO}${GR}iCloud Sync Refresh${NC}" ;;
        4) echo " 5) 💿 ${BO}${GR}Disk Image Utility${NC}" ;;
        5) echo " 6) 🔗 ${BO}${GR}Create Symlink${NC}" ;;
        6) echo "    7) ⚙️  ${BO}${GR}MacOS Preferences${NC}" ;;
        7) echo " 8) ℹ️  ${BO}${GR}About OneCommand${NC}" ;;
        *) echo "" ;;
    esac
}

# Function to get total number of menu items
get_menu_item_count() {
    echo 8
}

# Simple two-column layout (bash 3.2 compatible)
display_two_column_menu() {
    local num_items=$(get_menu_item_count)
    local mid_point=$(( (num_items + 1) / 2 ))
    
    for ((i=0; i<mid_point; i++)); do
        local left_item=$(get_menu_item $i)
        local right_index=$((i + mid_point))
        local right_item=""
        
        if [[ $right_index -lt $num_items ]]; then
            right_item=$(get_menu_item $right_index)
        fi
        
        # Simple formatting - no calculations, just basic spacing
        printf "%-50s %s\n" "$left_item" "$right_item"
    done
}

# Main Menu function
main_menu() {
    while true; do
        trap - SIGINT
        set_terminal_height_to_500p
        clear
        cat <<'EOF'
  ___            ___                              _ 
 / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
| (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
 \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|
EOF
        echo " ${BL}Created by Ryan Summer${NC}  |  ${BL}For macOS 12-26${NC}  |  ${BL}v1.0 (Lite)${NC}"
        echo
        echo "${GR}Choose a task:${NC}"
        echo
        display_two_column_menu
        show_navigation_prompt # already padded
        read -rp "➡️  ${GR}Enter your choice (or ${BL}navigation${NC} ${GR}choice)${NC}: " choice
        echo
        handle_navigation_input "$choice"
        nav=$?
        if   [[ $nav -eq $NAV_BACK ]]; then 
            continue
        fi
        case $choice in
            1) speed_test ;;
            2) top_activity_monitor ;;
            3) system_information ;;
            4) icloud_sync_refresh ;;
            5) disk_image_utility ;;
            6) create_symlink ;;
            7) macos_preferences ;;
            8) one_command_info ;;
            *) 
                echo -ne "❌ ${RE}Invalid choice.${NC} Please try again. "
                sleep 1
                continue
                ;;
        esac
    done
}

#====1==== 📡 Speed Test
function speed_test() {
    while true; do
        return_to_menu=true
        trap 'echo; echo "Returning to main menu...from func 10"; return_to_menu=true; return' SIGINT
        clear        
        echo "${GR}=================${NC}"
        echo "${BO}10) 📡 Speed Test${NC}"
        echo "${GR}=================${NC}"
        echo "↩️  Main Menu"
        show_navigation_prompt # already padded

        # Check if networkquality exists first
        if ! command -v networkquality &> /dev/null; then
            echo "❌ ${RE}networkquality command not found!${NC}"
            echo "   This requires macOS 12 (Monterey) or later"
            echo
            for i in 3 2 1; do
                echo -ne "\r${GR}🚪 Returning to Main Menu in $i...${NC} "
                # read one char, timeout after 1s
                read -t 1 -n 1 key

                if [[ $? -eq 0 ]]; then
                    # user pressed something - check for nav  
                    handle_navigation_input "$key"
                    nav=$?
                    if   [[ $nav -eq $NAV_QUIT ]]; then 
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        echo
                        return $NAV_BACK
                    else
                        echo
                        return $NAV_CONT
                    fi
                fi
            done
            # countdown expired, so retry normally
            echo -ne "\r                    \r"  # clear countdown line
            return $NAV_CONT
        fi
        
        echo "${BO}Choose test type:${NC}"
        echo "1) ${GR}Standard${NC}     -  Clean summary output"
        echo "2) ${GR}Verbose${NC}      -  Detailed test output"
        echo "3) ${GR}Config Only${NC}  -  Show network configuration"
        echo
       
       while true; do
            read -rp "➡️  ${GR}Select option ${NC}[1-3]: " choice
            
            case $choice in
                1)  # Default option (Enter key or 1)
                    clear
                    echo "${GR}===========================${NC}"
                    echo "${BO}1) 📡 Speed Test (Standard)${NC}"
                    echo "${GR}===========================${NC}"
                    echo "↩️  Speed Test"
                    echo "${BL}Navigation${NC}: ${GR}^C${NC} to interrupt test"
                    echo
                    echo "📡 ${GR}Testing network quality...${NC}"
                    echo "⏱️  ${BO}${GY}This may take 10-20 seconds...${NC}"
                    echo
                    
                    interrupted=false
                    trap 'interrupted=true; echo; kill $networkquality_pid 2>/dev/null' SIGINT
                    
                    # Run networkquality in background and capture its PID
                    networkquality &
                    networkquality_pid=$!
                    
                    # Wait for networkquality to complete or be interrupted
                    if wait $networkquality_pid 2>/dev/null; then
                        # Command completed normally
                        echo
                        echo "✅ ${GR}Done!${NC}"
                        return_to_menu=true
                        interrupted=false
                        trap 'echo; echo "returning from func 10"; return' SIGINT

                    else
                        # Command was interrupted or failed
                        trap 'echo; echo "returning from func 10"; return' SIGINT
                        if [ "$interrupted" = true ]; then
                            echo
                            echo "🛑 ${RE}Test interrupted by user.${NC}"
                            interrupted=false
                        fi
                    fi
                    break
                    ;;
                2)
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}==========================${NC}"
                    echo "${BO}2) 📡 Speed Test (Verbose)${NC}"
                    echo "${GR}==========================${NC}"
                    echo "↩️  Speed Test"
                    echo "${BL}Navigation${NC}: ${GR}^C${NC} to interrupt test"
                    echo
                    echo "📡 ${GR}Testing network quality...${NC}"
                    echo "⏱️  ${BO}${GY}This may take 10-30 seconds...${NC}"
                    echo
                    
                    interrupted=false
                    trap 'interrupted=true; kill $networkquality_pid 2>/dev/null' SIGINT
                    
                    # Run networkquality in background and capture its PID
                    networkquality -v &
                    networkquality_pid=$!
                    
                    # Wait for networkquality to complete or be interrupted
                    if wait $networkquality_pid 2>/dev/null; then
                        # Command completed normally
                        echo
                        echo "✅ ${GR}Done!${NC}"

                        return_to_menu=true
                        interrupted=false
                        trap 'echo; echo "returning from func 10"; return' SIGINT
                    else
                        # Command was interrupted or failed
                        trap 'echo; echo "returning from func 10"; return' SIGINT
                        if [ "$interrupted" = true ]; then
                            echo
                            echo "🛑 ${RE}Test interrupted by user.${NC}"
                            interrupted=false  # Reset the flag
                        fi
                    fi
                    break
                    ;;
                3)
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}===========================${NC}"
                    echo "${BO}3) 🔧 Network Configuration${NC}"
                    echo "${GR}===========================${NC}"
                    echo "↩️  Speed Test"
                    show_navigation_prompt # already padded
                    echo "📡 ${GR}Showing network configuration...${NC}"
                    echo "⏱️  ${BO}${GY}This may take 10-20 seconds...${NC}"
                    echo
                    
                    interrupted=false
                    trap 'interrupted=true; kill $networkquality_pid 2>/dev/null' SIGINT
                    
                    # Run networkquality in background and capture its PID
                    networkquality -c &
                    networkquality_pid=$!
                    
                    # Wait for networkquality to complete or be interrupted
                    if wait $networkquality_pid 2>/dev/null; then
                        # Command completed normally
                        echo
                        echo "✅ ${GR}Done!${NC}"
                        return_to_menu=true
                        interrupted=false
                        trap 'echo; echo "returning from func 10"; return' SIGINT
                    else
                        # Command was interrupted or failed
                        trap 'echo; echo "returning from func 10"; return' SIGINT
                        if [ "$interrupted" = true ]; then
                            echo
                            echo "🛑 ${RE}Test interrupted by user.${NC}"
                            interrupted=false
                        fi
                    fi
                    break
                    ;;
                *)
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        return
                    fi
                    echo "❌ ${RE}Invalid option. Please choose 1-3.${NC}"
                    sleep 1
                    continue 2
                    ;;
            esac
        done

        # Post-test handling
        # while true; do   
            # echo
            # echo "✅ ${GR}Finished${NC}"
        
        # Post-test handling
        while true; do
            show_navigation_prompt # already padded

            return_to_menu=true
            interrupted=false
            trap 'echo; echo "returning from func 10"; return' SIGINT

            read -rp "➡️  ${GR}Run another test? Press Enter (or ${BL}navigation${NC} ${GR}choice${NC}): " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                set_terminal_height_to_500p
                break
            else
                set_terminal_height_to_500p
                break
            fi
        done
    done
}

#====2==== 📊 Activity Monitor (Top)
function top_activity_monitor() {
    while true; do
        return_to_menu=true
        trap 'echo; echo "Returning to main menu...from func 9"; return_to_menu=true; return' SIGINT
        set_terminal_height_to_500p
        clear
        echo "${GR}=============================${NC}"
        echo "${BO}9) 📊 Activity Monitor (Top)${NC}"
        echo "${GR}=============================${NC}"
        echo "↩️  Main Menu"
        show_navigation_prompt # already padded

        echo "🔄 ${GR}Starting Activity Monitor...${NC}"
        echo
        echo "Tip: q = Quit | ? = Help | Space = Force Update"
        echo "     o = Sort Options; (then type: -cpu, -mem, etc.)"
        echo "     s = Set Update Interval; (then type: 1, 2, 3, etc.)"
        echo

        echo "${GR}Press Enter to start Activity Monitor (or ${BL}navigation${NC} ${GR}choice${NC}): "
        read -rp "" input
        handle_navigation_input "$input"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then 
            return 1  # back to main menu
        fi
        
        return_to_menu=false
        interrupted=false
        trap 'echo; echo "🛑 ${RE}Interrupted by user.${NC}"; interrupted=true; break' SIGINT

    # Inner loop: keep re-running top until user chooses "back" or "quit"
    # while true; do
        if [[ "$OSTYPE" == "darwin"* ]]; then
            set_terminal_height_to_1200p
            top -o cpu -s 2
            # break 1
        else
            set_terminal_height_to_1200p
            top -d 2
            # break 1
        fi
        
        return_to_menu=true
        interrupted=false
        trap 'echo; echo "returning from func 9"; return' SIGINT

    # done
    done
    # set_terminal_height_to_500p
}

#====3==== 🖥️ System Information
function system_information() {
    while true; do
        return_to_menu=true
        trap 'echo; echo "Returning to main menu...from func 12"; return_to_menu=true; return' SIGINT
        set_terminal_height_to_500p
        clear
        echo "${GR}=========================${NC}"
        echo "${BO}12) 🖥️  System Information${NC}"
        echo "${GR}=========================${NC}"
        echo "↩️  Main Menu"
        show_navigation_prompt # already padded
        echo "${BO}Choose information to be displayed:${NC}"
        echo "1) ${GR}System Profile Overview${NC}  Hardware, Software, Users"
        echo "2) ${GR}Hardware Summary${NC} ....... Model, CPU, Memory, Serial"
        echo "3) ${GR}Software Summary${NC} ....... macOS Version, Kernel, Uptime"
        echo "4) ${GR}Network Interfaces${NC} ..... Network hardware and config"
        echo "5) ${GR}USB Devices${NC} ............ Connected USB devices"
        echo "6) ${GR}Storage Devices${NC} ........ Disks and storage info"
        echo "7) ${GR}User Account Details${NC} ... Current user and system users"
        echo
        
        while true; do
            read -rp "➡️  ${GR}Select option (1-6) (or ${BL}navigation${NC} ${GR}choice${NC}): " choice
            
            case $choice in
                1)
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}=============================${NC}"
                    echo "${BO}1) 📋 System Profile Overview${NC}"
                    echo "${GR}=============================${NC}"
                    echo "↩️  System Information"
                    echo
                    # echo "📊 ${GR}Gathering complete system information...${NC}"
                    # echo "⏱️  This may take a few seconds..."
                    # echo
                    system_profiler SPHardwareDataType SPSoftwareDataType
                    echo "${BO}👤 User Account Details${NC}"
                    echo
                    echo "📊 ${GR}Current User Information:${NC}"
                    echo "${BO}Username:${NC} $(whoami)"
                    echo "${BO}UID:${NC}      $(id -u)"
                    echo "${BO}GID:${NC}      $(id -g)"
                    echo "${BO}Groups:${NC}   $(id -Gn)"
                    echo
                    echo "📋 ${GR}All System Users (UID 500+):${NC}"
                    dscl . -list /Users UniqueID | awk '$2 >= 500 {print "User: " $1 " | UID: " $2}' | sort -k4 -n
                    echo
                    echo "🔍 ${GR}Currently Logged In Users:${NC}"
                    w | tail -n +3 | awk '{print "User: " $1 " | UID: " $2 " | Login: " $4 " | From: " $3}'
                    echo
                    break
                    ;;
                2)
                    clear
                    echo "${GR}======================${NC}"
                    echo "${BO}2) 🖥️  Hardware Summary${NC}"
                    echo "${GR}======================${NC}"
                    echo "↩️  System Information"
                    echo
                    # echo "📊 ${GR}Gathering hardware information...${NC}"
                    # echo
                    system_profiler SPHardwareDataType
                    break
                    ;;
                3)
                    clear
                    echo "${GR}======================${NC}"
                    echo "${BO}3) 💿 Software Summary${NC}"
                    echo "${GR}======================${NC}"
                    echo "↩️  System Information"
                    echo
                    # echo "📊 ${GR}Gathering software information...${NC}"
                    # echo
                    system_profiler SPSoftwareDataType
                    break
                    ;;
                4)
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}========================${NC}"
                    echo "${BO}4) 🌐 Network Interfaces${NC}"
                    echo "${GR}========================${NC}"
                    echo "↩️  System Information"
                    echo
                    # echo "📊 ${GR}Gathering network information...${NC}"
                    # echo
                    system_profiler SPNetworkDataType
                    break
                    ;;
                5)
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}=================${NC}"
                    echo "${BO}5) 🔌 USB Devices${NC}"
                    echo "${GR}=================${NC}"
                    echo "↩️  System Information"
                    echo
                    # echo "📊 ${GR}Gathering USB device information...${NC}"
                    # echo
                    system_profiler SPUSBDataType
                    break
                    ;;
                6)
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}=====================${NC}"
                    echo "${BO}6) 💾 Storage Devices${NC}"
                    echo "${GR}=====================${NC}"
                    echo "↩️  System Information"
                    echo
                    # echo "📊 ${GR}Gathering storage information...${NC}"
                    # echo
                    system_profiler SPStorageDataType SPSerialATADataType
                    break
                    ;;
                7)
                    # set_terminal_height_to_1200p
                    clear
                    echo "${GR}==========================${NC}"
                    echo "${BO}7) 👤 User Account Details${NC}"
                    echo "${GR}==========================${NC}"
                    echo "↩️  System Information"
                    echo
                    echo "📊 ${GR}Current User Information:${NC}"
                    echo "${BO}Username:${NC} $(whoami)"
                    echo "${BO}UID:${NC}      $(id -u)"
                    echo "${BO}GID:${NC}      $(id -g)"
                    echo "${BO}Groups:${NC}   $(id -Gn)"
                    echo
                    echo "📋 ${GR}All System Users (UID 500+):${NC}"
                    dscl . -list /Users UniqueID | awk '$2 >= 500 {print "User: " $1 " | UID: " $2}' | sort -k4 -n
                    echo
                    echo "🔍 ${GR}Currently Logged In Users:${NC}"
                    w | tail -n +3 | awk '{print "User: " $1 " | UID: " $2 " | Login: " $4 " | From: " $3}'
                    echo
                    break
                    ;;
                *)
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break 2
                    fi
                    echo "❌ ${RE}Invalid option. Please choose 1-6.${NC}"
                    sleep 1
                    continue 2
                    ;;
            esac
        done     
        while true; do
            trimmed_output="$(show_navigation_prompt)"
            # Remove leading/trailing empty lines
            echo "$trimmed_output" | sed -e '1{/^$/d;}' -e '${/^$/d;}'
            echo
            # show_navigation_prompt # already padded

            return_to_menu=true
            interrupted=false
            trap 'echo; echo "returning from func 12"; return' SIGINT

            read -rp "➡️  ${GR}Choose another option? Press Enter (or ${BL}navigation${NC} ${GR}choice${NC}): " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                break
            else
                break
            fi
        done
    done
    set_terminal_height_to_500p
}

#====4==== 🔄 iCloud Sync Refresh
function icloud_sync_refresh() {
    while true; do
        return_to_menu=true
        trap 'echo; echo "Returning to main menu...from func 11"; return_to_menu=true; return' SIGINT
        clear
        echo "${GR}==========================${NC}"
        echo "${BO}11) 🔄 iCloud Sync Refresh${NC}"
        echo "${GR}==========================${NC}"
        echo "↩️  Main Menu"
        show_navigation_prompt # already padded
        echo "🔄 ${GR}Starting iCloud Sync Refresh...${NC}"
        echo
        echo "ℹ️  ${BO}This will restart the iCloud daemon (cloudd)${NC}"
        echo "   • iCloud sync will pause briefly and then resume"
        echo "   • May help resolve sync issues or stuck uploads"
        echo "   • All iCloud services will be affected momentarily"
        echo
        
        while true; do
            read -rp "➡️  ${GR}Refresh iCloud sync? (y/N)${NC}: " confirm

            # handle_navigation_input "$input"
            # nav=$?
            # if [[ $nav -eq $NAV_QUIT ]]; then
            #     return 0
            # elif [[ $nav -eq $NAV_BACK ]]; then
            #     return
            # fi

            case $confirm in
                [Yy]|[Yy][Ee][Ss])
                    echo
                    echo "☁️  ${GR}Restarting iCloud daemon...${NC}"
                    
                    return_to_menu=false
                    interrupted=false
                    trap 'echo; echo "🛑 ${RE}Interrupted by user.${NC}"; interrupted=true; break' SIGINT

                    # Kill the cloudd processes
                    # they will restart automatically - regarless of internet connection
                    killall cloudd
                    
                    echo "✅ ${GR}iCloud daemon restarted${NC}"
                    echo "   Sync processes will resume automatically."
                    # sleep 1
                    # echo
                    # echo "✅ ${GR}Done!${NC}"
                    # sleep 1
                    break
                    ;;

                [Nn]|[Nn][Oo])
                    echo
                    echo "❌ ${YE}iCloud refresh cancelled${NC}"
                    # sleep 1
                    break
                    ;;
                *)
                    handle_navigation_input "$confirm"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break 2 # back to main menu
                    fi
                    echo "❌ ${RE}Please enter y/yes or n/no${NC}"
                    # global_retry
                    sleep 1
                    continue 2
                    ;;
            esac
        done
        while true; do
            show_navigation_prompt # already padded

        return_to_menu=true
        interrupted=false
        trap 'echo; echo "returning from func 11"; return' SIGINT

            read -rp "➡️  ${GR}Return to main menu? Press Enter (or ${BL}navigation${NC} ${GR}choice${NC}): " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                break # back to main menu
            else
                break 2 # run again
            fi
        done
    done
}

#====5==== 💾 Disk Image Utility
function disk_image_utility () {
    while true; do
        return_to_menu=true
        trap 'echo; echo "Returning to main menu...from func 16"; return_to_menu=true; return' SIGINT
        clear
        echo "${GR}=========================${NC}"
        echo "${BO}16) 💿 Disk Image Utility${NC}"
        echo "${GR}=========================${NC}"
        echo "↩️  Main Menu"
        show_navigation_prompt # already padded
        echo "${BO}Choose an option.${NC}"
        echo "1) ${GR}Create new disk image${NC}"
        echo "2) ${GR}Resize existing disk image${NC}"
        echo
        read -rp "➡️  ${GR}Choose option [1-2] (or ${BL}navigation${NC} ${GR}choice)${NC}: " disk_util_choice
        handle_navigation_input "$disk_util_choice"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            break
        fi
        # if chose Creation option
        if [[ "$disk_util_choice" == "1" ]]; then
            # Step 1: Enter creation mode (empty vs from existing)
            while true; do
                clear
                echo "${GR}=====================${NC}"
                echo "${BO}💿 Create Disk Images${NC}"
                echo "${GR}=====================${NC}"
                echo "↩️  Disk Image Utility"
                show_navigation_prompt # already padded
                echo "${BO}Choose an option.${NC}"
                echo "1) ${GR}Create empty disk image${NC}"
                echo "2) ${GR}Create disk image from existing files/folders${NC}"
                echo
                read -rp "➡️  ${GR}Choose option [1-2] (or ${BL}navigation${NC} ${GR}choice)${NC}: " disk_creation_choice
                handle_navigation_input "$disk_creation_choice"
                nav=$?
                if [[ $nav -eq $NAV_QUIT ]]; then
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    continue 2
                fi
                # If from existing items, collect sources
                if [[ "$disk_creation_choice" == "2" ]]; then
                    sources_to_add=()                    
                    while true; do
                        clear
                        echo "${GR}===========================${NC}"
                        echo "${BO}Select Source Files/Folders${NC}"
                        echo "${GR}===========================${NC}"
                        echo "↩️  Create Disk Images"
                        show_navigation_prompt # already padded
                        echo "➡️  ${GR}Drag and drop one or more files/folders, then press Enter:${NC}"
                        echo
                        read -rp "" input
                        handle_navigation_input "$input"
                        nav=$?
                        if [[ $nav -eq $NAV_QUIT ]]; then
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            continue 2
                        fi

                        eval "set -- $input"

                        if [[ $# -eq 0 ]]; then
                            echo "❌ ${RE}No valid input provided.${NC}"
                            sleep 1
                            continue
                        fi

                        for item in "$@"; do
                            if [[ -e "$item" ]]; then
                                sources_to_add+=("$item")
                            else
                                echo "❌ ${RE}Skipping invalid path:${NC} $item"
                                sleep 1
                                continue
                            fi
                        done

                        if [[ ${#sources_to_add[@]} -gt 0 ]]; then
                            break
                        else
                            continue
                        fi
                    done
                # elif [[ "$disk_creation_choice" == "1" ]]; then # if create new
                #     continue 2
                fi    
                # Step 2: Name
                vol_name=""
                while true; do
                    clear
                    echo "${GR}===================${NC}"
                    echo "${BO}Set Disk Image Name${NC}"
                    echo "${GR}===================${NC}"
                    echo "↩️  Create Disk Images"
                    show_navigation_prompt # already padded
                    read -rp "➡️  ${GR}Enter a name for the disk image${NC}: " vol_name
                    handle_navigation_input "$vol_name"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break
                    fi

                    if [[ -n "$vol_name" ]]; then
                        # continue
                        echo
                        
                    else
                        echo "❌ ${RE}Name cannot be empty.${NC}"
                        sleep 1
                        continue
                    fi  
                    # Step 3: Size selection (sparse image)
                    disk_img_size=""
                    while true; do
                        clear
                        echo "${GR}======================${NC}"
                        echo "${BO}Choose Disk Image Size${NC}"
                        echo "${GR}======================${NC}"
                        echo "↩️  Set Disk Image Name"
                        show_navigation_prompt # already padded                        
                        echo "${YE}Note:${NC} ${BO}${GY}A sparse disk image will not use this space until you fill it.${NC}"
                        echo
                        echo "${BO}Choose an option${NC}"
                        echo "1) ${GR}1 GB${NC}"
                        echo "2) ${GR}5 GB${NC}"
                        echo "3) ${GR}25 GB${NC}"
                        echo "4) ${GR}Custom (GB)${NC}"
                        echo
                        read -rp "➡️  ${GR}Choose size [1-4] (or ${BL}navigation${NC} ${GR}choice)${NC}: " disk_img_size_choice
                        handle_navigation_input "$disk_img_size_choice"
                        nav=$?
                        if [[ $nav -eq $NAV_QUIT ]]; then
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            break
                        fi

                        case "$disk_img_size_choice" in
                            1) disk_img_size="1g";;
                            2) disk_img_size="5g";;
                            3) disk_img_size="25g";;
                            4)
                                while true; do
                                    clear
                                    echo "${GR}======================${NC}"
                                    echo "${BO}Custom Disk Image Size${NC}"
                                    echo "${GR}======================${NC}"
                                    echo "↩️  Choose Disk Image Size"
                                    show_navigation_prompt # already padded
                                    read -rp "➡️  ${GR}Enter custom size in GB (e.g., 12)${NC}: " custom_size_in_gb
                                    handle_navigation_input "$custom_size_in_gb"
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        break
                                    fi
                                    
                                    if echo "$custom_size_in_gb" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
                                        if [[ "$custom_size_in_gb" -gt 0 ]]; then
                                            disk_img_size="${custom_size_in_gb}g"
                                            break
                                        else
                                            echo "❌ ${RE}Please enter a whole number in GB (e.g., 10).${NC}"
                                            sleep 1
                                            continue
                                        fi   
                                    else
                                        echo "❌ ${RE}Please enter a number in GB (e.g., 10).${NC}"
                                        sleep 1
                                        continue
                                    fi
                                done    
                                ;;
                            *)
                                echo "❌ ${RE}Invalid choice. Please select 1-4.${NC}"
                                sleep 1
                                continue
                                ;;
                        esac
                        while true; do
                            # Step 4: Optional password (AES-256)
                            use_password="no"
                            password_value=""
                            while true; do
                                clear
                                echo "${GR}=============================${NC}"
                                echo "${BO}Password Protection (AES-256)${NC}"
                                echo "${GR}=============================${NC}"
                                echo "↩️  Choose Disk Image Size"
                                show_navigation_prompt # already padded
                                read -rp "➡️  ${GR}Set a password? (y/N)${NC}: " pw_choice
                                handle_navigation_input "$pw_choice"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break 2
                                fi

                                case "$pw_choice" in
                                    [Yy]|[Yy][Ee][Ss]) use_password="yes" ;;
                                    [Nn]|[Nn][Oo]) use_password="no" ;;
                                    *)
                                        echo "❌ ${RE}Please answer y/yes or n/no.${NC}"
                                        sleep 1
                                        continue
                                        ;;
                                esac

                                if [[ "$use_password" == "yes" ]]; then
                                    while true; do
                                        clear
                                        echo "${GR}=============================${NC}"
                                        echo "${BO}Password Protection (AES-256)${NC}"
                                        echo "${GR}=============================${NC}"
                                        echo "↩️  Choose Disk Image Size"
                                        show_navigation_prompt # already padded
                                        echo "${GR}Please choose password for the disk image.${NC}"
                                        # echo "${GR}You'll be asked to enter it twice.${NC}"
                                        # echo "${GR}It will also be hidden.${NC}"
                                        echo
                                        read -s -p "➡️  ${GR}Enter a password${NC}: " pw1
                                        handle_navigation_input "$pw1"
                                        nav=$?
                                        if [[ $nav -eq $NAV_QUIT ]]; then
                                            return 0
                                        elif [[ $nav -eq $NAV_BACK ]]; then
                                            break 2
                                        fi
                                        echo
                                        if [[ -z "$pw1" ]]; then
                                            echo "❌ ${RE}Password cannot be empty.${NC}"
                                            sleep 1
                                            continue
                                        fi    
                                        read -s -p "➡️  ${GR}Confirm password${NC}: " pw2
                                        handle_navigation_input "$pw2"
                                        nav=$?
                                        if [[ $nav -eq $NAV_QUIT ]]; then
                                            return 0
                                        elif [[ $nav -eq $NAV_BACK ]]; then
                                            break
                                        fi
                                        echo                 
                                        if [[ -z "$pw2" ]]; then
                                            echo "❌ ${RE}Password cannot be empty.${NC}"
                                            sleep 1
                                            continue
                                        fi      
                                        
                                        if [[ "$pw1" != "$pw2" ]]; then 
                                            echo "❌ ${RE}Passwords do not match. Try again.${NC}"
                                            sleep 1
                                            continue
                                        fi
                                        # fi
                                        # continue
                                        password_value="$pw1"
                                        break
                                    done
                                fi
                                # Step 5: Destination
                                dest_dir=""
                                while true; do
                                    clear
                                    echo "${GR}====================${NC}"
                                    echo "${BO}Choose Save Location${NC}"
                                    echo "${GR}====================${NC}"
                                    echo "↩️  Password Protection"
                                    show_navigation_prompt # already padded
                                    echo "${BO}Choose a location:${NC}"
                                    echo "1) ${GR}Save to Desktop${NC}"
                                    echo "2) ${GR}Choose a custom folder${NC}"
                                    echo
                                    read -rp "➡️  ${GR}Choose option [1-2] (or ${BL}navigation${NC} ${GR}choice)${NC}: " dest_choice
                                    handle_navigation_input "$dest_choice"
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then 
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        break
                                    fi

                                    if [[ "$dest_choice" == "1" ]]; then
                                        dest_dir="$HOME/Desktop" 
                                    elif [[ "$dest_choice" == "2" ]]; then
                                        custom_dest_dir=$(osascript -e 'try' \
                                                        -e 'set p to POSIX path of (choose folder with prompt "Choose destination folder for the disk image")' \
                                                        -e 'return p' \
                                                        -e 'on error' \
                                                        -e 'return ""' \
                                                        -e 'end try')
                                        if [[ -n "$custom_dest_dir" && -d "$custom_dest_dir" ]]; then
                                            dest_dir="${custom_dest_dir%/}"
                                        else
                                            echo "❌ ${RE}No folder chosen. Please try again.${NC}"
                                            sleep 1
                                            continue
                                        fi
                                    else
                                        echo "❌ ${RE}Invalid choice. Please select 1 or 2.${NC}"
                                        sleep 1
                                        continue
                                    fi
                                    # Disk Image Creation
                                    while true; do
                                        # Prepare path and create image via hdiutil
                                        disk_img_path="$dest_dir/$vol_name.sparseimage"
                                        # clear
                                        # echo "${GR}======================${NC}"
                                        # echo "${BO}Creating Disk Image...${NC}"
                                        # echo "${GR}======================${NC}"
                                        # echo "↩️  Disk Image Utility"
                                        # show_navigation_prompt # already padded
                                        # echo "📄 Name:        $vol_name"
                                        # echo "📦 Size:        $disk_img_size"
                                        # echo "🗂️  Location:    $dest_dir"
                                        # echo "🔒 Encrypted:   $( [[ "$use_password" == "yes" ]] && echo "Yes (AES-256)" || echo "No" )"
                                        # echo "📁 From Files:  $( [[ "$disk_creation_choice" == "2" ]] && echo "Yes" || echo "No" )"
                                        # echo

                                        create_ok=0
                                        if [[ "$use_password" == "yes" ]]; then
                                            printf "%s" "$password_value" | hdiutil create -type SPARSE -fs APFS -volname "$vol_name" -size "$disk_img_size" -encryption AES-256 -stdinpass "$disk_img_path" >/dev/null 2>&1
                                        else
                                            hdiutil create -type SPARSE -fs APFS -volname "$vol_name" -size "$disk_img_size" "$disk_img_path" >/dev/null 2>&1
                                        fi

                                        if [[ $? -eq 0 ]]; then 
                                            create_ok=1
                                        fi

                                        if [[ $create_ok -ne 1 ]]; then
                                            echo "❌ ${RE}Failed to create disk image.${NC}"
                                            echo "Please check that the name doesn't already exist"
                                            # echo
                                            show_navigation_prompt # already padded
                                            read -rp "➡️  ${GR}Press Enter to try again (or ${BL}navigation${NC} ${GR}choice)${NC}: " input
                                            handle_navigation_input "$input"
                                            nav=$?
                                            if [[ $nav -eq $NAV_QUIT ]]; then
                                                return 0
                                            elif [[ $nav -eq $NAV_BACK ]]; then
                                                break
                                            else
                                                continue
                                            fi
                                        fi

                                        # If from existing, attach, copy, detach
                                        if [[ "$disk_creation_choice" == "2" && ${#sources_to_add[@]} -gt 0 ]]; then
                                            # echo "🔄 ${GR}Populating image with selected items...${NC}"      
                                            mount_point="/Volumes/$vol_name"
                                            
                                            if [[ "$use_password" == "yes" ]]; then
                                                printf "%s" "$password_value" | hdiutil attach -stdinpass -nobrowse -mountpoint "$mount_point" "$disk_img_path" >/dev/null 2>&1
                                            else
                                                hdiutil attach -nobrowse -mountpoint "$mount_point" "$disk_img_path" >/dev/null 2>&1
                                            fi
                                            
                                            if [[ $? -ne 0 ]]; then
                                                echo "❌ ${RE}Failed to attach disk image for copying.${NC}"
                                            else
                                                for src in "${sources_to_add[@]}"; do 
                                                    cp -R "$src" "$mount_point/" 2>/dev/null
                                                done
                                                sync
                                                hdiutil detach "$mount_point" >/dev/null 2>&1
                                            fi
                                        fi

                                        # Summary
                                        echo
                                        echo "================================================================================"
                                        echo "${BO}Results:${NC}"
                                        if [[ -f "$disk_img_path" ]]; then
                                            echo "✅ ${GR}Disk image created successfully!${NC}"
                                            echo "📄 Name:        $vol_name"
                                            echo "📦 Size:        $disk_img_size (sparseimage)"
                                            echo "🔒 Encrypted:   $( [[ "$use_password" == "yes" ]] && echo "Yes (AES-256)" || echo "No" )"
                                            echo "🗂️  Location:    $dest_dir"
                                            echo "📁 From Files:  $( [[ "$disk_creation_choice" == "2" ]] && echo "Yes" || echo "No" )"
                                            if [[ "$disk_creation_choice" == "2" ]]; then 
                                                echo "📁 Seeded:      ${#sources_to_add[@]} item(s)"
                                            fi
                                        else
                                            echo "❌ ${RE}Disk image not found at destination.${NC}"
                                        fi
                                        echo "================================================================================"
                                        echo
                                        # show_navigation_prompt # already padded
                                        read -rp "➡️  ${GR}Create another image? Press Enter (or ${BL}navigation${NC} ${GR}choice)${NC}: " input
                                        handle_navigation_input "$input"
                                        nav=$?
                                        if [[ $nav -eq $NAV_QUIT ]]; then 
                                            return 0
                                        elif [[ $nav -eq $NAV_BACK ]]; then
                                            break
                                        else
                                            break 6
                                        fi
                                    done
                                done 
                            done 
                        done    
                    done                     
                done
            done
        # if chose Resizing option
        elif [[ "$disk_util_choice" == "2" ]]; then
            while true; do
                clear
                echo "${GR}====================${NC}"
                echo "${BO}Choose Disk Image...${NC}"
                echo "${GR}====================${NC}"
                echo "↩️  Disk Image Utility"
                show_navigation_prompt # already padded
                echo "➡️  ${GR}Drag and drop a .sparseimage (or .sparsebundle) here, then press Enter:${NC}"
                echo
                while true; do
                    read -rp "" disk_img_input
                    handle_navigation_input "$disk_img_input"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        continue 3
                    fi

                    eval "set -- $disk_img_input"
                    
                    if [[ $# -lt 1 ]]; then
                        echo "❌ ${RE}No path provided.${NC}"
                        sleep 1
                        continue 2
                    fi

                    while true; do
                        selected_disk_img_for_resize="$1"
                        if [[ ! -e "$selected_disk_img_for_resize" ]]; then
                            echo "❌ ${RE}Path not found.${NC}"
                            sleep 1
                            continue 3
                        fi

                        # Choose Resize Option
                        while true; do
                            clear
                            echo "${GR}================================================================================${NC}"
                            echo "${BO}Resize: $(basename "$selected_disk_img_for_resize")${NC}"
                            echo "${GR}================================================================================${NC}"
                            echo "↩️  Choose Disk Image..."
                            show_navigation_prompt # already padded
                            echo "1) ${GR}Grow maximum size${NC}"
                            echo "2) ${GR}Compact free space${NC}"
                            echo
                            read -rp "➡️  ${GR}Choose option [1-2] (or ${BL}navigation${NC} ${GR}choice)${NC}: " disk_resize_choice
                            handle_navigation_input "$disk_resize_choice"
                            nav=$?
                            if [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                break 3
                            fi
                            
                            # If Grow Image
                            if [[ "$disk_resize_choice" == "1" ]]; then
                                # Grow Image
                                while true; do
                                    clear
                                    echo "${GR}================================================================================${NC}"
                                    echo "${BO}Grow: $(basename "$selected_disk_img_for_resize")${NC}"
                                    echo "${GR}================================================================================${NC}"
                                    echo "↩️  Resize $(basename "$selected_disk_img_for_resize")"
                                    show_navigation_prompt # already padded
                                    handle_navigation_input
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        break
                                    fi

                                    # Get size in bytes, then convert
                                    get_current_file_size() {
                                        # local file="$selected_disk_img_for_resize"
                                        local bytes=$(stat -f%z "$selected_disk_img_for_resize")
                                        if [ "$bytes" -ge 1000000000 ]; then
                                            awk "BEGIN {printf \"%.2f GB (%.2f GiB)\", $bytes/1000000000, $bytes/1073741824}"
                                        else
                                            awk "BEGIN {printf \"%.2f MB (%.2f MiB)\", $bytes/1000000, $bytes/1048576}"
                                        fi
                                    }
                                    
                                    size_before=$(get_current_file_size "$selected_disk_img_for_resize")
                                    
                                    # echo "Getting current encryption status..."
                                    # echo
                                    # Getting encryption status...${NC}"       
                                    get_image_info() {
                                        # local file="$selected_disk_img_for_resize"
                                        local info_output=$(hdiutil imageinfo "$selected_disk_img_for_resize" 2>/dev/null | grep "Encryption") # | head -20)
                                        
                                        # Check encryption from the header info
                                        if echo "$info_output" | grep -qi "AES-256"; then
                                            echo "Yes (AES-256)"
                                        else
                                            echo "None"
                                        fi
                                    }

                                    echo "${GR}Getting current image size...${NC}"       

                                    encryption_status=$(get_image_info "$selected_disk_img_for_resize")
                                    # size_before=$(stat -f%z "$selected_disk_img_for_resize")

                                    # size_after=$(stat -f%z "$selected_disk_img_for_resize")
                                    
                                    echo "📦 Old Size:    $size_before (sparseimage)"
                                    # echo
                                    read -rp "➡️  ${GR}Enter new maximum size (e.g., 10g)${NC}: " new_size
                                    
                                    handle_navigation_input "$new_size"
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        continue 2
                                    fi

                                    if echo "$new_size" | grep -E '^[0-9]+[gGmMkKtT]$' >/dev/null 2>&1; then
                                        # echo
                                        echo "${GR}Growing...${NC}"
                                        hdiutil resize -size "$new_size" "$selected_disk_img_for_resize" >/dev/null 2>&1
                                        
                                        if [[ $? -eq 0 ]]; then
                                            echo "✅ ${GR}Grew successfully${NC}"
                                            sleep 1
                                            break
                                        else
                                            echo "❌ ${RE}Grow failed${NC}"
                                            sleep 1
                                            echo "${GR}Please try again - or try re-uploading.${NC}"
                                            sleep 2
                                            continue
                                        fi
                                    else
                                        echo "❌ ${RE}Use units like 10g, 500m, etc.${NC}"
                                        sleep 1
                                        continue
                                    fi
                                done
                            # If Compact Image
                            elif [[ "$disk_resize_choice" == "2" ]]; then
                                # Compact Image  
                                clear
                                echo "${GR}================================================================================${NC}"
                                echo "${BO}Compact: $(basename "$selected_disk_img_for_resize")${NC}"
                                echo "${GR}================================================================================${NC}"
                                echo "↩️  Resize $(basename "$selected_disk_img_for_resize")"
                                show_navigation_prompt # already padded
                                handle_navigation_input
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break 2
                                fi
                                
                                # Get size in bytes, then convert
                                # comp_old_size=$(hdiutil imageinfo "$disk_img_input" | grep "Total Bytes:" | awk '{if ($3 >= 1000000000) printf "%.2f GB (%.2f GiB)", $3/1000000000, $3/1073741824; else printf "%.2f MB (%.2f MiB)", $3/1000000, $3/1048576}')                            
                                get_current_file_size() {
                                    # local file="$selected_disk_img_for_resize"
                                    local bytes=$(stat -f%z "$selected_disk_img_for_resize")
                                    if [ "$bytes" -ge 1000000000 ]; then
                                        awk "BEGIN {printf \"%.2f GB (%.2f GiB)\", $bytes/1000000000, $bytes/1073741824}"
                                    else
                                        awk "BEGIN {printf \"%.2f MB (%.2f MiB)\", $bytes/1000000, $bytes/1048576}"
                                    fi
                                }

                                size_before=$(get_current_file_size "$selected_disk_img_for_resize")
                                
                                # echo "Getting current encryption status..."
                                # echo
                                
                                get_image_info() {
                                    # local file="$selected_disk_img_for_resize"
                                    local info_output=$(hdiutil imageinfo "$selected_disk_img_for_resize" 2>/dev/null | grep "Encryption") # | head -20)
                                    
                                    # Check encryption from the header info
                                    if echo "$info_output" | grep -qi "AES-256"; then
                                        echo "Yes (AES-256)"
                                    else
                                        echo "None"
                                    fi
                                }

                                echo "${GR}Getting current image size...${NC}"
                                
                                encryption_status=$(get_image_info "$selected_disk_img_for_resize")
                                # size_before=$(stat -f%z "$selected_disk_img_for_resize")

                                # size_after=$(stat -f%z "$selected_disk_img_for_resize")

                                echo "${GR}Compacting...${NC}"

                                hdiutil compact "$selected_disk_img_for_resize" >/dev/null 2>&1
                                if [[ $? -eq 0 ]]; then 
                                    echo "✅ ${GR}Compacted successfully${NC}"
                                    sleep 1
                                else
                                    echo "❌ ${RE}Compact failed.${NC}" 
                                    sleep 1
                                    echo "${GR}Please try again - or try re-uploading.${NC}"
                                    sleep 2
                                    continue
                                fi
                            else
                                echo "❌ ${RE}Invalid choice.${NC}"
                                sleep 1
                                continue
                            fi

                            # not using - requires password for each command
                            # is_comp_encrypted=($(hdiutil imageinfo $disk_img_input | grep "Encrypted" >/dev/null 2>&1))
                            # comp_new_size=$(hdiutil imageinfo "$selected_disk_img_for_resize" | grep "Total Bytes:" | awk '{if ($3 >= 1000000000) printf "%.2f GB (%.2f GiB)", $3/1000000000, $3/1073741824; else printf "%.2f MB (%.2f MiB)", $3/1000000, $3/1048576}')

                            size_after=$(get_current_file_size "$selected_disk_img_for_resize")

                            # Show Resize Summary
                            while true; do
                                echo
                                echo "================================================================================"
                                echo "${BO}Results:${NC}"
                                # echo "✅ ${GR}Resized to $new_size successfully${NC}"
                                # if [[ -f "$selected_disk_img_for_resize" ]]; then
                                # echo "✅ ${GR}Disk resized successfully!${NC}"
                                # echo "📄 Name:        $selected_disk_img_for_resize"
                                # if [[ -e "$comp_new_size" ]]; then
                                echo "📄 Name:        $(basename "$selected_disk_img_for_resize")"
                                echo "📦 Old Size:    $size_before (sparseimage)"
                                echo "📦 New Size:    $size_after (sparseimage)"
                                # fi
                                # if [[ $is_comp_Encrypted == true ]]; then
                                #     echo "Encrypted"
                                # else
                                #     echo "None"
                                # fi

                                # hdiutil -imageinfo $disk_img_input | grep "Name"
                                # if [[ $is_comp_Encrypted == true ]]; then
                                #     echo "🔒 Encrypted:   Yes (AES-256)"
                                # else
                                #     echo "🔒 Encrypted:   No"
                                # fi
                                echo "🔒 Encryption:  $( [[ "$$encryption_status" == "Yes (AES-256)" ]] && echo "Yes (AES-256)" || echo "None" )"
                                echo "🗂️  Location:    $disk_img_input"
                                echo "================================================================================"
                                # show_navigation_prompt # already padded
                                echo
                                read -rp "➡️  ${GR}Resize another image? Press Enter (or ${BL}navigation${NC} ${GR}choice)${NC}: " input
                                handle_navigation_input "$input"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then 
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break 2
                                else [[ $nav -eq $NAV_CONT ]]
                                    break 4
                                fi
                            done
                        done
                    done
                done    
            done
        else
            echo "❌ ${RE}Invalid choice. Please select 1 or 2.${NC}"
            sleep 1
            continue
        fi
    done    
}

#====6==== 🔗 create_symlink
function create_symlink() {
    while true; do
        return_to_menu=true
        trap 'echo; echo "Returning to main menu...from func 6"; return_to_menu=true; return' SIGINT
        clear
        echo "${GR}=======================${NC}"
        echo "${BO}6) 🔗 Create Symlink(s)${NC}"
        echo "${GR}=======================${NC}"
        echo "↩️  Main Menu"
        show_navigation_prompt # already padded
        # Step 1: Prompt for Source files
        echo "📂 ${BO}Step 1 of 2:${NC}"
        echo "${GR}Please drag and drop one or more"
        echo "SOURCE files/folders onto this terminal window,"
        echo "then press Enter:${NC}"
        echo
        read -rp "" input

        handle_navigation_input "$input"
        nav=$?
        if   [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            break
        fi

        # Process input to handle escaped spaces and special characters
        eval "set -- $input"

        # Initialize Counters
        local input_count=$#
        local files_found=()
        local paths_to_process=()
        #local symlink_count=0
        local processed_count=0
        local processed_failed=0
        local processed_skipped=0

        if [ "$input_count" -eq 0 ]; then
            echo "❌ ${RE}No valid input provided.${NC}"
            sleep 1
            echo "Please drag and drop valid files and try again."
            sleep 1
            continue
        fi

        # Validate Source Paths
        for source in "$@"; do
            if [ -e "$source" ]; then
                # sfilename=$(basename "$source")
                paths_to_process+=("$source")
                #((symlink_count++))
            else    
                echo "❌ ${RE}Invalid source path: $source${NC}"
            fi
        done
        if [ "${#paths_to_process[@]}" -eq 0 ]; then
            echo "Please drag and drop valid files and try again."
            global_retry
            continue
        fi

        # Destination Directory Selection (Nested Loop 2)
        while true; do
            show_navigation_prompt # already padded
            # Step 2: Prompt for Destination folder
            echo "📁 ${BO}Step 2 of 2:${NC}"
            echo "${GR}Drop the DESTINATION folder here,"
            echo "then press Enter:${NC}"
            echo
            read -rp "" dest_input

            handle_navigation_input "$dest_input"
            nav=$?
            if   [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                continue 2   # pop back to main menu
            fi
            
            while true; do
                # Process and validate the destination path
                destination="$(eval echo "$dest_input")"
                
                if [ ! -d "$destination" ]; then
                    xfilename=$(basename "$destination")
                    # echo
                    echo "❌ ${RE}Destination is not a valid directory:${NC}"
                    # echo "$xfilename"
                    global_retry
                    nav=$?
                    if [[ $nav -eq $NAV_BACK ]]; then
                        return 0
                    fi
                    continue 2
                fi

                while true; do
                    # Create symlinks
                    for source in "${paths_to_process[@]}"; do

                        # Check if we've been interrupted before processing
                        # if [ "$interrupted" = true ]; then
                        #     break 4
                        # fi

                        sfilename=$(basename "$source")
                        dfilename=$(basename "$destination")
                        # echo
                        # echo "🔗 ${BO}${GR}sudo ln -s${NC} $sfilename... → ${CY}$dfilename${NC}"
                        # echo
                        # echo "$sfilename... → ${CY}$dfilename${NC}"
                        # echo

                        return_to_menu=false
                        interrupted=false
                        trap 'echo; echo "🛑 ${RE}Interrupted by user.${NC} Showing summary..."; interrupted=true; break' SIGINT

                        sudo ln -s "$source" "$destination/$basename" 2>/dev/null

                        if [ $? -eq 0 ]; then
                            # echo
                            # echo "✅ ${BO}Done.${NC}"
                            echo "🔗 ${GR}sudo ln -s${NC} $sfilename → ${CY}$dfilename${NC}"
                            ((processed_count++)) # add to processed counter
                        else
                            # echo
                            echo "❌ ${RE}Failed to create symlink(s).${NC}"
                            ((processed_failed++)) # add to failed counter
                        fi
                        # Check for interruption after updating counters
                        # if [ "$interrupted" = true ]; then
                        #     break 4  # Break out of all loops to reach summary
                        # fi 
                    done
                    # If we completed all symlinks without interruption, break out
                    break 3 # Break out to summary
                done

                break 2 # This should never be reached due to break 3 above
            done   
        done     

                # break

        # Final summary
        echo
        echo "============================"  
        echo "${BO}Results:${NC}"
        echo "🛣️  Total paths found:     ${NC}$input_count"
        echo "🔗 Total links ${GR}processed${NC}: $processed_count"
        echo "⚠️  Total items ${RE}failed${NC}:    $processed_failed"
        echo "============================"  
        echo
        echo "${BO}Let's link later${NC} 🦾" 
        show_navigation_prompt # already padded

        return_to_menu=true
        interrupted=false
        trap 'echo; echo "returning from func 6"; return' SIGINT

        read -rp "➡️  ${GR}Process another file? Press Enter (or ${BL}navigation${NC} ${GR}choice${NC}): " input
        
        handle_navigation_input "$input"
        nav=$?
        if   [[ $nav -eq $NAV_QUIT ]]; then 
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then 
            continue # back to main menu
        else [[ $nav -eq $NAV_CONT ]]
            continue # back to main menu
        fi   
    done
}

#====7==== ⚙️ MacOS Preferences
function macos_preferences() {
    return_to_menu=true
    trap 'echo; echo "Returning to main menu...from func 14"; return_to_menu=true; return' SIGINT
    set_terminal_height_to_1200p
    # Define preference commands with their active/inactive/reset actions
    declare -a preference_commands=(

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🆕 [NEW for ${BL}macOS Tahoe 26]${NC}|"
        "🔑 Passwords: Disallow Contacting Websites ${BL}(Tahoe 26+)${NC}|com.apple.Passwords|WBSPasswordsAppBackgroundNetworkingEnabled|false|true||delete|Prevents network telemetry with websites from saved passwords. (This is how icons and names get shown)"
        "📋 Menu Bar: Show Menu Bar Background ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|SLSMenuBarUseBlurredAppearance|true|||delete|Shows or disables the menu bar's blurred appearance"
        "📁 Finder: 'Tint Folders Based On Tags' ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|AppleDisableTagBasedIconTinting||true||delete|Tints folders based on tags"
        "🗂️  Safari: Show Color Tab Bar ${BL}(Tahoe 26+)${NC}|com.apple.Safari|NeverUseBackgroundColorInToolbar|false|true|false|false|Shows color in Safari's tab bar"
        "💬 Messages: Screen Unknown Senders ${BL}(Tahoe 26+)${NC}|com.apple.MobileSMS|FilterMessageRequests|true|false|false|false|Screens unknown senders"
        "💬 Messages: Disable Automatic Sharing ${BL}(Tahoe 26+)${NC}|com.apple.SocialLayer|SharedWithYouEnabled|false|true|true|true|Screens unknown senders"
        "🌑 Appearance: Enable dark mode on icons ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|AppleIconAppearanceTheme|RegularDark|||darkmode|"
        "📞 Phone: Filter Unknown Callers ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|filterUnknownCallersAsNewCallers|true|false|false|false|Filters unknown callers"
        "✏️  Preview: Show Markup toolbar for PDFs by default ${BL}(Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForPDFs|true|false|false|delete|Shows Markup toolbar for PDFs by default"
        "✏️  Preview: Show Markup toolbar for images by default ${BL}(Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForImages|true|false|false|delete|Shows Markup toolbar for images by default"
        "📋 Menu Bar: Never Hide Menu Bar In Fullscreen ${BL}(Tahoe 26+)${NC}|com.apple.controlcenter|AutoHideMenuBarOption|3|2||NevaHideMenuBarinTahoe|Never hides the menu bar when in full screen"
        # "🖥️  Never Hide Menu Bar In Fullscreen|NSGlobalDomain|AppleMenuBarVisibleInFullscreen|true|false|false|delete|Never hides the menu bar when in full screen"
        "🔍 Spotlight: Enable Clipboard Manager/Search ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|SPPasteboardFTEEngaged|true|false|false|false|Enable Spotlight's Clipboard Manager/Search"
        # "🔍 Spotlight: Increase Clipboard history from 8hrs to 24hrs ${BO}(Untested)${NC} ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|PasteboardHistoryTimeout|86400|28800|28800|28800|Increase Clipboard history from 8hrs to 24hrs ${BO}(Untested)${NC}"
        "📏 Shrink sidebar width to the minimum (1 of 2) ${BL}(Tahoe 26+)${NC}|com.apple.finder|SidebarWidth2|135|161|188||Shrinks sidebar width to the minimum"    # Tahoe 26+
        "📏 Shrink sidebar width to the minimum (2 of 2) ${BL}(Tahoe 26+)${NC}|com.apple.finder|FK_SidebarWidth2|135|161|161||Shrinks sidebar width (in other views) to the minimum"    # Tahoe 26+
        
        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🆕 [NEW for ${BO}${GY}${GR}macOS Sonoma 14${NC} - ${MA}macOS Sequoia 15${NC}]|"
        "🚫 Dock: Disable 'click walpaper to show Desktop' ${BO}${GY}${GR}(Sonoma 14+)${NC}|com.apple.WindowManager|EnableStandardClickToShowDesktop|false|true|true||"
        "🚫 Dock: Disable 'Drag windows to screen edges to tile' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTilingByEdgeDrag|false|true|true|delete|"
        "🚫 Dock: Disable 'Drag windows to menu bar to fill screen' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTopTilingByEdgeDrag|false|true|true|delete|"
        "🪟 Dock: Enable 'Hold ⌥ key while dragging windows to tile' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTilingOptionAccelerator|true|false|true|delete|"
        "🚫 Dock: Disable 'Tiled windows have margins' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTiledWindowMargins|false|true|true|delete|"
        "🔑 Passwords: Show Passwords In The Menu Bar ${MA}(Sequoia 15+)${NC} ${BO}[Please enable manually for the first time]${NC}|com.apple.Passwords|EnableMenuBarExtra|true|false|false|PasswordManager|Shows the Passwords sub-menu icon in the menu bar"
        "🚫 Apple AI: Disable Apple Intelligence|com.apple.CloudSubscriptionFeatures.optIn|Dynamic (check with 'defaults read com.apple.CloudSubscriptionFeatures.optIn')|false|true|false|disable_Apple_Intelligence|Disables Apple Intelligence"
        "🕵️‍♂️  Spotlight: Disable 'Help Apple Improve Search'|com.apple.assistant.support|Search Queries Data Sharing Status|2|1|ture|delete|Disables 'Help Apple Improve Search'"
        "♿️ Accessibility: Zoomed Image While Screen Sharing|com.apple.universalaccess|closeViewZoomScreenShareEnabledKey|true|false|false|delete|Enables showing zoomed image while screen sharing"
        "🔎 Accessibility: Zoom Each Display Independently|com.apple.universalaccess|closeViewZoomIndividualDisplays|true|false|false|delete|Zooms each display independently"
        "⚡️ Energy: Show Low Power Mode in Menu Bar|com.apple.controlcenter|EnergyModeModule|9|19|19|-currentHost|Shows Low Power Mode control in the menu bar"
        "🚫 Finder: Hide Warning before removing from iCloud Drive ${MA}(Sequoia 15+)${NC}|com.apple.bird|com.apple.clouddocs.unshared.moveOut.suppress|1|0||delete|Disables the 'Remove from iCloud Drive' warning."
        "💾 Disk Utility: Show APFS Snapshots ${MA}(Sequoia 15+)${NC}|com.apple.DiskUtility|WorkspaceShowAPFSSnapshots|true|false|false|false|Disables the 'Remove from iCloud Drive' warning."

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|♿️ [Accessibility]|⚠️  ${YE}(Terminal requires Full Disk Access to write changes)${NC}"
        "🔎 Enable Zoom Hot Keys|com.apple.universalaccess|closeViewHotkeysEnabled|true|false|false|delete|Enables global zoom functionality via hot keys"
        "🔎 Zoom Continuously with Pointer|com.apple.universalaccess|closeViewPanningMode|false|true|false|false|Zooms continuously with pointer"
        "🔎 Zoom Always Follows Keyboard Focus|com.apple.universalaccess|closeViewZoomFocusFollowModeKey|1|2|2|delete|Zoom always follows keyboard focus when typing"
        "🔎 Keyboard Focus Centers Screen Image|com.apple.universalaccess|closeViewZoomFocusMovement|false|true|true|delete|Keyboard focus centers screen image"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|⚓️ [Dock]|"
        "🗑️  Wipe all app icons from Dock ${BO}(for fresh installs)${NC}|com.apple.dock|persistent-apps|-array|||delete|Removes all default app icons from the Dock."
        "👻 Dim Dock Icons of Hidden Apps|com.apple.dock|showhidden|true|false||delete|Makes hidden app icons appear dimmed in the Dock"
        "🫥 Auto-hide the Dock when the mouse is out|com.apple.dock|autohide|true|false||delete|Automatically hides the Dock when the cursor leaves the Dock area"
        "⚡ Make the dock appear faster ${BO}(Initial Auto-hide must be enabled)${NC}|com.apple.dock|autohide-time-modifier|0.0|0.5||delete|Make the dock appear faster (when auto-hide is active)"
        "⚡ Make the dock disappear faster ${BO}(Initial Auto-hide must be enabled)${NC}|com.apple.dock|autohide-delay|0|0.2|0.2|0.2|Make the dock disappear faster (when auto-hide is active)"
        "⚡ Minimize windows using Scale effect instead of Genie|com.apple.dock|mineffect|scale|genie||delete|Changes minimize animation from Genie to Scale effect"
        "📥 Minimize windows into their application icon|com.apple.dock|minimize-to-application|true|false||delete|Minimizes windows into their app icon instead of separate dock tile"
        "🚫 Disable Recent Items in Dock|com.apple.dock|show-recents|false|true||delete|Hides recent items from the Dock"
        "🚫 Speed Up Drag and Drop Spring Delay on Dock items|com.apple.dock|enable-spring-load-actions-on-all-items|false|true|true|true|Speeds up drag and drop spring delay on dock items."
        "⚪️ Show indicator lights for open apps ${BO}(depreciated)${NC}|com.apple.dock|show-process-indicators|true|false||delete|Shows dots under open applications in the Dock"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        # "GROUP|🖥️  [Desktop & Other Icon Views]|"
        # "⚙️  Set Custom Icon Views: Info/Labels/Arrange/Text/Icon/Grid|~/Library/Preferences/com.apple.finder.plist|PLISTBUDDY|Set :DesktopViewSettings:IconViewSettings:showItemInfo true|||-|plistbuddy|Applies multiple icon-view settings"
        # "⚙️  Set Custom Icon Views: Batch Apply|~/Library/Preferences/com.apple.finder.plist|PLISTBUDDY|'Set :DesktopViewSettings:IconViewSettings:showItemInfo true||Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true||Set :StandardViewSettings:IconViewSettings:showItemInfo true||Set :DesktopViewSettings:IconViewSettings:labelOnBottom true||Set :FK_StandardViewSettings:IconViewSettings:labelOnBottom true||Set :StandardViewSettings:IconViewSettings:labelOnBottom true||Set :DesktopViewSettings:IconViewSettings:arrangeBy name||Set :FK_StandardViewSettings:IconViewSettings:arrangeBy name||Set :StandardViewSettings:IconViewSettings:arrangeBy name||Set :DesktopViewSettings:IconViewSettings:textSize 14||Set :FK_StandardViewSettings:IconViewSettings:textSize 12||Set :StandardViewSettings:IconViewSettings:textSize 12||Set :DesktopViewSettings:IconViewSettings:iconSize 72||Set :FK_StandardViewSettings:IconViewSettings:iconSize 64||Set :StandardViewSettings:IconViewSettings:iconSize 72||Set :DesktopViewSettings:IconViewSettings:gridSpacing 71||Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 54||Set :StandardViewSettings:IconViewSettings:gridSpacing 71'||||plistbuddy|Desktop and icon-view layout"

        # "Show item info near icons on desktop & other icon views|~/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:showItemInfo|true|false|false|IconView_showItemInfo|"
        # "Show item info below icons on desktop & other icon views|~/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:labelOnBottom|true|false|false|IconView_labelOnBottom|"
        # "Enable sort-by-name for icons on desktop & other icon views|~/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:arrangeBy|name|false|false|IconView_arrangeBy|"
        # "Set text size for item info on desktop to 14|~/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:textSize|true|false|false|IconView_textSize|"
        # "Increase the size for item info on desktop to 72|~/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:iconSize|true|false|false|IconView_iconSize|"
        # "Increase grid spacing for icons on the desktop|~/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:gridSpacing|true|false|false|IconView_gridSpacing|"
        
        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"        
        # "GROUP|🔍 [Spotlight]|"
        # "🚫 Disable Indexing for Custom Items (When using FindAnyFile)|com.apple.spotlight|orderedItems|'{\"enabled\"=1;\"name\"=\"APPLICATIONS\";}' '\"{\"enabled\"=0;\"name\"=\"MENU_EXPRESSION\";}\" … (etc)’||defaults_array|Sets Spotlight orderedItems"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🔄 [Automatic Updates]|🔧 ${YE}(Shows current states only. Please adjust manually)${NC}"
        # "OLD=🚫 Disable macOS Auto-Update|softwareupdate|schedule|off|on||sudo|Disables automatic software updates"
        "🔄 Automatically Download macOS Updates|/Library/Preferences/com.apple.SoftwareUpdate|AutomaticDownload|true|false||SoftwareUpdates|"
        "🔄 Automatically Install macOS Updates|/Library/Preferences/com.apple.SoftwareUpdate|AutomaticallyInstallMacOSUpdates|true|false||SoftwareUpdates|"
        "🔄 Automatically Check for macOS Updates|/Library/Preferences/com.apple.SoftwareUpdate|AutomaticCheckEnabled|true|false||SoftwareUpdates|"
        "🔄 Automatically Install Config Data|/Library/Preferences/com.apple.SoftwareUpdate|ConfigDataInstall|true|false||SoftwareUpdates|"
        "🔄 Automatically Install Critical Updates|/Library/Preferences/com.apple.SoftwareUpdate|CriticalUpdateInstall|true|false||SoftwareUpdates|"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|⚙️  [System & UI]|"
        "🗂️  Always prefer tabs when opening documents|NSGlobalDomain|AppleWindowTabbingMode|always|manual||delete|Always prefer tabs when opening documents, not just in full-screen"
        "📜 Always Show Scroll Bars|NSGlobalDomain|AppleShowScrollBars|Always|Automatic||delete|Always shows scroll bars instead of auto-hiding"
        "🖱️  Change scrollbar to jump to the spot that's clicked|NSGlobalDomain|AppleScrollerPagingBehavior|true|false||delete|Makes scrollbars jump to clicked position"
        "📂 Expand Save Panel by Default (in Carbon/Cocoa apps)|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode|true|false||delete|Expands save dialogs system-wide (in Carbon/Cocoa apps) by default"
        "📂 Expand Save Panel by Default (in modern apps)|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode2|true|false||delete|Expands save dialogs system-wide (in modern apps) by default"
        "⚠️  Always ask to keep changes when closing documents|NSGlobalDomain|NSCloseAlwaysConfirmsChanges|true|false||delete|Always ask to keep changes when closing documents"
        "🖼️  Close All Windows After Quitting An Application|NSGlobalDomain|NSQuitAlwaysKeepsWindows|false|true|false|false|When enabled, open documents and windows will be not restored when you re-open an application."
        "🚫 Disable Universal Control|com.apple.universalcontrol|Disable|1|delete|delete|-currentHost|Disables Universal Control"
        "🚫 Disable Dashboard ${BO}(depreciated)${NC}|com.apple.dashboard|mcx-disabled|true|false|false|false|Disables Dashboard and widgets on older macOS's"
        "🚫 Disable Notification Center ${BO}(depreciated)${NC}|launchctl|/System/Library/LaunchAgents/com.apple.notificationcenterui|unload|load|load|launchctl|Disables Notification Center on older macOS's"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🪄 [Animations]|"
        "🚫 Disable Automatic Window Animations|NSGlobalDomain|NSAutomaticWindowAnimationsEnabled|false|true||delete|Disables automatic window animations system-wide"
        "🚫 Disable Finder Info Window Animations|com.apple.finder|DisableAllAnimations|true|false||delete|Disables all Finder info window animations"
        "🚫 Disable QuickLook Animations|NSGlobalDomain|QLPanelAnimationDuration|0.0|0.25||delete|Disables QuickLook panel animations"
        "🚀 Speed Up Mission Control Animations|com.apple.dock|expose-animation-duration|0.1|0.5||delete|Speeds up Mission Control animations"
        "🚀 Speed Up Finder's Drag and Drop Spring Delay|NSGlobalDomain|com.apple.springing.delay|0.2|0.5||delete|Reduces spring delay for Finder drag and drop"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|💾 [Disks]|"
        "💾 Show internal hard disks on desktop|com.apple.finder|ShowHardDrivesOnDesktop|true|false||delete|Shows internal hard disks on desktop"
        "💾 Show external hard disks on desktop|com.apple.finder|ShowExternalHardDrivesOnDesktop|true|false||delete|Shows external hard disks on desktop"
        "💾 Show removable media on desktop|com.apple.finder|ShowRemovableMediaOnDesktop|true|false||delete|Shows removable media (CDs, DVDs and iPods) on desktop"
        "💾 Show mounted servers on desktop|com.apple.finder|ShowMountedServersOnDesktop|true|false||delete|Shows mounted servers on desktop"
        "💾 Show all devices in Disk Utility|com.apple.DiskUtility|SidebarShowAllDevices|true|false||delete|Shows all devices in sidebar of Disk Utility"
        "🚫 Disable new disk requests for Time Machine|com.apple.TimeMachine|DoNotOfferNewDisksForBackup|true|false||delete|Disables new disk requests for Time Machine"
        "🔄 Set Time Machine backup frequency to 'Manually'|/Library/Preferences/com.apple.TimeMachine|AutoBackup|false|true|true|true|Sets Time Machine backup frequency to 'Manually'"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|📁 [Finder]|"
        "🏷️  Show all filename extensions|NSGlobalDomain|AppleShowAllExtensions|true|false|false|delete|Shows file extensions for all files"
        "🛤️  Show Path Bar in Finder|com.apple.finder|ShowPathbar|true|false||delete|Shows the path bar at the bottom of Finder windows"
        "📊 Show Status Bar in Finder|com.apple.finder|ShowStatusBar|true|false||delete|Shows the status bar at the bottom of Finder windows"
        "🗂️  Show Tab Bar in Finder|com.apple.finder|NSWindowTabbingShoudShowTabBarKey-com.apple.finder.TBrowserWindow|true|false|false|delete|Shows the tab bar at the top of Finder windows by default"
        "📚 Show hidden User ~/Library folder by default|com.apple.FinderInfo|ShowLibrary|nohidden|hidden||chflags|Makes the Library folder visible in Finder"
        "🗂️  Always open folders in a new tab|com.apple.finder|FinderSpawnTab|true|false||delete|Always opens folders in new tabs instead of new windows"
        "🏠 Set new Finder windows to show the Desktop folder|com.apple.finder|NewWindowTarget|PfDe|PfAF||delete|Sets new Finder windows to open the Desktop folder"
        # "🏠 Set Desktop folder path for new Finder windows|com.apple.finder|NewWindowTargetPath|file://${HOME}/Desktop/|file://${HOME}/||delete|Sets new Finder windows to open the Desktop folder"
        "📄 Set Default Finder to List View|com.apple.finder|FXPreferredViewStyle|Nlsv|icnv||delete|Sets Finder's default view to List instead of Icon"
        "🔍 Search the current folder when performing a search|com.apple.finder|FXDefaultSearchScope|SCcf|SCev|SCev|delete|Uses the current folder when performing a search"
        "📏 Set Finder/Settings sidebar icons to small instead of medium|NSGlobalDomain|NSTableViewDefaultSizeMode|1|2||delete|Sets Finder/Settings sidebar icons to small instead of medium"
        "📏 Shrink sidebar width to the minimum (1 of 2) ${MA}(Sequoia 15 and below)${NC}|com.apple.finder|SidebarWidth|143|164|164||Shrinks sidebar width to the minimum"        
        "📏 Shrink sidebar width to the minimum (2 of 2) ${MA}(Sequoia 15 and below)${NC}|com.apple.finder|FK_SidebarWidth|143|164|164||Shrinks sidebar width (in other views) to the minimum"        
        "👻 Show hidden files (or toggle them with ⌘ ⇧ .)|com.apple.finder|AppleShowAllFiles|true|false||delete|Shows hidden files. (You can also show them temporarily with ⌘ + ⇧ + .)"
        # "🚫 Don't show 'Recents' in the sidebar|com.apple.finder|PreferencesWindow.LastSelection|SDBR|SDBR|TAGS|TAGS|"
        "🚫 Disable the warning when changing a file extension|com.apple.finder|FXEnableExtensionChangeWarning|false|true||delete|Disables the warning when changing a file extension in the Finder"
        "🚫 Hide Warning before removing from iCloud Drive ${BO}${GY}${GR}(Sonoma 14 and below)${NC}|com.apple.finder|FXEnableRemoveFromICloudDriveWarning|1|0|0|delete|Disables the 'Remove from iCloud Drive' warning."
        "🏷️  Remove the Tags section from Sidebar|com.apple.finder|ShowRecentTags|false|true||delete|Removes the Tags section from Sidebar."
        # "🔍 Set Custom Get Info Pane Layout|com.apple.finder|FXInfoPanesExpanded|'{General=true;Comments=false;MetaData=true;Name=true;OpenWith=true;Preview=false;Privileges=true;}'|{}||defaults_dict|Sets Get Info pane expand/collapse"
        # "🔍 Set Custom Toolbar Items|com.apple.finder|NSToolbar Configuration Browser|'{\"TB Default Item Identifiers\"=(\"com.apple.finder.BACK\",\"com.apple.finder.SWCH\",NSToolbarSpaceItem,\"com.apple.finder.ARNG\",\"com.apple.finder.SHAR\",\"com.apple.finder.LABL\",\"com.apple.finder.ACTN\",NSToolbarSpaceItem,\"com.apple.finder.SRCH\");\"TB Display Mode\"=2;\"TB Icon Size Mode\"=1;\"TB Is Shown\"=1;\"TB Item Identifiers\"=(\"com.apple.finder.BACK\",\"com.apple.finder.loc \",\"com.apple.finder.AirD\",\"com.apple.finder.CNCT\",\"com.apple.finder.NFLD\",\"com.apple.finder.SHAR\",\"com.apple.finder.SWCH\",NSToolbarSpaceItem,\"com.apple.finder.ACTN\",NSToolbarSpaceItem,\"com.apple.finder.SRCH\");\"TB Size Mode\"=1;}'|{}||defaults_dict|Sets Finder toolbar"    
        
        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|📸 [Screencapture, Photo & Video]|"
        "🚫 Disable Screenshot border and shadow|com.apple.screencapture|disable-shadow|true|false||delete|Removes default border and shadow from screenshots"
        "🖼️  Set default Screenshot Format from PNG to JPG|com.apple.screencapture|type|jpg|png||delete|Changes default screenshot format from PNG to JPG"
        "🚫 Disable Screenshot Preview Thumbnails|com.apple.screencapture|show-thumbnail|false|true||delete|Disables screenshot preview thumbnails in order to save immediately"
        "🚫 Disable date and time in filenames|com.apple.screencapture|include-date|false|true|false|false|Disables screenshot preview thumbnails in order to save immediately"
        "🎥 Show Mouse Pointer in Screenshots|com.apple.screencapture|showsCursor|true|false||delete|Shows mouse cursor when screen recording"
        "🎥 Show Mouse Clicks When Screen Recording|com.apple.screencapture|showsClicks|true|false||delete|Shows mouse clicks when screen recording"
        "▶️  Auto-play videos when opened with QuickTime Player|com.apple.QuickTimePlayerX|MGPlayMovieOnOpen|true|false||false|Auto-plays videos when opened with QuickTime Player"
        "🚫 Prevent Photos from opening automatically when devices are plugged in|com.apple.ImageCapture|disableHotPlug|true|false|false|-currentHost|Prevents Photos from opening automatically when devices are plugged in"
        "🗂️  Show Tab Bar by default in QuickTime|com.apple.QuickTimePlayerX|NSWindowTabbingShoudShowTabBarKey-NSWindow-MGDocumentWindowController-MGDocumentWindowController-VT-FS|true|false|false|delete|Shows Tab Bar by default in QuickTime"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🖱️  [Mouse]|"
        "🚫 Disable Natural Scrolling ${BO}(Requires Logging Out)${NC}|NSGlobalDomain|com.apple.swipescrolldirection|false|true||delete|Disables natural scrolling direction"
        "🚀 Increase Mouse Tracking Speed beyond default ${BO}(Requires Restart)${NC}|NSGlobalDomain|com.apple.mouse.scaling|5|3.0||delete|Increases mouse tracking speed beyond default"
        "🖱️  Enable secondary button (on bluetooth multi-touch mice)|com.apple.driver.AppleBluetoothMultitouch.mouse|MouseButtonMode|TwoButton|OneButton||delete|Enables secondary button (on bluetooth multi-touch mice)"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        # "GROUP|💻 [TrackPad - Built-In]|"
        "GROUP|💻 [TrackPad]|"
        "💨 Increase Trackpad Tracking Speed|NSGlobalDomain|com.apple.trackpad.scaling|3|0.5||delete|Increases tracking speed to fastest setting"
        # "⚙️  Enable Tap to click|com.apple.AppleMultitouchTrackpad|Clicking|1|0||delete|Enables 'Tap to click' on built-in Trackpads"
        # "⚙️  Enable Tap to click (in login screen)|NSGlobalDomain|com.apple.mouse.tapBehavior|1|0||-currentHost|Enables 'Tap to click' on built-in Trackpads (in login screen)."
        "⚙️  Enable Tap To Click|NSGlobalDomain|com.apple.mouse.tapBehavior|1|0||-currentHost|Enables 'Tap to click' on Trackpads."
        "⚙️  Enable Two-Finger Tap To Right Click AND Bottom Right Click. ${BO}(Requires Logging Out)${NC}|Various|Various|true|false|delete|Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click|Enables Two-Finger Tap To Right Click AND Bottom Right Click. 📝 ${BO}${GY}Note that System Settings will show only 'Click in Bottom Right Corner' selected, but 'Click or Tap with Two Fingers' is also applied!'${NC}"
        # "⚙️  Enable secondary click|NSGlobalDomain|com.apple.trackpad.enableSecondaryClick|true|false||-currentHost|Enables bottom-right right-click on built-in Trackpads (in login screen)."
        # "⚙️  Enable two-finger tap to right-click|com.apple.AppleMultitouchTrackpad|TrackpadRightClick|true|false||delete|Enable two-finger right-click on built-in Trackpads"
        # "⚙️  Enable corner right-click (disables 'tap to right-click')|NSGlobalDomain|com.apple.trackpad.trackpadCornerClickBehavior|1|0||-currentHost|Enables corner right-click on built-in Trackpads (in login screen)."

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        # "GROUP|💻 [TrackPad - External/Bluetooth|"
        # "⚙️  Enable Tap to click|com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|1|0||delete|Enables 'Tap to click' on bluetooth Trackpads"
        # "⚙️  Enable two-finger tap to right-click|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadRightClick|1|0||delete|Enable two-finger right-click on bluetooth Trackpads"
        # "⚙️  Enable pinch-to-zoom|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadPinch|1|0||delete|Enables pinch-to-zoom on bluetooth Trackpads"
        # "⚙️  Enable corner right-click (disables 'tap to right-click')|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadCornerSecondaryClick|0|1||delete|Enables corner right-click on bluetooth Trackpads (disables tap to right click)"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|⌨️   [Keyboard]|📝 ${YE}Note that the last two require a restart to take effect.${NC}"
        "💨 Speed Up Initial Key Repeat Rate|NSGlobalDomain|KeyRepeat|2|6||delete|Speeds up the repeat of pressed keys"
        "💨 Speed Up Delay Until Key Repeat|NSGlobalDomain|InitialKeyRepeat|15|25||delete|Speeds up the delay until pressed keys are repeated"
        "🚫 Disable auto-capitalization|NSGlobalDomain|NSAutomaticCapitalizationEnabled|false|true|true|delete|Disables automatic capitalization"
        "🚫 Disable auto-correct|NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|false|true||delete|Disables automatic capitalization"
        "🚫 Disable auto-period substitution|NSGlobalDomain|NSAutomaticPeriodSubstitutionEnabled|false|true||delete|Disables automatic period substitution"
        "↔️  Allow tab navigation across UI|NSGlobalDomain|AppleKeyboardUIMode|2|0|2|delete|Enables full keyboard access for all controls"
        "😌 Fn/🌐 key Shows Emoji & Symbols ${BO}(Requires Restart)${NC}|com.apple.HIToolbox|AppleFnUsageType|2|0|0|0|Fn/🌐 key Shows Emoji & Symbols. ${BO}Note that this requires a restart to take effect.${NC}"
        "🚫 Disable accent options when a key is held down ${BO}(Requires Restart)${NC}|NSGlobalDomain|ApplePressAndHoldEnabled|false|true|true|true|Disables accent options when a key is held down. ${BO}Note that this requires a restart to take effect.${NC}"
        # "⌨️  Finder: Custom Shortcuts|com.apple.finder|NSUserKeyEquivalents|'{\"Get Info\"=\"@~i\";\"Show Inspector\"=\"@i\";\"Show Next Tab\"=\"@~\\U2192\";\"Show Previous Tab\"=\"@~\\U2190\";}'|{}||key_equivalents|Sets Finder keyboard shortcuts"
        # "⌨️  Ableton Live: Custom Shortcuts|com.ableton.live|NSUserKeyEquivalents|'{\"Freeze Track\"=\"@~f\";\"Plug-In Windows\"=\"@~w\";\"Record to Arrangement\"=\"@ \";}'|{}||key_equivalents|Sets Live keyboard shortcuts"
        # "⌨️  Preview: Toggle Markup Toolbar|com.apple.Preview|NSUserKeyEquivalents|'{\"Hide Markup Toolbar\"=\"@~m\";\"Show Markup Toolbar\"=\"@~m\";}'|{}||key_equivalents|Sets Preview keyboard shortcuts"
        # "⌨️  Safari: Next/Prev Tab|com.apple.Safari|NSUserKeyEquivalents|'{\"Show Next Tab\"=\"@~\\U2192\";\"Show Previous Tab\"=\"@~\\U2190\";}'|{}||key_equivalents|Sets Safari tab shortcuts"
        # "⌨️  Terminal: Common Shortcuts|com.apple.Terminal|NSUserKeyEquivalents|'{New=\"@t\";\"Show Fonts\"=\"@n\";\"Show Next Tab\"=\"@~\\U2192\";\"Show Previous Tab\"=\"@~\\U2190\";}'|{}||key_equivalents|Sets Terminal shortcuts"
        # "⌨️  Apparency: Next/Prev Tab|com.mothersruin.Apparency|NSUserKeyEquivalents|'{\"Show Next Tab\"=\"@~\\U2192\";\"Show Previous Tab\"=\"@~\\U2190\";}'|{}||key_equivalents|Sets Apparency tab shortcuts"
        # "⌨️  Suspicious Package: Tab Shortcuts|com.mothersruin.SuspiciousPackageApp|NSUserKeyEquivalents|'{\"Next Tab in Package\"=\"@~]\";\"Previous Tab in Package\"=\"@~[\";\"Show Next Tab\"=\"@~\\U2192\";\"Show Previous Tab\"=\"@~\\U2190\";}'|{}||key_equivalents|Sets Suspicious Package shortcuts"
        # "⌨️  TextEdit: Next/Prev Tab|com.apple.TextEdit|NSUserKeyEquivalents|'{\"Show Next Tab\"=\"@~\\U2192\";\"Show Previous Tab\"=\"@~\\U2190\";}'|{}||key_equivalents|Sets TextEdit tab shortcuts"
        # "⌨️  Sononym: Play/Stop|com.sononym.sononym|NSUserKeyEquivalents|'{\"Play Selected File\"=\"\\U2192\";\"Stop Playback/Recording\"=\"\\U2190\";}'|{}||key_equivalents|Sets Sononym shortcuts"
        # "⌨️  UTM: Common Shortcuts|com.utmapp.UTM|NSUserKeyEquivalents|'{\"Hide UTM\"=\"~h\";\"Open...\"=\"~o\";\"Quit UTM\"=\"~q\";}'|{}||key_equivalents|Sets UTM shortcuts"
        # "⌨️  MediaInfo: Close All|net.mediaarea.mediainfo.mac|NSUserKeyEquivalents|'{\"Close All Files\"=\"@~w\";}'|{}||key_equivalents|Sets MediaInfo shortcut"
        # "⌨️  FindAnyFile: Close All|org.tempel.findanyfile|NSUserKeyEquivalents|'{\"Close All Files\"=\"@~w\";}'|{}||key_equivalents|Sets FindAnyFile shortcut"
        
        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|📋 [Menu Bar & Control Center]|${YE}(To prevent clutter, hide all and just use Control Center 👍)${NC}"
        "🖥️  Never Hide Menu Bar In Fullscreen ${MA}(Sequoia 15 and below)${NC}|NSGlobalDomain|AppleMenuBarVisibleInFullscreen|true|false|false|delete|Never hides the menu bar when in full screen;"
        # "🍱 Show Control Center in Menu Bar|com.apple.controlcenter|NSStatusItem Visible BentoBox|true|false|true|delete|Shows Control Center in the menu bar"
        "🛜 Show WiFi in Menu Bar|com.apple.controlcenter|WiFi|2|8|8|-currentHost|Shows WiFi in Menu Bar"
        "🔵 Show Bluetooth in Menu Bar [Always]|com.apple.controlcenter|Bluetooth|2|8|8|-currentHost|Shows Bluetooth control in the menu bar"
        "🌀 Show AirDrop in Menu Bar [Always]|com.apple.controlcenter|AirDrop|2|8|8|-currentHost|Shows AirDrop control in the menu bar"
        "📵 Show Focus in Menu Bar [Always]|com.apple.controlcenter|FocusModes|18|8|2|-currentHost|Shows Focus control in the menu bar"
        "🚀 Show Stage Manager in Menu Bar [Always]|com.apple.controlcenter|StageManager|2|8|8|-currentHost|Shows Now Playing in the menu bar"
        "🖥️  Show Screen Mirroring in Menu Bar [Always]|com.apple.controlcenter|ScreenMirroring|18|8|2|-currentHost|Shows Screen Mirroring control in the menu bar"
        "🖥️  Show Display in Menu Bar [Always]|com.apple.controlcenter|Display|18|8|2|-currentHost|Shows Display control in the menu bar"
        "🔊 Show Sound in Menu Bar [Always]|com.apple.controlcenter|Sound|18|8|2|-currentHost|Shows sound control in the menu bar"
        "🚀 Show Now Playing in Menu Bar [Always]|com.apple.controlcenter|NowPlaying|18|8|2|-currentHost|Shows Now Playing in the menu bar"
        "♿️ Show Accessibility in Menu Bar|com.apple.controlcenter|AccessibilityShortcuts|3|9|9|-currentHost|Shows Now Playing in the menu bar"
        "📣 Show Music Recognition in Menu Bar|com.apple.controlcenter|MusicRecognition|6|12|12|-currentHost|"
        "🦻 Show Hearing in Menu Bar|com.apple.controlcenter|Hearing|2|8|8|-currentHost|"
        "🎤 Show Voice Control in Menu Bar|com.apple.controlcenter|VoiceControl|18|8|8|-currentHost|"
        "👤 Show Fast User Switching in Menu Bar|com.apple.controlcenter|UserSwitcher|2|8|8|-currentHost|"
        "🕒 Always show date in menu bar|com.apple.menuextra.clock|ShowDate|true|false|false|false|Always shows date in menu bar."        
        "🕒 Display the time with seconds|com.apple.menuextra.clock|ShowSeconds|true|false|false|false|Displays the time with seconds in menu bar"
        "🔮 Show Siri in Menu Bar|com.apple.controlcenter|Siri|2|8|8|-currentHost|"
        "⏳ Show Time Machine in Menu Bar|com.apple.systemuiserver|NSStatusItem Visible com.apple.menuextra.TimeMachine|true|false|false|Show_Time_Machine_Menu_Bar_Item|Shows Time Machine in the menu bar"
        "⏳ Show VPN in Menu Bar ${BO}(Must be configured to appear)${NC}|com.apple.systemuiserver|NSStatusItem Visible com.apple.menuextra.vpn|true|false|false|Show_VPN_Menu_Bar_Item|Shows VPN in the menu bar"
        # "🚀 Show Shortcuts in Menu Bar|com.apple.controlcenter|NSStatusItem Visible Shortcuts|true|false|false|delete|Shows Shortcuts control in the menu bar"
        # "🎥 Show FaceTime in Menu Bar|com.apple.controlcenter|NSStatusItem Visible FaceTime|true|false|delete|delete|Shows FaceTime control in the menu bar"
        "🔤 Show Text Input in Menu Bar|com.apple.TextInputMenu|visible|true|false|delete|delete|Shows text input in the Menu Bar"
        "🕹️  Show Remote Management in Menu Bar ${BO}(Must be enabled to appear)${NC}|/Library/Preferences/com.apple.RemoteManagement|LoadRemoteManagementMenuExtra|true|false|false|Remote_Management_Menu_Bar|"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|📋 [Menu Bar & Control Center - For Laptops]|"
        "🔋 Show Battery in Menu Bar|com.apple.controlcenter|Battery|3|9|9|-currentHost|Shows battery in the menu bar"
        "💯 Show Battery Percentage in Menu Bar|com.apple.controlcenter|BatteryShowPercentage|1|0|0|-currentHost|Shows battery percentage in the menu bar"
        "⌨️  Show Keyboard Brightness in Menu Bar|com.apple.controlcenter|KeyboardBrightness|3|9|9|-currentHost|Shows Keyboard Brightness in the menu bar"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|📶 [Connectivity]|"
        "🌐 Enable AirDrop over Ethernet|com.apple.NetworkBrowser|BrowseAllInterfaces|true|false||delete|Enables AirDrop over Ethernet and on unsupported Macs"
        "🚫 Disable AirPlay Receiver|com.apple.controlcenter|AirplayReceiverEnabled|false|true|true|-currentHost|Disables AirPlay Receiver"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|📝 [TextEdit]|"
        "🗂️  Always show tab bar in TextEdit|com.apple.TextEdit|NSWindowTabbingShoudShowTabBarKey-NSWindow-DocumentWindowController-DocumentWindowController-VT-FS|true|false|false|delete|Shows Tab Bar by default in TextEdit"
        "📝 Create a new document by default when opening TextEdit|com.apple.TextEdit|NSShowAppCentricOpenPanelInsteadOfUntitledFile|false|true||delete|Opens new document by default in TextEdit"
        "📝 Use Plain Text Mode for TextEdit|com.apple.TextEdit|RichText|false|true|true|true|Sets TextEdit to use Plain Text instead of Rich Text by default"
        "📂 Expand Default Save Panel in TextEdit (1 of 2)|com.apple.TextEdit|NSNavPanelExpandedStateForSaveMode|true|false|false|false|Expands the save dialog in TextEdit by default"
        "📂 Expand Default Save Panel in TextEdit (2 of 2)|com.apple.TextEdit|NSNavPanelExpandedStateForSaveMode2|true|false|false|false|Expands the save dialog in TextEdit by default"
        "📂 Set Default Save Panel in TextEdit to List View (1 of 2)|com.apple.TextEdit|NSNavPanelFileListModeForSaveMode2|2|3||delete|Sets default save panel in TextEdit to list view"
        "📂 Set Default Save Panel in TextEdit to List View (2 of 2)|com.apple.TextEdit|NSNavPanelFileLastListModeForSaveModeKey|2|3||delete|Sets default save panel in TextEdit to list view"
        "📂 Set Default Font Size in TextEdit to 14|com.apple.TextEdit|NSFixedPitchFontSize|14|11|11|delete|Sets default font size from 11 to 14 in Text Edit."

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|👾 [Terminal]|"
        "🗂️  Always show tab bar in Terminal|com.apple.Terminal|NSWindowTabbingShoudShowTabBarKey-TTWindow-TTWindowController-TTWindowController-VT-FS|true|false|false|delete|Shows Tab Bar by default in Terminal"
        "⭐️ Use bright colors for bold text|com.apple.Terminal|UseBrightBold|true|false|false|delete|Uses bright colors for bold text"
        
        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|📅 [Calendar]|"
        "🕛 Enable TimeZone Support|com.apple.iCal|TimeZone support enabled|true|false|false|false|Enables TimeZone Support"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|💬 [Messages]|"
        "🚫 Disable Send Read Receipts 1 of 2|com.apple.imagent|Setting.EnableReadReceipts|false|true|true|true|Disables Send Read Receipts (1 of 2)"
        "🚫 Disable Send Read Receipts 2 of 2|com.apple.imagent|Setting.GlobalReadReceiptsVersionID|2|1|1|1|Disables Send Read Receipts (2 of 2)"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🔎 [Preview]|"
        "🗂️  Show Tab Bar by default in Preview|com.apple.Preview|NSWindowTabbingShoudShowTabBarKey-PVWindow-PVWindowController-PVWindowController-VT-FS|true|false|false|delete|Shows Tab Bar by default in Preview"
        
        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🎵 [Music]|"
        "🚫 Disable Sound Check/Normalization|com.apple.Music|optimizeSongVolume|false|true|true|true|Disables Sound Check/Normalization"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🗜️  [Archive Utility]|"
        "🗑️  Move archives to trash after expanding|com.apple.archiveutility|dearchive-move-after|~/.Trash|.|.|.|"
        "🗑️  Move files to trash after archiving|com.apple.archiveutility|archive-move-after|~/.Trash|.|.|.|"
        "🚫 Don't reveal archives after expanding|com.apple.archiveutility|dearchive-reveal-after|false|true|true|true|"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|🌐 [Safari - General]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write changes)${NC}"
        "🗂️  Always Show Tab Bar in Safari|com.apple.Safari|AlwaysShowTabBar|1|0||0|"
        "🌐 Show Overlay Status Bar|com.apple.Safari|ShowOverlayStatusBar|true|false||false|"
        "⭐️ Show Favorites Bar|com.apple.Safari|ShowFavoritesBar-v2|true|false||true|"
        "🎞️  Safari opens with all windows from last session|com.apple.Safari|AlwaysRestoreSessionAtLaunch|true|false||false|"
        "🌐 New windows open with Empty Page|com.apple.Safari|NewWindowBehavior|1|4||4|"
        "🌐 New tabs open with Empty Page|com.apple.Safari|NewTabBehavior|1|4||4|"
        "🚫 Disable Auto Open Safe Downloads|com.apple.Safari|AutoOpenSafeDownloads|false|true||false|Disables 'Auto-open safe downloads'"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|[Safari - Tabs]|"
        "🌐 Always show website titles in tabs|com.apple.Safari|EnableNarrowTabs|false|true||true|"
        "🚫 Disable compact tab layout ${MA}(Sequoia 15 and below)${NC}|com.apple.Safari|ShowStandaloneTabBar|true|false||true|"
        "🗂️  Close Tabs Manually|com.apple.Safari|CloseTabsAutomatically|false|true||false|"
        "🗂️  Command + Click Opens New Tab or Window In Background|com.apple.Safari|CommandClickMakesTabs|true|false|true|true|"
        "🗂️  Don't make new tabs or windows active on command + click|com.apple.Safari|OpenNewTabsInFront|false|true|false|false|"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|[Safari - AutoFill]|"
        "🚫 Disable AutoFill Contacts|com.apple.Safari|AutoFillFromAddressBook|false|true|false|false|"
        "🚫 Disable AutoFill Passwords|com.apple.Safari|AutoFillPasswords|false|true|false|false|"        
        "🚫 Disable AutoFill Credit Cards|com.apple.Safari|AutoFillCreditCardData|false|true|false|false|"
        "🚫 Disable AutoFill Other Forms|com.apple.Safari|AutoFillMiscellaneousForms|false|true|false|false|"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|[Safari - Search]|"
        "🔎 Use DuckDuckGo as default search provider in ALL Browsing|com.apple.Safari|SearchProviderShortName|DuckDuckGo|Google||Google|"
        "🔎 Private Search Engine Uses Same Search Engine|com.apple.Safari|PrivateSearchEngineUsesNormalSearchEngineToggle|true|false||true|"
        "🚫 Disable Search Engine Suggestions|com.apple.Safari|SuppressSearchSuggestions|true|false||true|"
        "🚫 Disable Previously Visited Website Suggestions|com.apple.Safari|WebsiteSpecificSearchEnabled|false|true||false|"
        "🚫 Disable Preload Top Hit|com.apple.Safari|PreloadTopHit|false|true||false|"
        "🚫 Disable Favorites Suggestions|com.apple.Safari|ShowFavoritesUnderSmartSearchField|false|true||false|"
        "🔎 Private Search Engine Uses Same Search Engine|com.apple.Safari|PrivateSearchEngineUsesNormalSearchEngineToggle|true|false||true|"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|[Safari - Security]|"
        "🔒 Enable Safe Browsing|com.apple.Safari.SafeBrowsing|SafeBrowsingEnabled|true|false||delete|Enables Safe Browsing."
        "⚠️  Warn About Fraudulent Websites|com.apple.Safari|WarnAboutFraudulentWebsites|true|false||delete|Enables 'Warn About Fraudulent Websites'"
        "🌐 Warn before connecting to a website over HTTP|com.apple.Safari|UseHTTPSOnly|true|false||true|"
        "🕵️‍♂️  Private Browsing Requires Authentication|com.apple.Safari|PrivateBrowsingRequiresAuthentication|true|false||true|"
        "🚫 Disallow Websites To Send Notifications|com.apple.Safari|CanPromptForPushNotifications|false|true||false|"

        # Format: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Command|Type|Description"
        # Or group header: "GROUP|<Title>|<Optional Subtext>"
        "GROUP|[Safari - Advanced]|"
        "🌐 Show Full Website URL In Address Bar|com.apple.Safari|ShowFullURLInSmartSearchField|true|false||true|Shows full website URL in the address bar"
        "🕵️‍♂️  Enable Enhanced Privacy In ALL Browsing|com.apple.Safari|EnableEnhancedPrivacyInRegularBrowsing|true|false||true|"
        "🚫 Disallow Privacy-Preserving Measurment of Ad Effectiveness|com.apple.Safari|WebKitPreferences.privateClickMeasurementEnabled|false|true||false|"
        "🛠  Show Features For Web Developers|com.apple.Safari.SandboxBroker|ShowDevelopMenu|true|false||false|Enables Safari's Developer menu."

    )

    # Helper function to get current preference state
    get_preference_current_state() {
        local domain="$1"
        local key="$2"
        local type="$3"
        local active_val="$4"
        local inactive_val="$5"
        
        if [[ "$type" == "sudo" ]]; then
            echo "unknown"
            return
        fi

        if [[ "$domain" == "launchctl" ]]; then
            echo "unknown"
            return
        fi

        # Complex payload types: treat as custom to avoid brittle deep comparisons
        if [[ "$type" == "key_equivalents" || "$type" == "defaults_dict" || "$type" == "defaults_array" || "$type" == "plistbuddy" ]]; then
            echo "custom"
            return
        fi
        
        local current_value
        if [[ "$type" == "chflags" ]]; then
            if [[ "$key" == "ShowLibrary" ]]; then
                if [[ -d ~/Library ]] && [[ "$(ls -ldO ~/Library | grep hidden)" ]]; then
                    echo "inactive"
                    return
                else
                    echo "active"
                    return
                fi
            fi
            echo "unknown"
            return
        fi 

        # Handle special cases that return large amounts of data
        if [[ "$domain" == "com.apple.dock" && "$key" == "persistent-apps" ]]; then
            local app_count=$(defaults read "$domain" "$key" 2>/dev/null | grep "CFBundleIdentifier" 2>/dev/null | wc -l 2>/dev/null || echo "0")
            app_count=${app_count:-0}  # Ensure it's not empty
            if [[ "$app_count" -gt 0 ]]; then
                echo "custom"
            else
                echo "default"
            fi
            return
        fi

        # Handle trackpad tap to right click
        if [[ "$type" == "Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click" ]]; then
            if [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
               [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick)" == "1" ]] &&
               [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior)" == "1" ]] &&
               [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.enableSecondaryClick)" == "1" ]] &&
               [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
               [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadRightClick)" == "1" ]]; then
                echo "active"
                return
            else
                if [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "0" ]] &&
                   [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick)" == "0" ]] &&
                   [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior)" == "0" ]] &&
                   [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.enableSecondaryClick)" == "0" ]] &&
                   [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick)" == "0" ]] &&
                   [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadRightClick)" == "0" ]]; then
                    echo "inactive"
                    return
                else
                    echo "custom"
                    return
                fi
            fi
        fi

        # Handle Time Machine menu bar item
        if [[ "$type" == "Show_Time_Machine_Menu_Bar_Item" ]]; then
            # Check if TimeMachine is in menuExtras array
            tm_in_array="false"
            if /usr/libexec/PlistBuddy -c "Print :menuExtras" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null | grep -q "TimeMachine"; then
                tm_in_array="true"
            fi
            # Get visibility setting
            tm_visible=$(defaults read com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.TimeMachine" 2>/dev/null || echo "0")
            # Check if both conditions are met for "active" state
            if [[ "$tm_visible" == "1" ]] && [[ "$tm_in_array" == "true" ]]; then
                echo "active"
                return
            else
                if [[ "$tm_visible" == "0" ]] && [[ "$tm_in_array" == "false" ]]; then
                    echo "inactive"
                    return
                else
                    echo "default"
                    return
                fi
            fi
        fi

        # Handle VPN menu bar item
        if [[ "$type" == "Show_VPN_Menu_Bar_Item" ]]; then
            # Check if VPN is in menuExtras array
            tm_in_array="false"
            if /usr/libexec/PlistBuddy -c "Print :menuExtras" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null | grep -q "VPN"; then
                tm_in_array="true"
            fi
            # Get visibility setting
            tm_visible=$(defaults read com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.vpn" 2>/dev/null || echo "0")
            # Check if both conditions are met for "active" state
            if [[ "$tm_visible" == "1" ]] && [[ "$tm_in_array" == "true" ]]; then
                echo "active"
                return
            else
                if [[ "$tm_visible" == "0" ]] && [[ "$tm_in_array" == "false" ]]; then
                    echo "inactive"
                    return
                else
                    echo "custom"
                    return
                fi
            fi
        fi

        if [[ "$type" == "disable_Apple_Intelligence" ]]; then
            # Handle Apple Intelligence - Check current state first
            domain="com.apple.CloudSubscriptionFeatures.optIn"
            
            # Check if any keys are enabled (set to 1)
            enabled_keys=$(defaults read "$domain" 2>/dev/null | grep -E "^\s+[0-9]+ = 1;" | awk '{print $1}')
            disabled_keys=$(defaults read "$domain" 2>/dev/null | grep -E "^\s+[0-9]+ = 0;" | awk '{print $1}')
            
            if [[ -n "$enabled_keys" ]]; then
                echo "inactive"
                return
            elif [[ -n "$disabled_keys" ]]; then
                echo "active" 
                return
            else
                echo "custom"
                return
            fi
        fi    

        current_value=$(defaults read "$domain" "$key" 2>/dev/null || echo "")

        # Handle currentHost type
        if [[ "$type" == *"-currentHost"* ]]; then
            current_value=$(defaults -currentHost read "$domain" "$key" 2>/dev/null || echo "not set")
            if [[ -z "$current_value" ]]; then
                echo "default"
                return
            fi
        fi   

        # if [[ -z "$current_value" ]]; then
        #     echo "default"
        #     return
        # fi

        # Normalize values for comparison (handle 0 vs 0.0, YES/NO vs true/false)
        norm() {
            local v="$1"
            # Uppercase booleans/YES/NO for consistency
            v=$(echo "$v" | tr '[:lower:]' '[:upper:]')
            # Strip surrounding quotes if any
            v=$(echo "$v" | sed 's/^"\(.*\)"$/\1/')
            # If numeric, strip trailing .0s
            if echo "$v" | grep -E '^[0-9]+(\.[0-9]+)?$' >/dev/null 2>&1; then
                echo "$v" | sed 's/\.[0]*$//'
            else
                echo "$v"
            fi
        }

        local n_current=$(norm "$current_value")
        local n_active=$(norm "$active_val")
        local n_inactive=$(norm "$inactive_val")

        if [[ -n "$n_active" ]] || [[ -n "$n_inactive" ]]; then
            if [[ "$n_current" == "$n_active" ]]; then
                echo "active"
                return
            elif [[ "$n_current" == "$n_inactive" ]]; then
                echo "inactive"
                return
            fi
            # Special handling for common boolean synonyms
            if [[ "$n_active" == "TRUE" && ( "$n_current" == "YES" || "$n_current" == "1" ) ]]; then
                echo "active"; return
            fi
            if [[ "$n_inactive" == "FALSE" && ( "$n_current" == "NO" || "$n_current" == "0" ) ]]; then
                echo "inactive"; return
            fi
            if [[ "$n_active" == "FALSE" && ( "$n_current" == "NO" || "$n_current" == "0" ) ]]; then
                echo "active"; return
            fi
            if [[ "$n_inactive" == "TRUE" && ( "$n_current" == "YES" || "$n_current" == "1" ) ]]; then
                echo "inactive"; return
            fi
            echo "custom"
            return
        fi

        # Fallback generic mapping if no active/inactive values provided
        if [[ "$n_current" == "TRUE" || "$n_current" == "YES" || "$n_current" == "1" ]]; then
            echo "active"
        elif [[ "$n_current" == "FALSE" || "$n_current" == "NO" || "$n_current" == "0" ]]; then
            echo "inactive"
        else
            echo "custom"
        fi
    }

    # Helper function to get current preference value
    get_preference_current_value() {
        local domain="$1"
        local key="$2"
        local type="$3"
        
        if [[ "$type" == "sudo" ]]; then
            echo "sudo command - cannot read current value"
            return
        fi
        
        if [[ "$type" == "chflags" ]]; then
            if [[ "$key" == "ShowLibrary" ]]; then
                if [[ -d ~/Library ]] && [[ "$(ls -la ~/ | grep Library | grep hidden)" ]]; then
                    echo "hidden"
                    return
                else
                    echo "visible"
                    return
                fi
            fi
            echo "unknown"
            return
        fi

        # Complex payload types: don't try to print giant dicts/arrays; indicate custom
        if [[ "$type" == "key_equivalents" || "$type" == "defaults_dict" || "$type" == "defaults_array" || "$type" == "plistbuddy" ]]; then
            echo "custom"
            return
        fi

        # Handle trackpad tap to right click
        if [[ "$type" == "Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click" ]]; then
            if [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
               [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick)" == "1" ]] &&
               [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior)" == "1" ]] &&
               [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.enableSecondaryClick)" == "1" ]] &&
               [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
               [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadRightClick)" == "1" ]]; then
                echo "true"
                return
            else
                if [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "0" ]] &&
                   [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick)" == "0" ]] &&
                   [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior)" == "0" ]] &&
                   [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.enableSecondaryClick)" == "0" ]] &&
                   [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick)" == "0" ]] &&
                   [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadRightClick)" == "0" ]]; then
                    echo "false"
                    return
                else
                    echo "custom"
                    return
                fi
            fi
        fi
        # Handle Time Machine menu bar item
        if [[ "$type" == "Show_Time_Machine_Menu_Bar_Item" ]]; then
            # Check if TimeMachine is in menuExtras array
            tm_in_array="false"
            if /usr/libexec/PlistBuddy -c "Print :menuExtras" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null | grep -q "TimeMachine"; then
                tm_in_array="true"
            fi
            # Get visibility setting
            tm_visible=$(defaults read com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.TimeMachine" 2>/dev/null || echo "0")
            # Check if both conditions are met for "active" state
            if [[ "$tm_visible" == "1" ]] && [[ "$tm_in_array" == "true" ]]; then
                echo "true"
                return
            else
                if [[ "$tm_visible" == "0" ]] && [[ "$tm_in_array" == "false" ]]; then
                    echo "false"
                    return
                else
                    echo "custom"
                    return
                fi
            fi
        fi
        # Handle VPN menu bar item
        if [[ "$type" == "Show_VPN_Menu_Bar_Item" ]]; then
            # Check if VPN is in menuExtras array
            tm_in_array="false"
            if /usr/libexec/PlistBuddy -c "Print :menuExtras" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null | grep -q "VPN"; then
                tm_in_array="true"
            fi
            # Get visibility setting
            tm_visible=$(defaults read com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.vpn" 2>/dev/null || echo "0")
            # Check if both conditions are met for "active" state
            if [[ "$tm_visible" == "1" ]] && [[ "$tm_in_array" == "true" ]]; then
                echo "true"
                return
            else
                if [[ "$tm_visible" == "0" ]] && [[ "$tm_in_array" == "false" ]]; then
                    echo "false"
                    return
                else
                    echo "custom"
                    return
                fi
            fi
        fi

        if [[ "$type" == "disable_Apple_Intelligence" ]]; then
            # Handle Apple Intelligence - Check current state first
            domain="com.apple.CloudSubscriptionFeatures.optIn"
            
            # Check if any keys are enabled (set to 1)
            enabled_keys=$(defaults read "$domain" 2>/dev/null | grep -E "^\s+[0-9]+ = 1;" | awk '{print $1}')
            disabled_keys=$(defaults read "$domain" 2>/dev/null | grep -E "^\s+[0-9]+ = 0;" | awk '{print $1}')
            
            if [[ -n "$enabled_keys" ]]; then
                echo "true"
                return
            elif [[ -n "$disabled_keys" ]]; then
                echo "false" 
                return
            else
                echo "custom"
                return
            fi
        fi 

        # Handle currentHost type
        if [[ "$type" == *"-currentHost"* ]]; then
            local current_value=$(defaults -currentHost read "$domain" "$key" 2>/dev/null || echo "not set")
            # Limit output length for very long values
            if [[ ${#current_value} -gt 50 ]]; then
                echo "${current_value:0:47}..."
            else
                echo "$current_value"
            fi
            return
        fi
        
        # Handle special cases that return large amounts of data
        if [[ "$domain" == "com.apple.dock" && "$key" == "persistent-apps" ]]; then
            local app_count=$(defaults read "$domain" "$key" 2>/dev/null | grep "CFBundleIdentifier" 2>/dev/null | wc -l 2>/dev/null || echo "0")
            app_count=${app_count:-0}  # Ensure it's not empty
            if [[ "$app_count" -gt 0 ]]; then
                echo "$app_count app(s) in Dock"
            else
                echo "no apps in Dock"
            fi
            return
        fi
        
        if [[ "$domain" == "launchctl" ]]; then
            echo "launchctl command - cannot read current value"
            return
        fi
        
        local current_value=$(defaults read "$domain" "$key" 2>/dev/null || echo "not set")
        
        # Limit output length for very long values
        if [[ ${#current_value} -gt 50 ]]; then
            echo "${current_value:0:47}..."
        else
            echo "$current_value"
        fi
    }

    # Helper: write defaults with correct type based on value (bash 3.2 compatible)
    write_defaults_typed() {
        local domain="$1"
        local key="$2"
        local value="$3"
        local type="$4"

        # Determine if we need -currentHost flag
        local host_flag=""
        if [[ "$type" == *"-currentHost"* ]]; then
            host_flag="-currentHost"
        fi

        # Normalize for checks
        local upper=$(echo "$value" | tr '[:lower:]' '[:upper:]')

        # Empty array sentinel
        if [[ "$value" == "-array" ]]; then
            defaults $host_flag write "$domain" "$key" -array
            return
        fi

        # Boolean synonyms
        if [[ "$upper" == "TRUE" || "$upper" == "YES" ]]; then
            defaults $host_flag write "$domain" "$key" -bool true
            return
        fi
        if [[ "$upper" == "FALSE" || "$upper" == "NO" ]]; then
            defaults $host_flag write "$domain" "$key" -bool false
            return
        fi

        # Numeric detection (float before int)
        if echo "$value" | grep -E '^[0-9]+\.[0-9]+$' >/dev/null 2>&1; then
            defaults $host_flag write "$domain" "$key" -float "$value"
            return
        fi
        if echo "$value" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
            defaults $host_flag write "$domain" "$key" -int "$value"
            return
        fi

        # Fallback: string
        defaults $host_flag write "$domain" "$key" -string "$value"
    }

    # Helper function to apply preference change
    apply_preference_change() {
        local domain="$1"
        local key="$2"
        local value="$3"
        local type="$4"
        local action="$5"
        
        echo
        # echo "${YE}Applying $action for $key...${NC}"
        echo "${YE}Applying changes...${NC}"  

        # Handles type cases
        case "$type" in
            "delete")
                # For delete type, we need to handle active/inactive differently
                # Active/inactive should use defaults write, only reset should use defaults delete
                if [[ "$action" == "active" || "$action" == "inactive" ]]; then
                    # Use the provided value for active/inactive with proper typing
                    write_defaults_typed "$domain" "$key" "$value"
                else
                    # Use delete for reset to default
                    defaults delete "$domain" "$key" 2>/dev/null || true
                fi
                sleep 1
                ;;
            "key_equivalents")
                # Write a full NSUserKeyEquivalents dictionary blob as-is
                # Expect value to be a valid plist-style dict string: '{"Menu Item"="@~i"; ... }'
                defaults write "$domain" "$key" "$value"
                sleep 1
                ;;
            "defaults_dict")
                # Write complex dict payloads (e.g., Finder panes/toolbar)
                defaults write "$domain" "$key" "$value"
                sleep 1
                ;;
            "defaults_array")
                # Write an array payload. Allow multiple dict items passed in value.
                # If value already contains properly quoted items, use eval to expand them.
                eval "defaults write \"$domain\" \"$key\" -array $value"
                sleep 1
                ;;
            "plistbuddy")
                # Run one or more PlistBuddy commands against a plist path in domain
                # Commands are separated by '||' in value
                echo "$value" | sed 's/||/\n/g' | while IFS= read -r __cmd; do
                    if [[ -n "$__cmd" ]]; then
                        /usr/libexec/PlistBuddy -c "$__cmd" "$domain" 2>/dev/null || true
                    fi
                done
                # Refresh Finder to reflect Finder plist changes
                killall Finder 2>/dev/null || true
                sleep 1
                ;;
            *"-currentHost"*)
                # Handle currentHost types
                if [[ "$action" == "reset" ]]; then
                    # Use delete with -currentHost flag for reset
                    defaults -currentHost delete "$domain" "$key" 2>/dev/null || true
                else
                    # Use write with proper typing for active/inactive
                    write_defaults_typed "$domain" "$key" "$value" "$type"
                fi
                sleep 1
                ;;
            "darkmode")
                if [[ "$action" == "active" ]]; then
                    defaults write NSGlobalDomain AppleIconAppearanceTheme RegularDark 2>/dev/null || true
                    sleep 1
                    killall Finder 2>/dev/null || true
                    killall Dock 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults delete NSGlobalDomain AppleIconAppearanceTheme 2>/dev/null || true
                    sleep 1
                    killall Finder 2>/dev/null || true
                    killall Dock 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                fi
                ;;
            "NevaHideMenuBarinTahoe")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.controlcenter AutoHideMenuBarOption -int 3 2>/dev/null || true
                    defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true 2>/dev/null || true
                    sleep 1
                    killall ControlCenter 2>/dev/null || true
                    # killall Finder 2>/dev/null || true
                    # killall Dock 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.controlcenter AutoHideMenuBarOption -int 2 2>/dev/null || true
                    defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false 2>/dev/null || true
                    sleep 1
                    killall ControlCenter 2>/dev/null || true
                    # killall Finder 2>/dev/null || true
                    # killall Dock 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                fi
                ;;
            "Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click")
                # Handle trackpad tap to right click
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
                    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
                    defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 1
                    defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true
                    defaults write com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick -int 2
                    defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
                    echo "👤 ${BO}Note: Please log out for this to take effect.${NC}"
                else
                    if [[ "$action" == "inactive" ]]; then
                        defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 0
                        defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool false
                        defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 0
                        defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool false
                        defaults write com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick -int 0
                        defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool false
                        echo "👤 ${BO}Note: Please log out for this to take effect.${NC}"
                    fi
                fi
                sleep 1
                ;;
            "Show_Time_Machine_Menu_Bar_Item")
                # Handle Time Machine Menu Bar item
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.TimeMachine" -bool true

                    # Check if TimeMachine is already in menuExtras before adding
                    if ! /usr/libexec/PlistBuddy -c "Print :menuExtras" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null | grep -q "TimeMachine"; then
                        /usr/libexec/PlistBuddy -c "Add :menuExtras: string '/System/Library/CoreServices/Menu Extras/TimeMachine.menu'" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                    fi 
                else [[ "$action" == "inactive" ]]
                    defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.TimeMachine" -bool false
                    
                    # Find and remove TimeMachine from menuExtras array
                    for i in {0..10}; do
                        item=$(/usr/libexec/PlistBuddy -c "Print :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null)
                        if [[ $item == *"TimeMachine"* ]]; then
                            /usr/libexec/PlistBuddy -c "Delete :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                            break
                        fi
                    done
                fi
                sleep 1
                ;;
            "PasswordManager")
                # Handle Password Menu Bar item
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.Passwords EnableMenuBarExtra -bool true
                    defaults write com.apple.Passwords.MenuBarExtra "NSStatusItem Visible Item-0" -bool true
                else [[ "$action" == "inactive" ]]
                    defaults write com.apple.Passwords EnableMenuBarExtra -bool false
                    defaults write com.apple.Passwords.MenuBarExtra "NSStatusItem Visible Item-0" -bool false
                fi
                sleep 1
                ;;
            "Show_VPN_Menu_Bar_Item")
                # Handle VPN Menu Bar item
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.vpn" -bool true
                    # Check if VPN is already in menuExtras before adding
                    # if ! /usr/libexec/PlistBuddy -c "Print :menuExtras" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null | grep -q "VPN"; then
                    #     /usr/libexec/PlistBuddy -c "Add :menuExtras: string '/System/Library/CoreServices/Menu Extras/VPN.menu'" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                    # fi
                    /usr/libexec/PlistBuddy -c "Add :menuExtras: string '/System/Library/CoreServices/Menu Extras/VPN.menu'" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                else [[ "$action" == "inactive" ]]
                    defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.vpn" -bool false
                    
                    # Find and remove VPN from menuExtras array
                    # for i in {0..10}; do
                    #     item=$(/usr/libexec/PlistBuddy -c "Print :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null)
                    #     if [[ $item == *"VPN"* ]]; then
                    #         /usr/libexec/PlistBuddy -c "Delete :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                    #         break
                    #     fi
                    # done
                    /usr/libexec/PlistBuddy -c "Delete :menuExtras: string '/System/Library/CoreServices/Menu Extras/VPN.menu'" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                fi
                sleep 1
                ;;
            "disable_Apple_Intelligence")
                # Handle Apple Intelligence
                if [[ "$action" == "active" ]]; then
                    for key in $(defaults read com.apple.CloudSubscriptionFeatures.optIn 2>/dev/null | grep -E "^\s+[0-9]+ = 1;" | awk '{print $1}'); do
                        defaults write com.apple.CloudSubscriptionFeatures.optIn "$key" -bool false
                    done
                else [[ "$action" == "inactive" ]]
                    for key in $(defaults read com.apple.CloudSubscriptionFeatures.optIn 2>/dev/null | grep -E "^\s+[0-9]+ = 0;" | awk '{print $1}'); do
                        defaults write com.apple.CloudSubscriptionFeatures.optIn "$key" -bool true
                    done
                fi
                sleep 1
                ;;
            "Remote_Management_Menu_Bar")
                # Handle Remote Management Menu Bar
                if [[ "$action" == "active" ]]; then
                    # Only show warning if sudo credentials aren't cached
                    if ! sudo -n true 2>/dev/null; then
                        echo "📝 This requires sudo privileges. Please type your admin password, then press enter."
                    fi
                    sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist LoadRemoteManagementMenuExtra -bool true
                else
                    if [[ "$action" == "inactive" ]]; then
                        # Only show warning if sudo credentials aren't cached
                        if ! sudo -n true 2>/dev/null; then
                            echo "📝 This requires sudo privileges. Please type your admin password then press enter."
                        fi
                        sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist LoadRemoteManagementMenuExtra -bool false
                    fi
                fi
                sleep 1
                ;;
            "chflags")
                if [[ "$key" == "ShowLibrary" ]]; then
                    if [[ "$action" == "active" ]]; then
                        chflags nohidden ~/Library 2>/dev/null || true
                        xattr -d com.apple.FinderInfo ~/Library 2>/dev/null || true
                    else
                        chflags hidden ~/Library 2>/dev/null || true
                    fi
                fi
                sleep 1
                ;;
            "sudo")
                if [[ "$key" == "schedule" ]]; then
                    if [[ "$action" == "active" ]]; then
                        sudo softwareupdate --schedule on
                    else
                        sudo softwareupdate --schedule off
                    fi
                else
                    if [[ "$type" == "SoftwareUpdates" ]]; then
                        sudo defaults write "$domain" "$key" "$value"
                    fi
                fi
                ;;
            "launchctl")
                # No defaults write; handled in restart block
                sleep 1
                ;;
            *)
                write_defaults_typed "$domain" "$key" "$value" "$type"
                sleep 1
                ;;
        esac
        
        # Restart affected services
        case "$domain" in
            "com.apple.dock")
                killall Dock 2>/dev/null || true
                echo "${YE}Restarted Dock...${NC}"
                ;;
            "com.apple.finder")
                killall Finder 2>/dev/null || true
                echo "${YE}Restarted Finder...${NC}"
                ;;
            "com.apple.screencapture")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                ;;
            "com.apple.controlcenter")
                killall SystemUIServer 2>/dev/null || true
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter & SystemUIServer...${NC}"
                ;;
            "com.apple.menuextra.clock")
                killall SystemUIServer 2>/dev/null || true
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter & SystemUIServer...${NC}"
                ;;
            "com.apple.systemuiserver")
                # killall ControlCenter 2>/dev/null || true
                killall SystemUIServer 2>/dev/null || true
                ;;
            "com.apple.universalcontrol")
                killall SystemUIServer 2>/dev/null || true
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter & SystemUIServer...${NC}"
                ;;
            "com.apple.universalaccess")
                killall UniversalAccessApp 2>/dev/null || true
                # killall UniversalAccessAuthWarning 2>/dev/null || true
                # killall "System Preferences" 2>/dev/null
                echo "${YE}Restarted UniversalAccess...${NC}"
                ;;
            "NSGlobalDomain")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                ;;
            "launchctl")
                if [[ "$action" == "active" ]]; then
                    launchctl load -w "$key" 2>/dev/null || true
                else
                    launchctl unload -w "$key" 2>/dev/null || true
                fi
                ;;
        esac
        
        # echo "${GR}✅ $action completed successfully!${NC}"
        # echo "${GR}✅ Done!${NC}"        
        sleep 0.5
    }

    # Helper function to reset preference to default
    reset_preference_to_default() {
        local domain="$1"
        local key="$2"
        local reset_cmd="$3"
        local type="$4"
        
        echo
        # echo "${YE}Resetting $key to default...${NC}"
        echo "${YE}Applying changes...${NC}"  
        
        # Handles type cases
        case "$type" in
            "delete")
                defaults delete "$domain" "$key" 2>/dev/null || true
                ;;
            "chflags")
                if [[ "$key" == "ShowLibrary" ]]; then
                    chflags hidden ~/Library 2>/dev/null || true
                fi
                ;;
            *"-currentHost"*)
                # Handle currentHost types
                if [[ "$action" == "reset" ]]; then
                    # Use delete with -currentHost flag for reset
                    defaults -currentHost delete "$domain" "$key" 2>/dev/null || true
                else
                    # Use write with proper typing for active/inactive
                    write_defaults_typed "$domain" "$key" "$value" "$type"
                fi
                ;;
            "darkmode")
                defaults delete NSGlobalDomain AppleIconAppearanceTheme 2>/dev/null || true
                sleep 1
                killall Finder 2>/dev/null || true
                killall Dock 2>/dev/null || true
                killall SystemUIServer 2>/dev/null || true
                ;;
            "Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click")
                # Handle trackpad tap to right click
                if [[ "$action" == "reset" ]]; then
                    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 0
                    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool false
                    defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 0
                    defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool false
                    defaults write com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick -int 0
                    defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool false
                    echo "👤 ${BO}Note: Please log out for this to take effect.${NC}"
                else
                    echo "⚠️  ${BO}Could not reset to default: Two-Finger Tap To Right Click/Bottom Right Click.${NC}"
                fi
                ;;
            "Show_Time_Machine_Menu_Bar_Item")
                # Handle VPN Menu Bar item
                # if [[ "$key" == "Show_VPN_Menu_Bar_Item" ]]; then
                defaults delete com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.TimeMachine" 2>/dev/null
                
                # Find and remove VPN from menuExtras array
                # for i in {0..10}; do
                #     item=$(/usr/libexec/PlistBuddy -c "Print :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null)
                #     if [[ $item == *"VPN"* ]]; then
                #         /usr/libexec/PlistBuddy -c "Delete :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                #         break
                #     fi
                # done
                /usr/libexec/PlistBuddy -c "Delete :menuExtras: string '/System/Library/CoreServices/Menu Extras/TimeMachine.menu'" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null  
                # else
                #     echo "⚠️ ${BO}Could not reset to default: VPN Menu Bar item.${NC}"
                # fi
                ;;
            "Show_VPN_Menu_Bar_Item")
                # Handle VPN Menu Bar item
                # if [[ "$key" == "Show_VPN_Menu_Bar_Item" ]]; then
                defaults delete com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.vpn" 2>/dev/null
                
                # Find and remove VPN from menuExtras array
                # for i in {0..10}; do
                #     item=$(/usr/libexec/PlistBuddy -c "Print :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null)
                #     if [[ $item == *"VPN"* ]]; then
                #         /usr/libexec/PlistBuddy -c "Delete :menuExtras:$i" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                #         break
                #     fi
                # done
                /usr/libexec/PlistBuddy -c "Delete :menuExtras: string '/System/Library/CoreServices/Menu Extras/VPN.menu'" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                    
                # else
                #     echo "⚠️ ${BO}Could not reset to default: VPN Menu Bar item.${NC}"
                # fi
                ;;
            "Remote_Management_Menu_Bar")
                # Handle Remote Management Menu Bar
                if [[ "$action" == "reset" ]]; then
                    # Only show warning if sudo credentials aren't cached
                    if ! sudo -n true 2>/dev/null; then
                        echo "📝 This requires sudo privileges. Please type your admin password, then press enter."
                    fi
                    sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist LoadRemoteManagementMenuExtra -bool false
                else
                    echo "⚠️ ${BO}Could not reset Remote Management Menu Bar icon.${NC}"
                fi
                ;;
            "sudo")
                if [[ "$key" == "schedule" ]]; then
                    sudo softwareupdate --schedule on
                fi
                ;;
        esac
        
        # Restart affected services
        case "$domain" in
            "com.apple.dock")
                killall Dock 2>/dev/null || true
                echo "${YE}Restarted Dock...${NC}"
                ;;
            "com.apple.finder")
                killall Finder 2>/dev/null || true
                echo "${YE}Restarted Finder...${NC}"
                ;;
            "com.apple.screencapture")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                ;;
            "com.apple.controlcenter")
                killall SystemUIServer 2>/dev/null || true
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter & SystemUIServer...${NC}"
                ;;
            "com.apple.menuextra.clock")
                killall SystemUIServer 2>/dev/null || true
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter & SystemUIServer...${NC}"
                ;;
            "com.apple.systemuiserver")
                # killall ControlCenter 2>/dev/null || true
                killall SystemUIServer 2>/dev/null || true
                ;;
            "com.apple.universalcontrol")
                killall SystemUIServer 2>/dev/null || true
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter & SystemUIServer...${NC}"
                ;;
            "com.apple.universalaccess")
                killall UniversalAccessApp 2>/dev/null || true
                # killall UniversalAccessAuthWarning 2>/dev/null || true
                # killall "System Preferences" 2>/dev/null
                echo "${YE}Restarted UniversalAccess...${NC}"
                ;;
            "NSGlobalDomain")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                ;;
        esac
        
        # echo "${GR}✅ Reset back to default${NC}"
        sleep 2
    }
        
    # Show Info (Loop 1)
    while true; do
        clear
        # echo "Show Info (Loop 1)"
        # sleep 1
        echo "${GR}========================${NC}"
        echo "${BO}14) ⚙️  MacOS Preferences${NC}"
        echo "${GR}========================${NC}"
        echo "↩️  Main Menu"
        show_navigation_prompt # already padded
        # Warning about Terminal.app access request (show only once per session)
        if [[ -z "$TERMINAL_ACCESS_WARNING_SHOWN" ]]; then
            echo "--------------------------------------------------------------------------------"
            echo "ℹ️  ${BO}About:${NC}"
            echo "This sub-menu allows you to change over 180+ macOS preferences as well as"
            echo "show their active/inactive status."
            echo
            echo "Ex. ✅ ${GR}[Active]${NC} | ❌ ${RE}[Inactive]${NC} | ❔ ${BO}${GY}[Default/Not Set]${NC}"
            echo
            echo "If a status shows '"${BO}${GY}[Default/Not Set]${NC}"', this will usually change after"
            echo "applying 1 of the following 3 available options:"
            echo
            echo "1) ${GR}✅ Activate${NC} 2) ${RE}❌ Deactivate${NC} 3) ${BO}${GY}🔄 Reset to Default${NC} ${YE}<- (If available)${NC}"
            echo "--------------------------------------------------------------------------------"
            echo "📝 ${BO}Instructions:${NC}"
            echo "Step 1. ${GR}Press Enter at this first step to generate the list of preferences.${NC}" # (this page wont show again until the script is quit.)
            echo "Step 2. ${GR}Once the preferences load, press Enter to 'cache' the results,${NC}"
            echo "        (allowing them to load faster at next step)"
            echo "Step 3. ${GR}Choose from one of the preferences by typing their number, then press${NC}"
            echo "        ${GR}Enter to view more details.${NC}"
            echo "Step 4. ${GR}Review and choose an option. ${NC}(status's here will refresh automatically)"
            echo "Step 5. ${GR}Press b once to go back to Step 3, or again to refresh list at Step 2.${NC}"
            echo
            echo "Some changes may require logging out or restarting to take effect."
            echo "(You'll be prompted if this is the case)"
            echo
            echo "${BO}For best results, please quit all other open applications.${NC}"
            echo "--------------------------------------------------------------------------------"
            echo "⚠️  ${YE}Note:${NC}"
            echo "${YE}Terminal may request access to other apps to check current preference states.${NC}"
            echo "${BO}${GY}This is required to display the current status of these macOS preferences:${NC}"
            echo "- ${BO}TextEdit${NC}"
            echo "- ${BO}Preview${NC}"
            echo "- ${BO}QuickTime${NC}"
            echo
            echo "${YE}Additionally, Terminal requires${NC} ${BO}Full Disk Access${NC} ${YE}to read/write preferences for:${NC}"
            echo "- ${BO}Safari"
            echo "- ${BO}Accessibility${NC}"
            echo "--------------------------------------------------------------------------------"
            # show_navigation_prompt # already padded
            # echo "${GR}Press Enter to continue (or ${BL}navigation${NC} ${GR}choice)${NC}: "
            # read -rp "" input
            echo
            read -rp "1. ${GR}Press Enter to continue (or ${BL}navigation${NC} ${GR}choice)${NC}: " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then 
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                break 1
            fi
            #TERMINAL_ACCESS_WARNING_SHOWN="true"
        fi
        
        # Display all preferences with current state (Loop 2)
        while true; do
            set_terminal_width_to_1120p
            clear
            # echo "Display all preferences with current state (Loop 2)"
            # sleep 1
            echo "${GR}========================${NC}"
            echo "${BO}14) ⚙️  MacOS Preferences${NC}  ${CY}Legend: ✅ ${GR}Active${NC} | ❌ ${RE}Inactive${NC} | ❔ ${BO}${GY}Default/Not Set${NC}"
            echo "${GR}========================${NC}"
            show_navigation_prompt # already padded

            # Display all preferences with current state
            echo "${GR}Available preferences:${NC}"
            local i=1
            local visible_indices=()
            local preference_states=()  # Cache the states for fast mode
            local idx
            local current_group=""


            for idx in "${!preference_commands[@]}"; do
                local pref="${preference_commands[$idx]}"
                # Handle group headers (format: GROUP|Title|Subtext)
                if [[ "$pref" == GROUP\|* ]]; then
                    IFS='|' read -r _ group_title group_subtext <<< "$pref"
                    current_group="$group_title"   # <- track group
                    echo
                    # echo "${BO}$group_title${NC}"
                    if [[ -n "$group_subtext" ]]; then
                        echo "${BO}$group_title${NC}  $group_subtext"
                    else
                        echo "${BO}$group_title${NC}"
                    fi
                    continue
                fi

                IFS='|' read -r name domain key active_val inactive_val reset_cmd type desc <<< "$pref"

                # Get FRESH state (this is the slow part)
                local current_state=$(get_preference_current_state "$domain" "$key" "$type" "$active_val" "$inactive_val")
                preference_states[$((i-1))]="$current_state"  # Cache it

                local status_icon="❔ ${BO}${GY}[Default/Not Set]${NC}"
                if [[ "$current_state" == "active" ]]; then
                    status_icon="✅ ${GR}[Active]${NC}"
                elif [[ "$current_state" == "inactive" ]]; then
                    status_icon="❌ ${RE}[Inactive]${NC}"
                fi

                printf "%2d) %s %s\n" "$i" "$name" "$status_icon"
                visible_indices[$((i-1))]="$idx"
                visible_groups[$((i-1))]="$current_group"   # store group title
                ((i++))
            done

            show_navigation_prompt # already padded
            # echo "${GR}Available preferences:${NC} ${CY}(using cached states)${NC}"
            echo -e "2. ${GR}Press Enter to first cache results (or ${BL}navigation${NC} ${GR}choice)${NC}:"
            echo -e "   ${BO}${GY}This allows for faster loading time at the next step.${NC}"
            echo -e "   ${BO}${GY}Come back here to refresh at any time by pressing 'b'.${NC}"
            read -rp "" choice
            # Check for navigation input first
            handle_navigation_input "$choice"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                set_terminal_width_to_760p
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                set_terminal_width_to_760p
                break 1 # Exit this while loop, back to main 
            fi

            # Fast Mode (Loop 3) - Uses cached states
            while true; do
                clear
                # echo "Fast Mode (Loop 3) - Uses cached states"
                # sleep 1
                echo "${GR}========================${NC}"
                echo "${BO}14) ⚙️  MacOS Preferences${NC}  ${CY}Legend: ✅ ${GR}Active${NC} | ❌ ${RE}Inactive${NC} | ❔ ${BO}${GY}Default/Not Set${NC} ${RE}[Cached]${NC}"
                echo "${GR}========================${NC}"
                show_navigation_prompt # already padded
                
                # Display all preferences using CACHED states (FAST)
                echo "${GR}Available preferences:${NC} ⚠️  ${RE}(displaying cached results)${NC} ${BO}[Press${NC} ${GR}B ${NC}${BO}to refresh]${NC}"
                local display_i=1
                local current_group=""
                
                for idx in "${!preference_commands[@]}"; do
                    local pref="${preference_commands[$idx]}"
                    if [[ "$pref" == GROUP\|* ]]; then
                        IFS='|' read -r _ group_title group_subtext <<< "$pref"
                        current_group="$group_title"
                        echo
                        if [[ -n "$group_subtext" ]]; then
                            echo "${BO}$group_title${NC} 🔒 ${RE}[Cached]${NC} $group_subtext"
                        else
                            echo "${BO}$group_title${NC} 🔒 ${RE}[Cached]${NC}"
                        fi
                        continue
                    fi
                    
                    IFS='|' read -r name domain key active_val inactive_val reset_cmd type desc <<< "$pref"
                    
                    # Use CACHED state (no fresh calls)
                    local cached_state="${preference_states[$((display_i-1))]}"
                    local status_icon="❔ ${BO}${GY}[Default/Not Set]${NC}"
                    if [[ "$cached_state" == "active" ]]; then
                        status_icon="✅ ${GR}[Active]${NC}"
                    elif [[ "$cached_state" == "inactive" ]]; then
                        status_icon="❌ ${RE}[Inactive]${NC}"
                    fi
                    
                    printf "%2d) %s %s\n" "$display_i" "$name" "$status_icon"
                    ((display_i++))
                done

                # echo " Main Choice Selection (Loop 4)"
                # sleep 1
                local max_choice=${#visible_indices[@]}
                echo
                echo -e "🔒 ${RE}Displaying cached results${NC} ${BO}[Press${NC} ${GR}B ${NC}${BO}to refresh]${NC}"
                echo -e "   ${BO}${GY}(Updated statuses will always be shown in the next (or previous) step).${NC}"
                show_navigation_prompt # already padded
                echo -e "3. ${GR}Select a preference${NC} (1-$max_choice) ${GR}(or ${BL}navigation${NC} ${GR}choice)${NC}: "
                read -rp "" choice

                # Check for navigation input first
                handle_navigation_input "$choice"
                nav=$?
                if [[ $nav -eq $NAV_QUIT ]]; then
                    set_terminal_width_to_760p
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    break
                fi

                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $max_choice ]]; then
                    local arr_idx="${visible_indices[$((choice-1))]}"
                    local current_group="${visible_groups[$((choice-1))]}"   # <- grab group here
                    local selected_pref="${preference_commands[$arr_idx]}"
                    IFS='|' read -r name domain key active_val inactive_val reset_cmd type desc <<< "$selected_pref"
                else
                    echo "❌ ${RE}Invalid option. Please choose 1-$max_choice.${NC}"
                    sleep 1
                    continue
                fi

                # Show Individual Preference States/Options (Loop 5)
                while true; do
                    clear
                    # echo " Main Choice Selection (Loop 5)"
                    # sleep 1
                    echo "${GR}================================================================================${NC}"
                    echo "${BO}$current_group${NC}"
                    # printf "%+3s %s\n" "${BO}$current_group${NC}"
                    # echo "${NC}Choice: $choice) $name${NC}"
                    # printf "Choice: %-3s %s\n" "$choice)" "$name"
                    # printf "%-3s %s\n" "$choice)" "$name"
                    printf "%-3s %s\n" "$choice)" "$name"
                    # echo "$choice) $name"
                    echo "${GR}================================================================================${NC}"
                    echo "${CY}Description:${NC} $desc"
                    echo
                    
                    # Show current state
                    local current_state=$(get_preference_current_state "$domain" "$key" "$type" "$active_val" "$inactive_val")
                    local current_value=$(get_preference_current_value "$domain" "$key" "$type")
                    echo "${BO}Current State:${NC} ${BO}${GY}(refreshes automatically)${NC}"
                    if [[ "$current_state" == "active" ]]; then
                        echo "  Status: ✅ ${GR}Active${NC}"
                    elif [[ "$current_state" == "inactive" ]]; then
                        echo "  Status: ❌ ${RE}Inactive${NC}"
                    else
                        echo "  Status: ❔ ${BO}${GY}Default/Not Set${NC}"
                    fi
                    if [[ -n "$current_value" ]]; then
                        echo "  Value:  $current_value"
                        echo "  Key:    $key"
                        echo "  Domain: $domain"
                        # echo "  Type:   $type"
                    fi
                    
                    # local read_display_ch=$(defaults -currentHost read "$domain" | grep "$key" 2>/dev/null || true)
                    # local read_display=$(defaults read "$domain" | grep "$key" 2>/dev/null || true)
                    # if [[ -z "$read_display" ]]; then
                    #     echo "  Key:    $read_display_ch"
                    # else
                    #     echo "  Key:    $read_display"
                    # fi
                    # echo "$read_display_ch"
                    # echo "$read_display"

                    # if [[$(defaults read "$domain" "$key")]]
                    echo
                    # Display actions
                    echo "${BO}Available actions:${NC}"
                    echo "1) ✅ ${GR}Activate${NC} (sets to: "$active_val")"
                    echo "2) ❌ ${RE}Deactivate${NC} (sets to: "$inactive_val")"
                    if [[ -n "$reset_cmd" ]]; then
                        echo "3) 🔄 ${BO}${GY}Reset to Default${NC} (sets to: "$reset_cmd")"
                    fi
                    show_navigation_prompt # already padded
                    
                    read -rp "4. ${GR}Select action (or ${BL}navigation${NC} ${GR}choice)${NC}: " action_choice
                    
                    # Check for navigation input first
                    handle_navigation_input "$action_choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        set_terminal_width_to_760p
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break  # Exit this while loop, back to preference selection
                    fi

                    # Apply Actions (Loop 5)
                    while true; do
                        case $action_choice in
                            1)
                                if apply_preference_change "$domain" "$key" "$active_val" "$type" "active"; then
                                    echo "✅ ${GR}Preference activated successfully!${NC}"
                                    echo "🔄 Refreshing state..."
                                else
                                    echo "❌ ${RE}Failed to activate preference.${NC}"
                                    echo "Please try again..."
                                fi
                                sleep 1
                                break
                                ;;
                            2)
                                if apply_preference_change "$domain" "$key" "$inactive_val" "$type" "inactive"; then
                                    echo "✅ ${GR}Preference deactivated successfully!${NC}"
                                    echo "🔄 Refreshing state..."
                                else
                                    echo "❌ ${RE}Failed to deactivate preference.${NC}"
                                    echo "Please try again..."
                                fi
                                sleep 1
                                break
                                ;;
                            3)
                                if [[ -n "$reset_cmd" ]]; then
                                    if reset_preference_to_default "$domain" "$key" "$reset_cmd" "$type"; then
                                        echo "✅ ${GR}Preference reset to default successfully!${NC}"
                                        echo "🔄 Refreshing state..."
                                    else
                                        echo "❌ ${RE}Failed to reset preference.${NC}"
                                        echo "Please try again..."
                                    fi
                                    sleep 1
                                    break
                                else
                                    echo "❌ ${RE}Reset not available for this preference.${NC}"
                                    sleep 1
                                    break
                                fi
                                ;;
                            *)
                                echo "❌ ${RE}Invalid option. Please try again.${NC}"
                                sleep 1
                                break
                                ;;
                        esac
                    done    
                done
                
            done    
        done    
    done

    # Restore Terminal window size after exiting menu
    set_terminal_height_to_500p
}

#====8==== ℹ️ About OneCommand
function one_command_info() {
    while true; do  
        return_to_menu=true
        trap 'echo; echo "Returning to main menu...from func 18"; return_to_menu=true; return' SIGINT
        clear
        echo "${GR}===========${NC}"
        echo "${BO}ℹ️  20) Info${NC}"
        echo "${GR}===========${NC}"
        echo "↩️  Main Menu"
        cat <<'EOF'
  ___            ___                              _ 
 / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
| (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
 \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|
EOF
        echo
        echo "${BO}Chose an option:${NC}"
        echo "1) ${GR}About${NC}"
        # echo "x) ${GR}Instructions${NC}"
        echo "2) ${GR}ChangeLog${NC}"
        echo "3) ${GR}Check for updates${NC}"
        show_navigation_prompt # already padded
        read -rp "➡️  ${GR}Select an option (or ${BL}navigation${NC} ${GR}choice${NC}): " choice
        
        while true; do    
            case $choice in
                1)
                    # Show Instructions    
                    return_to_menu=true
                    trap 'echo; echo "Returning to main menu...from func 18"; return_to_menu=true; return' SIGINT
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}========${NC}"
                    echo "${BO}❔ About${NC}"
                    echo "${GR}========${NC}"
                    echo "↩️  Info"
                    cat <<'EOF'
  ___            ___                              _ 
 / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
| (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
 \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|
EOF
                    echo
                    echo "${GR}OneCommand${NC} ${BO}is a macOS utility script that provides a comprehensive set of"
                    echo "system administration and file management tools through an interactive"
                    echo "terminal interface."
                    echo "${NC}"
                    echo "${GR}Core Functionality${NC}"
                    echo "  - ${BO}File Security & Permissions${NC}: Remove quarantine flags, change permissions,"
                    echo "    modify ownership"
                    echo "  - ${BO}Code Signing${NC}: Sign applications and bundles with ad-hoc signatures"
                    echo "  - ${BO}Hash Generation${NC}: Generate SHA256 hashes for files and bundles"
                    echo "  - ${BO}Package Management${NC}: Batch install .pkg files"
                    echo "  - ${BO}Disk Image Tools${NC}: Create/resize disk images and make macOS installers"
                    echo "  - ${BO}System Utilities${NC}: DNS management, network testing, system information"
                    echo "  - ${BO}macOS Preferences${NC}: Configure various default system settings and behaviors"
                    echo "  - ${BO}Difference Tracker${NC}: Track differences/changes to the file system"
                    echo
                    echo "${GR}Architecture${NC}"
                    echo "  - ${BO}Interactive menu-driven interface with navigation controls${NC}"
                    echo "  - ${BO}Modular function-based design with 20 utility functions${NC}"
                    echo "  - ${BO}Color-coded output using ANSI escape sequences${NC}"
                    echo "  - ${BO}Error handling and interruption support${NC}"
                    echo "  - ${BO}Support for drag-and-drop file operations${NC}"
                    echo
                    echo "${GR}Key Design Patterns${NC}"
                    echo "  - ${BO}Global navigation system${NC} (back/continue/interrupt/quit)"
                    echo "  - ${BO}Consistent error handling and retry mechanisms${NC}"
                    echo "  - ${BO}Automatic Terminal window resizing when displaying large output${NC}"
                    echo "  - ${BO}Modular function organization with clear separation of concerns${NC}"
                    echo "  - ${BO}User-friendly prompts and status reporting${NC}"
                    break
                    ;;
                x)
                    # Show Instructions    
                    return_to_menu=true
                    trap 'echo; echo "Returning to main menu...from func 18"; return_to_menu=true; return' SIGINT
                    # set_terminal_height_to_1200p
                    clear
                    echo "${GR}===============${NC}"
                    echo "${BO}📋 Instructions${NC}"
                    echo "${GR}===============${NC}"
                    echo "↩️  Info"
                    cat <<'EOF'
  ___            ___                              _ 
 / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
| (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
 \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|
EOF
                    echo
                    break
                    ;;
                2)
                    # Show ChangeLog
                    return_to_menu=true
                    trap 'echo; echo "Returning to main menu...from func 18"; return_to_menu=true; return' SIGINT
                    set_terminal_height_to_1200p
                    clear
                    echo "${GR}============${NC}"
                    echo "${BO}📝 ChangeLog${NC}           ${CY}[For the latest updates, visit]${NC}"
                    echo "${GR}============${NC}      ${CY}[https://shop.ryansummer.com/p/onecommand]${NC}"
                    echo "↩️  Info"
                    cat <<'EOF'
  ___            ___                              _ 
 / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
| (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
 \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|
EOF
                    echo
                    echo "${BO}Beta v0.1.0 - 7/27/2025${NC}"
                    echo "- Public Beta"
                    echo
                    echo "${BO}Beta v0.2.0 - 08/07/2025${NC}"
                    echo "- ${GR}Added${NC} 6 new menu options/functions:"
                    echo "    📊 Activity Monitor (Top) ${BO}${GY}(a CLI activity monitor)${NC}"
                    echo "    📡 Speed Test ${BO}${GY}(a CLI speed test)${NC}"
                    echo "    🔄 iCloud Sync Refresh ${BO}${GY}(for forcing iCloud sync)${NC}"
                    echo "    ℹ️  System Information ${BO}${GY}(displays a more complete system profile overview)${NC}"
                    echo "    🌐 DNS Utility ${BO}${GY}(for testing, showing or flushing DNS settings)${NC}"
                    echo "    ⚙️  MacOS Preferences ${BO}${GY}(contains over 75+ customizations)${NC}"
                    echo "- ${BL}Condensed${NC} the Navigation controls to 1 line instead of 4"
                    echo "- ${MA}Updated${NC} some menu option emojis to better represent their functions"
                    echo
                    echo "${BO}Beta v0.3.0 - 08/30/2025${NC}"
                    echo "- ${GR}Added${NC} 4 new menu options/functions:"
                    echo "    📝 OneCommand ChangeLog ${BO}${GY}(Built in changeLog for this script)${NC}"
                    echo "    💿 Create Disk Image ${BO}${GY}(create/resize/password protect disk images)${NC}"
                    echo "    🍏 Create macOS Installer ${BO}${GY}(create a bootable macOS installer)${NC}"
                    echo "    ⚙️  macOS Diff Tracker ${BO}${GY}(compare differences/changes in the file system)${NC}"
                    echo "- ${GR}Added${NC} over 95+ more customizations to ⚙️  MacOS Preferences ${BO}${GY}(170 in total)${NC}"
                    echo "- ${GR}Added${NC} 'fn ⬆️  Page Up | fn ⬇️  Page Down' to the navigation bar"
                    echo
                    echo "${BO}Beta v0.4.0 - 09/04-2025${NC}"
                    echo "- ${GR}Added${NC} 2 new menu options/functions:"
                    echo "    🧼 VM Isolation Check ${BO}${GY}(check VM leakage for testing untrusted software)${NC}"
                    echo "    ⏳ Time Machine Utility ${BO}${GY}(view, delete and thin local snapshots)${NC}"
                    echo "- ${GR}Fine-tuned${NC} all traps for interrupting sudo password prompts, etc."
                    echo "- ${RE}Removed${NC} 'fn ⬆️  Page Up | fn ⬇️  Page Down | ^C Quit' from the navigation bar"
                    echo "- ${GR}Added${NC} '^C Interrupt/Exit | Q Main Menu' to the navigation bar"
                    echo "- ${GR}Added${NC} '↩️  Main Menu' under each menu item header"
                    echo "- ${GR}Added${NC} '↩️  <Previous Step>' under most sub menu headers"
                    echo "    ${BO}${GY}(This helps better understand what pressing 'b' will go back to).${NC}"
                    echo
                    echo "- ${GR}Added${NC} 'User Account Details' as an option to menu item:"
                    echo "   12) ℹ️  System Information"
                    echo
                    echo "${BO}Public Release v1.0 - 09/15-2025${NC}"
                    echo "- ${GR}Added${NC} 14 new ⚙️  MacOS Preferences for ${BL}macOS Tahoe${NC} ${BO}${GY}(184 in total)${NC}"
                    break
                    ;;
                3)
                    # Check for updates
                    open https://shop.ryansummer.com/p/onecommand
                    continue 2
                    ;;
                *)
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break 2
                    fi
                    echo "❌ ${RE}Invalid option. Please choose 1-3.${NC}"
                    sleep 1
                    continue 2
                    ;;
            esac
        done
        while true; do
            show_navigation_prompt # already padded
            
            return_to_menu=true
            interrupted=false
            trap 'echo; echo "returning from func 20"; return' SIGINT

            read -rp "➡️  ${GR}Choose another option? Press Enter (or ${BL}navigation${NC} ${GR}choice${NC}): " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                set_terminal_height_to_500p
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                set_terminal_height_to_500p
                break
            else
                set_terminal_height_to_500p
                break
            fi
        done 
    done
}

# Script entry point
main_menu
# intentionally left blank