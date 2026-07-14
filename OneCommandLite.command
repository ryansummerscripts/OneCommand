#!/usr/bin/env bash
#   ___            ___                              _ 
#  / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
# | (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
#  \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|
#
# Version: 2.1.2 (Lite)
# by Ryan Summer
# https://shop.ryansummer.com/p/onecommand

# === Set Variables ===========================================================
# Color Definitions
NC=$'\033[0m'
BO=$'\033[1m'
DM=$'\033[2m'
BK=$'\033[5m'
RE=$'\033[1;31m'
GR=$'\033[1;32m'
YE=$'\033[1;33m'
BL=$'\033[1;34m'
MA=$'\033[1;35m'
CY=$'\033[1;36m'
GY="${BO}${DM}"
# Navigation Codes
NAV_BACK=0
NAV_CONT=1
NAV_QUIT=2
NAV_REFRESH=3
# Misc.
interrupted=false
saved_paths_to_process=()
use_saved_paths=false
# Define bundle extensions that should be treated as single units
bundle_extensions=("app" "bundle" "framework" "component" "vst" "vst3" "aaxplugin" "plugin" "kext")
# Preferences
DontAskAgainAbout_SavingPaths_Path_Picker=false
DontAskAgainAbout_OverwritingPaths_Path_Picker=false
DisablePathPickerWhenPathsAreSaved_Quick_Stats=false
DisablePathPickerWhenPathsAreSaved_Create_Symlinks=false
DisableTerminalResizing_Horizonal=false
DisableTerminalResizing_Vertical=false
DisableBlinkingText=false
DisableColoredText=false
DisableSavedPathEncryption=false
SudoKeepAliveOnStartUp=false
DisableWelcomeText_QuickMenus=false
HideIncompatible_macOS_Preferences=false
# nav flags
used_keyboard_shortcut_s=false
used_keyboard_shortcut_p=false
came_from_main_menu=false
# more nav stuff
current_main_menu_choice=""
current_sub_menu_choice=""
MAIN_MENU_ITEMS_TOTAL=10
# --- Store configuration details for certain functions -----------------------
# --- Detect OS version -------------------------------------------------------
product_version=$(sw_vers -productVersion)
os_vers=( ${product_version//./ } )
MACOS_MAJOR="${os_vers[0]}"
MACOS_MINOR="${os_vers[1]}"
MACOS_PATCH="${os_vers[2]:-0}"
# os_vers_build=$(sw_vers -buildVersion)    # not needed
# --- Detect Architecture (Apple Silicon vs Intel) ----------------------------
ARCH_TYPE=$(uname -m)
# --- Detect device type (to grey-out irrelevant macOS preferences) -----------
SP_HW_INFO=$(system_profiler SPHardwareDataType)
# SP_SW_INFO=$(system_profiler SPSoftwareDataType)    # not needed
model_id=$(sysctl -n hw.model 2>/dev/null)    # no longer reliable to detect laptops (e.g., Mac17,2 is a MacBook Pro)
model_name=$(sysctl -n hw.product 2>/dev/null)    # no longer reliable to detect laptops (e.g., Mac17,2 is a MacBook Pro)
battery_info=$(ioreg -rd1 -c AppleSmartBattery -r)    # Without -d1, ioreg recurses deeply into the whole tree. On slow/busy machines this can take a noticeable moment.
device_check_1=""
device_check_2=""
DEVICE_TYPE=""
# --- Detect laptop vs desktop (method 1) -------------------------------------
if echo "$SP_HW_INFO" | grep -iqE 'virtual|vmware|parallels|qemu|virtualbox|kvm|xen|bochs|bhyve'; then
    device_check_1="vm"
# elif echo "$SP_HW_INFO" | grep -q "Book"; then
elif echo "$SP_HW_INFO" | grep -q "Model Name:.*Book"; then
    device_check_1="laptop"
else
    device_check_1="desktop"
fi
# --- Detect laptop vs desktop (method 2) -------------------------------------
if echo "$battery_info" | grep -q '"BatteryInstalled" = Yes'; then
    device_check_2="laptop"
elif echo "$battery_info" | grep -q '"BatteryInstalled" = No'; then
    device_check_2="desktop"
else
    # Class absent — could be VM or a desktop with no battery controller
    # Let method 1 be the tiebreaker; mark as inconclusive here
    device_check_2="$device_check_1"   # defer, won't cause "unknown" below
fi
# --- Compare both methods ----------------------------------------------------
if [[ "$device_check_1" == "$device_check_2" ]]; then
    DEVICE_TYPE="$device_check_1"
else
    DEVICE_TYPE="unknown"
fi
# --- Detect Architecture (Apple Silicon vs Intel) ----------------------------
if [[ "$ARCH_TYPE" == "arm64" ]]; then
    # SP_PROCESSOR_NAME=$(echo "$SP_HW_INFO" | grep "Chip" | awk -F': ' '{print $2}')
    SP_PROCESSOR_NAME=$(echo "$SP_HW_INFO" | grep -m 1 "Chip" | awk -F': ' '{print $2}')
elif [[ "$ARCH_TYPE" == "x86_64" ]]; then
    SP_PROCESSOR_NAME=$(echo "$SP_HW_INFO" | grep "Processor Name" | awk -F': ' '{print $2}')
fi
# SP_MODEL_NAME=$(echo "$SP_HW_INFO" | grep "Model Name" | awk -F': ' '{print $2}')
SP_MODEL_NAME=$(echo "$SP_HW_INFO" | grep -m 1 "Model Name" | awk -F': ' '{print $2}')
# Build custom display output
system_info_for_display="${GY}System Info: macOS $product_version | $SP_PROCESSOR_NAME $SP_MODEL_NAME${NC}"
# --- Store Permission-Related Info -------------------------------------------
# Get currently logged-in user
REAL_USER=$(stat -f "%Su" /dev/console)
uid=$(id -u)
ADMIN_STATUS=$(if id -Gn | grep -q '\badmin\b'; then echo "✅"; else echo "❌"; fi)
# --- Saved Paths Enc Key -----------------------------------------------------
# Derives a machine+user specific key — no password prompt, but not portable
_get_paths_enc_key() {
    local hw_uuid
    hw_uuid=$(ioreg -rd1 -c IOPlatformExpertDevice \
        | awk -F'"' '/IOPlatformUUID/ { print $4 }')
    # Mix in username so key is user-scoped too
    printf '%s:%s:OneCommand' "$hw_uuid" "$USER" \
        | shasum -a 256 \
        | awk '{print $1}'
}
# --- Preference Saving/Loading -----------------------------------------------
PREFS_FILE="${HOME}/.OneCommand/preferences.conf"
# Write a single key=value to the prefs file (adds or updates)
save_pref() {
    local key="$1" value="$2"
    mkdir -p "${HOME}/.OneCommand"
    
    if [[ -f "$PREFS_FILE" ]] && grep -q "^${key}=" "$PREFS_FILE"; then
        # Update existing key (BSD sed compatible — macOS default)
        sed -i '' "s|^${key}=.*|${key}=${value}|" "$PREFS_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$PREFS_FILE"
    fi
    chmod 600 "$PREFS_FILE"
}
# Read a single value by key (prints value or empty string)
load_pref() {
    local key="$1"
    [[ ! -f "$PREFS_FILE" ]] && return
    grep "^${key}=" "$PREFS_FILE" | cut -d'=' -f2-
}
# Toggle prefs in Settings Menu
_toggle_pref() {
    local varname="$1"
    local current
    current=$(load_pref "$varname")
    [[ -z "$current" ]] && current="false"

    if [[ "$current" == "true" ]]; then
        printf -v "$varname" '%s' "false"
        save_pref "$varname" "false"
    else
        printf -v "$varname" '%s' "true"
        save_pref "$varname" "true"
    fi
}
# --- Preference Management ---------------------------------------------------
# Load all known prefs into their variables
load_all_prefs() {
    [[ ! -f "$PREFS_FILE" ]] && return
    local val

    val=$(load_pref "DontAskAgainAbout_SavingPaths_Path_Picker");              [[ -n "$val" ]] && DontAskAgainAbout_SavingPaths_Path_Picker="$val"
    val=$(load_pref "DontAskAgainAbout_OverwritingPaths_Path_Picker");         [[ -n "$val" ]] && DontAskAgainAbout_OverwritingPaths_Path_Picker="$val"
    val=$(load_pref "DisablePathPickerWhenPathsAreSaved_Quick_Stats");         [[ -n "$val" ]] && DisablePathPickerWhenPathsAreSaved_Quick_Stats="$val"
    val=$(load_pref "DisablePathPickerWhenPathsAreSaved_Create_Symlinks");     [[ -n "$val" ]] && DisablePathPickerWhenPathsAreSaved_Create_Symlinks="$val"
    val=$(load_pref "DisableTerminalResizing_Horizonal");                      [[ -n "$val" ]] && DisableTerminalResizing_Horizonal="$val"
    val=$(load_pref "DisableTerminalResizing_Vertical");                       [[ -n "$val" ]] && DisableTerminalResizing_Vertical="$val"
    val=$(load_pref "DisableBlinkingText");                                    [[ -n "$val" ]] && DisableBlinkingText="$val"
    val=$(load_pref "DisableColoredText");                                     [[ -n "$val" ]] && DisableColoredText="$val"
    val=$(load_pref "DisableSavedPathEncryption");                             [[ -n "$val" ]] && DisableSavedPathEncryption="$val"
    val=$(load_pref "SudoKeepAliveOnStartUp");                                 [[ -n "$val" ]] && SudoKeepAliveOnStartUp="$val"
    val=$(load_pref "DisableWelcomeText_QuickMenus");                          [[ -n "$val" ]] && DisableWelcomeText_QuickMenus="$val"
    val=$(load_pref "HideIncompatible_macOS_Preferences");                     [[ -n "$val" ]] && HideIncompatible_macOS_Preferences="$val"

    # Future prefs just add lines here:
    # val=$(load_pref "some_other_pref")
    # [[ -n "$val" ]] && some_other_pref="$val"
}
# Wipe the prefs file and reset all pref vars to defaults
reset_all_prefs() {
    rm -f "$PREFS_FILE"
    reset_all_prefs_to_default
    # Future prefs reset here too
}
# Reset ALL prefs to defaults (file + vars)
reset_all_prefs_to_default() {
    DontAskAgainAbout_SavingPaths_Path_Picker=false
    DontAskAgainAbout_OverwritingPaths_Path_Picker=false
    DisablePathPickerWhenPathsAreSaved_Quick_Stats=false
    DisablePathPickerWhenPathsAreSaved_Create_Symlinks=false
    DisableTerminalResizing_Horizonal=false
    DisableTerminalResizing_Vertical=false
    DisableBlinkingText=false
    DisableColoredText=false
    BK=$'\033[5m'
    NC=$'\033[0m'
    BO=$'\033[1m'
    DM=$'\033[2m'
    RE=$'\033[1;31m'
    GR=$'\033[1;32m'
    YE=$'\033[1;33m'
    BL=$'\033[1;34m'
    MA=$'\033[1;35m'
    CY=$'\033[1;36m'
    GR=$'\033[1;32m'
    GY="${BO}${DM}"
    DisableSavedPathEncryption=false
    save_paths_to_file
    SudoKeepAliveOnStartUp=false
    DisableWelcomeText_QuickMenus=false
    HideIncompatible_macOS_Preferences=false
}
_count_saved_prefs() {
    [[ ! -f "$PREFS_FILE" ]] && echo 0 && return
    # grep pattern filters for =true specifically - updating _count_saved_prefs after a menu refresh
    grep -c "=true$" "$PREFS_FILE" 2>/dev/null

    # # grep pattern matches any key=value line regardless of whether the value is true or false
    # grep -c "^[^#[:space:]].*=." "$PREFS_FILE" 2>/dev/null
}
# --- Enc/Save/Load/Dec Saved Paths -------------------------------------------
SAVED_PATHS_FILE="${HOME}/.OneCommand/saved_paths.enc"
# pbkdf2 requires LibreSSL 3.3+ — available from macOS 13 (Ventura) onwards
if [[ "$MACOS_MAJOR" -ge 13 ]]; then
    OPENSSL_KDF_FLAGS="-pbkdf2"
else
    OPENSSL_KDF_FLAGS="-md sha256"
fi
save_paths_to_file() {
    mkdir -p "${HOME}/.OneCommand"
    
    if [[ "$DisableSavedPathEncryption" == "false" ]]; then
        local key
        key=$(_get_paths_enc_key)

        # Write one path per line, encrypt with AES-256-CBC
        printf '%s\n' "${saved_paths_to_process[@]}" \
            | openssl enc -aes-256-cbc $OPENSSL_KDF_FLAGS \
                -pass pass:"$key" \
                -out "$SAVED_PATHS_FILE" 2>/dev/null
    else
        printf '%s\n' "${saved_paths_to_process[@]}" > "$SAVED_PATHS_FILE"
    fi

    chmod 600 "$SAVED_PATHS_FILE"
}
load_paths_from_file() {
    [[ ! -f "$SAVED_PATHS_FILE" ]] && return

    local decrypted

    if [[ "$DisableSavedPathEncryption" == "false" ]]; then
        local key
        key=$(_get_paths_enc_key)
        decrypted=$(openssl enc -aes-256-cbc $OPENSSL_KDF_FLAGS -d \
            -pass pass:"$key" \
            -in "$SAVED_PATHS_FILE" 2>/dev/null)
        # Bail silently if decryption fails (corrupted/wrong key)
        [[ $? -ne 0 || -z "$decrypted" ]] && return
    else
        decrypted=$(cat "$SAVED_PATHS_FILE")
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] && saved_paths_to_process+=("$line")
    done <<< "$decrypted"
}
# --- Saved Path Helpers ------------------------------------------------------
clear_saved_path_data() {
    saved_paths_to_process=()
    rm -f "$SAVED_PATHS_FILE"
}
# Prune paths that have disappeared since last session
prune_paths() {
    local valid=()
    for p in "${saved_paths_to_process[@]}"; do
        [[ -e "$p" ]] && valid+=("$p")
    done
    # --- Re-save pruned list if anything was removed -----------------------------
    [[ "${#valid[@]}" -lt "${#saved_paths_to_process[@]}" ]] && save_paths_to_file
    saved_paths_to_process=("${valid[@]}")
}
# --- Path Sorting (and singular vs plural definitions) -----------------------
sort_paths_to_process_with_defs() {
    # singular vars
    path_or_paths="path"
    this_or_these="this"
    item_or_items="item"

    # Sort paths_to_process by basename
    if [[ "${#paths_to_process[@]}" -gt 1 ]]; then
        sorted_files=()
        while IFS='|' read -r fname fpath; do
            sorted_files+=("$fpath")
        done < <(for f in "${paths_to_process[@]}"; do
            printf '%s|%s\n' "$(basename "$f")" "$f"
        done | sort -t'|' -k1,1)

        paths_to_process=("${sorted_files[@]}")

        # plural vars
        path_or_paths="paths"
        this_or_these="these"
        item_or_items="items"
    fi
}
sort_paths_to_process_without_defs() {
    # Sort paths_to_process by basename
    if [[ "${#paths_to_process[@]}" -gt 1 ]]; then
        sorted_files=()
        while IFS='|' read -r fname fpath; do
            sorted_files+=("$fpath")
        done < <(for f in "${paths_to_process[@]}"; do
            printf '%s|%s\n' "$(basename "$f")" "$f"
        done | sort -t'|' -k1,1)
        
        paths_to_process=("${sorted_files[@]}")
    fi
}
set_plurality_for_saved_paths_to_process() {
    local count="${1:-${#saved_paths_to_process[@]}}"
    if [[ "$count" -gt 1 ]]; then
        path_or_paths="paths" this_or_these="these" item_or_items="items"
    else
        path_or_paths="path"  this_or_these="this"  item_or_items="item"
    fi
}
# --- Global Navigation handlers ----------------------------------------------
handle_navigation_input() {
    local choice="$1"
    case "$choice" in
        "q"|"Q"|"quit"|"QUIT"|"exit"|"EXIT")
            interrupted=false
            return $NAV_QUIT
            ;;
        "b"|"B"|"back"|"BACK")
            interrupted=false
            return $NAV_BACK
            ;;
        "s"|"S")
            if [[ "$used_keyboard_shortcut_p" == "true" ]]; then
                echo -n "${YE}Must exit Quick Picker first.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            elif [[ "$used_keyboard_shortcut_s" == "true" ]]; then
                echo -n "${YE}Already in Quick Settings.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            elif [[ "$came_from_settings_manage_saved_paths_path_picker" == "true" ]]; then
                echo -n "${YE}Already in Settings.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            elif [[ "$came_from_command_center_settings" == "true" ]]; then
                echo -n "${YE}Already in Settings.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            elif [[ "$came_from_main_menu" == "true" ]]; then
                echo -n "${YE}Already in Settings.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            fi
            interrupted=false
            used_keyboard_shortcut_s=true
            quick_settings
            used_keyboard_shortcut_s=false
            return $NAV_REFRESH
            ;;
        "p"|"P")
            if [[ "$came_from_command_center_path_picker" == "true" ]]; then
                echo -n "${YE}Already in Path Picker.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            elif [[ "$came_from_settings_manage_saved_paths_path_picker" == "true" ]]; then
                echo -n "${YE}Already in Path Picker.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            elif [[ "$used_keyboard_shortcut_s" == "true" ]]; then
                echo -n "${YE}Must exit Quick Settings first.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            elif [[ "$used_keyboard_shortcut_p" == "true" ]]; then
                echo -n "${YE}Already in Quick Picker.${NC} "
                read -r -t 1 -n 1
                return $NAV_REFRESH
            fi
            interrupted=false
            used_keyboard_shortcut_p=true
            quick_picker
            used_keyboard_shortcut_p=false
            return $NAV_REFRESH
            ;;
        *)
            interrupted=false
            return $NAV_CONT
            ;;
    esac
}
handle_main_menu_AZ_navigation_input() {
    local direction="$1" current="$2"
    if [[ "$direction" == "a" || "$direction" == "A" ]]; then
        current_main_menu_choice=$(( (current - 1 + MAIN_MENU_ITEMS_TOTAL) % MAIN_MENU_ITEMS_TOTAL ))
        return 0
    elif [[ "$direction" == "z" || "$direction" == "Z" ]]; then
        current_main_menu_choice=$(( (current + 1) % MAIN_MENU_ITEMS_TOTAL ))
        return 0
    fi
    return 1
}
handle_sub_menu_AZ_navigation_input() {
    local direction="$1" current="$2" min="$3" max="$4"
    if [[ "$direction" == "a" || "$direction" == "A" ]]; then
        current_sub_menu_choice=$(( current - 1 < min ? max : current - 1 ))
        return 0
    elif [[ "$direction" == "z" || "$direction" == "Z" ]]; then
        current_sub_menu_choice=$(( current + 1 > max ? min : current + 1 ))
        return 0
    fi
    return 1
}
# --- Terminal Window Auto-Resize ---------------------------------------------
# Resize Terminal window for either Terminal.app or iTerm2
resize_terminal() {
	[[ "$DisableTerminalResizing_Horizonal" == "true" ]] && return
    local cols="$1"
	local rows="$2"
	
	if [ "$TERM_PROGRAM" = "Apple_Terminal" ]; then
		if [ -n "$cols" ] && [ -n "$rows" ]; then
			# Both specified - resize both (use single -e to avoid timing issues)
			osascript -e "tell application \"Terminal\" to tell front window to set {number of columns, number of rows} to {$cols, $rows}" >/dev/null 2>&1
		elif [ -n "$cols" ]; then
			# Only width specified
			osascript -e "tell application \"Terminal\" to tell front window to set number of columns to $cols" >/dev/null 2>&1
		elif [ -n "$rows" ]; then
			# Only height specified
			osascript -e "tell application \"Terminal\" to tell front window to set number of rows to $rows" >/dev/null 2>&1
		fi
	elif [ "$TERM_PROGRAM" = "iTerm.app" ]; then
		if [ -n "$cols" ] && [ -n "$rows" ]; then
			# Both specified - use single command
			osascript -e "tell application \"iTerm\" to tell current window to tell current session to set {columns, rows} to {$cols, $rows}" >/dev/null 2>&1
		elif [ -n "$cols" ]; then
			osascript -e "tell application \"iTerm\" to tell current window to tell current session to set columns to $cols" >/dev/null 2>&1
		elif [ -n "$rows" ]; then
			osascript -e "tell application \"iTerm\" to tell current window to tell current session to set rows to $rows" >/dev/null 2>&1
		fi
	else
		# ANSI escape sequences
		if [ -n "$cols" ] && [ -n "$rows" ]; then
			printf "\033[8;${rows};${cols}t"
		elif [ -n "$cols" ]; then
			printf "\033[3;${cols}t"
		elif [ -n "$rows" ]; then
			printf "\033[2;${rows}t"
		fi
	fi
}
# Resize Terminal window taller via osascript
set_terminal_height_to_2200p() {
	[[ "$DisableTerminalResizing_Vertical" == "true" ]] && return
    if [ "$TERM_PROGRAM" = "Apple_Terminal" ]; then
		osascript <<-'EOF' >/dev/null 2>&1
			tell application "Terminal"
				set b to bounds of front window
				set leftEdge to item 1 of b
				set topEdge to item 2 of b
				set rightEdge to item 3 of b
				set bottomEdge to item 4 of b
				-- Keep left/top, keep width same (right - left)
				set newBottomEdge to topEdge + 2200 -- increase height by 2200 pixels
				set bounds of front window to {leftEdge, topEdge, rightEdge, newBottomEdge}
			end tell
		EOF
	elif [ "$TERM_PROGRAM" = "iTerm.app" ]; then
		osascript <<-'EOF' >/dev/null 2>&1
			tell application "iTerm"
				tell current window
					set b to bounds
					set leftEdge to item 1 of b
					set topEdge to item 2 of b
					set rightEdge to item 3 of b
					set bottomEdge to item 4 of b
					-- Keep left/top, keep width same (right - left)
					set newBottomEdge to topEdge + 2200 -- increase height by 2200 pixels
					set bounds to {leftEdge, topEdge, rightEdge, newBottomEdge}
				end tell
			end tell
		EOF
	fi
}
# --- Echo Formatting ---------------------------------------------------------
echo_centered() {
    if [[ "$DisableTerminalResizing_Horizonal" == "true" ]]; then
        echo "$1"
        return
    fi
    local text="$1"
    local width=$(tput cols)  # Get current terminal width

    # Remove ANSI color codes to get actual visible length
    local visible_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local text_length=${#visible_text}
    local padding=$(( (width - text_length) / 2 ))
    
    printf "%${padding}s%b\n" "" "$text"
}
echo_n_centered() {
    if [[ "$DisableTerminalResizing_Horizonal" == "true" ]]; then 
        echo -n "$1"
        return
    fi
    local text="$1"
    local width=$(tput cols)  # Get current terminal width

    # Remove ANSI color codes to get actual visible length
    local visible_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local text_length=${#visible_text}
    local padding=$(( (width - text_length) / 2 ))
    
    printf "%${padding}s%b" "" "$text"
}
echo_justified() {
    # if [[ "$DisableTerminalResizing_Horizonal" == "true" ]]; then
    #     echo "$1" "| $2" # "$3" # ${3::}
    #     return
    # fi
    local left_text="$1"
    local right_text="$2"
    # local width="${3:-80}"  # Default to 80 if not specified, or use $(tput cols)
    local width="${3:-95}"  # Default to 80 if not specified, or use $(tput cols)
    
    # Remove ANSI color codes to get actual visible length
    local visible_left=$(echo -e "$left_text" | sed 's/\x1b\[[0-9;]*m//g')
    local visible_right=$(echo -e "$right_text" | sed 's/\x1b\[[0-9;]*m//g')
    
    local left_length=${#visible_left}
    local right_length=${#visible_right}
    
    # Calculate spacing needed between left and right text
    local spacing=$(( width - left_length - right_length ))
    
    # Ensure spacing is at least 1
    if [ "$spacing" -lt 1 ]; then
        spacing=1
    fi
    
    printf "%b%${spacing}s%b\n" "$left_text" "" "$right_text"
}
# --- ASCII Headers -----------------------------------------------------------
display_OneCommand_header_for_95px() {
    echo -n "${BO}"
    cat <<'EOF'
                       ___            ___                              _ 
                      / _ \ _ _  ___ / __|___ _ __  _ __  __ _ _ _  __| |
                     | (_) | ' \/ -_) (__/ _ \ '  \| '  \/ _` | ' \/ _` |
                      \___/|_||_\___|\___\___/_|_|_|_|_|_\__,_|_||_\__,_|
EOF
    echo -n "${NC}"
    echo "                   ${BL}Created by Ryan Summer${NC} | ${BL}For macOS 12-26${NC} | ${BL}v2.1.2 (Lite)${NC}"
    echo
}
display_macos_preferences_header() {
    echo -n "${BO}"
    cat <<'EOF'
                                     ___  ___   ___          __                            
                      _ __  __ _ __ / _ \/ __| | _ \_ _ ___ / _|___ _ _ ___ _ _  __ ___ ___
                     | '  \/ _` / _| (_) \__ \ |  _/ '_/ -_)  _/ -_) '_/ -_) ' \/ _/ -_|_-<
                     |_|_|_\__,_\__|\___/|___/ |_| |_| \___|_| \___|_| \___|_||_\__\___/__/
EOF
    echo -n "${NC}"
    echo "                                               ${BL}For macOS 12-26${NC}"
}
display_Disk_Image_Utility_header_for_95px() {
    echo -n "${BO}"
    cat <<'EOF'
               ___  _    _     ___                       _   _ _   _ _ _ _        
              |   \(_)__| |__ |_ _|_ __  __ _ __ _ ___  | | | | |_(_) (_) |_ _  _ 
              | |) | (_-< / /  | || '  \/ _` / _` / -_) | |_| |  _| | | |  _| || |
              |___/|_/__/_\_\ |___|_|_|_\__,_\__, \___|  \___/ \__|_|_|_|\__|\_, |
                                             |___/                           |__/ 
EOF
    echo -n "${NC}"
    echo
}
# --- Navigation Prompts ------------------------------------------------------
show_nav_prompt_not_centered() {
    echo
    echo "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}^C${NC} Stop | ${BL}P${NC} Path Picker | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_centered() {
    echo
    echo_centered "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}^C${NC} Stop | ${BL}P${NC} Path Picker | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_with_AZ_not_centered() {
    echo
    echo "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}A${NC} Previous | ${BL}Z${NC} Next | ${BL}^C${NC} Stop | ${BL}P${NC} Path Picker | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_with_AZ_centered() {
    echo
    echo_centered "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}A${NC} Previous | ${BL}Z${NC} Next | ${BL}^C${NC} Stop | ${BL}P${NC} Path Picker | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_for_categories_not_centered() {
    echo
    echo "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}A${NC} Previous Category | ${BL}Z${NC} Next Category | ${BL}^C${NC} Stop | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_for_categories_centered() {
    echo
    echo_centered "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}A${NC} Previous Category | ${BL}Z${NC} Next Category | ${BL}^C${NC} Stop | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_for_preferences_not_centered() {
    echo
    echo "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}A${NC} Previous Preference | ${BL}Z${NC} Next Preference | ${BL}^C${NC} Stop | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_with_AZ_for_settings_centered() {
    echo
    echo_centered "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}A${NC} Previous | ${BL}Z${NC} Next | ${BL}^C${NC} Stop | ${BL}P${NC} Path Picker | ${BL}Q${NC} Main Menu"
    echo
}
show_nav_prompt_with_AZ_for_quick_settings_centered() {
    echo
    echo_centered "${BL}⮑ ${NC} Continue | ${BL}A${NC} Previous | ${BL}Z${NC} Next | ${BL}B/^C${NC} Back | ${BL}Q${NC} Exit Quick Settings"
    echo
}
# --- Path Picker Prompts -----------------------------------------------------
show_path_picker_options() {
    echo "${GR}Please provide path(s) to a file or folder.${NC}"
    echo
    echo "${BO}Path Picker Options:${NC}  ${GY}(or use drag & drop)${NC}"
    echo " 1) 📂 ${GR}Reveal Finder ${NC} ${GY}(for Drag & Drop)${NC}"
    echo " 2) 📄 ${GR}Choose file(s)${NC} ${GY}(via Finder dialog)${NC}"
    echo " 3) 📁 ${GR}Choose folder ${NC} ${GY}(via Finder dialog)${NC}"
    if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
        echo " 4) 💾 ${GR}Use saved $path_or_paths${NC} (${#saved_paths_to_process[@]})"
        echo " 5) 🗑️  ${GR}Clear saved $path_or_paths${NC} (${#saved_paths_to_process[@]})"
    fi
    echo
    echo "⬇️  ${GR}Drag & drop multiple files/folders onto this window, then press Enter.${NC}"
    echo "   ${GY}Tip: You can also press ⌥⌘C to copy multiple files/folders as a pathname${NC}"
    echo
}
show_path_picker_save_options() {
    if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
        echo " 4) 💾 ${GR}Use saved $path_or_paths${NC} (${#saved_paths_to_process[@]})"
        echo " 5) 🗑️  ${GR}Clear saved $path_or_paths${NC} (${#saved_paths_to_process[@]})"
    fi
}
show_save_path_confirmation() {
    echo "───────────────────────────────────────────────────────────────────────────────────────────────"
    echo "💾 ${BO}Would you like to save $this_or_these $path_or_paths/$item_or_items for future use?${NC}"
    echo
    echo " 1) ${GR}Yes - Save as a Path Picker option${NC}"
    echo " 2) ${RE}Don't ask again${NC}"
    echo " ${GR}⮑ ${NC} ${BO}Skip${NC}"
    echo
}
show_clear_saved_paths_prompt() {
    echo "───────────────────────────────────────────────────────────────────────────────────────────────"
    echo "⚠️  ${RE}Are you sure you want to clear and forget $this_or_these saved $path_or_paths/$item_or_items?:${NC}"
    echo
    for saved_path in "${saved_paths_to_process[@]}"; do
        # if [[ ! -e "$saved_path" ]]; then
        #     echo -n "⚠️  ${YE}Saved path no longer exists:${NC} ${saved_path##*/}"
        # else
        local name="${saved_path##*/}"
        local display_name=""

        if [ -L "$saved_path" ]; then
            # echo "parent is a link"
            local target
            target=$(readlink "$path" 2>/dev/null)
            
            if [ -n "$target" ]; then
                # echo "parent link target points to something"
                if [ -d "$saved_path" ]; then
                    # echo "parent link target points to a dir"
                    display_name="🔗 ${MA}${name}/${NC} → 📂 ${CY}${target}/${NC}"
                elif [ -f "$saved_path" ]; then
                    # echo "parent link target points to a file"
                    display_name="🔗 ${MA}${name}${NC} → 📄 ${BO}${target}${NC}"
                else
                    # echo "parent link target is broken"
                    display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ${GY}${target}${NC}"
                fi
            else
                # echo "parent link target does not point to anything (edge case)"
                display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ..."
            fi
        elif [ -d "$saved_path" ]; then
            # echo "parent is a directory"
            display_name="📂 ${CY}${name}/${NC}"
        elif [ -f "$saved_path" ]; then
            # echo "parent is a file or alias"
            display_name="📄 ${BO}${name}${NC}"
        else
            # Other type
            display_name="📄 ${name}"
        fi
        echo "$display_name"
        echo "${GY}'$saved_path'${NC}"
    done
    echo
}
show_overwrite_saved_path_confirmation() {
    echo "───────────────────────────────────────────────────────────────────────────────────────────────"
    echo "⚠️  ${RE}Do you want to overwrite $this_or_these currently saved $path_or_paths/$item_or_items?${NC}:"
    echo
    for saved_path in "${saved_paths_to_process[@]}"; do
        # if [[ ! -e "$saved_path" ]]; then
        #     echo -n "⚠️  ${YE}Saved path no longer exists:${NC} ${saved_path##*/}"
        # else
        local name="${saved_path##*/}"
        local display_name=""

        if [ -L "$saved_path" ]; then
            # echo "parent is a link"
            local target
            target=$(readlink "$path" 2>/dev/null)
            
            if [ -n "$target" ]; then
                # echo "parent link target points to something"
                if [ -d "$saved_path" ]; then
                    # echo "parent link target points to a dir"
                    display_name="🔗 ${MA}${name}/${NC} → 📂 ${CY}${target}/${NC}"
                elif [ -f "$saved_path" ]; then
                    # echo "parent link target points to a file"
                    display_name="🔗 ${MA}${name}${NC} → 📄 ${BO}${target}${NC}"
                else
                    # echo "parent link target is broken"
                    display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ${GY}${target}${NC}"
                fi
            else
                # echo "parent link target does not point to anything (edge case)"
                display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ..."
            fi
        elif [ -d "$saved_path" ]; then
            # echo "parent is a directory"
            display_name="📂 ${CY}${name}/${NC}"
        elif [ -f "$saved_path" ]; then
            # echo "parent is a file or alias"
            display_name="📄 ${BO}${name}${NC}"
        else
            # Other type
            display_name="📄 ${name}"
        fi
        echo "$display_name"
        echo "${GY}'$saved_path'${NC}"
    done
    echo
}
show_overwrite_saved_path_options() {
    echo " 1) ${GR}Yes - Replace with new path(s)${NC}"
    echo " 2) ${RE}Don't ask again${NC}"
    echo " ${GR}⮑ ${NC} ${BO}Skip${NC}"
    echo
}
show_invalid_path_prompt() {
    echo "───────────────────────────────────────────────────────────────────────────────────────────────"
    echo "❌ ${RE}Invalid path(s):${NC}"
    for invalid_path in "${invalid_paths[@]}"; do
        echo "$invalid_path"
    done
    echo
}
# --- Enable/Disable Global Sudo Privileges -----------------------------------
# Call this once after the user opts in
enable_sudo_keepalive() {
    trap - SIGINT  # clear so ^C during password gives real exit code
    sudo -v 2>/dev/null
    local exit_code=$?
    trap 'return' SIGINT  # restore caller's trap
    if [[ $exit_code -ne 0 ]]; then
        return 1
    fi
    # Refresh every 60s (sudo timeout is usually 300s, but this stays safe)
    while true; do
        sleep 60
        sudo -v 2>/dev/null
    done &
    _sudo_keepalive_pid=$!
}
# Call this on script exit to clean up
disable_sudo_keepalive() {
    if [[ -n "$_sudo_keepalive_pid" ]]; then
        kill "$_sudo_keepalive_pid" 2>/dev/null
        _sudo_keepalive_pid=""
    fi
}
# --- Main Menu Display -------------------------------------------------------
# Function to get menu item by index (simulates array access)
get_menu_item() {
    local index=$1
    case $index in
        0) echo " 0) 💨 ${BO}${GR}Quick Stats${NC}" ;;
        1) echo " 1) 📡 ${BO}${GR}Speed Test${NC}" ;;
        2) echo " 2) 📊 ${BO}${GR}Activity Monitor (Top)${NC}" ;;
        3) echo " 3) ℹ️  ${BO}${GR}System Information${NC}" ;;
        4) echo " 4) 🔄 ${BO}${GR}iCloud Sync Refresh${NC}" ;;
        5) echo " 5) 💿 ${BO}${GR}Disk Image Utility${NC}" ;;
        6) echo " 6) 🔗 ${BO}${GR}Create Symlink${NC}" ;;
        7) echo " 7) ⚙️  ${BO}${GR}macOS Preferences${NC}" ;;
        8) echo " 8) 🕹️  ${BO}${GR}Command Center${NC}" ;;
        9) echo " 9) 🛠️  ${BO}${GR}Settings${NC}" ;;
        *) echo "" ;;
    esac
}
# function for script arguments/aliases
get_menu_aliases() {
    local index=$1
    case $index in
        0)  echo "qs" ;;
        1) echo "st / networkquality / speedtest" ;;
        2)  echo "am / top" ;;
        3) echo "si / sysinfo / info / sp" ;;
        4) echo "isr / icloud / cloudd" ;;
        5) echo "diu / hdiutil" ;;
        6)  echo "cs / ln / symlink" ;;
        7) echo "mp / prefs / defaults" ;;
        8) echo "cc" ;;
        9) echo "s / settings" ;;
        *)  echo "" ;;
    esac
}
# Simple two-column layout (bash 3.2 compatible)
display_two_column_menu() {
    # local num_items=$(get_menu_item_count)
    local num_items=$MAIN_MENU_ITEMS_TOTAL
    local mid_point=$(( (num_items + 1) / 2 ))
    local right_col=53
    local left_offset=10  # Adjust this value to add spacing before left column (e.g., 2 for 2 spaces)
    
    for ((i=0; i<mid_point; i++)); do
        local left_item=$(get_menu_item $i)
        local right_index=$((i + mid_point))
        local right_item=""
        
        if [[ $right_index -lt $num_items ]]; then
            right_item=$(get_menu_item $right_index)
        fi
        
        # Print left column with offset, move cursor to a fixed column, then print right column
        # Use printf padding: %*s creates a field of 'left_offset' width (right-aligned, empty string fills with spaces)
        if [[ $left_offset -gt 0 ]]; then
            printf "%*s%s" $left_offset "" " $left_item"
        else
            printf "%s" " $left_item"
        fi
        printf '\033[%dG' $right_col
        printf "%s\n" "   $right_item"
    done
}
# --- Shared Functions --------------------------------------------------------
is_bundle() {
    local path="${1%/}"
    local ext
    for ext in "${bundle_extensions[@]}"; do
        [[ "$path" == *."$ext" ]] && return 0
    done
    return 1
}
is_quarantined() {
    xattr -p com.apple.quarantine "$1" >/dev/null 2>&1
}
execute_remove_quarantine() {
    if [[ "$apply_recursively" == "true" ]]; then
        local recursive_flag=" -r"
        local xattr_check_cmd="xattr -r"
    else
        local recursive_flag=""
        local xattr_check_cmd="xattr"
    fi

    if $xattr_check_cmd "$path" 2>/dev/null | grep -q "com.apple.quarantine"; then
        if sudo xattr$recursive_flag -d com.apple.quarantine "$path" 2>/dev/null; then
            echo "✅ ${GR}xattr$recursive_flag -d com.apple.quarantine${NC} $display_name"
            ((processed_count++))
        else
            echo "❌ ${RE}xattr$recursive_flag -d com.apple.quarantine${NC} $display_name"
            ((processed_failed++))
        fi
    else
        echo "⚠️  ${YE}Quarantine already removed for:${NC} $display_name"
        ((processed_skipped++))
    fi
}
show_acl_owners() {
    local path="$1"
    local acl_username_color="$2"
    local acl_perms_color="$3"
    local acl_result_label="$4"  # e.g. "${GY}[None]${NC}" or "" to suppress
    local acl_title_label="$5"   # e.g. "${GY}ACLs:${NC} " or "" to suppress
    local acl_lines

    acl_lines=$(ls -led "$path" 2>/dev/null | grep -E "^[[:space:]]*[0-9]+:[[:space:]]user:")
    if [[ -z "$acl_lines" ]]; then
        [[ -n "$acl_result_label" ]] && echo "$acl_result_label"
        return 0
    fi

    local users=() perms=() u p
    while IFS= read -r line; do
        u=$(echo "$line" | sed 's/.*[[:space:]]user:\([^ ]*\).*/\1/')
        p=$(echo "$line" | sed 's/.*allow[[:space:]]*//')
        [[ -z "$u" || "$u" == "$line" ]] && continue
        users+=("$u")
        perms+=("$p")
    done <<< "$acl_lines"
    if [[ "${#users[@]}" -eq 0 ]]; then
        [[ -n "$acl_result_label" ]] && echo "$acl_result_label"
        return 0
    fi

    local joined_users joined_perms
    joined_users=$(IFS=,; echo "${users[*]}")
    joined_perms=$(IFS='|'; echo "${perms[*]}")
    echo "${acl_title_label}${acl_username_color}${joined_users}${NC} ${acl_perms_color}${joined_perms}${NC}"
}
get_signature_status_label() {
    local path="$1"
    # local detail_output
    local verify_output
    local verify_exit
    local assess_output
    local assess_exit
    local status
    local needs_signing=0

    # Step 1: Get detailed signature info
    detail_output=$(codesign -dvvv "$path" 2>&1)

    # Store for later use
    LAST_SIG_DETAIL="$detail_output"
    LAST_SIG_VERIFY=""
    LAST_SIG_ASSESS="$assess_output"

    # Step 2: Check if it's a bundle or standalone executable
    # and verify signatures cryptographically
    local is_bundle=0
    if [[ "$path" == *.app ]] || [[ "$path" == *.app/ ]] || [[ -d "$path" ]]; then
        is_bundle=1
    fi

    # Verify signature (use --verify without --deep for standalone executables)
    if [ $is_bundle -eq 1 ]; then
        verify_output=$(codesign --verify --deep --strict "$path" 2>&1)
        verify_exit=$?
    else
        # For standalone executables, don't use --deep
        verify_output=$(codesign --verify --strict "$path" 2>&1)
        verify_exit=$?
    fi

    # Assess with Gatekeeper (only for .app bundles)
    if [ $is_bundle -eq 1 ] && [[ "$path" == *.app ]] || [[ "$path" == *.app/ ]]; then
        assess_output=$(spctl --assess --type execute -vv "$path" 2>&1)
        assess_exit=$?
    else
        assess_output=""
        assess_exit=1  # Skip assessment for non-bundles
    fi

    LAST_SIG_ASSESS="$assess_output"  # STORE IT

    # Step 3: Extract signature characteristics
    local is_adhoc=$(echo "$detail_output" | grep -q "Signature=adhoc" && echo "yes" || echo "no")
    local is_not_signed=$(echo "$detail_output" | grep -q "code object is not signed at all" && echo "yes" || echo "no")
    local has_apple_authority=$(echo "$detail_output" | grep -q "Authority=Apple" && echo "yes" || echo "no")
    local has_developer_id=$(echo "$detail_output" | grep -q "Authority=Developer ID" && echo "yes" || echo "no")
    local has_notarization=$(echo "$detail_output" | grep -q "Notarization Ticket" && echo "yes" || echo "no")
    local gatekeeper_accepts=$([ $assess_exit -eq 0 ] && echo "yes" || echo "no")
    local verify_passes=$([ $verify_exit -eq 0 ] && echo "yes" || echo "no")

    # Check for signature presence
    local has_signature="no"
    if echo "$detail_output" | grep -q "Signature="; then
        has_signature="yes"
    elif echo "$detail_output" | grep -q "Authority="; then
        has_signature="yes"
    fi

    # Check for missing/unbound bundle
    local missing_bundle="no"
    if echo "$detail_output" | grep -q "Info.plist file that wasn't found"; then
        missing_bundle="yes"
    elif echo "$detail_output" | grep -q "Info.plist=not bound"; then
        missing_bundle="yes"
    fi

    # Step 4: Decision algorithm
    if [[ "$is_not_signed" == "yes" ]]; then
        # Explicitly unsigned
        status="NOT_SIGNED"
    elif [[ "$is_adhoc" == "yes" ]]; then
        # Ad-hoc signature
        status="ADHOC"
    elif [[ "$missing_bundle" == "yes" ]]; then
        # Special case: executable extracted from bundle (CHECK THIS EARLY!)
        if [[ "$has_developer_id" == "yes" ]]; then
            status="EXTRACTED_DEVELOPER_ID"
        elif [[ "$has_apple_authority" == "yes" ]]; then
            status="EXTRACTED_APPLE"
        elif [[ "$has_signature" == "yes" ]]; then
            status="EXTRACTED_SIGNED"
        else
            status="UNKNOWN"
        fi
    elif [[ "$gatekeeper_accepts" == "yes" ]]; then
        # Gatekeeper trusts it - determine type
        if echo "$assess_output" | grep -q "source=Notarized Developer ID"; then
            status="NOTARIZED"
        elif echo "$assess_output" | grep -q "source=Developer ID"; then
            status="DEVELOPER_ID"
        elif echo "$assess_output" | grep -q "source=Mac App Store"; then
            status="APP_STORE"
        elif [[ "$has_apple_authority" == "yes" ]]; then
            status="APPLE_SIGNED"
        else
            status="TRUSTED"
        fi
    elif [[ "$verify_passes" == "yes" ]]; then
        # Signature is cryptographically valid but Gatekeeper doesn't trust it
        # This is the "valid but untrusted" case
        if [[ "$has_developer_id" == "yes" ]]; then
            # Has Developer ID but not trusted (expired, revoked, or invalid cert chain)
            status="UNTRUSTED_DEVELOPER_ID"
        elif [[ "$has_apple_authority" == "yes" ]]; then
            # Has Apple authority but not trusted
            status="UNTRUSTED_APPLE"
        else
            # Signed by someone else, valid signature but not trusted
            status="UNTRUSTED_THIRD_PARTY"
        fi
    elif [[ "$has_signature" == "yes" ]]; then
        # Has a signature but verification failed
        if [[ "$has_developer_id" == "yes" ]] || [[ "$has_apple_authority" == "yes" ]]; then
            # Claims to be from Apple/Developer but signature is broken
            status="INVALID_SIGNATURE"
        else
            # Third-party signature that's broken
            status="INVALID_THIRD_PARTY"
        fi
    else
        # Fallback for edge cases
        status="UNKNOWN"
    fi
    
    # Return just the label
    case "$status" in
        "NOTARIZED")
            SIGNATURE_STATUS="✅ ${GR}[Notarized Developer ID]${NC}"
            NEEDS_SIGNING=0
            ;;
        "DEVELOPER_ID")
            SIGNATURE_STATUS="✅ ${GR}[Developer ID (Signed & Trusted)]${NC}"
            NEEDS_SIGNING=0
            ;;
        "APP_STORE")
            SIGNATURE_STATUS="✅ ${GR}[Mac App Store]${NC}"
            NEEDS_SIGNING=0
            ;;
        "APPLE_SIGNED")
            SIGNATURE_STATUS="✅ ${GR}[Apple Signed]${NC}"
            NEEDS_SIGNING=0
            ;;
        "TRUSTED")
            SIGNATURE_STATUS="✅ ${GR}[Trusted]${NC}"
            NEEDS_SIGNING=0
            ;;
        "ADHOC")
            SIGNATURE_STATUS="⚠️  ${YE}[Ad-hoc Signature] (Valid locally)${NC}"
            NEEDS_SIGNING=0
            ;;
        "UNTRUSTED_DEVELOPER_ID")
            SIGNATURE_STATUS="⚠️  ${YE}[Developer ID - ${RE}Untrusted Certificate]${NC}"
            NEEDS_SIGNING=1
            ;;
        "UNTRUSTED_APPLE")
            SIGNATURE_STATUS="⚠️  ${YE}[Apple Certificate - ${RE}Untrusted]${NC}"
            NEEDS_SIGNING=1
            ;;
        "UNTRUSTED_THIRD_PARTY")
            SIGNATURE_STATUS="⚠️  ${YE}[Third-Party Certificate - ${RE}Untrusted]${NC}"
            NEEDS_SIGNING=1
            ;;
        "INVALID_SIGNATURE")
            SIGNATURE_STATUS="❌ ${RE}[Invalid Signature] (Tampered or Corrupted)${NC}"
            NEEDS_SIGNING=1
            ;;
        "INVALID_THIRD_PARTY")
            SIGNATURE_STATUS="❌ ${RE}[Invalid Third-Party Signature]${NC}"
            NEEDS_SIGNING=1
            ;;
        "NOT_SIGNED")
            SIGNATURE_STATUS="❌ ${RE}[Not Signed]${NC}"
            NEEDS_SIGNING=1
            ;;
        "EXTRACTED_DEVELOPER_ID")
            SIGNATURE_STATUS="⚠️  ${YE}[Signed by Developer ID]${NC} ${RE}(Missing or inaccessible bundle)${NC}"
            NEEDS_SIGNING=1  # Needs re-signing in bundle context
            ;;
        "EXTRACTED_APPLE")
            SIGNATURE_STATUS="⚠️  ${YE}[Signed by Apple]${NC} ${RE}(Missing or inaccessible bundle)${NC}"
            NEEDS_SIGNING=1  # Needs re-signing in bundle context
            ;;
        "EXTRACTED_SIGNED")
            SIGNATURE_STATUS="⚠️  ${YE}[Signed]${NC} ${RE}(Missing or inaccessible bundle)${NC}"
            NEEDS_SIGNING=1  # Needs re-signing in bundle context
            ;;
        "UNKNOWN")
            # SIGNATURE_STATUS="? ${GY}[Unknown Status]${NC}"
            SIGNATURE_STATUS="${GY}[N/A]${NC}"
            NEEDS_SIGNING=1
            ;;
    esac
}
quick_picker() {
    local backed_up_paths_to_process
    local changes_made=false
    # restore_functions_current_paths_to_process() {
        # if [[ "${#backed_up_paths_to_process[@]}" -gt 0 ]]; then

    # }

    # backup paths_to_process if currently populated in another function, so that we can restore it in case no changes were made here
    if [[ "${#paths_to_process[@]}" -gt 0 ]]; then
        backed_up_paths_to_process=("${paths_to_process[@]}")
    fi

    while true; do
        trap - SIGINT
        interrupted=false
        trap 'echo; return' SIGINT
        resize_terminal 95 24
        clear
        if [[ "$used_keyboard_shortcut_p" == "true" ]]; then
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}🛣️  Path Picker${NC} ${BK}${RE}[Quick Picker]${NC}" "${GY}(Use Q to jump back to previous menu)${NC}" "96"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo "↩ Previous Menu"
            # echo
            echo_centered "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}^C/Q${NC} Exit Quick Picker"
            echo
            if [[ "$DisableWelcomeText_QuickMenus" == "false" ]]; then
                echo_centered "${GR}Welcome to Quick Picker${NC}"
                echo
                echo_centered "${BO}Instant access to Path Picker at any time, in any menu.${NC}"
                echo_centered "${BO}Without ever losing your place.${NC}"
                echo
            fi
        elif [[ "$used_keyboard_shortcut_s" == "true" ]]; then
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}🛣️  Path Picker${NC} ${BK}${RE}[Quick Settings]${NC}" "${GY}(Use Q to jump back to previous menu)${NC}" "96"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo "↩ Manage Saved Paths"
            echo
            echo_centered "${BL}⮑ ${NC} Continue | ${BL}B/^C${NC} Back | ${BL}Q${NC} Exit Quick Settings"
            echo
        elif [[ "$came_from_settings_manage_saved_paths_path_picker" == "true" ]]; then
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}🛣️  Path Picker${NC} [Save New Paths]" "" "96"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo "↩ Manage Saved Paths"
            echo
            echo_centered "${BL}⮑ ${NC} Continue | ${BL}B/^C${NC} Back | ${BL}Q${NC} Main Menu"
            echo
        elif [[ "$came_from_command_center_path_picker" == "true" ]]; then
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}🛣️  Path Picker [Save New Paths]${NC}" "" "96"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo "↩ Home [Command Center]"
            echo
            echo_centered "${BL}⮑ ${NC} Continue | ${BL}B/^C${NC} Back | ${BL}Q${NC} Main Menu"
            echo
        else # came from somewhere else
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}🛣️  Path Picker [Save New Paths]${NC}" "" "96"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo "↩ Manage Saved Paths"
            echo
            echo_centered "${BL}⮑ ${NC} Continue | ${BL}B/^C${NC} Back | ${BL}Q${NC} Main Menu"
            echo
        fi

        echo "${GR}Please provide path(s) to a file or folder.${NC}"
        echo
        echo "${BO}Path Picker Options:${NC}  ${GY}(or use drag & drop)${NC}"
        echo " 1) 📂 ${GR}Reveal Finder ${NC} ${GY}(for Drag & Drop)${NC}"
        echo " 2) 📄 ${GR}Choose file(s)${NC} ${GY}(via Finder dialog)${NC}"
        echo " 3) 📁 ${GR}Choose folder ${NC} ${GY}(via Finder dialog)${NC}"
        if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
            echo " 4) 💾 ${GR}Use saved $path_or_paths${NC} (${#saved_paths_to_process[@]})"
            echo " 5) 🗑️  ${GR}Clear saved $path_or_paths${NC} (${#saved_paths_to_process[@]})"
        fi
        echo
        echo "⬇️  ${GR}Drag & drop multiple files/folders onto this window, then press Enter.${NC}"
        echo "   ${GY}Tip: You can also press ⌥⌘C to copy multiple files/folders as a pathname${NC}"
        echo
        read -rp "" input
        handle_navigation_input "$input"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then
            if [[ "$changes_made" == "true" ]]; then
                # restore paths_to_process since user came back after making changes
                paths_to_process=("${backed_up_paths_to_process[@]}")
            fi
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            if [[ "$changes_made" == "true" ]]; then
                # restore paths_to_process since user came back after making changes
                paths_to_process=("${backed_up_paths_to_process[@]}")
            fi
            return 0
        elif [[ $nav -eq $NAV_REFRESH ]]; then 
            continue
        fi

        # Handle Path Picker Options (all input methods flow into paths_to_process)

        case "$input" in
            1) open /System/Library/CoreServices/Finder.app; continue ;;
            2)
                # don't make local so that we can access things if already in other sub-menu function
                # a backup was made above in order to restore items in case no changes were made
                paths_to_process=()
                changes_made=true

                # Open Finder open panel (for files)
                local selected_paths=$(osascript -e 'try' \
                                -e 'set fileList to choose file with prompt "Choose files to remove quarantine" with multiple selections allowed' \
                                -e 'set pathList to {}' \
                                -e 'repeat with aFile in fileList' \
                                -e '    set end of pathList to POSIX path of aFile' \
                                -e 'end repeat' \
                                -e 'set AppleScript'"'"'s text item delimiters to linefeed' \
                                -e 'set pathString to pathList as text' \
                                -e 'return pathString' \
                                -e 'on error' \
                                -e 'return ""' \
                                -e 'end try')
                if [[ -n "$selected_paths" ]]; then
                    while IFS= read -r line; do
                        if [[ -n "$line" ]]; then
                            # Normalize path by removing trailing slash
                            line="${line%/}"
                            paths_to_process+=("$line")
                        fi
                    done <<< "$selected_paths"
                else
                    echo "❌ ${RE}No selection made.${NC}"
                    echo -n "   Please try again. "
                    read -r -t 1 -n 1
                    continue
                fi
                ;;
            3)
                # don't make local so that we can access things if already in other sub-menu function
                # a backup was made above in order to restore items in case no changes were made
                paths_to_process=()
                changes_made=true
                
                # Open Finder open panel (for folders)
                local selected_path=$(osascript -e 'try' \
                                -e 'set p to POSIX path of (choose folder with prompt "Choose a folder to remove quarantine")' \
                                -e 'return p' \
                                -e 'on error' \
                                -e 'return ""' \
                                -e 'end try')
                if [[ -n "$selected_path" && -e "$selected_path" ]]; then
                    # Normalize path by removing trailing slash
                    selected_path="${selected_path%/}"
                    paths_to_process=("$selected_path")
                else
                    echo "❌ ${RE}No selection made.${NC}"
                    echo -n "   Please try again. "
                    read -r -t 1 -n 1
                    continue
                fi
                ;;
            4) 
                if [[ "$came_from_command_center_path_picker" == "true" ]] || [[ "$used_keyboard_shortcut_p" == "true" ]]; then
                    echo
                    echo -n "✅ ${GR}Using saved $path_or_paths.${NC} "
                    read -r -t 1 -n 1
                fi
                return 0 
                ;;
            5)
                if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                    echo "❌ ${RE}No saved path(s) to clear.${NC}"
                    echo -n "   Please provide path(s) again. "
                    read -r -t 3 -n 1
                    continue
                else
                    # Clear Saved Path(s)
                    trap - SIGINT
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                    show_clear_saved_paths_prompt
                    read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " input
                    handle_navigation_input "$input"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        if [[ "$changes_made" == "true" ]]; then
                            # restore paths_to_process
                            paths_to_process=("${backed_up_paths_to_process[@]}")
                        fi
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        continue
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    fi

                    case $input in
                        y|Y)
                            clear_saved_path_data
                            if [[ "$came_from_command_center_path_picker" == "true" ]] || [[ "$used_keyboard_shortcut_p" == "true" ]]; then
                                echo
                                echo -n "✅ ${GR}Cleared all saved paths.${NC} "
                                read -r -t 1 -n 1
                            fi
                            continue
                            ;;
                        *)
                            # echo -n "❌ ${RE}Cancelled.${NC} "
                            # read -r -t 1 -n 1
                            continue
                            ;;
                    esac
                fi
                ;;
            /)
                echo "❌ ${RE}The root directory cannot be chosen.${NC}"
                echo -n "   Please provide another path. "
                read -r -t 3 -n 1
                continue
                ;;
            *)
                # don't make local so that we can access things if already in other sub-menu function
                # a backup was made above in order to restore paths_to_process in case no changes were made
                paths_to_process=()
                changes_made=true
                
                # Process drag & drop input to handle escaped spaces and quoted paths
                eval "set -- $input"

                local arg_count=$#

                if [[ "$arg_count" -eq 0 ]]; then
                    echo "❌ ${RE}No paths provided.${NC}"
                    echo -n "   Please try again. "
                    read -r -t 1 -n 1
                    continue
                fi

                local invalid_paths=()

                # Process each input path
                for path in "$@"; do
                    if [[ -e "$path" ]]; then
                        paths_to_process+=("$path")
                    else
                        invalid_paths+=("$path")
                    fi
                done

                # check if there are valid paths to process
                if [[ "${#paths_to_process[@]}" -eq 0 ]]; then
                    echo "❌ ${RE}No valid files to process.${NC}"
                    echo -n "   Please try again. "
                    read -r -t 1 -n 1
                    continue
                fi

                if [[ "${#invalid_paths[@]}" -gt 0 ]]; then
                    show_invalid_path_prompt
                    read -rp "➡️  ${GR}Press Enter to continue with valid paths (or ${BL}nav${NC} ${GR}choice):${NC} " input
                    handle_navigation_input "$input"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        # restore paths_to_process
                        if [[ "${#backed_up_paths_to_process[@]}" -gt 0 ]]; then
                            paths_to_process=("${backed_up_paths_to_process[@]}")
                        fi
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        continue
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    fi
                fi
                ;;
        esac

        # Handle Saved Paths
        # if   [[ "$DontAskAgainAbout_SavingPaths_Path_Picker" == "true" ]]; then
        #     sort_paths_to_process_without_defs
        #     path_count="${#paths_to_process[@]}"
        # elif [[ "$use_saved_paths" == "true" ]]; then
        #     use_saved_paths=false
        #     paths_to_process=("${valid_paths[@]}")
        #     path_count="${#paths_to_process[@]}"
        if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
            # # Prompt to Save Path(s)
            # trap - SIGINT
            # trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
            
            sort_paths_to_process_with_defs
            saved_paths_to_process=("${paths_to_process[@]}")
            save_paths_to_file

            # if already in another function using paths_to_process, the new paths_to_process here now replace it. Not sure yet if this is ideal. To be determined...
            
            if [[ "$came_from_command_center_path_picker" == "true" ]] || [[ "$used_keyboard_shortcut_p" == "true" ]]; then
                echo
                echo -n "✅ ${GR}$path_or_paths saved.${NC} "
                read -r -t 1 -n 1
            fi
            # path_count="${#paths_to_process[@]}"

            # show_save_path_confirmation
            # read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
            # handle_navigation_input "$saved_paths_choice"
            # nav=$?
            # if   [[ $nav -eq $NAV_QUIT ]]; then
            #     return 0
            # elif [[ $nav -eq $NAV_BACK ]]; then 
            #     continue
            # elif [[ $nav -eq $NAV_REFRESH ]]; then 
            #     continue
            # # elif handle_main_menu_AZ_navigation_input "$saved_paths_choice" "$main_menu_choice"; then
            # #     return
            # fi

            # case $saved_paths_choice in
            #     1)
            #         saved_paths_to_process=("${paths_to_process[@]}")
            #         save_paths_to_file
            #         ;;
            #     2)
            #         DontAskAgainAbout_SavingPaths_Path_Picker="true"
            #         save_pref "DontAskAgainAbout_SavingPaths_Path_Picker" "true"
            #         ;;
            # esac
            return 0
        elif [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
            # if [[ "$DontAskAgainAbout_OverwritingPaths_Path_Picker" == "false" ]]; then
            # Prompt to Overwrite Saved Path(s)
            trap - SIGINT
            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

            sort_paths_to_process_without_defs
            # path_count="${#paths_to_process[@]}"
            
            show_overwrite_saved_path_confirmation
            read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                # restore backed up items in case already in another sub-menu function
                if [[ "${#backed_up_paths_to_process[@]}" -gt 0 ]]; then
                    paths_to_process=("${backed_up_paths_to_process[@]}")
                fi
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                continue
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue
            fi
            
            case $input in
                y|Y)
                    saved_paths_to_process=("${paths_to_process[@]}")
                    save_paths_to_file
                    set_plurality_for_saved_paths_to_process
                    
                    # if already in another function using paths_to_process, the new paths_to_process here now replace it. Not sure yet if this is ideal. To be determined...

                    if [[ "$came_from_command_center_path_picker" == "true" ]] || [[ "$used_keyboard_shortcut_p" == "true" ]]; then
                        echo
                        echo -n "✅ ${GR}New $path_or_paths saved.${NC} "
                        read -r -t 1 -n 1
                    fi
                    return 0
                    # echo -n "✅ ${GR}Overwritten.${NC} "
                    # read -r -t 1 -n 1
                    ;;
                *)
                    # User declined overwrite — restore original paths_to_process and loop
                    if [[ "${#backed_up_paths_to_process[@]}" -gt 0 ]]; then
                        paths_to_process=("${backed_up_paths_to_process[@]}")
                    else
                        paths_to_process=()
                    fi
                    changes_made=false
                    continue
                    
                    # echo -n "❌ ${RE}Cancelled.${NC} "
                    # read -r -t 1 -n 1
                    # Continue with provided path(s) without overwriting
                    # continue
                    ;;
            esac

            # else
            #     # Overwrite with provided path(s)
            #     saved_paths_to_process=("${paths_to_process[@]}")
            #     save_paths_to_file
            #     set_plurality_for_saved_paths_to_process
            #     if [[ "$came_from_command_center_path_picker" == "true" ]] || [[ "$used_keyboard_shortcut_p" == "true" ]]; then
            #         echo
            #         echo -n "✅ ${GR}New $path_or_paths saved.${NC} "
            #         read -r -t 1 -n 1
            #     fi
            #     return 0

            #     # # Continue with provided path(s) without overwriting
            #     # sort_paths_to_process_without_defs
            #     # path_count="${#paths_to_process[@]}"
            # fi
        else
            # Should never reach here - all states covered above
            
            sort_paths_to_process_without_defs
            # path_count="${#paths_to_process[@]}"
        fi
    done
    return 0
}
# --- Main Functions ----------------------------------------------------------
#========= 🛠️ OneCommand Main Menu
main_menu() {
    while true; do
        trap - SIGINT
        # If we have a pending choice from handle_main_menu_AZ_navigation_input, skip menu display
        if [[ -z "$current_main_menu_choice" ]]; then
            resize_terminal 95 24
            clear
            display_OneCommand_header_for_95px
            echo
            echo_centered "${BO}Choose a task:${NC}"
            echo
            display_two_column_menu
            echo
            echo
            echo
            echo_centered "${BL}⮑ ${NC} Continue | ${BL}B${NC} Back | ${BL}A${NC} Previous | ${BL}Z${NC} Next | ${BL}P${NC} Path Picker | ${BL}S${NC} Settings | ${BL}Q${NC} Main Menu | ${BL}^C${NC} Exit"
            echo
            echo_n_centered "➡️  ${GR}Enter your choice (or ${BL}nav${NC} ${GR}choice):${NC} "
            read -r main_menu_choice
            handle_navigation_input "$main_menu_choice"
            nav=$?
            if   [[ $nav -eq $NAV_BACK ]]; then 
                echo_n_centered "❌ ${RE}Nothing to go back to.${NC} ${BO}Use ^C to exit.${NC} "
                read -r -t 1 -n 1
                continue
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue
            elif [[ "$main_menu_choice" == "a" ]] || [[ "$main_menu_choice" == "A" ]]; then
                main_menu_choice=9
            elif [[ "$main_menu_choice" == "z" ]] || [[ "$main_menu_choice" == "Z" ]]; then
                main_menu_choice=0
            elif [[ $nav -eq $NAV_QUIT ]]; then 
                echo_n_centered "❌ ${RE}Invalid choice.${NC} ${BO}Use ^C to exit.${NC} "
                read -r -t 1 -n 1
                continue
            fi 
        else
            # Use the pending choice from A/Z navigation
            main_menu_choice="$current_main_menu_choice"
            current_main_menu_choice=""
        fi

        case $main_menu_choice in
            0) quick_stats ;;
            1) speed_test ;;
            2) top_activity_monitor ;;
            3) system_information ;;
            4) icloud_sync_refresh ;;
            5) disk_image_utility ;;
            6) create_symlink ;;
            7) macos_preferences ;;
            8) command_center ;;
            9) 
                came_from_main_menu=true
                quick_settings 
                came_from_main_menu=false
                ;;
            *) 
                echo_n_centered "❌ ${RE}Invalid choice.${NC} Please try again. "
                read -r -t 1 -n 1
                continue
                ;;
        esac
    done
}
#====0==== 💨 quick_stats
function quick_stats() {
    # Quick Stats

    STAT_INDENT="   "   # set to "" to remove all stat indenting globally
    HC=${NC}  # header color
    sha_algo=256
    # Formatting for ACL display
    local acl_username_color="$GR" acl_perms_color="$BL" acl_result_label="${GY}[None]${NC}" acl_title_label=""

    if true; then    # only used to quickly collapse functions below
        # ─────────────────────────────────────────────────────────────────
        # HELPERS
        # ─────────────────────────────────────────────────────────────────

        # Converts raw bytes to human-readable string.
        # Uses bc if available, awk as fallback.
        format_size() {
            local bytes="$1"
            if [[ -z "$bytes" || "$bytes" == "Unknown" ]]; then
                echo "Unknown"
                return
            fi
            if command -v bc >/dev/null 2>&1; then
                if   (( bytes >= 1073741824 )); then echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
                elif (( bytes >= 1048576    )); then echo "$(echo "scale=2; $bytes/1048576"    | bc) MB"
                elif (( bytes >= 1024       )); then echo "$(echo "scale=2; $bytes/1024"       | bc) KB"
                else echo "${bytes} B"
                fi
            else
                awk -v bytes="$bytes" 'BEGIN {
                    if      (bytes >= 1073741824) printf "%.2f GB", bytes/1073741824
                    else if (bytes >= 1048576)    printf "%.2f MB", bytes/1048576
                    else if (bytes >= 1024)       printf "%.2f KB", bytes/1024
                    else                          printf "%d B",    bytes
                }'
            fi
        }

        # Returns raw byte count for a file.
        # stat -f%z is macOS syntax; -c%s fallback covers Linux if ever needed.
        get_file_size_bytes() {
            local path="$1"
            local size=""
            size=$(stat -f%z "$path" 2>/dev/null)
            [[ -z "$size" ]] && size=$(stat -c%s "$path" 2>/dev/null)
            [[ -z "$size" ]] && size=$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}')
            echo "${size:-0}"
        }

        # Returns a formatted ACL string for user: entries, or 'None'.
        # Called by _print_permissions — not printed directly.
        # show_acl_owners(){}  # used at top of script under 'Shared Execution Functions"

        # Formats an arch string (output of lipo -archs) into a colored display label.
        format_arches_display() {
            local arches_str="$1"
            local arch_array=($arches_str)
            local arch_count=${#arch_array[@]}

            if [[ $arch_count -eq 1 ]]; then
                local arch="${arch_array[0]}"
                case "$arch" in
                    arm64|arm64e) echo "${GR}ARM Only${NC} ($arch)"   ;;
                    x86_64|i386)  echo "${BL}Intel Only${NC} ($arch)" ;;
                    *)             echo "${YE}Other${NC} ($arch)"      ;;
                esac
            else
                echo "${MA}Universal${NC} ($arches_str)"
            fi
        }

        # Returns 0 if the file is a Mach-O binary, 1 otherwise.
        is_macho_file() {
            file "$1" 2>/dev/null | grep -q "Mach-O"
        }

        # # Returns lipo -archs output for a file, with result caching.
        # # Cache arrays must be declared in the parent function scope:
        # #   local arch_cache_files=()
        # #   local arch_cache_results=()
        # get_archs_cached() {
        #     local _file="$1"
        #     local _idx=0

        #     for cached_file in "${arch_cache_files[@]}"; do
        #         if [[ "$cached_file" == "$_file" ]]; then
        #             echo "${arch_cache_results[$_idx]}"
        #             return 0
        #         fi
        #         (( _idx++ ))
        #     done

        #     local _archs
        #     _archs=$(lipo -archs "$_file" 2>/dev/null)
        #     arch_cache_files+=("$_file")
        #     if [[ $? -eq 0 && -n "$_archs" ]]; then
        #         arch_cache_results+=("$_archs")
        #         echo "$_archs"
        #         return 0
        #     else
        #         arch_cache_results+=("")
        #         return 1
        #     fi
        # }

        # Returns space-separated arch string for a file, with result caching.
        # Uses `file` instead of `lipo` — no Xcode CLT required.
        # Cache arrays must be declared in the parent function scope:
        #   local arch_cache_files=()
        #   local arch_cache_results=()
        get_archs_cached() {
            local _file="$1"
            local _idx=0
            for cached_file in "${arch_cache_files[@]}"; do
                if [[ "$cached_file" == "$_file" ]]; then
                    echo "${arch_cache_results[$_idx]}"
                    [[ -n "${arch_cache_results[$_idx]}" ]] && return 0 || return 1
                fi
                (( _idx++ ))
            done

            local file_output
            file_output=$(file "$_file" 2>/dev/null)

            local _archs=""
            if echo "$file_output" | grep -q "universal binary"; then
                # e.g. "... [x86_64:Mach-O ...] [arm64:Mach-O ...]"
                # Extract the arch token from each bracketed section
                _archs=$(echo "$file_output" \
                    | grep -oE '\[[a-z0-9_]+[]:]' \
                    | tr -d '[' \
                    | tr -d ':' \
                    | tr -d ']' \
                    | tr '\n' ' ' \
                    | sed 's/ *$//')
            else
                # e.g. "foo: Mach-O 64-bit executable arm64"
                local last_word
                last_word=$(echo "$file_output" | awk '{print $NF}')
                case "$last_word" in
                    arm64|arm64e|x86_64|i386) _archs="$last_word" ;;
                esac
            fi

            arch_cache_files+=("$_file")
            if [[ -n "$_archs" ]]; then
                arch_cache_results+=("$_archs")
                echo "$_archs"
                return 0
            else
                arch_cache_results+=("")
                return 1
            fi
        }

        # Sets globals: SIGNATURE_STATUS, NEEDS_SIGNING, LAST_SIG_DETAIL, LAST_SIG_ASSESS.
        # NOTE: uses a local variable named is_bundle=0 (shadows the is_bundle() function
        # within this function's scope only — no impact on callers).
        # get_signature_status_label() {}  # used at top of script under 'Shared Execution Functions"

        # Resolves a bundle's main executable path and echoes it.
        # Returns 1 (and prints nothing) if resolution fails.
        # Shared by _hash_bundle and _print_arch — single source of truth.
        _resolve_bundle_executable() {
            local path="$1"
            local bundle_plist="$path/Contents/Info.plist"
            local executable_name
            executable_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$bundle_plist" 2>/dev/null)

            [[ -z "$executable_name" ]] && return 1

            if   [[ -f "$path/Contents/MacOS/$executable_name" ]];   then echo "$path/Contents/MacOS/$executable_name"
            elif [[ -f "$path/Versions/Current/$executable_name" ]]; then echo "$path/Versions/Current/$executable_name"
            elif [[ -f "$path/$executable_name" ]];                  then echo "$path/$executable_name"
            else return 1
            fi
        }

        # ── Stat helpers ──────────────────────────────────────────────────
        # All stat output uses $STAT_INDENT for leading whitespace.
        # Set STAT_INDENT="" in shared config to remove all indenting globally.
        # Signature detail sub-lines use double-indent (${STAT_INDENT}${STAT_INDENT}).

        # Prints indented quarantine result line.
        # Skipped for broken symlinks (caller's responsibility).
        _print_quarantine_status() {
            if is_quarantined "$1"; then
                echo "${STAT_INDENT}🛡️  ${HC}Quarantine Status:${NC} ${RE}[Quarantined]${NC}"
                # quarantine_removal_needed=1
            else
                echo "${STAT_INDENT}🛡️  ${HC}Quarantine Status:${NC} ${GR}[Not Quarantined]${NC}"
            fi
        }

        # Prints indented permissions line: owner:group  sym  [octal]  ACLs (if any).
        # Checked on bundle root, not inner executable.
        # Skipped for broken symlinks (caller's responsibility).
        _print_permissions() {
            local path="$1"
            local perms_sym_raw perms_num perms_sym_fmt owner group acl_info
            perms_sym_raw=$(stat -f "%Sp" "$path" 2>/dev/null)
            perms_num=$(stat -f "%A"  "$path" 2>/dev/null)
            perms_sym_fmt="${perms_sym_raw:1:3}|${perms_sym_raw:4:3}|${perms_sym_raw:7:3}"
            owner=$(stat -f "%Su" "$path" 2>/dev/null)
            group=$(stat -f "%Sg" "$path" 2>/dev/null)
            acl_info=$(show_acl_owners "$path" "$acl_username_color" "$acl_perms_color" "$acl_result_label" "$acl_title_label")
            # echo "${STAT_INDENT}${GY}$owner:$group${NC} ${BL}$perms_sym_fmt${NC} ${BL}[$perms_num]${NC}${acl_info:+ $acl_info}"
            echo "${STAT_INDENT}👥 ${HC}Owner:Group:${NC} ${GR}$owner:$group${NC}"
            echo "${STAT_INDENT}🔐 ${HC}Permissions:${NC} ${GR}$perms_sym_fmt${NC} ${GY}[$perms_num]${NC}"
            echo "${STAT_INDENT}🗝️  ${HC}ACLs:${NC} ${acl_info}"
        }

        # Prints indented xattr list, or [None] if absent.
        # Lists all xattrs — quarantine is included here if present.
        # Skipped for broken symlinks (caller's responsibility).
        _print_xattrs() {
            local path="$1"
            local xattrs
            xattrs=$(xattr "$path" 2>/dev/null | tr '\n' ',' | sed 's/,$//; s/,/, /g')
            if [[ -n "$xattrs" ]]; then
                echo "${STAT_INDENT}🏷️  ${HC}Xattrs:${NC} ${GR}${xattrs}${NC}"
            else
                echo "${STAT_INDENT}🏷️  ${HC}Xattrs: ${GY}[None]${NC}"
            fi
        }

        # Prints indented true file type from the 'file' command (strips path prefix).
        # Called for files and symlinks-to-files only — dirs and bundles are skipped
        # since their type is already structurally known.
        # Skipped for broken symlinks (caller's responsibility).
        _print_file_type() {
            local path="$1"
            local file_type
            file_type=$(file "$path" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//')
            if [[ -n "$file_type" ]]; then
                echo "${STAT_INDENT}🩻 ${HC}File Type:${NC} ${GR}${file_type}${NC}"
            else
                echo "${STAT_INDENT}🩻 ${HC}File Type:${NC} ${GY}[Unknown]${NC}"
            fi
        }

        # Prints indented human-readable size.
        # Dirs and bundles use du -sk (recursive total); files use get_file_size_bytes.
        # Skipped for broken symlinks (caller's responsibility).
        _print_size() {
            local path="$1"
            local size_bytes size
            if [[ -d "$path" ]]; then
                size_bytes=$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}')
            else
                size_bytes=$(get_file_size_bytes "$path")
            fi
            size=$(format_size "${size_bytes:-0}")
            echo "${STAT_INDENT}📏 ${HC}Size:${NC} ${GR}${size}${NC}"
        }

        # Prints indented binary architecture info.
        # Accepts any path type — resolves bundle executables internally via
        # _resolve_bundle_executable. Non-Mach-O files print [Not a binary].
        # Regular (non-bundle) dirs are skipped — caller's responsibility not to call.
        # Skipped for broken symlinks (caller's responsibility).
        # Requires in parent function scope:
        #   local arch_cache_files=()
        #   local arch_cache_results=()
        #   local arm64_count=0 x86_64_count=0 universal_count=0 other_arch_count=0
        _print_arch() {
            local path="$1"
            local target_path="$path"

            if [[ -d "$path" ]] && is_bundle "$path"; then
                target_path=$(_resolve_bundle_executable "$path")
                if [[ -z "$target_path" ]]; then
                    echo "${STAT_INDENT}🧬 ${HC}Architecture:${NC} ${GY}N/A - executable not resolved${NC}"
                    return
                fi
            fi

            if ! is_macho_file "$target_path"; then
                echo "${STAT_INDENT}🧬 ${HC}Architecture:${NC} ${GY}Not a binary${NC}"
                return
            fi

            local lipo_output
            lipo_output=$(get_archs_cached "$target_path")
            if [[ $? -ne 0 || -z "$lipo_output" ]]; then
                echo "${STAT_INDENT}🧬 ${HC}Architecture:${NC} ${GY}N/A${NC}"
                return
            fi

            local arch_array=($lipo_output)
            local arch_count=${#arch_array[@]}
            if [[ $arch_count -eq 1 ]]; then
                case "${arch_array[0]}" in
                    arm64|arm64e) (( arm64_count++      )) ;;
                    x86_64|i386)  (( x86_64_count++     )) ;;
                    *)             (( other_arch_count++ )) ;;
                esac
            else
                (( universal_count++ ))
            fi

            local arches_display
            arches_display=$(format_arches_display "$lipo_output")
            echo "${STAT_INDENT}🧬 ${HC}Architecture:${NC} $arches_display"
        }

        # Prints indented signature status + detail sub-lines
        # (Identifier, TeamIdentifier, Authority, Signature, Notarization Ticket).
        # Detail sub-lines use double-indent (${STAT_INDENT}${STAT_INDENT}).
        # For bundles, codesign runs on the bundle root.
        # Skipped for broken symlinks (caller's responsibility).
        # Requires in parent function scope:
        #   local adhoc_signature_needed=0
        _print_signature() {
            local path="$1"

            get_signature_status_label "$path"

            echo "${STAT_INDENT}✍️  ${HC}Signature:${NC} $SIGNATURE_STATUS"

            # [[ "$NEEDS_SIGNING" -eq 1 ]] && adhoc_signature_needed=1

            # Detail sub-lines — always shown in Quick Stats (no scan_depth gating).
            # Double-indented so they nest visually under the sig: label.
            local detail_lines
            detail_lines=$(
                {
                    echo "$LAST_SIG_DETAIL" | grep "^Identifier="       | grep -v "^TeamIdentifier="
                    echo "$LAST_SIG_DETAIL" | grep "^TeamIdentifier="
                    echo "$LAST_SIG_DETAIL" | grep "^Authority="
                    echo "$LAST_SIG_DETAIL" | grep "^Signature="
                    echo "$LAST_SIG_DETAIL" | grep "^Notarization Ticket="
                } | grep -v "^$"
            )
            if [[ -n "$detail_lines" ]]; then
                echo "${GY}$detail_lines${NC}" | sed "s/^/${STAT_INDENT}${STAT_INDENT}/"
                # echo "$detail_lines" | sed 's/^/    /'
            fi
        }

        # Resolves, hashes, and prints a bundle's main executable.
        # Refactored to use _resolve_bundle_executable.
        # Prints only indented result line(s) — caller prints the name line.
        _hash_bundle() {
            local path="$1"
            local executable_path
            executable_path=$(_resolve_bundle_executable "$path")

            if [[ -z "$executable_path" ]]; then
                local bundle_plist="$path/Contents/Info.plist"
                local executable_name
                executable_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$bundle_plist" 2>/dev/null)
                if [[ -z "$executable_name" ]]; then
                    echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GY}[No CFBundleExecutable found]${NC}"
                else
                    echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GY}[Executable not found: $executable_name]${NC}"
                fi
                return
            fi

            local rel_path="${executable_path#$path/}"
            local hash_result
            hash_result=$(shasum -a "$sha_algo" "$executable_path" 2>/dev/null | awk '{print $1}')
            if [[ -n "$hash_result" ]]; then
                echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo${NC} ${GY}($rel_path):${NC} ${GR}${hash_result}${NC}"
            else
                echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo${NC} ${GY}($rel_path): [N/A]${NC}"
            fi
        }
    fi

    while true; do
        if [[ "$DisablePathPickerWhenPathsAreSaved_Quick_Stats" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
            local paths_to_process=()
            paths_to_process=("${saved_paths_to_process[@]}")
            path_count="${#paths_to_process[@]}"
        else
            trap 'return' SIGINT
            resize_terminal 95 24
            clear
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}0) 💨 Quick Stats${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "94"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "↩ Main Menu" "Summary ↪"
            show_nav_prompt_with_AZ_centered
            show_path_picker_options
            read -rp "" input
            handle_navigation_input "$input"
            nav=$?
            if   [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then 
                return 0
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue
            elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                return
            fi

            # Handle Path Picker Options (all input methods flow into paths_to_process)
            local paths_to_process=()

            case "$input" in
                1) open /System/Library/CoreServices/Finder.app; continue ;;
                2)
                    # Open Finder open panel (for files)
                    local selected_paths=$(osascript -e 'try' \
                                    -e 'set fileList to choose file with prompt "Choose files to process" with multiple selections allowed' \
                                    -e 'set pathList to {}' \
                                    -e 'repeat with aFile in fileList' \
                                    -e '    set end of pathList to POSIX path of aFile' \
                                    -e 'end repeat' \
                                    -e 'set AppleScript'"'"'s text item delimiters to linefeed' \
                                    -e 'set pathString to pathList as text' \
                                    -e 'return pathString' \
                                    -e 'on error' \
                                    -e 'return ""' \
                                    -e 'end try')
                    if [[ -n "$selected_paths" ]]; then
                        while IFS= read -r line; do
                            if [[ -n "$line" ]]; then
                                # Normalize path by removing trailing slash
                                line="${line%/}"
                                paths_to_process+=("$line")
                            fi
                        done <<< "$selected_paths"
                    else
                        echo "❌ ${RE}No selection made.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi
                    ;;
                3)
                    # Open Finder open panel (for folders)
                    local selected_path=$(osascript -e 'try' \
                                    -e 'set p to POSIX path of (choose folder with prompt "Choose a folder to process")' \
                                    -e 'return p' \
                                    -e 'on error' \
                                    -e 'return ""' \
                                    -e 'end try')
                    if [[ -n "$selected_path" && -e "$selected_path" ]]; then
                        # Normalize path by removing trailing slash
                        selected_path="${selected_path%/}"
                        paths_to_process=("$selected_path")
                    else
                        echo "❌ ${RE}No selection made.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi
                    ;;
                4)
                    if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No saved path(s) found.${NC}"
                        echo -n "   Please provide path(s) again. "
                        read -r -t 3 -n 1
                        continue
                    fi

                    local valid_paths=()
                    local invalid_paths=()

                    # Validate saved paths still exist
                    for saved_path in "${saved_paths_to_process[@]}"; do
                        if [[ -e "$saved_path" ]]; then
                            valid_paths+=("$saved_path")
                        else
                            invalid_paths+=("$saved_path")
                        fi
                    done

                    # check if there are valid paths to process
                    if [[ "${#valid_paths[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No valid saved path(s) to process.${NC}"
                        echo -n "   Please provide path(s) again. "
                        read -r -t 3 -n 1
                        continue
                    fi

                    if [[ "${#invalid_paths[@]}" -gt 0 ]]; then
                        show_invalid_path_prompt
                        read -rp "➡️  ${GR}Press Enter to continue with valid paths (or ${BL}nav${NC} ${GR}choice):${NC} " invalid_path_choice
                        handle_navigation_input "$invalid_path_choice"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then 
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            continue
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        elif handle_sub_menu_AZ_navigation_input "$invalid_path_choice" "$sub_menu_choice" 0 $QUICK_PRESETS_MENU_ITEMS_TOTAL; then
                            break
                        fi
                    fi

                    use_saved_paths=true
                    ;;
                5)
                    if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No saved path(s) to clear.${NC}"
                        echo -n "   Please provide path(s) again. "
                        read -r -t 3 -n 1
                        continue
                    else
                        # Clear Saved Path(s)
                        trap - SIGINT
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                        show_clear_saved_paths_prompt
                        read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                        handle_navigation_input "$saved_paths_choice"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then 
                            continue
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        elif handle_sub_menu_AZ_navigation_input "$saved_paths_choice" "$sub_menu_choice" 0 $QUICK_PRESETS_MENU_ITEMS_TOTAL; then
                            break
                        fi

                        case $saved_paths_choice in
                            y|Y)
                                clear_saved_path_data
                                # echo -n "✅ ${GR}Cleared all saved paths.${NC} "
                                # read -r -t 1 -n 1
                                continue
                                ;;
                            *)
                                # echo -n "❌ ${RE}Cancelled.${NC} "
                                # read -r -t 1 -n 1
                                continue
                                ;;
                        esac
                    fi
                    ;;
                /)
                    echo "❌ ${RE}The root directory cannot be chosen.${NC}"
                    echo -n "   Please provide another path. "
                    read -r -t 3 -n 1
                    continue
                    ;;
                *)
                    # Process drag & drop input to handle escaped spaces and quoted paths
                    eval "set -- $input"

                    local arg_count=$#

                    if [[ "$arg_count" -eq 0 ]]; then
                        echo "❌ ${RE}No paths provided.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi

                    local invalid_paths=()

                    # Process each input path
                    for path in "$@"; do
                        if [[ -e "$path" ]]; then
                            paths_to_process+=("$path")
                        else
                            invalid_paths+=("$path")
                        fi
                    done

                    # check if there are valid paths to process
                    if [[ "${#paths_to_process[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No valid files to process.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi

                    if [[ "${#invalid_paths[@]}" -gt 0 ]]; then
                        show_invalid_path_prompt
                        read -rp "➡️  ${GR}Press Enter to continue with valid paths (or ${BL}nav${NC} ${GR}choice):${NC} " invalid_path_choice
                        handle_navigation_input "$invalid_path_choice"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then 
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            continue
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        elif handle_sub_menu_AZ_navigation_input "$invalid_path_choice" "$sub_menu_choice" 0 $QUICK_PRESETS_MENU_ITEMS_TOTAL; then
                            break
                        fi
                    fi
                    ;;
            esac

            # Handle Saved Paths
            if   [[ "$use_saved_paths" == "true" ]]; then
                use_saved_paths=false
                paths_to_process=("${valid_paths[@]}")
                path_count="${#paths_to_process[@]}"
            elif [[ "$DontAskAgainAbout_SavingPaths_Path_Picker" == "true" ]]; then
                sort_paths_to_process_without_defs
                path_count="${#paths_to_process[@]}"
            elif [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                # Prompt to Save Path(s)
                trap - SIGINT
                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

                sort_paths_to_process_with_defs
                path_count="${#paths_to_process[@]}"

                show_save_path_confirmation
                read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                handle_navigation_input "$saved_paths_choice"
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then 
                    continue
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                elif handle_sub_menu_AZ_navigation_input "$saved_paths_choice" "$sub_menu_choice" 0 $QUICK_PRESETS_MENU_ITEMS_TOTAL; then
                    break
                fi

                case $saved_paths_choice in
                    1)
                        saved_paths_to_process=("${paths_to_process[@]}")
                        save_paths_to_file
                        ;;
                    2)
                        DontAskAgainAbout_SavingPaths_Path_Picker="true"
                        save_pref "DontAskAgainAbout_SavingPaths_Path_Picker" "true"
                        ;;
                esac
            elif [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                if [[ "$DontAskAgainAbout_OverwritingPaths_Path_Picker" == "false" ]]; then
                    # Prompt to Overwrite Saved Path(s)
                    trap - SIGINT
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

                    sort_paths_to_process_without_defs
                    path_count="${#paths_to_process[@]}"
                    
                    show_overwrite_saved_path_confirmation
                    show_overwrite_saved_path_options
                    read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                    handle_navigation_input "$saved_paths_choice"
                    nav=$?
                    if   [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then 
                        continue
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    elif handle_sub_menu_AZ_navigation_input "$saved_paths_choice" "$sub_menu_choice" 0 $QUICK_PRESETS_MENU_ITEMS_TOTAL; then
                        break
                    fi
                    
                    case $saved_paths_choice in
                        1)
                            saved_paths_to_process=("${paths_to_process[@]}")
                            save_paths_to_file
                            set_plurality_for_saved_paths_to_process
                            # echo -n "✅ ${GR}Overwritten.${NC} "
                            # read -r -t 1 -n 1
                            ;;
                        2)
                            DontAskAgainAbout_OverwritingPaths_Path_Picker=true
                            save_pref "DontAskAgainAbout_OverwritingPaths_Path_Picker" "true"
                            ;;
                        *)
                            # echo -n "❌ ${RE}Cancelled.${NC} "
                            # read -r -t 1 -n 1
                            # Continue with provided path(s) without overwriting
                            # continue
                            :
                            ;;
                    esac
                else
                    # Continue with provided path(s) without overwriting
                    sort_paths_to_process_without_defs
                    path_count="${#paths_to_process[@]}"
                fi
            else
                # Should never reach here - all states covered above
                sort_paths_to_process_without_defs
                path_count="${#paths_to_process[@]}"
            fi
        fi

        # EXECUTION BLOCK
        while true; do
            trap - SIGINT
            trap 'echo; echo "🛑 ${RE}Interrupted.${NC} Showing summary..."; break' SIGINT
            resize_terminal 150 34
            if [ "$path_count" -gt 1 ]; then
                set_terminal_height_to_2200p
            fi
            clear
            if [[ "$DisablePathPickerWhenPathsAreSaved_Quick_Stats" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}0) 💨 Quick Stats [Summary]${NC} $([[ "$DisablePathPickerWhenPathsAreSaved_Quick_Stats" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]] && echo "${GY}[Using saved $path_or_paths]${NC}")" "${GY}(Use A/Z to cycle menus)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Main Menu" "Main Menu ↪"
            else
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "📊 ${BO}Summary" "${GY}(Use A/Z to toggle presets)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Path Picker]" "Home [Path Picker] ↪"
            fi
            show_nav_prompt_with_AZ_not_centered
            echo "🔄 ${BO}Scanning for stats...${NC}"

            # ─────────────────────────────────────────────────────────────────
            # PARENT FUNCTION SCOPE — declare before the loop
            # ─────────────────────────────────────────────────────────────────
            local arch_cache_files=()
            local arch_cache_results=()
            local arm64_count=0
            local x86_64_count=0
            local universal_count=0
            local other_arch_count=0
            # local adhoc_signature_needed=0
            # local quarantine_removal_needed=0
            
            # Start timing
            SECONDS=0

            # Get stats of parent path(s)
            # ─────────────────────────────────────────────────────────────────
            # MAIN LOOP
            # Pattern: echo name line → indented result lines
            # Order per item:
            #   name → quarantine → permissions → xattrs → type* → size → arch → sig → hash
            #   (* files and symlinks-to-files only)
            # ─────────────────────────────────────────────────────────────────
            echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"
            for path in "${paths_to_process[@]}"; do
                if [[ "$interrupted" == "true" ]]; then
                    echo
                    echo -n "🛑 ${RE}Interrupted.${NC} Incomplete... "
                    interrupted=false
                    break
                fi

                # -e alone misses broken symlinks; -L catches those too
                [[ ! -e "$path" && ! -L "$path" ]] && continue

                local name=${path##*/}
                local hash_result

                if [[ -L "$path" ]]; then
                    local target
                    target=$(readlink "$path" 2>/dev/null)

                    if [[ -z "$target" ]]; then
                        echo "⛓️‍💥 ${MA}${name}${NC} ${GY}[Unknown]${NC}"
                        continue
                    fi

                    if [[ -d "$path" ]]; then
                        if is_bundle "$path"; then
                            echo "🔗 ${MA}${name}/${NC} → 📦 ${CY}${target}/${NC}"
                            _print_quarantine_status "$path"
                            _print_permissions "$path"
                            _print_xattrs "$path"
                            _print_file_type "$path"
                            _print_size "$path"
                            _print_arch "$path"
                            if ! command -v codesign >/dev/null 2>&1; then
                                echo "${STAT_INDENT}✍️  ${HC}Signature:${NC} ${GY}N/A (codesign not installed — run: xcode-select --install)${NC}"
                            else
                                _print_signature "$path"
                            fi
                            _hash_bundle "$path"
                        else
                            echo "🔗 ${MA}${name}/${NC} → 📂 ${CY}${target}/${NC}"
                            _print_quarantine_status "$path"
                            _print_permissions "$path"
                            _print_xattrs "$path"
                            _print_file_type "$path"
                            _print_size "$path"
                            _print_arch "$path"
                            if ! command -v codesign >/dev/null 2>&1; then
                                echo "${STAT_INDENT}✍️  ${HC}Signature:${NC} ${GY}N/A (codesign not installed — run: xcode-select --install)${NC}"
                            else
                                _print_signature "$path"
                            fi
                            hash_result=$(shasum -a "$sha_algo" "$path" 2>/dev/null | awk '{print $1}')
                            if [[ -n "$hash_result" ]]; then
                                echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GR}${hash_result}${NC}"
                            else
                                echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GY}[N/A]${NC}"
                            fi
                        fi
                    elif [[ -f "$path" ]]; then
                        echo "🔗 ${MA}${name}${NC} → 📄 ${BO}${target}${NC}"
                        _print_quarantine_status "$path"
                        _print_permissions "$path"
                        _print_xattrs "$path"
                        _print_file_type "$path"
                        _print_size "$path"
                        _print_arch "$path"
                        if ! command -v codesign >/dev/null 2>&1; then
                            echo "${STAT_INDENT}✍️  ${HC}Signature:${NC} ${GY}N/A (codesign not installed — run: xcode-select --install)${NC}"
                        else
                            _print_signature "$path"
                        fi
                        hash_result=$(shasum -a "$sha_algo" "$path" 2>/dev/null | awk '{print $1}')
                        if [[ -n "$hash_result" ]]; then
                            echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GR}${hash_result}${NC}"
                        else
                            echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GY}[N/A]${NC}"
                        fi
                    else
                        # Broken symlink — skip all stat helpers (target unreachable)
                        echo "🔗 ${MA}${name}${NC} → ⛓️‍💥 ${GY}${target} [Broken Link]${NC}"
                    fi
                elif [[ -d "$path" ]]; then
                    if is_bundle "$path"; then
                        echo "📦 ${CY}${name}/${NC}"
                        _print_quarantine_status "$path"
                        _print_permissions "$path"
                        _print_xattrs "$path"
                        _print_file_type "$path"
                        _print_size "$path"
                        _print_arch "$path"
                        if ! command -v codesign >/dev/null 2>&1; then
                            echo "${STAT_INDENT}✍️  ${HC}Signature:${NC} ${GY}N/A (codesign not installed — run: xcode-select --install)${NC}"
                        else
                            _print_signature "$path"
                        fi
                        _hash_bundle "$path"
                    else
                        echo "📂 ${CY}${name}/${NC}"
                        _print_quarantine_status "$path"
                        _print_permissions "$path"
                        _print_xattrs "$path"
                        _print_file_type "$path"
                        _print_size "$path"
                        _print_arch "$path"
                        if ! command -v codesign >/dev/null 2>&1; then
                            echo "${STAT_INDENT}✍️  ${HC}Signature:${NC} ${GY}N/A (codesign not installed — run: xcode-select --install)${NC}"
                        else
                            _print_signature "$path"
                        fi
                        echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GY}folders are not hashable - try scanning with 🧪 Generate SHA Hash${NC}"
                    fi
                else
                    echo "📄 ${BO}${name}${NC}"
                    _print_quarantine_status "$path"
                    _print_permissions "$path"
                    _print_xattrs "$path"
                    _print_file_type "$path"
                    _print_size "$path"
                    _print_arch "$path"
                    if ! command -v codesign >/dev/null 2>&1; then
                        echo "${STAT_INDENT}✍️  ${HC}Signature:${NC} ${GY}N/A (codesign not installed — run: xcode-select --install)${NC}"
                    else
                        _print_signature "$path"
                    fi
                    hash_result=$(shasum -a "$sha_algo" "$path" 2>/dev/null | awk '{print $1}')
                    if [[ -n "$hash_result" ]]; then
                        echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GR}${hash_result}${NC}"
                    else
                        echo "${STAT_INDENT}🧪 ${HC}SHA-$sha_algo:${NC} ${GY}[N/A]${NC}"
                    fi
                fi
                if [[ "$interrupted" == "true" ]]; then
                    echo
                    echo -n "🛑 ${RE}Interrupted.${NC} Incomplete... "
                    interrupted=false
                    break
                fi
            done
            echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"

            # Stop timing and calculate elapsed time
            local elapsed_seconds=$SECONDS
            local elapsed_display
            if [ $elapsed_seconds -ge 60 ]; then
                local minutes=$((elapsed_seconds / 60))
                local seconds=$((elapsed_seconds % 60))
                elapsed_display="${minutes}m ${seconds}s"
            else
                elapsed_display="${elapsed_seconds}s"
            fi

            trap - SIGINT
            interrupted=false
            if [[ "$DisablePathPickerWhenPathsAreSaved_Quick_Stats" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                trap 'return' SIGINT
            else
                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; break' SIGINT
            fi
            echo
            echo "${BO}Scan Results:${NC}"
            echo "${GR}─────────────────────────${NC}"
            echo "🛣️  Total paths found: $path_count"
            echo "⏱️  Total scan time:   ${elapsed_display}"
            echo "${GR}─────────────────────────${NC}"
            echo
            if [[ "$DisablePathPickerWhenPathsAreSaved_Quick_Stats" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                read -rp "➡️  ${GR}Return to Main Menu? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                handle_navigation_input "$input"
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then 
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    return 0
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                elif handle_quick_presets_AZ_navigation_input "$input" "$sub_menu_choice" 0 $QUICK_PRESETS_MENU_ITEMS_TOTAL; then
                    return
                elif [[ $nav -eq $NAV_CONT ]]; then
                    return 0
                fi
            else
                read -rp "➡️  ${GR}Get stats on another file? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                handle_navigation_input "$input"
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then 
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    break
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                    return
                elif [[ $nav -eq $NAV_CONT ]]; then
                    break # back to Path Picker
                fi
            fi
        done
    done
}
#====1==== 📡 Speed Test
function speed_test() {
    while true; do
        trap 'return' SIGINT
        resize_terminal 95 24
        clear
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "${BO}1) 📡 Speed Test${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "94"
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "↩ Main Menu" "TBD ↪"
        show_nav_prompt_with_AZ_centered

        # Check if networkquality exists first
        if ! command -v networkquality &> /dev/null; then
            echo_centered "❌ ${RE}networkquality command not found!${NC}"
            echo
            echo_centered "   This requires macOS 12 (Monterey) or later"
            echo
            for i in 3 2 1; do
                echo -ne "\r                       ${GR}🚪 Returning to Main Menu in $i...${NC} "
                # read one char, timeout after 1s
                read -t 1 -n 1 key
                if [[ $? -eq 0 ]]; then
                    return 0
                fi
            done
            # countdown expired, so retry normally
            # echo -ne "\r                    \r"  # clear countdown line
            return 0
        fi
        
        echo "${BO}Choose test type:${NC}"
        echo " 1) ${GR}Standard${NC} ${GY}......${NC} Clean summary output"
        echo " 2) ${GR}Verbose${NC} ${GY}.......${NC} Detailed test output"
        echo " 3) ${GR}Config Only${NC} ${GY}...${NC} Show network configuration"
        echo
        read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " choice
        handle_navigation_input "$choice"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            return 0
        elif [[ $nav -eq $NAV_REFRESH ]]; then 
            continue
        elif handle_main_menu_AZ_navigation_input "$choice" "$main_menu_choice"; then
            return
        fi

        case $choice in
            1)  
                trap - SIGINT
                interrupted=false
                trap 'interrupted=true; echo; kill $networkquality_pid 2>/dev/null' SIGINT
                clear
                echo "${GR}═══════════════════════════${GR}╗${NC}"
                echo "${BO}1) 📡 Speed Test (Standard)${GR}║${NC}"
                echo "${GR}═══════════════════════════${GR}╝${NC}"
                echo "↩ Home [Choose Test Type]"
                echo
                echo "📡 ${GR}Testing network quality...${NC}"
                echo "⏱️  ${GY}This may take 10-20 seconds...${NC}"
                echo
                echo "${BL}nav${NC}: ${GR}^C${NC} to interrupt test"
                echo
                # Run networkquality in background and capture its PID
                networkquality &
                networkquality_pid=$!
                
                # Wait for networkquality to complete or be interrupted
                if wait $networkquality_pid 2>/dev/null; then
                    # Command completed normally
                    echo
                    echo "✅ ${GR}Done!${NC}"
                else
                    # Command was interrupted or failed
                    if [[ "$interrupted" == "true" ]]; then
                        echo
                        echo "🛑 ${RE}Test interrupted.${NC}"
                    fi
                fi
                ;;
            2)
                trap - SIGINT
                interrupted=false
                trap 'interrupted=true; kill $networkquality_pid 2>/dev/null' SIGINT
                set_terminal_height_to_2200p
                clear
                echo "${GR}══════════════════════════${GR}╗${NC}"
                echo "${BO}2) 📡 Speed Test (Verbose)${GR}║${NC}"
                echo "${GR}══════════════════════════${GR}╝${NC}"
                echo "↩ Home [Choose Test Type]"
                echo
                echo "📡 ${GR}Testing network quality...${NC}"
                echo "⏱️  ${GY}This may take 10-30 seconds...${NC}"
                echo
                echo "${BL}nav${NC}: ${GR}^C${NC} to interrupt test"
                echo                    
                # Run networkquality in background and capture its PID
                networkquality -v &
                networkquality_pid=$!
                
                # Wait for networkquality to complete or be interrupted
                if wait $networkquality_pid 2>/dev/null; then
                    # Command completed normally
                    echo
                    echo "✅ ${GR}Done!${NC}"
                else
                    # Command was interrupted or failed
                    if [[ "$interrupted" == "true" ]]; then
                        echo
                        echo "🛑 ${RE}Test interrupted.${NC}"
                    fi
                fi
                ;;
            3)
                trap - SIGINT
                interrupted=false
                trap 'interrupted=true; kill $networkquality_pid 2>/dev/null' SIGINT
                set_terminal_height_to_2200p
                clear
                echo "${GR}═══════════════════════════${GR}╗${NC}"
                echo "${BO}3) 🔧 Network Configuration${GR}║${NC}"
                echo "${GR}═══════════════════════════${GR}╝${NC}"
                echo "↩ Home [Choose Test Type]"
                echo
                echo "📡 ${GR}Showing network configuration...${NC}"
                echo "⏱️  ${GY}This may take 10-20 seconds...${NC}"
                echo
                echo "${BL}nav${NC}: ${GR}^C${NC} to interrupt test"
                echo
                # Run networkquality in background and capture its PID
                networkquality -c &
                networkquality_pid=$!
                
                # Wait for networkquality to complete or be interrupted
                if wait $networkquality_pid 2>/dev/null; then
                    # Command completed normally
                    echo
                    echo "✅ ${GR}Done!${NC}"
                else
                    # Command was interrupted or failed
                    if [[ "$interrupted" == "true" ]]; then
                        echo
                        echo "🛑 ${RE}Test interrupted.${NC}"
                    fi
                fi
                ;;
            *)
                echo -n "❌ ${RE}Invalid choice.${NC} "
                read -r -t 1 -n 1
                continue
                ;;
        esac

        # Post-test handling
        while true; do
            trap - SIGINT
            interrupted=false
            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back a step: "; interrupted=true; break' SIGINT
            show_nav_prompt_with_AZ_not_centered
            read -rp "➡️  ${GR}Choose another test type? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                break
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                break
            elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                return
            fi
            break
        done
    done
}
#====2==== 📊 Activity Monitor (Top)
function top_activity_monitor() {
    while true; do
        trap 'return' SIGINT
        resize_terminal 95 24
        clear
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "${BO}2) 📊 Activity Monitor${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "94"
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "↩ Main Menu" "top ↪"
        show_nav_prompt_with_AZ_centered

        echo "🔄 ${GR}Starting Activity Monitor (top)...${NC}"
        echo
        echo "───────────────────────────────────────────────────────────────────────────────────────────────"
        echo "${MA}top${NC} ${BL}Nav${NC}:  ${GR}Q${NC} = Quit | ${GR}?${NC} = Help | ${GR}Spacebar${NC} = Force Update"
        echo "          ${GR}o${NC} = Sort Options ${GY}- (then type: -cpu, -mem, etc.)${NC}"
        echo "          ${GR}S${NC} = Set Update Interval ${GY}- (then type: 1, 2, 3, etc.)${NC}"
        echo "───────────────────────────────────────────────────────────────────────────────────────────────"
        echo
        echo -n "➡️  ${GR}Press Enter to continue (or ${BL}nav${NC} ${GR}choice):${NC} "
        read -rp "" input
        handle_navigation_input "$input"
        nav=$?
        if   [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then 
            return 0
        elif [[ $nav -eq $NAV_REFRESH ]]; then 
            continue
        elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
            return
        fi

        trap - SIGINT
        trap 'echo; continue' SIGINT

        if [[ "$OSTYPE" == "darwin"* ]]; then
            set_terminal_height_to_2200p
            top -o cpu -s 2
        else
            set_terminal_height_to_2200p
            top -d 2
        fi
    done
}
#====3==== 🖥️ System Information
function system_information() {
    while true; do
        trap 'return' SIGINT
        resize_terminal 95 24
        # If we have a pending choice from handle_sub_menu_AZ_navigation_input, skip menu display
        if [[ -z "$current_sub_menu_choice" ]]; then
            clear
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}3) 🖥️  System Information${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "96"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "↩ Main Menu" "TBD ↪"
            show_nav_prompt_with_AZ_centered

            echo "${BO}Choose information to be displayed:${NC}"
            echo " 1) ${GR}System Profile Overview${NC} ${GY}...${NC} Hardware, Software, Users"
            echo " 2) ${GR}Hardware Summary${NC} ${GY}..........${NC} Model, CPU, Memory, Serial"
            echo " 3) ${GR}Software Summary${NC} ${GY}..........${NC} macOS Version, Kernel, Uptime"
            echo " 4) ${GR}Network Interfaces${NC} ${GY}........${NC} Network hardware and config"
            echo " 5) ${GR}USB Devices${NC} ${GY}...............${NC} Connected USB devices"
            echo " 6) ${GR}Storage Devices${NC} ${GY}...........${NC} Disks and storage info"
            echo " 7) ${GR}User Account Details${NC} ${GY}......${NC} Current user and system users"
            echo
            read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " sub_menu_choice
            handle_navigation_input "$sub_menu_choice"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                return 0
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue 
            elif handle_main_menu_AZ_navigation_input "$sub_menu_choice" "$main_menu_choice"; then
                return
            fi
        else
            # Use the pending choice from A/Z navigation
            sub_menu_choice="$current_sub_menu_choice"
            current_sub_menu_choice=""
        fi

        case $sub_menu_choice in
            1)
                set_terminal_height_to_2200p
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}1) 📋 System Profile Overview${NC}" "${GY}(use A/Z to cycle info options)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Info Options]" "Home [Info Options] ↪"
                echo
                system_profiler SPHardwareDataType | tail -n +3
                system_profiler SPSoftwareDataType | tail -n +3
                echo "${BO}👤 User Account Details${NC}"
                echo
                
                echo "📊 ${GR}Current User Information:${NC}"
                echo "${BO}Username:${NC} $(whoami)"
                echo "${BO}UID:${NC}      $(id -u)"
                echo "${BO}GID:${NC}      $(id -g)"
                echo "${BO}Groups:${NC}   $(id -Gn)"
                echo
                
                echo "📋 ${GR}All System Users (UID 500+):${NC}"
                dscl . -list /Users UniqueID | awk '$2 >= 500 {print $1 ":" $2}' | sort -t: -k2 -n | while IFS=: read username uid; do
                    gid=$(id -g "$username" 2>/dev/null || echo "N/A")
                    groups=$(id -Gn "$username" 2>/dev/null || echo "(none)")
                    echo "${BO}Username:${NC} $username"
                    echo "${BO}UID:${NC}      $uid"
                    echo "${BO}GID:${NC}      $gid"
                    echo "${BO}Groups:${NC}   $groups"
                    echo
                done

                echo "🔍 ${GR}Currently Logged In Users:${NC}"
                w | tail -n +3 | awk '{print "User: " $1 " | UID: " $2 " | Login: " $4 " | From: " $3}'
                echo
                ;;
            2)
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}2) 🖥️  Hardware Summary${NC}" "${GY}(use A/Z to cycle info options)${NC}" "96"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Info Options]" "Home [Info Options] ↪"
                echo
                system_profiler SPHardwareDataType | tail -n +3
                ;;
            3)
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}3) 💿 Software Summary${NC}" "${GY}(use A/Z to cycle info options)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Info Options]" "Home [Info Options] ↪"
                echo
                system_profiler SPSoftwareDataType | tail -n +3
                ;;
            4)
                set_terminal_height_to_2200p
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}4) 🌐 Network Interfaces${NC}" "${GY}(use A/Z to cycle info options)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Info Options]" "Home [Info Options] ↪"
                echo
                system_profiler SPNetworkDataType | tail -n +3
                ;;
            5)
                set_terminal_height_to_2200p
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}5) 🔌 USB Devices${NC}" "${GY}(use A/Z to cycle info options)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Info Options]" "Home [Info Options] ↪"
                echo
                system_profiler SPUSBDataType # | tail -n +3
                ;;
            6)
                set_terminal_height_to_2200p
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}6) 💾 Storage Devices${NC}" "${GY}(use A/Z to cycle info options)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Info Options]" "Home [Info Options] ↪"
                echo
                system_profiler SPStorageDataType | tail -n +3
                echo
                system_profiler SPSerialATADataType | tail -n +3
                ;;
            7)
                set_terminal_height_to_2200p
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}7) 👤 User Account Details${NC}" "${GY}(use A/Z to cycle info options)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Info Options]" "Home [Info Options] ↪"
                echo
                echo "📊 ${GR}Current User Information:${NC}"
                echo "${BO}Username:${NC} $(whoami)"
                echo "${BO}UID:${NC}      $(id -u)"
                echo "${BO}GID:${NC}      $(id -g)"
                echo "${BO}Groups:${NC}   $(id -Gn)"
                echo

                echo "📋 ${GR}All System Users (UID 500+):${NC}"
                dscl . -list /Users UniqueID | awk '$2 >= 500 {print $1 ":" $2}' | sort -t: -k2 -n | while IFS=: read username uid; do
                    gid=$(id -g "$username" 2>/dev/null || echo "N/A")
                    groups=$(id -Gn "$username" 2>/dev/null || echo "(none)")
                    echo "${BO}Username:${NC} $username"
                    echo "${BO}UID:${NC}      $uid"
                    echo "${BO}GID:${NC}      $gid"
                    echo "${BO}Groups:${NC}   $groups"
                    echo
                done

                echo "🔍 ${GR}Currently Logged In Users:${NC}"
                w | tail -n +3 | awk '{print "User: " $1 " | UID: " $2 " | Login: " $4 " | From: " $3}'
                echo
                ;;
            *)
                echo -n "❌ ${RE}Invalid choice.${NC} "
                read -r -t 1 -n 1
                continue
                ;;
        esac

        while true; do
            trap - SIGINT
            interrupted=false
            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
            trimmed_output="$(show_nav_prompt_with_AZ_not_centered)"
            # Remove leading/trailing empty lines
            echo "$trimmed_output" | sed -e '1{/^$/d;}' -e '${/^$/d;}'
            echo
            # show_nav_prompt_not_centered
            read -rp "➡️  ${GR}Choose another option? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                break
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                break
            elif handle_sub_menu_AZ_navigation_input "$input" "$sub_menu_choice" 1 7; then
                break
            fi
            break
        done
    done
}
#====4==== 🔄 iCloud Sync Refresh
function icloud_sync_refresh() {
    while true; do
        trap 'return' SIGINT
        resize_terminal 95 24
        clear
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "${BO}4) 🔄 iCloud Sync Refresh${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "94"
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "↩ Main Menu" "Refresh iCloud Sync ↪"
        show_nav_prompt_with_AZ_centered

        echo "🔄 ${GR}Starting iCloud Sync Refresh...${NC}"
        echo
        echo "ℹ️  ${BO}This will restart the iCloud daemon (cloudd)${NC}"
        echo "   • iCloud sync will pause briefly and then resume"
        echo "   • May help resolve sync issues or stuck uploads"
        echo "   • All iCloud services will be affected momentarily"
        echo
        read -rp "➡️  ${GR}Refresh iCloud sync? [y/N] (or ${BL}nav${NC} ${GR}choice):${NC} " confirm
        handle_navigation_input "$confirm"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            return 0
        elif [[ $nav -eq $NAV_REFRESH ]]; then 
            continue
        elif handle_main_menu_AZ_navigation_input "$confirm" "$main_menu_choice"; then
            return
        fi

        case $confirm in
            [Yy]|[Yy][Ee][Ss])
                while true; do
                    echo
                    echo "☁️  ${GR}Restarting iCloud daemon...${NC}"
                    
                    trap - SIGINT
                    interrupted=false
                    trap 'echo; echo "🛑 ${RE}Interrupted.${NC}"; interrupted=true; break' SIGINT

                    # Kill the cloudd processes
                    # it will restart automatically - regardless of internet connection
                    killall cloudd
                    
                    echo "✅ ${GR}iCloud daemon restarted${NC}"
                    echo "   Sync processes will resume automatically."
                    read -r -t 1 -n 1
                    break
                done
                ;;
            *)
                echo -n "❌ ${YE}iCloud refresh cancelled${NC} "
                read -r -t 1 -n 1
                continue
                ;;
        esac

        while true; do
            trap - SIGINT
            interrupted=false
            trap 'return' SIGINT
            echo
            read -rp "➡️  ${GR}Return to main menu? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
            handle_navigation_input "$input"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                break
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                break
            elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                return
            fi
            break 2
        done
    done
}
#====5==== 💾 Disk Image Utility
function disk_image_utility () {
    if true; then    # only used to quickly collapse functions below
        # Helper: format size for display in headers and summaries
        format_disk_size_display() {
            local raw="$1"
            # Treat bare numbers (no unit) as MB derived from source content
            if [[ -z "$raw" ]]; then
                echo ""
                return
            fi

            case "$raw" in
                *[mM])
                    # e.g., "512m" -> "512 MB"
                    echo "${raw%[mM]} MB"
                    ;;
                *[gG])
                    # e.g., "1g" -> "1 GB"
                    echo "${raw%[gG]} GB"
                    ;;
                *[tT])
                    # e.g., "1t" -> "1 TB"
                    echo "${raw%[tT]} TB"
                    ;;
                *)
                    # Bare number from existing items: interpret as MB and promote to GB when >= 1000MB
                    if echo "$raw" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
                        local mb="$raw"
                        if [ "$mb" -ge 1000 ]; then
                            # Convert to GB with one decimal place
                            local size_gb=$(( (mb * 10) / 1000 ))
                            local size_display="${size_gb%?}.${size_gb: -1} GB"
                            # Clean up trailing zero (e.g., 1.0 -> 1)
                            size_display=$(echo "$size_display" | sed 's/\.0 GB$/ GB/')
                            echo "$size_display"
                        elif [ "$mb" -lt 2 ]; then
                            echo "2 MB"                        
                        else
                            echo "${mb} MB"
                        fi
                    else
                        # Fallback: show as-is
                        echo "$raw"
                    fi
                    ;;
            esac
        }
        # Helper: normalize size value for hdiutil -size argument
        normalize_disk_size_for_hdiutil() {
            local raw="$1"
            if [[ -z "$raw" ]]; then
                echo ""
                return
            fi

            case "$raw" in
                *[mMgGtT])
                    # Already has a unit suffix understood by hdiutil
                    echo "$raw"
                    ;;
                *)
                    # Treat bare numbers as MB
                    echo "${raw}m"
                    ;;
            esac
        }
        # Helper: convert disk image size string (e.g., 2m, 1g, 500, etc.) to MB
        convert_disk_size_to_mb() {
            local raw="$1"
            local mb=0

            if [[ -z "$raw" ]]; then
                echo 0
                return
            fi

            if echo "$raw" | grep -E '[mM]$' >/dev/null 2>&1; then
                local num
                num=$(echo "$raw" | sed 's/[mM]$//')
                if echo "$num" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
                    mb=$num
                fi
            elif echo "$raw" | grep -E '[gG]$' >/dev/null 2>&1; then
                local num
                num=$(echo "$raw" | sed 's/[gG]$//')
                if echo "$num" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
                    mb=$((num * 1024))
                fi
            elif echo "$raw" | grep -E '[tT]$' >/dev/null 2>&1; then
                local num
                num=$(echo "$raw" | sed 's/[tT]$//')
                if echo "$num" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
                    mb=$((1024 * 1024))
                fi
            elif echo "$raw" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
                mb=$raw
            fi

            echo "$mb"
        }
        estimate_sparseimage_initial_mb() {
            local capacity_mb="$1"

            if [[ -z "$capacity_mb" ]] || [ "$capacity_mb" -le 0 ]; then
                echo 0
                return
            fi

            # Lookup table based on actual measured APFS + AES-256 encrypted sparse images (du -sh on macOS)
            # Capacity (MB) -> estimated initial file size (MB)
            if    [ "$capacity_mb" -le 2 ];    then echo 3    # ~2.1 MB
            elif  [ "$capacity_mb" -le 5 ];    then echo 6    # ~5.1 MB
            elif  [ "$capacity_mb" -le 10 ];   then echo 9    # ~8.1 MB
            elif  [ "$capacity_mb" -le 25 ];   then echo 8    # ~7.1 MB
            elif  [ "$capacity_mb" -le 500 ];  then echo 9    # ~8.1 MB (50m-500m all identical)
            elif  [ "$capacity_mb" -le 1024 ]; then echo 10   # ~9.1 MB
            elif  [ "$capacity_mb" -le 2048 ]; then echo 11   # ~11 MB
            elif  [ "$capacity_mb" -le 5120 ]; then echo 14   # ~14 MB
            else                                    echo 16   # ~16 MB (10g+)
            fi
        }
        # Apple's Finder display - decimal (base-10) calculations 
        get_sparse_image_file_size() {
            local path_to_disk_img="$1"
            local size=""
            local bytes
            
            # Get actual size on disk in kilobytes, then convert to bytes
            local kb=$(du -k "$path_to_disk_img" | cut -f1)
            bytes=$((kb * 1024))
            
            # Convert to human-readable format using decimal (base-10) like Finder
            if [ $bytes -ge 1000000000000 ]; then
                size=$(awk "BEGIN {printf \"%.1f TBs\", $bytes/1000000000000}")
            elif [ $bytes -ge 1000000000 ]; then
                size=$(awk "BEGIN {printf \"%.1f GBs\", $bytes/1000000000}")
            elif [ $bytes -ge 1000000 ]; then
                size=$(awk "BEGIN {printf \"%.1f MBs\", $bytes/1000000}")
            elif [ $bytes -ge 1000 ]; then
                size=$(awk "BEGIN {printf \"%.1f KBs\", $bytes/1000}")
            else
                size="${bytes} bytes"
            fi
            echo "$size"
        }
        get_sparse_image_capacity() {
            local image="$1"
            local sectors
            sectors=$(hdiutil resize -limits "$image" 2>/dev/null | tail -1 | awk '{print $2}')

            if [ -z "$sectors" ]; then
                echo "N/A"
                return
            fi

            local bytes=$(( sectors * 512 ))

            if [ "$bytes" -ge 1000000000000 ]; then
                awk "BEGIN {printf \"%.1f TBs\", $bytes/1000000000000}"
            elif [ "$bytes" -ge 1000000000 ]; then
                awk "BEGIN {printf \"%.1f GBs\", $bytes/1000000000}"
            elif [ "$bytes" -ge 1000000 ]; then
                awk "BEGIN {printf \"%.1f MBs\", $bytes/1000000}"
            elif [ "$bytes" -ge 1000 ]; then
                awk "BEGIN {printf \"%.1f KBs\", $bytes/1000}"
            else
                echo "${bytes} bytes"
            fi
        }
        populate_pending_disk_image_info() {
            if [[ -z "$sparse_image_capacity_after" ]]; then
                # Human-friendly capacity display for header
                header_capacity="$(format_disk_size_display "$disk_img_size")"
            else
                header_capacity=$sparse_image_capacity_after
            fi

            if [[ -z "$sparse_image_file_size_after" ]]; then
                # Estimate on-disk sparseimage file size:
                # - If creating from source files, use calculated_size (MB) from their total.
                # - Otherwise, estimate from the chosen capacity using calibration data.
                local est_mb=""
                if [[ "$create_from_source" == "true" && -n "$calculated_size" ]]; then
                    est_mb="$calculated_size"
                else
                    local capacity_mb
                    capacity_mb="$(convert_disk_size_to_mb "$disk_img_size")"
                    if [[ -n "$capacity_mb" && "$capacity_mb" -gt 0 ]]; then
                        est_mb="$(estimate_sparseimage_initial_mb "$capacity_mb")"
                    fi
                fi

                local est_display="16 MB"
                if [[ -n "$est_mb" && "$est_mb" -gt 0 ]]; then
                    est_display="$(format_disk_size_display "$est_mb")"
                fi
            else
                est_display=$sparse_image_file_size_after
            fi
            if [[ -z "$sparse_image_capacity_after" ]] && [[ -z "$sparse_image_file_size_after" ]]; then
                echo_centered "${BO}Pending Disk Image Info:${NC}"
                echo "${GR}Name:${NC} $( if [[ -n "$vol_name" ]]; then echo "$vol_name.sparseimage"; elif [[ -n "$existing_vol_name" ]]; then echo "$existing_vol_name.sparseimage"; fi )"
                echo_centered "${GR}Est. File Size:${NC}  | ~$est_display |  ${GR}Est. Capacity:${NC}  | $( if [[ -z $header_capacity ]]; then echo "$header_capacity"; else echo "~$header_capacity"; fi ) |  ${GR}Encryption:${NC}  | $( if [[ "$use_password_active" == "true" ]]; then echo "✅"; elif [[ "$use_password_active" == "false" ]]; then echo "❌"; else echo ""; fi ) |"
                echo
            else
                echo_centered "${BO}Pending Disk Image Info:${NC}"
                echo "${GR}Name:${NC} $( if [[ -n "$vol_name" ]]; then echo "$vol_name.sparseimage"; elif [[ -n "$existing_vol_name" ]]; then echo "$existing_vol_name.sparseimage"; fi )"
                echo_centered "${GR}Est. File Size:${NC}  | $est_display |  ${GR}Est. Capacity:${NC}  | $( if [[ -z $header_capacity ]]; then echo "$header_capacity"; else echo "$header_capacity"; fi ) |  ${GR}Encryption:${NC}  | $( if [[ "$use_password_active" == "true" ]]; then echo "✅"; elif [[ "$use_password_active" == "false" ]]; then echo "❌"; else echo ""; fi ) |"
                echo
            fi
        }
        populate_managed_disk_image_info() {
            echo_centered "${BO}Current Disk Image Info:${NC}"
            echo
            # echo "${GR}Name:${NC} $selected_disk_img_basename"
            echo_centered "${GR}File Size:${NC}  | $(get_sparse_image_file_size "$selected_disk_img_for_sizing") |  ${GR}Capacity:${NC}  | $header_capacity |  ${GR}Encryption:${NC}  | $(encryption_status) |"
            echo
        }

        # Total number of size options
        local total_number_of_size_options=32

        # Function to get menu item by index (simulates array access)
        get_size_options() {
            local index=$1
            case $index in
                0) echo " 1) ${GR}2 MBs${NC}" ;;
                1) echo " 2) ${GR}5 MBs${NC}" ;;
                2) echo " 3) ${GR}15 MBs${NC}" ;;
                3) echo " 4) ${GR}25 MBs${NC}" ;;
                4) echo " 5) ${GR}50 MBs${NC}" ;;
                5) echo " 6) ${GR}100 MBs${NC}" ;;
                6) echo " 7) ${GR}500 MBs${NC}" ;;
                7) echo " 8) ${GR}750 MBs${NC}" ;;
                8) echo " 9) ${GR}1 GB${NC}" ;;
                9) echo "10) ${GR}2 GBs${NC}" ;;
                10) echo "11) ${GR}3 GBs${NC}" ;;
                11) echo "12) ${GR}4 GBs${NC}" ;;
                12) echo "13) ${GR}5 GBs${NC}" ;;
                13) echo "14) ${GR}6 GBs${NC}" ;;
                14) echo "15) ${GR}7 GBs${NC}" ;;
                15) echo "16) ${GR}8 GBs${NC}" ;;
                16) echo "17) ${GR}10 GBs${NC}" ;;
                17) echo "18) ${GR}15 GBs${NC}" ;;
                18) echo "19) ${GR}25 GBs${NC}" ;;
                19) echo "20) ${GR}50 GBs${NC}" ;;
                20) echo "21) ${GR}100 GBs${NC}" ;;
                21) echo "22) ${GR}250 GBs${NC}" ;;
                22) echo "23) ${GR}500 GBs${NC}" ;;
                23) echo "24) ${GR}750 GBs${NC}" ;;
                24) echo "25) ${GR}1 TB${NC}" ;;
                25) echo "26) ${GR}2 TBs${NC}" ;;
                26) echo "27) ${GR}3 TBs${NC}" ;;
                27) echo "28) ${GR}4 TBs${NC}" ;;
                28) echo "29) ${GR}5 TBs${NC}" ;;
                29) echo "30) ${GR}6 TBs${NC}" ;;
                30) echo "31) ${GR}7 TBs${NC}" ;;
                31) echo "32) ${GR}Custom${NC}" ;;
                *) echo "" ;;
            esac
        }
        # Simple four-column layout (bash 3.2 compatible)
        # update num_items as needed
        display_four_column_size_options() {
            local num_items=$total_number_of_size_options
            local items_per_col=$(( (num_items + 3) / 4 ))
            # change width between columns here
            local col2_start=25
            local col3_start=50
            local col4_start=75

            
            for ((i=0; i<items_per_col; i++)); do
                local col1_index=$i
                local col2_index=$((i + items_per_col))
                local col3_index=$((i + items_per_col * 2))
                local col4_index=$((i + items_per_col * 3))
                
                local col1_item=""
                local col2_item=""
                local col3_item=""
                local col4_item=""
                
                # Get column 1 item
                if [[ $col1_index -lt $num_items ]]; then
                    col1_item=$(get_size_options $col1_index)
                fi
                
                # Get column 2 item
                if [[ $col2_index -lt $num_items ]]; then
                    col2_item=$(get_size_options $col2_index)
                fi
                
                # Get column 3 item
                if [[ $col3_index -lt $num_items ]]; then
                    col3_item=$(get_size_options $col3_index)
                fi

                # Get column 4 item
                if [[ $col4_index -lt $num_items ]]; then
                    col4_item=$(get_size_options $col4_index)
                fi
                
                # Print column 1
                printf "%s" " $col1_item"
                
                # Move to column 2 and print
                if [[ -n "$col2_item" ]]; then
                    printf '\033[%dG' $col2_start
                    printf "%s" "   $col2_item"
                fi
                
                # Move to column 3 and print
                if [[ -n "$col3_item" ]]; then
                    printf '\033[%dG' $col3_start
                    printf "%s" "   $col3_item"
                fi        

                # Move to column 4 and print
                if [[ -n "$col4_item" ]]; then
                    printf '\033[%dG' $col4_start
                    printf "%s" "   $col4_item"
                fi
                
                printf "\n"
            done
        }
    fi
    # Loop 1: Create or Manage a disk image
    while true; do
        trap 'return' SIGINT
        local disk_util_path=""
        resize_terminal 95 24
        clear
        display_Disk_Image_Utility_header_for_95px
        echo_centered "${BO}Fast creation & management of sparse image files on macOS${NC}"
        echo
        echo "${GR}What is a .sparseimage file?${NC}"
        echo "• A sparse image is a disk image format that grows dynamically as you add data"
        echo "• Supports up to AES-256 encryption ${GY}(optional but recommended)${NC}"
        echo "${GR}How does it work?${NC}"
        echo "- When creating a sparse image, you set a maximum size limit (or capacity)"
        echo "- As you add files to the mounted disk image, it grows up to that limit"
        echo "- If you ever need to grow or shrink the capacity, you can resize it later"
        echo "- After deleting files inside, you can also 'compact' it to shrink its file size"
        echo
        echo "${BO}Would you like to create a new image or resize/compact an existing one?${NC}"
        echo " 1) 🪄 ${GR}Create new disk image${NC}"
        echo " 2) ↔️  ${GR}Resize/Compact an image${NC}"
        show_nav_prompt_with_AZ_centered
        read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " disk_util_choice
        handle_navigation_input "$disk_util_choice"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            break
        elif [[ $nav -eq $NAV_REFRESH ]]; then 
            continue
        elif handle_main_menu_AZ_navigation_input "$disk_util_choice" "$main_menu_choice"; then
            return
        fi

        case "$disk_util_choice" in
            1) disk_util_path=create ;;
            2) disk_util_path=manage ;;
        esac

        if [[ "$disk_util_path" == "create" ]]; then
            # Loop 2
            while true; do
                trap - SIGINT
                interrupted=false
                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                clear
                echo "${GR}════════════════════════${GR}╗${NC}"
                echo "${BO}🪄 Create New Disk Image${GR}║${NC}"
                echo "${GR}════════════════════════${GR}╝${NC}"
                echo_justified "↩ Home [Create or Resize]" "TBD ↪"
                show_nav_prompt_centered

                echo "${GR}Create a blank image or create one from existing files or folders?${NC}"
                echo
                echo "${BO}Choose an option:${NC}"
                echo " 1) ${GR}Create blank image${NC}"
                echo " 2) ${GR}Create from existing files/folders${NC}"
                echo
                read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " disk_creation_choice
                handle_navigation_input "$disk_creation_choice"
                nav=$?
                if [[ $nav -eq $NAV_QUIT ]]; then
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    break
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                fi
                
                vol_name=""    
                custom_vol_name=""
                display_chosen_disk_image_name=""
                display_pending_disk_image_name=""

                disk_img_size=""
                custom_disk_img_size=""
                display_chosen_disk_image_size=""
                display_pending_disk_image_size=""

                use_password_active=""

                case $disk_creation_choice in 
                    1)
                        create_from_source=false
                    ;;
                    2)
                        create_from_source=true
                    ;;
                    *)
                        echo -n "❌ ${RE}Invalid choice.${NC} "
                        read -r -t 1 -n 1
                        continue
                    ;;
                esac

                # Creation Loop 2: Create from source (buffer loop)
                while true; do
                    # Source files loop - skipped for new images
                    if   [[ "$create_from_source" == "true" ]]; then
                        prep_sources_with_defs() {
                            # singular vars
                            path_or_paths="path"
                            this_or_these="this"
                            item_or_items="item"

                            # Sort paths_to_process by basename
                            if [[ "${#sources_to_add[@]}" -gt 1 ]]; then
                                sorted_files=()
                                while IFS='|' read -r fname fpath; do
                                    sorted_files+=("$fpath")
                                done < <(for f in "${sources_to_add[@]}"; do
                                    printf '%s|%s\n' "$(basename "$f")" "$f"
                                done | sort -t'|' -k1,1)

                                sources_to_add=("${sorted_files[@]}")

                                # plural vars
                                path_or_paths="paths"
                                this_or_these="these"
                                item_or_items="items"
                            fi

                            path_count="${#sources_to_add[@]}"

                            # Set existing_vol_name from first source (for default naming)
                            existing_vol_name=$(basename "${sources_to_add[0]}")

                            # Calculate total size in MB
                            total_size=0
                            for path in "${sources_to_add[@]}"; do
                                # Get size in 512-byte blocks, convert to MB
                                path_size=$(du -sk "$path" | awk '{print $1}')
                                total_size=$((total_size + path_size))
                            done

                            # Convert from KB to MB and add ~10% overhead for filesystem
                            calculated_size=$(( (total_size / 1024) + (total_size / 1024 / 10) + 1 ))

                            # Ensure minimum size of 2MB (absolute technical minimum for APFS)
                            # Users can resize the image later if needed
                            if [[ $calculated_size -lt 2 ]]; then
                                existing_img_size=2
                            else
                                existing_img_size=$calculated_size
                            fi

                        }
                        
                        prep_sources_without_defs() {
                            # Sort paths_to_process by basename
                            if [[ "${#sources_to_add[@]}" -gt 1 ]]; then
                                sorted_files=()
                                while IFS='|' read -r fname fpath; do
                                    sorted_files+=("$fpath")
                                done < <(for f in "${sources_to_add[@]}"; do
                                    printf '%s|%s\n' "$(basename "$f")" "$f"
                                done | sort -t'|' -k1,1)

                                sources_to_add=("${sorted_files[@]}")
                            fi

                            path_count="${#sources_to_add[@]}"

                            # Set existing_vol_name from first source (for default naming)
                            existing_vol_name=$(basename "${sources_to_add[0]}")

                            # Calculate total size in MB
                            total_size=0
                            for path in "${sources_to_add[@]}"; do
                                # Get size in 512-byte blocks, convert to MB
                                path_size=$(du -sk "$path" | awk '{print $1}')
                                total_size=$((total_size + path_size))
                            done

                            # Convert from KB to MB and add ~10% overhead for filesystem
                            calculated_size=$(( (total_size / 1024) + (total_size / 1024 / 10) + 1 ))

                            # Ensure minimum size of 2MB (absolute technical minimum for APFS)
                            # Users can resize the image later if needed
                            if [[ $calculated_size -lt 2 ]]; then
                                existing_img_size=2
                            else
                                existing_img_size=$calculated_size
                            fi
                        }
                        
                        existing_vol_name=""
                        existing_img_size=""

                        trap - SIGINT
                        interrupted=false
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                        clear
                        echo "${GR}═══════════════════════════${GR}╗${NC}"
                        echo "${BO}Select Source Files/Folders${GR}║${NC}"
                        echo "${GR}═══════════════════════════${GR}╝${NC}"
                        echo_justified "↩ Create New Disk Image [Options]" "Confirm Auto-Generated Name ↪"
                        show_nav_prompt_centered
                        show_path_picker_options
                        read -rp "" input
                        handle_navigation_input "$input"
                        nav=$?
                        if [[ $nav -eq $NAV_QUIT ]]; then
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            break
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        fi

                        # Handle Path Picker Options (all input methods flow into sources_to_add)
                        local sources_to_add=()

                        case "$input" in
                            1) open /System/Library/CoreServices/Finder.app; continue ;;
                            2)
                                # Open Finder open panel (for files)
                                local selected_paths=$(osascript -e 'try' \
                                                -e 'set fileList to choose file with prompt "Choose source files for disk image" with multiple selections allowed' \
                                                -e 'set pathList to {}' \
                                                -e 'repeat with aFile in fileList' \
                                                -e '    set end of pathList to POSIX path of aFile' \
                                                -e 'end repeat' \
                                                -e 'set AppleScript'"'"'s text item delimiters to linefeed' \
                                                -e 'set pathString to pathList as text' \
                                                -e 'return pathString' \
                                                -e 'on error' \
                                                -e 'return ""' \
                                                -e 'end try')
                                if [[ -n "$selected_paths" ]]; then
                                    while IFS= read -r line; do
                                        if [[ -n "$line" ]]; then
                                            # Normalize path by removing trailing slash
                                            line="${line%/}"
                                            sources_to_add+=("$line")
                                        fi
                                    done <<< "$selected_paths"
                                else
                                    echo "❌ ${RE}No selection made.${NC}"
                                    echo -n "   Please try again. "
                                    read -r -t 1 -n 1
                                    continue
                                fi
                                ;;
                            3)
                                # Open Finder open panel (for folders)
                                local selected_path=$(osascript -e 'try' \
                                                -e 'set p to POSIX path of (choose folder with prompt "Choose source folder for disk image")' \
                                                -e 'return p' \
                                                -e 'on error' \
                                                -e 'return ""' \
                                                -e 'end try')
                                if [[ -n "$selected_path" && -e "$selected_path" ]]; then
                                    # Normalize path by removing trailing slash
                                    selected_path="${selected_path%/}"
                                    sources_to_add=("$selected_path")
                                else
                                    echo "❌ ${RE}No selection made.${NC}"
                                    echo -n "   Please try again. "
                                    read -r -t 1 -n 1
                                    continue
                                fi
                                ;;
                            4)
                                if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                                    echo "❌ ${RE}No saved path(s) found.${NC}"
                                    echo -n "   Please provide path(s) again. "
                                    read -r -t 3 -n 1
                                    continue
                                fi

                                local valid_paths=()
                                local invalid_paths=()

                                # Validate saved paths still exist
                                for saved_path in "${saved_paths_to_process[@]}"; do
                                    if [[ -e "$saved_path" ]]; then
                                        valid_paths+=("$saved_path")
                                    else
                                        invalid_paths+=("$saved_path")
                                    fi
                                done

                                # check if there are valid paths to process
                                if [[ "${#valid_paths[@]}" -eq 0 ]]; then
                                    echo "❌ ${RE}No valid saved path(s) to process.${NC}"
                                    echo -n "   Please provide path(s) again. "
                                    read -r -t 3 -n 1
                                    continue
                                fi

                                if [[ "${#invalid_paths[@]}" -gt 0 ]]; then
                                    show_invalid_path_prompt
                                    read -rp "➡️  ${GR}Press Enter to continue with valid paths (or ${BL}nav${NC} ${GR}choice):${NC} " invalid_path_choice
                                    handle_navigation_input "$invalid_path_choice"
                                    nav=$?
                                    if   [[ $nav -eq $NAV_QUIT ]]; then 
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        continue
                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                        continue
                                    fi
                                fi

                                use_saved_paths=true
                                ;;
                            5)
                                if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                                    echo "❌ ${RE}No saved path(s) to clear.${NC}"
                                    echo -n "   Please provide path(s) again. "
                                    read -r -t 3 -n 1
                                    continue
                                else
                                    # Clear Saved Path(s)
                                    trap - SIGINT
                                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                                    show_clear_saved_paths_prompt
                                    read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                                    handle_navigation_input "$saved_paths_choice"
                                    nav=$?
                                    if   [[ $nav -eq $NAV_QUIT ]]; then
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then 
                                        continue
                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                        continue
                                    fi

                                    case $saved_paths_choice in
                                        y|Y)
                                            clear_saved_path_data
                                            # echo -n "✅ ${GR}Cleared all saved paths.${NC} "
                                            # read -r -t 1 -n 1
                                            continue
                                            ;;
                                        *)
                                            # echo -n "❌ ${RE}Cancelled.${NC} "
                                            # read -r -t 1 -n 1
                                            continue
                                            ;;
                                    esac
                                fi
                                ;;
                            /)
                                echo "❌ ${RE}The root directory cannot be chosen.${NC}"
                                echo -n "   Please provide another path. "
                                read -r -t 3 -n 1
                                continue
                                ;;
                            *)
                                # Process drag & drop input to handle escaped spaces and quoted paths
                                eval "set -- $input"

                                local arg_count=$#

                                if [[ "$arg_count" -eq 0 ]]; then
                                    echo "❌ ${RE}No paths provided.${NC}"
                                    echo -n "   Please try again. "
                                    read -r -t 1 -n 1
                                    continue
                                fi

                                local invalid_paths=()

                                # Process each input path
                                for path in "$@"; do
                                    if [[ -e "$path" ]]; then
                                        sources_to_add+=("$path")
                                    else
                                        invalid_paths+=("$path")
                                    fi
                                done

                                # check if there are valid paths to process
                                if [[ "${#sources_to_add[@]}" -eq 0 ]]; then
                                    echo "❌ ${RE}No valid files to process.${NC}"
                                    echo -n "   Please try again. "
                                    read -r -t 1 -n 1
                                    continue
                                fi

                                if [[ "${#invalid_paths[@]}" -gt 0 ]]; then
                                    show_invalid_path_prompt
                                    read -rp "➡️  ${GR}Press Enter to continue with valid paths (or ${BL}nav${NC} ${GR}choice):${NC} " invalid_path_choice
                                    handle_navigation_input "$invalid_path_choice"
                                    nav=$?
                                    if   [[ $nav -eq $NAV_QUIT ]]; then 
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        continue
                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                        continue
                                    fi
                                fi
                                ;;
                        esac

                        # Handle Saved Paths
                        if   [[ "$use_saved_paths" == "true" ]]; then
                            use_saved_paths=false
                            sources_to_add=("${valid_paths[@]}")
                            prep_sources_without_defs
                        elif [[ "$DontAskAgainAbout_SavingPaths_Path_Picker" == "true" ]]; then
                            if [[ "${#sources_to_add[@]}" -gt 0 ]]; then
                                prep_sources_without_defs
                            else
                                continue
                            fi
                        elif [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                            # Prompt to Save Path(s)
                            trap - SIGINT
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

                            if [[ "${#sources_to_add[@]}" -gt 0 ]]; then
                                prep_sources_with_defs
                            else
                                continue
                            fi

                            show_save_path_confirmation
                            read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                            handle_navigation_input "$saved_paths_choice"
                            nav=$?
                            if   [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then 
                                continue
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            case $saved_paths_choice in
                                1)
                                    saved_paths_to_process=("${sources_to_add[@]}")
                                    save_paths_to_file
                                    ;;
                                2)
                                    DontAskAgainAbout_SavingPaths_Path_Picker="true"
                                    save_pref "DontAskAgainAbout_SavingPaths_Path_Picker" "true"
                                    ;;
                            esac
                        elif [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                            if [[ "$DontAskAgainAbout_OverwritingPaths_Path_Picker" == "false" ]]; then
                                # Prompt to Overwrite Saved Path(s)
                                trap - SIGINT
                                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

                                if [[ "${#sources_to_add[@]}" -gt 0 ]]; then
                                    prep_sources_without_defs
                                else
                                    continue
                                fi
                                
                                show_overwrite_saved_path_confirmation
                                show_overwrite_saved_path_options
                                read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                                handle_navigation_input "$saved_paths_choice"
                                nav=$?
                                if   [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then 
                                    continue
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                case $saved_paths_choice in
                                    1)
                                        saved_paths_to_process=("${sources_to_add[@]}")
                                        save_paths_to_file
                                        set_plurality_for_saved_paths_to_process
                                        # echo -n "✅ ${GR}Overwritten.${NC} "
                                        # read -r -t 1 -n 1
                                        ;;
                                    2)
                                        DontAskAgainAbout_OverwritingPaths_Path_Picker=true
                                        save_pref "DontAskAgainAbout_OverwritingPaths_Path_Picker" "true"
                                        ;;
                                    *)
                                        # echo -n "❌ ${RE}Cancelled.${NC} "
                                        # read -r -t 1 -n 1
                                        # Continue with provided path(s) without overwriting
                                        # continue
                                        :
                                        ;;
                                esac
                            else
                                # Continue with provided path(s) without overwriting
                                if [[ "${#sources_to_add[@]}" -gt 0 ]]; then
                                    prep_sources_without_defs
                                else
                                    continue
                                fi
                            fi
                        else
                            # Should never reach here - all states covered above
                            if [[ "${#sources_to_add[@]}" -gt 0 ]]; then
                                prep_sources_without_defs
                            else
                                continue
                            fi
                        fi
                    elif [[ "$create_from_source" == "false" ]]; then
                        if [[ "$interrupted" == "true" ]]; then
                            break
                        fi
                    else
                        break
                    fi

                    # Creation Loop 3: Choose Name
                    while true; do
                        trap - SIGINT
                        interrupted=false
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                        if [[ -n "$existing_vol_name" ]] && [[ -z "$custom_vol_name" ]]; then
                            clear
                            echo "${GR}═══════════════════════════${GR}╗${NC}"
                            echo "${BO}Confirm Auto-Generated Name${GR}║${NC}"
                            echo "${GR}═══════════════════════════${GR}╝${NC}"
                            echo_justified "↩ Select Source Files/Folders" "Confirm Minimum Capacity ↪"
                            show_nav_prompt_centered

                            populate_pending_disk_image_info # already bottom-padded

                            vol_name=""
                            no_custom_size_provided_yet="true"    # used mainly for navigation

                            echo "${BO}Use the name:${NC} '$existing_vol_name'?"
                            echo " 1) ${GR}Yes${NC}"
                            echo " 2) ${GR}Custom name${NC}"
                            echo
                            read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " vol_name_input
                            handle_navigation_input "$vol_name_input"
                            nav=$?
                            if [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                existing_vol_name=""
                                custom_vol_name=""
                                vol_name=""
                                break
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            case $vol_name_input in
                                1) 
                                    # using existing_vol_name
                                    vol_name="$existing_vol_name"
                                ;;
                                2) 
                                    # set custom_vol_name here so that we continue this while loop,
                                    # and then hit the 2nd condition '[[ -n "$custom_vol_name" ]]' in this block
                                    custom_vol_name="placeholder"
                                    continue
                                ;;
                                *)
                                    echo -n "❌ ${RE}Invalid choice.${NC} "
                                    read -r -t 1 -n 1
                                    continue
                                    ;;
                            esac
                        elif [[ -n "$custom_vol_name" ]]; then
                            clear
                            echo "${GR}═══════════════════════${GR}╗${NC}"
                            echo "${BO}Set New Disk Image Name${GR}║${NC}"
                            echo "${GR}═══════════════════════${GR}╝${NC}"
                            echo_justified "↩ Confirm Auto-Generated Name" "Choose Capacity ↪"
                            show_nav_prompt_centered
                            populate_pending_disk_image_info # already bottom-padded
                            read -rp "➡️  ${GR}Enter a new name for the disk image${NC}: " custom_vol_name
                            handle_navigation_input "$custom_vol_name"
                            nav=$?
                            if [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                if [[ "$create_from_source" == "true" ]]; then
                                    custom_vol_name=""
                                    continue
                                fi
                                break
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            if [[ -n "$custom_vol_name" ]]; then
                                vol_name="$custom_vol_name"
                            else
                                echo -n "❌ ${RE}Name cannot be empty.${NC} "
                                read -r -t 1 -n 1
                                continue
                            fi
                        else
                            clear
                            echo "${GR}═══════════════════${GR}╗${NC}"
                            echo "${BO}Set Disk Image Name${GR}║${NC}"
                            echo "${GR}═══════════════════${GR}╝${NC}"
                            echo_justified "↩ Create New Disk Image [Options]" "Choose Capacity ↪"
                            show_nav_prompt_centered
                            populate_pending_disk_image_info # already bottom-padded
                            read -rp "➡️  ${GR}Enter a name for the disk image${NC}: " new_vol_name
                            handle_navigation_input "$new_vol_name"
                            nav=$?
                            if [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                if [[ "$create_from_source" == "true" ]]; then
                                    break
                                fi
                                break 2
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            if [[ -n "$new_vol_name" ]]; then
                                vol_name="$new_vol_name"
                            else
                                echo -n "❌ ${RE}Name cannot be empty.${NC} "
                                read -r -t 1 -n 1
                                continue
                            fi
                        fi

                        # Creation Loop 4: Choose Size
                        while true; do
                            trap - SIGINT
                            interrupted=false
                            if [[ -z "$sparse_image_capacity_after" ]]; then
                                parse_image_capacity_after=""
                            fi
                            if [[ -z "$sparse_image_file_size_after" ]]; then
                                sparse_image_file_size_after=""
                            fi
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                            if [[ -n "$existing_vol_name" ]] && [[ -z "$custom_vol_name" ]]; then
                                if [[ $no_custom_size_provided_yet == "true" ]]; then
                                    clear
                                    echo "${GR}════════════════════════${GR}╗${NC}"
                                    echo "${BO}Confirm Minimum Capacity${GR}║${NC}"
                                    echo "${GR}════════════════════════${GR}╝${NC}"
                                    echo_justified "↩ Confirm Auto-Generated Name" "Encryption ↪"
                                else
                                    clear
                                    echo "${GR}═══════════════════${GR}╗${NC}"
                                    echo "${BO}Choose New Capacity${GR}║${NC}"
                                    echo "${GR}═══════════════════${GR}╝${NC}"
                                    echo_justified "↩ Confirm Minimum Capacity" "Encryption ↪"
                                fi
                            else
                                if [[ "$create_from_source" == "true" ]]; then
                                    clear
                                    echo "${GR}════════════════════════${GR}╗${NC}"
                                    echo "${BO}Confirm Minimum Capacity${GR}║${NC}"
                                    echo "${GR}════════════════════════${GR}╝${NC}"
                                    echo_justified "↩ Set New Disk Image Name" "Encryption ↪"
                                else
                                    clear
                                    echo "${GR}═══════════════${GR}╗${NC}"
                                    echo "${BO}Choose Capacity${GR}║${NC}"
                                    echo "${GR}═══════════════${GR}╝${NC}"
                                    echo_justified "↩ Set Disk Image Name" "Encryption ↪"
                                fi
                            fi
                            show_nav_prompt_centered
                            populate_pending_disk_image_info # already bottom-padded

                            if [[ -n "$existing_img_size" ]] && [[ $no_custom_size_provided_yet == "true" ]]; then
                                # Format size display using helper function
                                if [[ -z "$sparse_image_file_size_after" ]]; then
                                    size_display="$(format_disk_size_display "$existing_img_size")"
                                else
                                    size_display="$sparse_image_file_size_after"
                                fi

                                if [[ $calculated_size -lt 2 ]] || [[ "$create_from_source" == "true" ]]; then
                                    echo "${BO}Use the minimum required capacity:${NC} ${size_display}?"
                                else
                                    echo "${BO}Use the capacity:${NC} ${size_display}?"
                                fi
                                echo " 1) ${GR}Yes${NC}"
                                echo " 2) ${GR}Custom size${NC}"
                                echo
                                echo "💡 ${GY}You can always resize this later!${NC}"
                                echo
                                read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " custom_size_input
                                handle_navigation_input "$custom_size_input"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi
                                
                                case $custom_size_input in
                                    1) 
                                        disk_img_size="$existing_img_size"
                                        no_custom_size_provided_yet="false"  # used mainly for navigation
                                    ;;
                                    2) 
                                        no_custom_size_provided_yet="false"  # used mainly for navigation
                                        custom_img_size=""
                                        continue 
                                    ;;
                                    *)
                                        echo -n "❌ ${RE}Invalid choice.${NC} "
                                        read -r -t 1 -n 1
                                        continue
                                        ;;
                                esac
                            else
                                if [[ "$create_from_source" == "true" ]]; then
                                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; no_custom_size_provided_yet="true"; continue;' SIGINT
                                else
                                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break;' SIGINT
                                fi
                                echo "${BO}Choose a preset:${NC} ${GY}(or choose Custom)${NC}"
                                display_four_column_size_options
                                echo
                                echo_centered "💡 ${GY}A sparse disk image will NOT use this space until you fill it up!${NC}"
                                echo
                                echo_n_centered "➡️  ${GR}Choose capacity (or ${BL}nav${NC} ${GR}choice):${NC} "
                                read -r disk_img_size_input
                                handle_navigation_input "$disk_img_size_input"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    if [[ "$create_from_source" == "true" ]]; then
                                        no_custom_size_provided_yet="true"  # used mainly for navigation
                                        continue
                                    fi
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                case "$disk_img_size_input" in
                                    1) disk_img_size="2m";;
                                    2) disk_img_size="5m";;
                                    3) disk_img_size="15m";;
                                    4) disk_img_size="25m";;
                                    5) disk_img_size="50m";;
                                    6) disk_img_size="100m";;
                                    7) disk_img_size="500m";;
                                    8) disk_img_size="750m";;
                                    9) disk_img_size="1g";;
                                    10) disk_img_size="2g";;
                                    11) disk_img_size="3g";;
                                    12) disk_img_size="4g";;
                                    13) disk_img_size="5g";;
                                    14) disk_img_size="6g";;
                                    15) disk_img_size="7g";;
                                    16) disk_img_size="8g";;
                                    17) disk_img_size="10g";;
                                    18) disk_img_size="15g";;
                                    19) disk_img_size="25g";;
                                    20) disk_img_size="50g";;
                                    21) disk_img_size="100g";;
                                    22) disk_img_size="250g";;
                                    23) disk_img_size="500g";;
                                    24) disk_img_size="750g";;
                                    25) disk_img_size="1t";;
                                    26) disk_img_size="2t";;
                                    27) disk_img_size="3t";;
                                    28) disk_img_size="4t";;
                                    29) disk_img_size="5t";;
                                    30) disk_img_size="6t";;
                                    31) disk_img_size="7t";;
                                    32)
                                        # Creation Loop 5/Custom Size Loop 1: Choose Custom Size
                                        while true; do
                                            trap - SIGINT
                                            interrupted=false
                                            if [[ "$create_from_source" == "true" ]]; then
                                                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; no_custom_size_provided_yet="true"; break;' SIGINT
                                            else
                                                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                                            fi
                                            clear
                                            echo "${GR}════════════════${GR}╗${NC}"
                                            echo "${BO}Custom Capacity${GR}║${NC}"
                                            echo "${GR}════════════════${GR}╝${NC}"
                                            if [[ "$create_from_source" == "true" ]]; then
                                                echo_justified "↩ Choose New Capacity" "Encryption ↪"
                                            else
                                                echo_justified "↩ Choose Capacity" "Encryption ↪"
                                            fi
                                            show_nav_prompt_centered

                                            populate_pending_disk_image_info # already bottom-padded
                                            
                                            read -rp "➡️  ${GR}Enter custom size (whole number - e.g., 2m, 500m, 1g, 500g, 1t, etc.)${NC}: " custom_capacity_size
                                            handle_navigation_input "$custom_capacity_size"
                                            nav=$?
                                            if [[ $nav -eq $NAV_QUIT ]]; then
                                                return 0
                                            elif [[ $nav -eq $NAV_BACK ]]; then
                                                if [[ "$create_from_source" == "true" ]]; then
                                                    no_custom_size_provided_yet="true"  # used mainly for navigation
                                                    break
                                                fi
                                                continue 2
                                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                continue
                                            fi
                                            
                                            # Convert to lowercase and remove all spaces for case-insensitive matching
                                            # This handles formats like "5 GBs" or "100 MB" by normalizing to "5gbs" or "100mb"
                                            custom_size_lower=$(echo "$custom_capacity_size" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
                                            
                                            # Extract number and unit - handle formats:
                                            # number, number+m, number+mb, number+mbs, number+g, number+gb, number+gbs number+t, number+tb, number+tbs
                                            # (spaces are already removed above, so pattern doesn't need to account for them)
                                            if echo "$custom_size_lower" | grep -E '^[0-9]+(m|mb|mbs|g|gb|gbs|t|tb|tbs)?$' >/dev/null 2>&1; then
                                                # Check if it ends with 'm', 'mb', or 'mbs' (MB)
                                                if echo "$custom_size_lower" | grep -E '(m|mb|mbs)$' >/dev/null 2>&1; then
                                                    # Use separate checks for BSD sed compatibility (macOS default) - check longest first
                                                    if echo "$custom_size_lower" | grep -E 'mbs$' >/dev/null 2>&1; then
                                                        size_number=$(echo "$custom_size_lower" | sed 's/mbs$//')
                                                    elif echo "$custom_size_lower" | grep -E 'mb$' >/dev/null 2>&1; then
                                                        size_number=$(echo "$custom_size_lower" | sed 's/mb$//')
                                                    else
                                                        size_number=$(echo "$custom_size_lower" | sed 's/m$//')
                                                    fi
                                                    if [[ "$size_number" -gt 1 ]]; then
                                                        disk_img_size="${size_number}m"
                                                        break
                                                    else
                                                        echo -n "❌ ${RE}Please enter a number greater than 1 MB.${NC} "
                                                        read -r -t 2 -n 1
                                                        continue
                                                    fi
                                                # Check if it ends with 'g', 'gb', or 'gbs' (GB)
                                                elif echo "$custom_size_lower" | grep -E '(g|gb|gbs)$' >/dev/null 2>&1; then
                                                    # Use separate checks for BSD sed compatibility (macOS default) - check longest first
                                                    if echo "$custom_size_lower" | grep -E 'gbs$' >/dev/null 2>&1; then
                                                        size_number=$(echo "$custom_size_lower" | sed 's/gbs$//')
                                                    elif echo "$custom_size_lower" | grep -E 'gb$' >/dev/null 2>&1; then
                                                        size_number=$(echo "$custom_size_lower" | sed 's/gb$//')
                                                    else
                                                        size_number=$(echo "$custom_size_lower" | sed 's/g$//')
                                                    fi
                                                    if [[ "$size_number" -gt 0 ]]; then
                                                        disk_img_size="${size_number}g"
                                                        break
                                                    else
                                                        echo -n "❌ ${RE}Please enter a number greater than 0.${NC} "
                                                        read -r -t 2 -n 1
                                                        continue
                                                    fi
                                                elif echo "$custom_size_lower" | grep -E '(t|tb|tbs)$' >/dev/null 2>&1; then
                                                    # Use separate checks for BSD sed compatibility (macOS default) - check longest first
                                                    if echo "$custom_size_lower" | grep -E 'tbs$' >/dev/null 2>&1; then
                                                        size_number=$(echo "$custom_size_lower" | sed 's/tbs$//')
                                                    elif echo "$custom_size_lower" | grep -E 'tb$' >/dev/null 2>&1; then
                                                        size_number=$(echo "$custom_size_lower" | sed 's/tb$//')
                                                    else
                                                        size_number=$(echo "$custom_size_lower" | sed 's/t$//')
                                                    fi
                                                    if [[ "$size_number" -gt 0 ]]; then
                                                        disk_img_size="${size_number}t"
                                                        break
                                                    else
                                                        echo -n "❌ ${RE}Please enter a number greater than 0.${NC} "
                                                        read -r -t 2 -n 1
                                                        continue
                                                    fi
                                                # No unit specified, default to MB (safer default to prevent accidentally huge images)
                                                else
                                                    if [[ "$custom_capacity_size" -gt 1 ]]; then
                                                        disk_img_size="${custom_capacity_size}m"
                                                        break
                                                    else
                                                        echo -n "❌ ${RE}Please enter a number greater than 1 MB.${NC} "
                                                        read -r -t 2 -n 1
                                                        continue
                                                    fi
                                                fi
                                            else
                                                echo -n "❌ ${RE}Please enter a valid size.${NC} "
                                                read -r -t 1 -n 1
                                                continue
                                            fi
                                        done    
                                        ;;
                                    *)
                                        echo_n_centered "❌ ${RE}Invalid choice.${NC} "
                                        read -r -t 1 -n 1
                                        continue
                                        ;;
                                esac
                            fi

                            # Skip validation if user navigated back from custom size prompt
                            if [[ "$no_custom_size_provided_yet" == "true" ]]; then
                                no_custom_size_provided_yet=false  # used mainly for navigation
                                continue
                            fi

                            # Validate disk image size if creating from source files
                            if [[ "$create_from_source" == "true" && -n "$calculated_size" && ${#sources_to_add[@]} -gt 0 ]]; then
                                # Convert disk_img_size (format like "1m", "5g", or bare number) to MB for comparison
                                disk_img_size_mb="$(convert_disk_size_to_mb "$disk_img_size")"
                                
                                # Compare with calculated_size (already in MB with overhead)
                                if [[ $disk_img_size_mb -lt $calculated_size ]]; then
                                    # Format sizes for display
                                    required_size_display="$(format_disk_size_display "$calculated_size")"
                                    chosen_size_display="$(format_disk_size_display "$disk_img_size")"
                                    
                                    echo
                                    echo "❌ ${RE}Disk image size is too small!${NC}"
                                    echo "   ${BO}Source files require at least:${NC} ${YE}$required_size_display${NC}"
                                    echo "   ${BO}Size chosen:${NC} ${RE}$chosen_size_display${NC}"
                                    echo "   ${GY}Please choose a larger size.${NC}"
                                    echo
                                    read -rp "➡️  ${GR}Press Enter to choose a different size (or ${BL}nav${NC} ${GR}choice):${NC} " input
                                    handle_navigation_input "$input"
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        no_custom_size_provided_yet="false"  # used mainly for navigation
                                        continue
                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                        continue
                                    fi
                                    # Reset disk_img_size and continue loop to re-prompt
                                    disk_img_size=""
                                    no_custom_size_provided_yet="false"  # used mainly for navigation
                                    continue
                                fi
                            fi

                            # Creation Loop 5: Choose Encryption Preference
                            while true; do
                                trap - SIGINT
                                interrupted=false
                                if [[ "$create_from_source" == "true" ]]; then
                                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; no_custom_size_provided_yet="true"; break' SIGINT
                                else
                                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                                fi
                                use_password=""
                                password_value=""
                                clear
                                echo "${GR}════════════════════${GR}╗${NC}"
                                echo "${BO}Encryption (AES-256)${GR}║${NC}"
                                echo "${GR}════════════════════${GR}╝${NC}"
                                if [[ "$create_from_source" == "true" ]]; then
                                    echo_justified "↩ Confirm Minimum Capacity" "Choose Save Location ↪"
                                else
                                    echo_justified "↩ Choose Capacity" "Choose Save Location ↪"
                                fi
                                show_nav_prompt_centered
                                populate_pending_disk_image_info # already bottom-padded
                                echo "${BO}Set a password?${NC}"
                                echo " 1) ${GR}Yes${NC}"
                                echo " 2) ${RE}No${NC}"
                                echo
                                read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " pw_choice
                                handle_navigation_input "$pw_choice"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    disk_img_size=""
                                    custom_img_size=""
                                    if [[ "$create_from_source" == "true" ]]; then
                                        no_custom_size_provided_yet="true"  # used mainly for navigation
                                    fi
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                case "$pw_choice" in
                                    1) use_password="yes" ;;
                                    2) use_password="no"; use_password_active="false" ;;
                                    *)
                                        echo -n "❌ ${RE}Invalid choice.${NC} "
                                        read -r -t 1 -n 1
                                        continue
                                        ;;
                                esac

                                if [[ "$use_password" == "yes" ]]; then
                                    # Creation Loop 6/Encryption Loop 1: Set Encryption
                                    while true; do
                                        trap - SIGINT
                                        interrupted=false
                                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                                        clear
                                        echo "${GR}════════════════════${GR}╗${NC}"
                                        echo "${BO}Encryption (AES-256)${GR}║${NC}"
                                        echo "${GR}════════════════════${GR}╝${NC}"
                                        echo_justified "↩ Choose Disk Image Size" "Choose Save Location ↪"
                                        show_nav_prompt_centered
                                        populate_pending_disk_image_info # already bottom-padded
                                        read -s -p "➡️  ${GR}Enter a password${NC}: " pw1
                                        handle_navigation_input "$pw1"
                                        nav=$?
                                        if [[ $nav -eq $NAV_QUIT ]]; then
                                            return 0
                                        elif [[ $nav -eq $NAV_BACK ]]; then
                                            continue 2
                                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                            continue
                                        fi
                                        echo
                                        if [[ -z "$pw1" ]]; then
                                            echo -n "❌ ${RE}Password cannot be empty.${NC} "
                                            read -r -t 1 -n 1
                                            continue
                                        fi

                                        # Creation Loop 7/Encryption Loop 2: Verify Encryption
                                        while true; do
                                            read -s -p "➡️  ${GR}Confirm password${NC}: " pw2
                                            handle_navigation_input "$pw2"
                                            nav=$?
                                            if [[ $nav -eq $NAV_QUIT ]]; then
                                                return 0
                                            elif [[ $nav -eq $NAV_BACK ]]; then
                                                continue 2
                                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                continue 2
                                            fi
                                            echo                 
                                            if [[ -z "$pw2" ]]; then
                                                echo -n "❌ ${RE}Password cannot be empty.${NC} "
                                                read -r -t 1 -n 1
                                                continue
                                            fi      
                                            
                                            if [[ "$pw1" != "$pw2" ]]; then 
                                                echo "❌ ${RE}Passwords do not match. Try again.${NC}"
                                                read -r -t 1 -n 1
                                                continue
                                            fi
                                            break
                                        done
                                        password_value="$pw1"
                                        use_password_active="true"
                                        break
                                    done
                                fi
                                
                                # Creation Loop 6: Choose Save Location
                                dest_dir=""
                                while true; do
                                    trap - SIGINT
                                    interrupted=false
                                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; use_password_active=""; break' SIGINT
                                    clear
                                    echo "${GR}════════════════════${GR}╗${NC}"
                                    echo "${BO}Choose Save Location${GR}║${NC}"
                                    echo "${GR}════════════════════${GR}╝${NC}"
                                    echo_justified "↩ Encryption" "Disk Image Creation ↪"
                                    show_nav_prompt_centered
                                    populate_pending_disk_image_info # already bottom-padded
                                    echo "${BO}Choose a location:${NC} ${GY}(or use drag & drop)${NC}"
                                    echo " 1) 🖥️  ${GR}Save to Desktop${NC}"
                                    echo " 2) 📩 ${GR}Save to Downloads${NC}"
                                    echo " 3) 🗄️  ${GR}Save to Documents${NC}"
                                    echo " 4) 📂 ${GR}Reveal Finder${NC} ${GY}(for Drag & Drop)${NC}"
                                    echo " 5) 📁 ${GR}Choose a custom location${NC} ${GY}(via Finder dialog)${NC}"
                                    echo
                                    echo "⬇️  ${GR}Drag & drop a folder/directory onto this window, then press Enter.${NC}"
                                    echo "   ${GY}Tip: You can also press ⌥⌘C to copy a folder as a pathname${NC}"
                                    echo
                                    read -rp "" dest_choice
                                    handle_navigation_input "$dest_choice"
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then 
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        use_password_active=""
                                        break
                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                        continue
                                    fi

                                    case $dest_choice in
                                        1) dest_dir="$HOME/Desktop" ;;
                                        2) dest_dir="$HOME/Downloads" ;;
                                        3) dest_dir="$HOME/Documents" ;;
                                        4) open /System/Library/CoreServices/Finder.app; continue ;;
                                        5) 
                                            # Open Finder save panel
                                            custom_dest_dir=$(osascript -e 'try' \
                                                            -e 'set p to POSIX path of (choose folder with prompt "Choose destination folder for the disk image")' \
                                                            -e 'return p' \
                                                            -e 'on error' \
                                                            -e 'return ""' \
                                                            -e 'end try')
                                            if [[ -n "$custom_dest_dir" && -d "$custom_dest_dir" ]]; then
                                                dest_dir="${custom_dest_dir%/}"
                                            else
                                                echo "❌ ${RE}No folder chosen.${NC}"
                                                echo -n "   Please try again. "
                                                read -r -t 1 -n 1
                                                continue
                                            fi
                                            ;;
                                        /)
                                            echo "❌ ${RE}The root directory cannot be chosen.${NC}"
                                            echo -n "   Please provide another path. "
                                            read -r -t 3 -n 1
                                            continue
                                            ;;
                                        *)
                                            # Process drag & drop input to handle escaped spaces and quoted paths
                                            eval "set -- $dest_choice"

                                            if [[ $# -eq 0 ]]; then
                                                echo "❌ ${RE}No valid input provided.${NC}"
                                                echo -n "   Please try again. "
                                                read -r -t 1 -n 1
                                                continue
                                            fi

                                            if [[ -d "$1" ]]; then
                                                dest_dir="${1%/}"
                                            else
                                                echo -n "❌ ${RE}Invalid path:${NC} " # $1 "
                                                read -r -t 1 -n 1
                                                continue
                                            fi
                                            ;;
                                    esac

                                    # # Prepare path and create image via hdiutil
                                    disk_img_path="$dest_dir/$vol_name.sparseimage"

                                    # Creation Loop 7.1: Check if disk image already exists at destination
                                    while true; do
                                        if [[ -f "$disk_img_path" ]]; then
                                            trap - SIGINT
                                            interrupted=false
                                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                                            clear
                                            echo "${GR}══════════════════${GR}╗${NC}"
                                            echo "${BO}Fix Duplicate Name${GR}║${NC}"
                                            echo "${GR}══════════════════${GR}╝${NC}"
                                            echo_justified "↩ Choose Save Location" "Creation Summary ↪"
                                            show_nav_prompt_centered
                                            populate_pending_disk_image_info # already bottom-padded
                                            echo "⚠️  ${YE}A disk image with this name already exists:${NC}"
                                            echo "   ${BO}$vol_name.sparseimage${NC}"
                                            echo
                                            echo "${BO}Choose an option:${NC}"
                                            echo " 1) 🔄 ${GR}Overwrite existing image${NC}"
                                            echo " 2) 📝 ${GR}Auto-rename${NC} ${GY}(ex. 'Image_Name (2).sparseimage')${NC}"
                                            echo " 3) ✏️  ${GR}Enter new name${NC}"
                                            echo " 4) 📁 ${GR}Choose different save location${NC}"
                                            echo
                                            read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " conflict_choice
                                            handle_navigation_input "$conflict_choice"
                                            nav=$?
                                            if   [[ $nav -eq $NAV_QUIT ]]; then
                                                return 0
                                            elif [[ $nav -eq $NAV_BACK ]]; then
                                                continue 2
                                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                continue
                                            fi
                                            
                                            case "$conflict_choice" in
                                                1)
                                                    # Overwrite - delete existing file
                                                    read -rp "✋ ${RE}Are you sure?${NC} ${BO}Type [y/N]:${NC} " overwrite_confirmation
                                                    handle_navigation_input "$overwrite_confirmation"
                                                    nav=$?
                                                    if   [[ $nav -eq $NAV_QUIT ]]; then
                                                        return 0
                                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                                        continue
                                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                        continue
                                                    fi
                                                    case "$overwrite_confirmation" in
                                                        [Yy]) : ;;
                                                        *)
                                                            echo -n "❌ ${BO}Canceled${NC} "
                                                            read -r -t 1 -n 1
                                                            continue
                                                        ;;
                                                    esac

                                                    echo "🗑️  ${YE}Removing existing image...${NC}"
                                                    rm -f "$disk_img_path"
                                                    if [[ $? -eq 0 ]]; then
                                                        echo -n "✅ ${GR}Existing image removed${NC} "
                                                        read -r -t 2 -n 1
                                                        break # advance to Creation Loop 7.2
                                                    else
                                                        echo "❌ ${RE}Failed to remove existing image${NC}"
                                                        echo -n "   Please try again. "
                                                        read -r -t 2 -n 1
                                                        continue
                                                    fi
                                                    ;;
                                                2)
                                                    # Auto-rename with smart suffix replacement
                                                    local base_vol_name="$vol_name"
                                                    local counter=2
                                                    
                                                    # Strip any existing " (number)" suffix
                                                    # This prevents "Image (2) (2)"
                                                    base_vol_name="${base_vol_name% \([0-9]*\)}"  # Remove " (2)", " (3)", etc.
                                                    
                                                    # Try incrementing numbers until we find one that doesn't exist
                                                    while true; do
                                                        local new_vol_name="${base_vol_name} (${counter})"
                                                        local test_path="$dest_dir/${new_vol_name}.sparseimage"
                                                        
                                                        if [[ ! -f "$test_path" ]]; then
                                                            vol_name="$new_vol_name"
                                                            disk_img_path="$test_path"
                                                            echo
                                                            echo -n "📝 ${GR}Using new name:${NC} ${BO}${vol_name}.sparseimage${NC} "
                                                            read -r -t 2 -n 1
                                                            break 2  # advance to Creation Loop 7.2
                                                        fi
                                                        ((counter++))
                                                        
                                                        # Safety limit to prevent infinite loop
                                                        if [[ $counter -gt 5 ]]; then
                                                            echo
                                                            echo "❌ ${RE}Too many similar duplicates exist${NC}"
                                                            echo -n "   Please try again. "
                                                            read -r -t 2 -n 1
                                                            continue 2  # continue to Creation Loop 7.1
                                                        fi
                                                    done
                                                    ;;
                                                3)
                                                    # Manual rename
                                                    read -rp "➡️  ${GR}Enter new name (without .sparseimage):${NC} " new_name
                                                    handle_navigation_input "$new_name"
                                                    nav=$?
                                                    if   [[ $nav -eq $NAV_QUIT ]]; then
                                                        return 0
                                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                                        continue
                                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                        continue
                                                    fi

                                                    if [[ -z "$new_name" ]]; then
                                                        echo "❌ ${RE}No name provided${NC}"
                                                        echo -n "   Please try again. "
                                                        read -r -t 2 -n 1
                                                        continue
                                                    fi
                                                    
                                                    disk_img_path="$dest_dir/$new_name.sparseimage"
                                                    
                                                    # Check if new name also exists
                                                    if [[ -f "$disk_img_path" ]]; then
                                                        echo "⚠️  ${YE}This name already exists!${NC}"
                                                        echo -n "   Please try again. "
                                                        read -r -t 2 -n 1
                                                        continue
                                                    fi
                                                    
                                                    read -rp "➡️  ${GR}Use the name${NC} ${BO}$new_name.sparseimage${GR} ?${NC} [y/N] " confirm
                                                    handle_navigation_input "$confirm"
                                                    nav=$?
                                                    if   [[ $nav -eq $NAV_QUIT ]]; then
                                                        return 0
                                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                                        disk_img_path="$dest_dir/$vol_name.sparseimage"
                                                        continue
                                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                        continue
                                                    fi
                                                    
                                                    case $confirm in
                                                        y|Y)
                                                            vol_name="$new_name"
                                                            disk_img_path="$dest_dir/$vol_name.sparseimage"
                                                            break  # advance to Creation Loop 7.2
                                                            ;;
                                                        *)
                                                            disk_img_path="$dest_dir/$vol_name.sparseimage"
                                                            echo -n "❌ ${RE}Canceled.${NC}"
                                                            read -r -t 1 -n 1
                                                            continue
                                                            ;;
                                                    esac

                                                    ;;
                                                4)
                                                    # Choose different location
                                                    continue 2  # continue to Creation Loop 6: Choose Save Location
                                                    ;;
                                                *)
                                                    echo
                                                    echo "❌ ${RE}Invalid choice${NC}"
                                                    echo -n "   Please try again. "
                                                    read -r -t 1 -n 1
                                                    continue
                                                    ;;
                                            esac
                                        fi
                                        break
                                    done

                                    # Creation Loop 7.2: Disk Image Creation
                                    while true; do
                                        trap - SIGINT
                                        interrupted=false
                                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                                        clear
                                        echo "${GR}══════════════════════${GR}╗${NC}"
                                        echo "${BO}🔄 Disk Image Creation${GR}║${NC}"
                                        echo "${GR}══════════════════════${GR}╝${NC}"
                                        echo_justified "↩ Choose Save Location" "Creation Summary ↪"
                                        show_nav_prompt_centered
                                        populate_pending_disk_image_info # already bottom-padded
                                        
                                        echo "🪄 ${GR}Creating Disk Image...${NC}"

                                        create_ok=0
                                        # Normalize size for hdiutil
                                        size_arg="$(normalize_disk_size_for_hdiutil "$disk_img_size")"
                                        if [[ "$use_password" == "yes" ]]; then
                                            echo "🔒 ${GR}Encrypting...${NC}"
                                            printf "%s" "$password_value" | hdiutil create -type SPARSE -fs APFS -volname "$vol_name" -size "$size_arg" -encryption AES-256 -stdinpass "$disk_img_path" >/dev/null 2>&1
                                        else
                                            hdiutil create -type SPARSE -fs APFS -volname "$vol_name" -size "$size_arg" "$disk_img_path" >/dev/null 2>&1
                                        fi

                                        if [[ $? -eq 0 ]]; then 
                                            create_ok=1
                                        fi

                                        # If from existing, attach, copy, detach
                                        copy_operation_status=""
                                        if [[ "$disk_creation_choice" == "2" && ${#sources_to_add[@]} -gt 0 ]]; then
                                            mount_point="/Volumes/$vol_name"
                                            echo "💾 ${GR}Mounting/Attaching...${NC}"
                                            # if [[ "$use_password" == "yes" ]]; then
                                            #     printf "%s" "$password_value" | hdiutil attach -stdinpass -nobrowse -mountpoint "$mount_point" "$disk_img_path" >/dev/null 2>&1
                                            # else
                                            #     hdiutil attach -nobrowse -mountpoint "$mount_point" "$disk_img_path" >/dev/null 2>&1
                                            # fi
                                            if [[ "$use_password" == "yes" ]]; then
                                                printf "%s" "$password_value" | hdiutil attach -stdinpass -mountpoint "$mount_point" "$disk_img_path" >/dev/null 2>&1
                                            else
                                                hdiutil attach -mountpoint "$mount_point" "$disk_img_path" >/dev/null 2>&1
                                            fi

                                            if [[ $? -ne 0 ]]; then
                                                echo "❌ ${RE}Failed to copy items...${NC}"
                                                copy_operation_status="failed"
                                            else
                                                copy_failed=0
                                                echo "📦 ${GR}Populating image with selected items...${NC}"
                                                for src in "${sources_to_add[@]}"; do 
                                                    cp -R "$src" "$mount_point/" >/dev/null 2>&1
                                                    if [[ $? -ne 0 ]]; then
                                                        copy_failed=1
                                                        echo "❌ ${RE}Failed to copy:${NC} $(basename "$src")"
                                                    fi
                                                done

                                                if [[ $copy_failed -eq 0 ]]; then
                                                    echo "✅ ${GR}Successfully copied items.${NC}"
                                                    copy_operation_status="success"
                                                    echo "⏏️  ${GR}Unmounting/Detaching...${NC}"
                                                    sync
                                                    hdiutil detach "$mount_point" >/dev/null 2>&1
                                                else
                                                    copy_operation_status="partial"
                                                    echo "⚠️  ${YE}Failed to copy some items...${NC}"
                                                    # echo "⏏️  ${GR}Unmounting/Detaching...${NC}"
                                                    # sync
                                                    # hdiutil detach "$mount_point" >/dev/null 2>&1
                                                fi
                                            fi
                                            read -r -t 1 -n 1
                                        fi

                                        encryption_status() {
                                            local encryption_result=$(hdiutil isencrypted "$disk_img_path" 2>&1)
                                            if echo "$encryption_result" | grep -q "encrypted: YES"; then
                                                echo "✅"
                                            elif echo "$encryption_result" | grep -q "Resource temporarily unavailable"; then
                                                # echo "Mounted"
                                                echo "⚠️ "
                                            else
                                                echo "❌"
                                            fi
                                        }
                                        # Creation Loop 8: Summary
                                        while true; do
                                            trap - SIGINT
                                            interrupted=false
                                            sparse_image_file_size_after=$(get_sparse_image_file_size "$disk_img_path")
                                            stored_enc_status=$(encryption_status "$disk_img_path")
                                            if [[ "$stored_enc_status" == "✅" ]] || [[ "$stored_enc_status" == "⚠️ " ]]; then
                                                # echo "is encrypted"
                                                if [[ -n $password_value ]]; then
                                                    # echo "password_value not empty"
                                                    sectors=$(printf "%s" "$password_value" | hdiutil resize -limits "$disk_img_path" -stdinpass 2>/dev/null | tail -1 | awk '{print $2}')
                                                    if [ -n "$sectors" ]; then
                                                        # echo "sectors not empty"
                                                        local bytes=$(( sectors * 512 ))
                                                        if [ "$bytes" -ge 1000000000000 ]; then
                                                            header_capacity=$(awk "BEGIN {printf \"%.1f TBs\", $bytes/1000000000000}")
                                                        elif [ "$bytes" -ge 1000000000 ]; then
                                                            header_capacity=$(awk "BEGIN {printf \"%.1f GBs\", $bytes/1000000000}")
                                                        elif [ "$bytes" -ge 1000000 ]; then
                                                            header_capacity=$(awk "BEGIN {printf \"%.1f MBs\", $bytes/1000000}")
                                                        else
                                                            header_capacity=$(awk "BEGIN {printf \"%.1f KBs\", $bytes/1000}")
                                                        fi
                                                        sparse_image_capacity_after="$header_capacity"   # ← snapshot after value
                                                    else
                                                        # echo "sectors empty"
                                                        sparse_image_capacity_after="$(format_disk_size_display "$disk_img_size")"
                                                    fi
                                                else
                                                    # echo "password_value is empty"
                                                    sparse_image_capacity_after="$(format_disk_size_display "$disk_img_size")"
                                                fi
                                            else
                                                # echo "is not encrypted"
                                                header_capacity=$(get_sparse_image_capacity "$disk_img_path")
                                                sparse_image_capacity_after="$header_capacity"   # ← snapshot after value
                                            fi
                                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break 2' SIGINT
                                            if [[ "$copy_operation_status" == "partial" ]]; then
                                                resize_terminal 95 27
                                            fi
                                            clear
                                            echo "${GR}═══════════════════${GR}╗${NC}"
                                            echo "${BO}🪄 Creation Summary${GR}║${NC}"
                                            echo "${GR}═══════════════════${GR}╝${NC}"
                                            echo_justified "↩ Choose Save Location" "Create New Disk Image [Options] ↪"
                                            show_nav_prompt_centered

                                            echo_centered "${BO}Current Disk Image Info:${NC}"
                                            echo "${GR}Name:${NC} $vol_name.sparseimage"
                                            echo_centered "${GR}File Size:${NC}  | $sparse_image_file_size_after |  ${GR}Capacity:${NC}  | $sparse_image_capacity_after |  ${GR}Encryption:${NC}  | $stored_enc_status |"
                                            echo

                                            if [[ -f "$disk_img_path" ]]; then
                                                if [[ "$disk_creation_choice" == "1" ]]; then
                                                    if [[ "$create_ok" -eq 1 ]]; then
                                                        echo "✅ ${GR}Disk image created successfully!${NC}"
                                                    else
                                                        echo "❌ ${RE}Failed to create disk image.${NC}"
                                                        echo "   ${GY}This could be due to insufficient disk space, permissions, or other issues.${NC}"
                                                        echo
                                                        read -rp "➡️  ${GR}Try again? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                                                        handle_navigation_input "$input"
                                                        nav=$?
                                                        if [[ $nav -eq $NAV_QUIT ]]; then
                                                            return 0
                                                        elif [[ $nav -eq $NAV_BACK ]]; then
                                                            break 2
                                                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                            continue
                                                        else
                                                            break
                                                        fi
                                                    fi
                                                elif [[ "$disk_creation_choice" == "2" ]]; then
                                                    if  [[ "$copy_operation_status" == "success" ]]; then
                                                        echo "✅ ${GR}Disk image created successfully!${NC}"
                                                    elif [[ "$copy_operation_status" == "partial" ]]; then
                                                        echo "⚠️  ${YE}Disk image partially created${NC}"
                                                        echo "   ${YE}Some files failed to copy. Disk image will remain mounted.${NC}"
                                                        echo "   ${GY}You can manually copy files or detach the image.${NC}"
                                                    else
                                                        echo "❌ ${RE}Failed to attach disk image for copying.${NC}"
                                                    fi
                                                fi

                                                echo
                                                echo "${BO}Results:${NC}"
                                                echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                                                echo "📄 ${GR}File Name:${NC}   $vol_name.sparseimage"
                                                echo "📦 ${GR}File Size:${NC}   $sparse_image_file_size_after"
                                                echo "📏 ${GR}Capacity: ${NC}   $sparse_image_capacity_after"
                                                if [[ "$stored_enc_status" == "✅" ]]; then
                                                    echo "🔒 ${GR}Encryption:${NC}  $stored_enc_status (AES-256)"                                                
                                                else
                                                    echo "🔒 ${GR}Encryption:${NC}  $stored_enc_status"
                                                fi
                                                echo "🗂️  ${GR}Location:${NC}    $dest_dir"
                                                if [[ "$disk_creation_choice" == "2" ]]; then
                                                    if [[ ${#sources_to_add[@]} -ge 2 ]]; then
                                                        echo "📁 ${GR}Seeded from:${NC} ${#sources_to_add[@]} item(s)"
                                                    else
                                                        echo "📁 ${GR}Seeded from:${NC} ${#sources_to_add[@]} item"
                                                    fi
                                                    # Display copy operation status if applicable
                                                    if [[ "$copy_operation_status" == "success" ]]; then
                                                        echo "📋 ${GR}Copy Status:${NC} ✅ ${GR}All files copied successfully${NC}"
                                                    elif [[ "$copy_operation_status" == "partial" ]]; then
                                                        echo "📋 ${GR}Copy Status:${NC} ⚠️  ${YE}Some files failed to copy${NC}"
                                                    elif [[ "$copy_operation_status" == "failed" ]]; then
                                                        echo "📋 ${GR}Copy Status:${NC} ❌ ${RE}Failed to attach disk image for copying${NC}"
                                                    fi
                                                fi
                                                echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                                            else
                                                echo "❌ ${RE}Disk image not found at destination.${NC}"
                                                echo
                                                echo "The disk image creation may have failed,"
                                                echo "or the file was not created at the expected location."
                                                echo "${BO}Please check the destination directory and try again.${NC}"
                                                echo
                                                read -rp "➡️  ${GR}Try again? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                                                handle_navigation_input "$input"
                                                nav=$?
                                                if [[ $nav -eq $NAV_QUIT ]]; then 
                                                    return 0
                                                elif [[ $nav -eq $NAV_BACK ]]; then
                                                    break 2
                                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                    continue
                                                else
                                                    break
                                                fi
                                            fi
                                            echo
                                            read -rp "➡️  ${GR}Create another image? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                                            handle_navigation_input "$input"
                                            nav=$?
                                            if [[ $nav -eq $NAV_QUIT ]]; then 
                                                return 0
                                            elif [[ $nav -eq $NAV_BACK ]]; then
                                                break 2
                                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                                continue
                                            else
                                                break 7
                                            fi
                                        done
                                    done
                                done 
                            done 
                        done                     
                    done
                done
            done
        elif [[ "$disk_util_path" == "manage" ]]; then
            # Loop 2
            while true; do
                trap - SIGINT
                interrupted=false
                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                encryption_status() {
                    local encryption_result=$(hdiutil isencrypted "$selected_disk_img_for_sizing" 2>&1)
                    if echo "$encryption_result" | grep -q "encrypted: YES"; then
                        echo "✅"
                    elif echo "$encryption_result" | grep -q "Resource temporarily unavailable"; then
                        # echo "Mounted"
                        echo "⚠️ "
                    else
                        echo "❌"
                    fi
                }

                password_input=""  # initialize (or clean up if user came back)

                clear
                echo "${GR}═══════════════════════${GR}╗${NC}"
                echo "${BO}↔️  Choose Disk Image...${GR}║${NC}"
                echo "${GR}═══════════════════════${GR}╝${NC}"
                echo_justified "↩ Home [Create or Manage Size]" "Resize/Compact Options ↪"
                show_nav_prompt_centered
                    
                echo_centered "⚠️  ${YE}Please make sure to unmount/eject the image before continuing.${NC}"
                echo_centered "${GY}(Otherwise, tasks may fail)${NC}"
                echo
                echo "${GR}Please provide your .sparseimage file to view resize/compact options.${NC}"
                echo
                echo "${BO}Path Picker Options:${NC} ${GY}(or use drag & drop)${NC}"
                echo " 1) 📂 ${GR}Reveal Finder${NC} ${GY}(for Drag & Drop)${NC}"
                echo " 2) 💾 ${GR}Choose image ${NC} ${GY}(via Finder dialog)${NC}"
                if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                    for f in "${saved_paths_to_process[@]}"; do
                        [[ "$f" == *.sparseimage ]] && { show_saved=1; break; }
                    done
                    if [[ "$show_saved" -eq 1 ]]; then
                        echo " 3) 💾 ${GR}Use saved $path_or_paths ${NC} (${#saved_paths_to_process[@]})"
                        echo " 4) 🗑️  ${GR}Clear saved $path_or_paths${NC} (${#saved_paths_to_process[@]})"
                    fi
                fi
                echo
                echo "⬇️  ${GR}Drag & drop it onto this Terminal window, then press Enter.${NC}"
                echo "   ${GY}Tip: You can also press ⌥⌘C to copy it as a pathname${NC}"
                echo
                read -rp "" disk_img_input
                handle_navigation_input "$disk_img_input"
                nav=$?
                if [[ $nav -eq $NAV_QUIT ]]; then
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    break
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                fi

                # Handle Path Picker Options
                case "$disk_img_input" in
                    1) open /System/Library/CoreServices/Finder.app; continue ;;
                    2) 
                        # Open Finder dialog (for single file)
                        selected_disk_img_for_sizing=$(osascript -e 'try' \
                                -e 'set selectedFile to choose file with prompt "Choose your .sparseimage image file" of type {"sparseimage"}' \
                                -e 'return POSIX path of selectedFile' \
                                -e 'on error' \
                                -e 'return ""' \
                                -e 'end try')
                        if [[ -n "$selected_disk_img_for_sizing" && -e "$selected_disk_img_for_sizing" ]]; then
                            # Normalize path by removing trailing slash
                            selected_disk_img_for_sizing="${selected_disk_img_for_sizing%/}"
                            
                            # Validate it's a sparseimage file
                            if [[ "$selected_disk_img_for_sizing" != *.sparseimage ]]; then
                                echo "❌ ${RE}Selected file is not a .sparseimage.${NC}"
                                echo -n "   Please try again. "
                                read -r -t 2 -n 1
                                continue
                            fi
                        else
                            echo "❌ ${RE}No file chosen.${NC}"
                            echo -n "   Please try again. "
                            read -r -t 1 -n 1
                            continue
                        fi
                        ;;
                    3)
                        # Use Saved Path(s)
                        sparse_images=()
                        for f in "${saved_paths_to_process[@]}"; do
                            [[ "$f" == *.sparseimage ]] && sparse_images+=("$f")
                        done

                        case "${#sparse_images[@]}" in
                            0)  
                                echo -n "❌ ${YE}No .sparseimage files found in saved paths.${NC} "
                                read -r -t 1 -n 1
                                continue 
                                ;;
                            1)  
                                echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                                echo "${GR}Found 1 sparse image path saved. Use this one?${NC}"
                                echo
                                echo "${BO}$(basename "${sparse_images[0]}")${NC}"
                                echo "${GY}'${sparse_images[0]}${NC}'"
                                echo
                                read -rp "➡️  ${GR}Type ${NC}[y/Y] ${GR}or press any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                                handle_navigation_input "$choice"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                case $choice in
                                    y|Y) selected_disk_img_for_sizing=("${sparse_images[0]}") ;;
                                    *) continue ;;
                                esac
                                ;;
                            *)
                                echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                                echo "⚠️  ${GR}Multiple sparse images found. Please select one:${NC}"
                                echo
                                for i in "${!sparse_images[@]}"; do
                                    echo " $((i+1))) ${BO}$(basename "${sparse_images[$i]}")${NC}"
                                done
                                echo
                                read -rp "➡️  ${GR}Enter number (1-${#sparse_images[@]}) (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                                handle_navigation_input "$choice"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi
                                if [[ "$choice" =~ ^[0-9]+$ ]] && \
                                [[ "$choice" -ge 1 ]] && \
                                [[ "$choice" -le "${#sparse_images[@]}" ]]; then
                                    selected_disk_img_for_sizing=("${sparse_images[$((choice-1))]}")
                                else
                                    echo "❌ ${RE}Invalid selection.${NC}"
                                    echo -n "   Please try again. "
                                    read -r -t 1 -n 1
                                    continue
                                fi
                                use_saved_paths=true
                                ;;
                        esac
                        ;;
                    4)
                        if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                            echo "❌ ${RE}No saved path(s) to clear.${NC}"
                            echo -n "   Please provide path(s) again. "
                            read -r -t 3 -n 1
                            continue
                        else
                            # Clear Saved Path(s)
                            trap - SIGINT
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                            show_clear_saved_paths_prompt
                            read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                            handle_navigation_input "$saved_paths_choice"
                            nav=$?
                            if   [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then 
                                continue
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            case $saved_paths_choice in
                                y|Y)
                                    clear_saved_path_data
                                    # echo -n "✅ ${GR}Cleared all saved paths.${NC} "
                                    # read -r -t 1 -n 1
                                    continue
                                    ;;
                                *)
                                    # echo -n "❌ ${RE}Cancelled.${NC} "
                                    # read -r -t 1 -n 1
                                    continue
                                    ;;
                            esac
                        fi
                        ;;
                    /)
                        echo "❌ ${RE}The root directory cannot be chosen.${NC}"
                        echo -n "   Please provide another path. "
                        read -r -t 3 -n 1
                        continue
                        ;;
                    *)
                        # Process drag & drop input to handle escaped spaces and quoted paths
                        eval "set -- $disk_img_input"
                        
                        if [[ $# -lt 1 ]]; then
                            echo "❌ ${RE}No path provided.${NC} "
                            echo -n "   Please try again. "
                            read -r -t 1 -n 1
                            continue
                        fi

                        if [[ $# -gt 1 ]]; then
                            echo "⚠️  ${RE}Multiple files not supported.${NC} "
                            echo -n "   Please provide only one. "
                            read -r -t 3 -n 1
                            continue
                        fi

                        selected_disk_img_for_sizing="$1"
                        if [[ ! -e "$selected_disk_img_for_sizing" ]]; then
                            echo "❌ ${RE}Path not found.${NC} "
                            echo -n "   Please try again. "
                            read -r -t 1 -n 1
                            continue
                        fi
                        
                        # Validate it's a sparseimage file
                        if [[ "$selected_disk_img_for_sizing" != *.sparseimage ]]; then
                            echo "❌ ${RE}File is not a .sparseimage.${NC}"
                            echo -n "   Please try again. "
                            read -r -t 2 -n 1
                            continue
                        fi
                        ;;
                esac

                # Handle Saved Paths
                if   [[ "$use_saved_paths" == "true" ]]; then
                    use_saved_paths=false
                    # prep_sources_without_defs
                elif [[ "$DontAskAgainAbout_SavingPaths_Path_Picker" == "true" ]]; then
                    # if [[ "${#sources_to_add[@]}" -gt 0 ]]; then
                    #     prep_sources_without_defs
                    # else
                    #     continue
                    # fi
                    :
                elif [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                    # Prompt to Save Path(s)
                    trap - SIGINT
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

                    # if [[ "${#sources_to_add[@]}" -gt 0 ]]; then
                    #     prep_sources_with_defs
                    # else
                    #     continue
                    # fi

                    show_save_path_confirmation
                    read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                    handle_navigation_input "$saved_paths_choice"
                    nav=$?
                    if   [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then 
                        continue
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    fi

                    case $saved_paths_choice in
                        1)
                            saved_paths_to_process=("$selected_disk_img_for_sizing")
                            save_paths_to_file
                            ;;
                        2)
                            DontAskAgainAbout_SavingPaths_Path_Picker="true"
                            save_pref "DontAskAgainAbout_SavingPaths_Path_Picker" "true"
                            ;;
                    esac
                elif [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                    if [[ "$DontAskAgainAbout_OverwritingPaths_Path_Picker" == "false" ]]; then
                        # Prompt to Overwrite Saved Path(s)
                        trap - SIGINT
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                        
                        show_overwrite_saved_path_confirmation
                        show_overwrite_saved_path_options
                        read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                        handle_navigation_input "$saved_paths_choice"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then 
                            continue
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        fi
                        
                        case $saved_paths_choice in
                            1)
                                saved_paths_to_process=("$selected_disk_img_for_sizing")
                                save_paths_to_file
                                set_plurality_for_saved_paths_to_process
                                # echo -n "✅ ${GR}Overwritten.${NC} "
                                # read -r -t 1 -n 1
                                ;;
                            2)
                                DontAskAgainAbout_OverwritingPaths_Path_Picker=true
                                save_pref "DontAskAgainAbout_OverwritingPaths_Path_Picker" "true"
                                ;;
                            *)
                                # echo -n "❌ ${RE}Cancelled.${NC} "
                                # read -r -t 1 -n 1
                                # Continue with provided path(s) without overwriting
                                # continue
                                :
                                ;;
                        esac
                    else
                        # Continue with provided path(s) without overwriting
                        :
                    fi
                else
                    # Should never reach here - all states covered above
                    :
                fi

                selected_disk_img_basename="$(basename "$selected_disk_img_for_sizing")"
                header_capacity=""
                capacity_declined=false
                capacity_before="N/A"  # snapshot for summary if user chose not unlock image

                # Loop 3: Choose Resize/Compact Options
                while true; do
                    trap - SIGINT
                    interrupted=false
                    trap 'echo; echo_n_centered "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT

                    stored_enc_status=$(encryption_status "$selected_disk_img_for_sizing")
                    if [[ "$stored_enc_status" == "✅" ]] || [[ "$stored_enc_status" == "⚠️ " ]]; then
                        # echo "is encrypted"
                        # Only prompt if we don't have it yet AND user hasn't declined
                        if [[ -z "$header_capacity" ]] && [[ "$capacity_declined" == "false" ]]; then
                            # echo "before password prompt"
                            # account for if user navigates back from summary
                            if [[ -z "$password_input" ]]; then
                                # echo "password input is empty"
                                header_capacity="${BK}🔒${NC}"
                                clear
                                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                echo "${BO}↔️  Unlock Image for Stats | $selected_disk_img_basename${NC}"
                                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                echo_justified "↩ Choose Disk Image..." "Resize/Compact Options ↪"
                                show_nav_prompt_centered
                                populate_managed_disk_image_info # already bottom-padded

                                echo_centered "🔒 ${YE}Disk Image is Encrypted${NC}"
                                echo
                                echo_centered "${GR}Reveal current capacity?${NC}"
                                echo
                                echo_n_centered "${GR}This will prompt for the disk image password.${NC} [y/N]: "
                                read -r reveal_reply
                                handle_navigation_input "$reveal_reply"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                if [[ "$reveal_reply" == "y" ]] || [[ "$reveal_reply" == "Y" ]]; then
                                    echo_n_centered "➡️  ${GR}Enter disk image password:${NC} "
                                    read -rs password_input
                                    echo
                                    
                                    sectors=$(printf "%s" "$password_input" | hdiutil resize -limits "$selected_disk_img_for_sizing" -stdinpass 2>/dev/null | tail -1 | awk '{print $2}')
                                    if [ -n "$sectors" ]; then
                                        local bytes=$(( sectors * 512 ))
                                        if [ "$bytes" -ge 1000000000000 ]; then
                                            header_capacity=$(awk "BEGIN {printf \"%.1f TBs\", $bytes/1000000000000}")
                                        elif [ "$bytes" -ge 1000000000 ]; then
                                            header_capacity=$(awk "BEGIN {printf \"%.1f GBs\", $bytes/1000000000}")
                                        elif [ "$bytes" -ge 1000000 ]; then
                                            header_capacity=$(awk "BEGIN {printf \"%.1f MBs\", $bytes/1000000}")
                                        else
                                            header_capacity=$(awk "BEGIN {printf \"%.1f KBs\", $bytes/1000}")
                                        fi
                                        capacity_before="$header_capacity"   # ← snapshot before value
                                    else
                                        password_input=""   # ← clear bad password so re-prompt works
                                        header_capacity=""
                                        echo_n_centered "❌ ${RE}Wrong password.${NC} "
                                        read -r -t 1 -n 1
                                        # header_capacity stays empty → will re-prompt next loop
                                        continue
                                    fi
                                elif [[ "$reveal_reply" == "n" ]] || [[ "$reveal_reply" == "N" ]]; then
                                    capacity_declined=true
                                    echo_n_centered "❌ ${BO}Skipped...${NC} "
                                    read -r -t 1 -n 1
                                else    
                                    header_capacity=""  # reset to trigger prompt again
                                    echo_centered "❌ ${RE}Invalid choice.${NC}"
                                    echo_n_centered "   ${BO}Please type y/Y or n/N.${NC} "
                                    read -r -t 1 -n 1
                                    continue
                                fi
                            else
                                # echo "password is already stored"
                                capacity_before="$header_capacity"   # ← snapshot new before value from summary/execution loop
                            fi
                        else
                            # echo "snapshotting new capacity from summary"
                            # use new capacity if user navigates back from summary and disk was unlocked
                            if [[ "$capacity_before" == "N/A" ]]; then
                                # echo "capacity_before is N/A"
                                :
                                # capacity_before="N/A" # ← change summary display to N/A instead of 🔒 
                            else
                                # echo "capacity_before is not N/A"
                                capacity_before="$header_capacity"   # ← snapshot NEW before value
                            fi
                        fi
                    else
                        # echo "is not encrypted"
                        header_capacity=$(get_sparse_image_capacity "$selected_disk_img_for_sizing")
                        capacity_before="$header_capacity"   # ← snapshot before value
                    fi

                    clear
                    echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                    echo "${BO}↔️  Resize/Compact Options | $selected_disk_img_basename${NC}"
                    echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                    echo_justified "↩ Choose Disk Image..." "TBD ↪"
                    show_nav_prompt_centered
                    populate_managed_disk_image_info # already bottom-padded

                    echo "${BO}Choose an option:${NC}"
                    echo " 1) ${GR}Resize ${NC} ${GY}(grow or shrink an image's maximum capacity)${NC}"
                    echo " 2) ${GR}Compact${NC} ${GY}(reclaim file size after deleting contents)${NC}"
                    if [[ $capacity_declined == "true" ]] && [[ -z "$password_input" ]]; then
                        echo " 3) ${GR}Re-prompt for password${NC} ${GY}(to reveal current capacity)${NC}"
                    fi
                    echo
                    read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " manage_choice
                    handle_navigation_input "$manage_choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    fi

                    case $manage_choice in
                        1) manage_path=resize ;;
                        2) manage_path=compact ;;
                        3) manage_path=unlock
                    esac

                    if [[ "$manage_path" == "resize" ]]; then
                        # Loop 4: Choose Capacity
                        while true; do
                            trap - SIGINT
                            interrupted=false
                            custom_img_size=""
                            trap 'echo; echo_n_centered "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                            clear
                            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                            echo "${BO}↔️  Choose Capacity | $selected_disk_img_basename${NC}"
                            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                            echo_justified "↩ Resize/Compact Options" "Resize Disk Image ↪"
                            show_nav_prompt_centered
                            populate_managed_disk_image_info # already bottom-padded

                            echo "${BO}Choose a new max capacity:${NC} ${GY}(or choose Custom)${NC}"
                            display_four_column_size_options
                            echo
                            echo_centered "💡 ${GY}A sparse disk image will NOT use this space until you fill it up!${NC}"
                            echo
                            echo_n_centered "➡️  ${GR}Choose capacity (or ${BL}nav${NC} ${GR}choice):${NC} "
                            read -r new_capacity_size
                            handle_navigation_input "$new_capacity_size"
                            nav=$?
                            if [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                continue 2
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            case "$new_capacity_size" in
                                1) new_capacity_size="2m";;
                                2) new_capacity_size="5m";;
                                3) new_capacity_size="15m";;
                                4) new_capacity_size="25m";;
                                5) new_capacity_size="50m";;
                                6) new_capacity_size="100m";;
                                7) new_capacity_size="500m";;
                                8) new_capacity_size="750m";;
                                9) new_capacity_size="1g";;
                                10) new_capacity_size="2g";;
                                11) new_capacity_size="3g";;
                                12) new_capacity_size="4g";;
                                13) new_capacity_size="5g";;
                                14) new_capacity_size="6g";;
                                15) new_capacity_size="7g";;
                                16) new_capacity_size="8g";;
                                17) new_capacity_size="10g";;
                                18) new_capacity_size="15g";;
                                19) new_capacity_size="25g";;
                                20) new_capacity_size="50g";;
                                21) new_capacity_size="100g";;
                                22) new_capacity_size="250g";;
                                23) new_capacity_size="500g";;
                                24) new_capacity_size="750g";;
                                25) new_capacity_size="1t";;
                                26) new_capacity_size="2t";;
                                27) new_capacity_size="3t";;
                                28) new_capacity_size="4t";;
                                29) new_capacity_size="5t";;
                                30) new_capacity_size="6t";;
                                31) new_capacity_size="7t";;
                                32)
                                    # Resize Loop 4.5/Custom Capacity Loop 1: Choose Custom Capacity
                                    while true; do
                                        trap - SIGINT
                                        interrupted=false
                                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                                        clear
                                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                        echo "${BO}↔️  Custom Capacity | $selected_disk_img_basename${NC}"
                                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                        echo_justified "↩ Choose Capacity" "Resize Disk Image ↪"
                                        show_nav_prompt_centered
                                        populate_managed_disk_image_info # already bottom-padded
                                        
                                        read -rp "➡️  ${GR}Enter custom size (whole number - e.g., 2m, 500m, 1g, 500g, 1t etc.)${NC}: " custom_capacity_size
                                        handle_navigation_input "$custom_capacity_size"
                                        nav=$?
                                        if [[ $nav -eq $NAV_QUIT ]]; then
                                            return 0
                                        elif [[ $nav -eq $NAV_BACK ]]; then
                                            continue 2
                                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                            continue
                                        fi
                                        
                                        # Convert to lowercase and remove all spaces for case-insensitive matching
                                        # This handles formats like "5 GBs" or "100 MB" by normalizing to "5gbs" or "100mb"
                                        custom_size_lower=$(echo "$custom_capacity_size" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
                                        
                                        # Extract number and unit - handle formats: 
                                        # number, number+m, number+mb, number+mbs, number+g, number+gb, number+gbs number+t, number+tb, number+tbs
                                        # (spaces are already removed above, so pattern doesn't need to account for them)
                                        if echo "$custom_size_lower" | grep -E '^[0-9]+(m|mb|mbs|g|gb|gbs|t|tb|tbs)?$' >/dev/null 2>&1; then
                                            # Check if it ends with 'm', 'mb', or 'mbs' (MB)
                                            if echo "$custom_size_lower" | grep -E '(m|mb|mbs)$' >/dev/null 2>&1; then
                                                # Use separate checks for BSD sed compatibility (macOS default) - check longest first
                                                if echo "$custom_size_lower" | grep -E 'mbs$' >/dev/null 2>&1; then
                                                    size_number=$(echo "$custom_size_lower" | sed 's/mbs$//')
                                                elif echo "$custom_size_lower" | grep -E 'mb$' >/dev/null 2>&1; then
                                                    size_number=$(echo "$custom_size_lower" | sed 's/mb$//')
                                                else
                                                    size_number=$(echo "$custom_size_lower" | sed 's/m$//')
                                                fi
                                                if [[ "$size_number" -gt 1 ]]; then
                                                    new_capacity_size="${size_number}m"
                                                    break
                                                else
                                                    echo -n "❌ ${RE}Please enter a number greater than 1 MB.${NC} "
                                                    read -r -t 2 -n 1
                                                    continue
                                                fi
                                            # Check if it ends with 'g', 'gb', or 'gbs' (GB)
                                            elif echo "$custom_size_lower" | grep -E '(g|gb|gbs)$' >/dev/null 2>&1; then
                                                # Use separate checks for BSD sed compatibility (macOS default) - check longest first
                                                if echo "$custom_size_lower" | grep -E 'gbs$' >/dev/null 2>&1; then
                                                    size_number=$(echo "$custom_size_lower" | sed 's/gbs$//')
                                                elif echo "$custom_size_lower" | grep -E 'gb$' >/dev/null 2>&1; then
                                                    size_number=$(echo "$custom_size_lower" | sed 's/gb$//')
                                                else
                                                    size_number=$(echo "$custom_size_lower" | sed 's/g$//')
                                                fi
                                                if [[ "$size_number" -gt 0 ]]; then
                                                    new_capacity_size="${size_number}g"
                                                    break
                                                else
                                                    echo -n "❌ ${RE}Please enter a number greater than 0.${NC} "
                                                    read -r -t 2 -n 1
                                                    continue
                                                fi
                                            elif echo "$custom_size_lower" | grep -E '(t|tb|tbs)$' >/dev/null 2>&1; then
                                                # Use separate checks for BSD sed compatibility (macOS default) - check longest first
                                                if echo "$custom_size_lower" | grep -E 'tbs$' >/dev/null 2>&1; then
                                                    size_number=$(echo "$custom_size_lower" | sed 's/tbs$//')
                                                elif echo "$custom_size_lower" | grep -E 'tb$' >/dev/null 2>&1; then
                                                    size_number=$(echo "$custom_size_lower" | sed 's/tb$//')
                                                else
                                                    size_number=$(echo "$custom_size_lower" | sed 's/t$//')
                                                fi
                                                if [[ "$size_number" -gt 0 ]]; then
                                                    new_capacity_size="${size_number}t"
                                                    break
                                                else
                                                    echo -n "❌ ${RE}Please enter a number greater than 0.${NC} "
                                                    read -r -t 2 -n 1
                                                    continue
                                                fi
                                            # No unit specified, default to MB (safer default to prevent accidentally huge images)
                                            else
                                                if [[ "$custom_capacity_size" -gt 1 ]]; then
                                                    new_capacity_size="${custom_capacity_size}m"
                                                    break
                                                else
                                                    echo -n "❌ ${RE}Please enter a number greater than 1 MB.${NC} "
                                                    read -r -t 2 -n 1
                                                    continue
                                                fi
                                            fi
                                        else
                                            echo -n "❌ ${RE}Please enter a valid size.${NC} "
                                            read -r -t 1 -n 1
                                            continue
                                        fi
                                    done    
                                    ;;
                                *)
                                    echo_n_centered "❌ ${RE}Invalid choice.${NC} "
                                    read -r -t 1 -n 1
                                    continue
                                    ;;
                            esac

                            if echo "$new_capacity_size" | grep -E '^[0-9]+[gGmMtT]$' >/dev/null 2>&1; then
                                :
                            else
                                echo_n_centered "❌ ${RE}Use units like 2m, 500m, 1g, 500g, 1t, etc.${NC} "
                                read -r -t 1 -n 1
                                continue
                            fi

                            # store old image file size
                            sparse_image_file_size_before=$(get_sparse_image_file_size "$selected_disk_img_for_sizing")
                            
                            # Loop 5: Resize/Execution loop
                            while true; do
                                trap - SIGINT
                                interrupted=false
                                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                                clear
                                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                echo "${BO}↔️  Resizing... $selected_disk_img_basename${NC}"
                                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                echo_justified "↩ Choose Capacity" "Summary ↪"
                                show_nav_prompt_centered
                                populate_managed_disk_image_info # already bottom-padded

                                echo "📏 ${GR}Resizing capacity to:${NC} $new_capacity_size..."
                                echo
                                read -rp "➡️  ${GR}Press enter to resize disk image (or ${BL}nav${NC} ${GR}choice):${NC} " confirm
                                handle_navigation_input "$confirm"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                echo
                                echo "↔️  ${GR}Resizing...${NC}"
                                echo

                                if [[ -n $password_input ]]; then
                                    resize_result=$(printf "%s" "$password_input" | hdiutil resize -size "$new_capacity_size" "$selected_disk_img_for_sizing" -stdinpass 2>&1)
                                else
                                    resize_result=$(hdiutil resize -size "$new_capacity_size" "$selected_disk_img_for_sizing" 2>&1)
                                fi

                                resize_exit_status=$?
                                if [[ $resize_exit_status -eq 0 ]]; then
                                    echo "✅ ${GR}Resized successfully${NC}"
                                    echo "↪️  ${BO}Showing summary...${NC}"
                                    read -r -t 1 -n 1
                                    break 2
                                else
                                    case "$resize_result" in
                                        *"Authentication error"*)
                                            echo "⚠️  ${RE}Resize failed${NC}"
                                            echo "   ${BO}Incorrect password.${YE}"
                                            ;;
                                        *"Resource temporarily unavailable"*)
                                            echo "⚠️  ${RE}Resize failed${NC}"
                                            echo "   ${BO}Disk may currently be in use.${NC}"
                                            echo "   Please make sure it is unmounted/ejected first."
                                            ;;
                                        *)
                                            echo "⚠️  ${RE}Resize failed${NC}"
                                            echo "   ${BO}Try choosing a larger size.${NC}"
                                            echo "$resize_result"
                                            ;;
                                    esac

                                    echo
                                    read -rp "➡️  ${GR}Try again? (or ${BL}nav${NC} ${GR}choice):${NC} " resize_error
                                    handle_navigation_input "$resize_error"
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        break
                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                        continue
                                    fi
                                    continue
                                fi
                            done
                        done
                    elif [[ "$manage_path" == "compact" ]]; then                       
                        # store old image file size
                        sparse_image_file_size_before=$(get_sparse_image_file_size "$selected_disk_img_for_sizing")
                        
                        # Loop 4: Compact Image  
                        while true; do
                            trap - SIGINT
                            interrupted=false
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                            clear
                            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                            echo "${BO}↔️  Compacting... $selected_disk_img_basename${NC}"
                            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                            echo_justified "↩ Resize/Compact Options" "Summary ↪"
                            show_nav_prompt_centered
                            populate_managed_disk_image_info # already bottom-padded

                            read -rp "➡️  ${GR}Press enter to compact disk image (or ${BL}nav${NC} ${GR}choice):${NC} " confirm
                            handle_navigation_input "$confirm"
                            nav=$?
                            if [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                continue 2
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            echo
                            echo "↔️  ${GR}Compacting...${NC}"
                            echo

                            if [[ -n $password_input ]]; then
                                compact_result=$(printf "%s" "$password_input" | hdiutil compact "$selected_disk_img_for_sizing" -stdinpass 2>&1)
                            else
                                compact_result=$(hdiutil compact "$selected_disk_img_for_sizing" 2>&1)
                            fi
                            
                            compact_exit_status=$?
                            if [[ $compact_exit_status -eq 0 ]]; then
                                echo "✅ ${GR}Compacted successfully${NC}"
                                echo "↪️  ${BO}Showing summary...${NC}"
                                read -r -t 1 -n 1
                                break
                            else
                                case "$compact_result" in
                                    *"Authentication error"*)
                                        echo "⚠️  ${RE}Compact failed${NC}"
                                        echo "   ${BO}Incorrect password.${YE}"
                                        ;;
                                    *"Resource temporarily unavailable"*)
                                        echo "⚠️  ${RE}Compact failed${NC}"
                                        echo "   ${BO}Disk may currently be in use.${NC}"
                                        echo "   Please make sure it is unmounted/ejected first."
                                        ;;
                                    *)
                                        echo "⚠️  ${RE}Compact failed${NC}"
                                        echo "$compact_result"
                                        ;;
                                esac

                                echo
                                read -rp "➡️  ${GR}Try again? (or ${BL}nav${NC} ${GR}choice):${NC} " compact_error
                                handle_navigation_input "$compact_error"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    continue 2
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi
                                continue
                            fi
                        done
                    elif [[ "$manage_path" == "unlock" ]] && [[ "$capacity_declined" == "true" ]]; then
                        header_capacity=""
                        capacity_declined=false
                        continue
                    else
                        echo -n "❌ ${RE}Invalid choice.${NC} "
                        read -r -t 1 -n 1
                        continue
                    fi

                    # Loop 3.5: Show Resize/Compact Summary
                    while true; do
                        trap - SIGINT
                        interrupted=false
                        trap 'echo; echo_n_centered "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                        
                        stored_enc_status=$(encryption_status "$selected_disk_img_for_sizing")
                        if [[ "$stored_enc_status" == "✅" ]] || [[ "$stored_enc_status" == "⚠️ " ]]; then
                            # echo "is encrypted"
                            if [[ -z "$password_input" ]]; then
                                # echo "password input is empty"
                                clear
                                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                echo "${BO}Unlock Image for Stats | $selected_disk_img_basename${NC}"
                                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                                echo_justified "↩ Resize/Compact Options" "Summary ↪"
                                show_nav_prompt_centered
                                populate_managed_disk_image_info # already bottom-padded

                                echo_centered "${GR}Reveal new capacity?${NC}"
                                echo_n_centered "${BO}This will prompt for the disk image password again.${NC} [y/N]: "
                                read -r reveal_reply
                                handle_navigation_input "$reveal_reply"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                if [[ "$reveal_reply" == "y" ]] || [[ "$reveal_reply" == "Y" ]]; then
                                    echo_n_centered "➡️  ${GR}Enter disk image password:${NC} "
                                    read -rs password_input
                                    echo
                                    
                                    sectors=$(printf "%s" "$password_input" | hdiutil resize -limits "$selected_disk_img_for_sizing" -stdinpass 2>/dev/null | tail -1 | awk '{print $2}')
                                    if [ -n "$sectors" ]; then
                                        local bytes=$(( sectors * 512 ))
                                        if [ "$bytes" -ge 1000000000000 ]; then
                                            header_capacity=$(awk "BEGIN {printf \"%.1f TBs\", $bytes/1000000000000}")
                                        elif [ "$bytes" -ge 1000000000 ]; then
                                            header_capacity=$(awk "BEGIN {printf \"%.1f GBs\", $bytes/1000000000}")
                                        elif [ "$bytes" -ge 1000000 ]; then
                                            header_capacity=$(awk "BEGIN {printf \"%.1f MBs\", $bytes/1000000}")
                                        else
                                            header_capacity=$(awk "BEGIN {printf \"%.1f KBs\", $bytes/1000}")
                                        fi
                                    else
                                        password_input=""   # ← clear bad password so re-prompt works
                                        echo_n_centered "❌ ${RE}Wrong password.${NC} "
                                        read -r -t 1 -n 1
                                        continue
                                    fi
                                elif [[ "$reveal_reply" == "n" ]] || [[ "$reveal_reply" == "N" ]]; then
                                    echo_n_centered "❌ ${BO}Skipped...${NC} "
                                    read -r -t 1 -n 1
                                else
                                    echo_centered "❌ ${RE}Invalid choice.${NC}"
                                    echo_n_centered "   ${BO}Please type y/Y or n/N.${NC} "
                                    read -r -t 1 -n 1
                                    continue
                                fi
                            else
                                # echo "password SHOULD already stored"
                                # reuse pw to get new capacity
                                sectors=$(printf "%s" "$password_input" | hdiutil resize -limits "$selected_disk_img_for_sizing" -stdinpass 2>/dev/null | tail -1 | awk '{print $2}')
                                if [ -n "$sectors" ]; then
                                    local bytes=$(( sectors * 512 ))
                                    if [ "$bytes" -ge 1000000000000 ]; then
                                        header_capacity=$(awk "BEGIN {printf \"%.1f TBs\", $bytes/1000000000000}")
                                    elif [ "$bytes" -ge 1000000000 ]; then
                                        header_capacity=$(awk "BEGIN {printf \"%.1f GBs\", $bytes/1000000000}")
                                    elif [ "$bytes" -ge 1000000 ]; then
                                        header_capacity=$(awk "BEGIN {printf \"%.1f MBs\", $bytes/1000000}")
                                    else
                                        header_capacity=$(awk "BEGIN {printf \"%.1f KBs\", $bytes/1000}")
                                    fi
                                else
                                    # echo "password was changed during script"
                                    password_input=""   # ← clear bad password so re-prompt works
                                    echo_n_centered "❌ ${RE}Wrong password.${NC} "
                                    read -r -t 1 -n 1
                                    continue
                                fi
                            fi
                        else
                            # echo "is not encrypted"
                            header_capacity=$(get_sparse_image_capacity "$selected_disk_img_for_sizing")
                        fi

                        # store new image file size
                        sparse_image_file_size_after=$(get_sparse_image_file_size "$selected_disk_img_for_sizing")

                        # File size difference
                        file_size_diff=$(awk -v before="$sparse_image_file_size_before" -v after="$sparse_image_file_size_after" '
                        BEGIN {
                            split(before, a, " "); split(after, b, " ")
                            
                            # Normalize both to MB
                            before_mb = a[1]
                            if (a[2] == "GBs" || a[2] == "GB") before_mb = a[1] * 1000
                            if (a[2] == "KBs" || a[2] == "KB") before_mb = a[1] / 1000
                            
                            after_mb = b[1]
                            if (b[2] == "GBs" || b[2] == "GB") after_mb = b[1] * 1000
                            if (b[2] == "KBs" || b[2] == "KB") after_mb = b[1] / 1000
                            
                            diff = after_mb - before_mb
                            sign = (diff < 0) ? "-" : "+"
                            if (diff < 0) diff = -diff
                            
                            # Suppress if no meaningful difference
                            if (diff < 0.05) exit  

                            # Format result
                            if (diff >= 1000) printf "%s%.1f GBs", sign, diff/1000
                            else if (diff >= 1)   printf "%s%.1f MBs", sign, diff
                            else                  printf "%s%.1f KBs", sign, diff * 1000
                        }')

                        # Capacity difference (only if both before and after are real values, not N/A or lock icon)
                        if [[ "$capacity_before" =~ ^[0-9] ]] && [[ "$header_capacity" =~ ^[0-9] ]]; then
                            capacity_diff=$(awk -v before="$capacity_before" -v after="$header_capacity" '
                            BEGIN {
                                split(before, a, " "); split(after, b, " ")
                                
                                # Normalize both to MB
                                before_mb = a[1]
                                if (a[2] == "GBs" || a[2] == "GB") before_mb = a[1] * 1000
                                if (a[2] == "KBs" || a[2] == "KB") before_mb = a[1] / 1000
                                
                                after_mb = b[1]
                                if (b[2] == "GBs" || b[2] == "GB") after_mb = b[1] * 1000
                                if (b[2] == "KBs" || b[2] == "KB") after_mb = b[1] / 1000
                                
                                diff = after_mb - before_mb
                                sign = (diff < 0) ? "-" : "+"
                                if (diff < 0) diff = -diff
                                
                                # Suppress if no meaningful difference
                                if (diff < 0.05) exit                       

                                # Format result
                                if (diff >= 1000) printf "%s%.1f GBs", sign, diff/1000
                                else if (diff >= 1)   printf "%s%.1f MBs", sign, diff
                                else                  printf "%s%.1f KBs", sign, diff * 1000
                            }')
                        else
                            capacity_diff=""
                        fi

                        clear
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "${BO}Summary | $selected_disk_img_basename${NC}"
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "↩ Resize/Compact Options" "Choose Another Disk Image ↪"
                        show_nav_prompt_centered

                        echo_centered "${BO}Current Disk Image Info:${NC}"
                        echo
                        echo_centered "${GR}File Size:${NC}  | $sparse_image_file_size_after |  ${GR}Capacity:${NC}  | $header_capacity |  ${GR}Encryption:${NC}  | $(encryption_status) |"
                        echo
                        echo "${BO}Results:${NC}"
                        echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                        echo "➖ ${GR}Old File Size:${NC} $sparse_image_file_size_before"
                        echo "➕ ${GR}New File Size:${NC} ${BO}$sparse_image_file_size_after${NC}${file_size_diff:+ (${BO}${file_size_diff}${NC})}"
                        echo "➖ ${GR}Old Capacity: ${NC} $capacity_before"
                        echo "➕ ${GR}New Capacity: ${NC} ${BO}$header_capacity${NC}${capacity_diff:+ (${BO}${capacity_diff}${NC})}"
                        echo "───────────────────────────────────────────────────────────────────────────────────────────────"

                        if [[ "$header_capacity" == "${BK}🔒${NC}" ]]; then
                            capacity_before="N/A"
                        else
                            capacity_before="$header_capacity"   # ← snapshot NEW before value
                        fi
                        
                        echo
                        read -rp "➡️  ${GR}Resize or compact another image? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                        handle_navigation_input "$input"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then 
                            password_input=""  # clean up
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            break
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        elif [[ $nav -eq $NAV_CONT ]]; then
                            break 2
                        fi
                    done
                done
            done
        else
            echo -n "❌ ${RE}Invalid choice.${NC} "
            read -r -t 1 -n 1
            continue
        fi
    done
}
#====6==== 🔗 create_symlink
function create_symlink() {
    while true; do
        if [[ "$DisablePathPickerWhenPathsAreSaved_Create_Symlinks" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
            local paths_to_process=()
            paths_to_process=("${saved_paths_to_process[@]}")
            path_count="${#paths_to_process[@]}"
        else
            trap 'return' SIGINT
            resize_terminal 95 24
            clear
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}6) 🔗 Create Symlink${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "94"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "↩ Main Menu" "Choose Destination ↪"
            show_nav_prompt_with_AZ_centered
            
            # Step 1: Prompt for Source files/folders
            echo "${BO}Step 1 of 2:${NC} ${GR}Please provide SOURCE path(s) to a file or folder.${NC}"
            echo
            echo "${BO}Path Picker Options:${NC}  ${GY}(or use drag & drop)${NC}"
            echo " 1) 📂 ${GR}Reveal Finder ${NC} ${GY}(for Drag & Drop)${NC}"
            echo " 2) 📄 ${GR}Choose file(s)${NC} ${GY}(via Finder dialog)${NC}"
            echo " 3) 📁 ${GR}Choose folder ${NC} ${GY}(via Finder dialog)${NC}"
            show_path_picker_save_options
            echo
            echo "⬇️  ${GR}Drag & drop multiple files/folders onto this window, then press Enter.${NC}"
            echo "   ${GY}Tip: You can also press ⌥⌘C to copy multiple files/folders as a pathname${NC}"
            echo
            read -rp "" input
            handle_navigation_input "$input"
            nav=$?
            if   [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                return 0
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue
            elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                return
            fi

            # Handle Path Picker Options (all input methods flow into paths_to_process)
            local paths_to_process=()

            case "$input" in
                1) open /System/Library/CoreServices/Finder.app; continue ;;
                2)
                    # Open Finder open panel (for files)
                    local selected_paths=$(osascript -e 'try' \
                                    -e 'set fileList to choose file with prompt "Choose SOURCE files to create symlinks from" with multiple selections allowed' \
                                    -e 'set pathList to {}' \
                                    -e 'repeat with aFile in fileList' \
                                    -e '    set end of pathList to POSIX path of aFile' \
                                    -e 'end repeat' \
                                    -e 'set AppleScript'"'"'s text item delimiters to linefeed' \
                                    -e 'set pathString to pathList as text' \
                                    -e 'return pathString' \
                                    -e 'on error' \
                                    -e 'return ""' \
                                    -e 'end try')
                    if [[ -n "$selected_paths" ]]; then
                        while IFS= read -r line; do
                            if [[ -n "$line" ]]; then
                                # Normalize path by removing trailing slash
                                line="${line%/}"
                                paths_to_process+=("$line")
                            fi
                        done <<< "$selected_paths"
                    else
                        echo "❌ ${RE}No selection made.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi
                    ;;
                3)
                    # Open Finder open panel (for folder)
                    local selected_path=$(osascript -e 'try' \
                                    -e 'set p to POSIX path of (choose folder with prompt "Choose SOURCE folder to create symlink from")' \
                                    -e 'return p' \
                                    -e 'on error' \
                                    -e 'return ""' \
                                    -e 'end try')
                    if [[ -n "$selected_path" && -e "$selected_path" ]]; then
                        # Normalize path by removing trailing slash
                        selected_path="${selected_path%/}"
                        paths_to_process=("$selected_path")
                    else
                        echo "❌ ${RE}No selection made.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi
                    ;;
                4)
                    if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No saved path(s) found.${NC}"
                        echo -n "   Please provide path(s) again. "
                        read -r -t 3 -n 1
                        continue
                    fi

                    local valid_paths=()
                    local invalid_paths=()

                    # Validate saved paths still exist
                    for saved_path in "${saved_paths_to_process[@]}"; do
                        if [[ -e "$saved_path" ]]; then
                            valid_paths+=("$saved_path")
                        else
                            invalid_paths+=("$saved_path")
                        fi
                    done

                    # check if there are valid paths to process
                    if [[ "${#valid_paths[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No valid saved path(s) to process.${NC}"
                        echo -n "   Please provide path(s) again. "
                        read -r -t 3 -n 1
                        continue
                    fi

                    if [[ "${#invalid_paths[@]}" -gt 0 ]]; then
                        show_invalid_path_prompt
                        read -rp "➡️  ${GR}Press Enter to continue with valid paths (or ${BL}nav${NC} ${GR}choice):${NC} " invalid_path_choice
                        handle_navigation_input "$invalid_path_choice"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then 
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            continue
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        elif handle_main_menu_AZ_navigation_input "$invalid_path_choice" "$main_menu_choice"; then
                            return
                        fi
                    fi

                    use_saved_paths=true
                    ;;
                5)
                    if [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No saved path(s) to clear.${NC}"
                        echo -n "   Please provide path(s) again. "
                        read -r -t 3 -n 1
                        continue
                    else
                        # Clear Saved Path(s)
                        trap - SIGINT
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                        show_clear_saved_paths_prompt
                        read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                        handle_navigation_input "$saved_paths_choice"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then 
                            continue
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        elif handle_main_menu_AZ_navigation_input "$saved_paths_choice" "$main_menu_choice"; then
                            return
                        fi

                        case $saved_paths_choice in
                            y|Y)
                                clear_saved_path_data
                                # echo -n "✅ ${GR}Cleared all saved paths.${NC} "
                                # read -r -t 1 -n 1
                                continue
                                ;;
                            *)
                                # echo -n "❌ ${RE}Cancelled.${NC} "
                                # read -r -t 1 -n 1
                                continue
                                ;;
                        esac
                    fi
                    ;;
                /)
                    echo "❌ ${RE}The root directory cannot be chosen.${NC}"
                    echo -n "   Please provide another path. "
                    read -r -t 3 -n 1
                    continue
                    ;;
                *)
                    # Process drag & drop input to handle escaped spaces and quoted paths
                    eval "set -- $input"

                    local arg_count=$#

                    if [[ "$arg_count" -eq 0 ]]; then
                        echo "❌ ${RE}No paths provided.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi

                    local invalid_paths=()

                    # Process each input path
                    for path in "$@"; do
                        if [[ -e "$path" ]]; then
                            paths_to_process+=("$path")
                        else
                            invalid_paths+=("$path")
                        fi
                    done

                    # check if there are valid paths to process
                    if [[ "${#paths_to_process[@]}" -eq 0 ]]; then
                        echo "❌ ${RE}No valid files to process.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi

                    if [[ "${#invalid_paths[@]}" -gt 0 ]]; then
                        show_invalid_path_prompt
                        read -rp "➡️  ${GR}Press Enter to continue with valid paths (or ${BL}nav${NC} ${GR}choice):${NC} " invalid_path_choice
                        handle_navigation_input "$invalid_path_choice"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then 
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            continue
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue
                        elif handle_main_menu_AZ_navigation_input "$invalid_path_choice" "$main_menu_choice"; then
                            return
                        fi
                    fi
                    ;;
            esac

            # Handle Saved Paths
            if   [[ "$use_saved_paths" == "true" ]]; then
                use_saved_paths=false
                paths_to_process=("${valid_paths[@]}")
                path_count="${#paths_to_process[@]}"
            elif [[ "$DontAskAgainAbout_SavingPaths_Path_Picker" == "true" ]]; then
                sort_paths_to_process_without_defs
                path_count="${#paths_to_process[@]}"
            elif [[ "${#saved_paths_to_process[@]}" -eq 0 ]]; then
                # Prompt to Save Path(s)
                trap - SIGINT
                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

                sort_paths_to_process_with_defs
                path_count="${#paths_to_process[@]}"

                show_save_path_confirmation
                read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                handle_navigation_input "$saved_paths_choice"
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then 
                    continue
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                elif handle_main_menu_AZ_navigation_input "$saved_paths_choice" "$main_menu_choice"; then
                    return
                fi

                case $saved_paths_choice in
                    1)
                        saved_paths_to_process=("${paths_to_process[@]}")
                        save_paths_to_file
                        ;;
                    2)
                        DontAskAgainAbout_SavingPaths_Path_Picker="true"
                        save_pref "DontAskAgainAbout_SavingPaths_Path_Picker" "true"
                        ;;
                esac
            elif [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                if [[ "$DontAskAgainAbout_OverwritingPaths_Path_Picker" == "false" ]]; then
                    # Prompt to Overwrite Saved Path(s)
                    trap - SIGINT
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

                    sort_paths_to_process_without_defs
                    path_count="${#paths_to_process[@]}"
                    
                    show_overwrite_saved_path_confirmation
                    show_overwrite_saved_path_options
                    read -rp "➡️  ${GR}Choose an option (or ${BL}nav${NC} ${GR}choice):${NC} " saved_paths_choice
                    handle_navigation_input "$saved_paths_choice"
                    nav=$?
                    if   [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then 
                        continue
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    elif handle_main_menu_AZ_navigation_input "$saved_paths_choice" "$main_menu_choice"; then
                        return
                    fi
                    
                    case $saved_paths_choice in
                        1)
                            saved_paths_to_process=("${paths_to_process[@]}")
                            save_paths_to_file
                            set_plurality_for_saved_paths_to_process
                            # echo -n "✅ ${GR}Overwritten.${NC} "
                            # read -r -t 1 -n 1
                            ;;
                        2)
                            DontAskAgainAbout_OverwritingPaths_Path_Picker=true
                            save_pref "DontAskAgainAbout_OverwritingPaths_Path_Picker" "true"
                            ;;
                        *)
                            # echo -n "❌ ${RE}Cancelled.${NC} "
                            # read -r -t 1 -n 1
                            # Continue with provided path(s) without overwriting
                            # continue
                            :
                            ;;
                    esac
                else
                    # Continue with provided path(s) without overwriting
                    sort_paths_to_process_without_defs
                    path_count="${#paths_to_process[@]}"
                fi
            else
                # Should never reach here - all states covered above
                sort_paths_to_process_without_defs
                path_count="${#paths_to_process[@]}"
            fi
        fi
        # Destination Directory Selection (Nested Loop 2)
        while true; do
            trap - SIGINT
            interrupted=false
            if [[ "$DisablePathPickerWhenPathsAreSaved_Create_Symlinks" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                trap 'return' SIGINT
            else
                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
            fi
            resize_terminal 95 24
            clear
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            echo_justified "${BO}6) 🔗 Choose Destination${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "94"
            echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
            if [[ "$DisablePathPickerWhenPathsAreSaved_Create_Symlinks" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                echo_justified "↩ Main Menu" "Summary ↪"
            else
                echo_justified "↩ Home [Choose Source]" "Summary ↪"
            fi
            show_nav_prompt_with_AZ_not_centered
            [[ "$DisablePathPickerWhenPathsAreSaved_Create_Symlinks" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]] && echo_centered "💾 ${GY}Using saved $path_or_paths${NC}" && echo
            
            # Step 2: Prompt for Destination folder
            echo "${BO}Step 2 of 2:${NC} ${GR}Please provide the DESTINATION path.${NC}"
            echo
            echo "${BO}Path Picker Options:${NC}  ${GY}(or use drag & drop)${NC}"
            echo " 1) 📂 ${GR}Reveal Finder ${NC} ${GY}(for Drag & Drop)${NC}"
            echo " 2) 📁 ${GR}Choose folder ${NC} ${GY}(via Finder dialog)${NC}"
            echo
            echo "⬇️  ${GR}Drag & drop a folder onto this window, then press Enter.${NC}"
            echo "   ${GY}Tip: You can also press ⌥⌘C to copy a folder as a pathname${NC}"
            echo
            read -rp "" dest_input
            handle_navigation_input "$dest_input"
            nav=$?
            if   [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                if [[ "$DisablePathPickerWhenPathsAreSaved_Create_Symlinks" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                    return 0
                else
                    break
                fi
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue
            elif handle_main_menu_AZ_navigation_input "$dest_input" "$main_menu_choice"; then
                return
            fi

            local destination=""

            # Handle Destination Folder Picker Options
            case "$dest_input" in
                1) open /System/Library/CoreServices/Finder.app; continue ;;
                2)
                    # Open Finder open panel (for destination folder)
                    destination=$(osascript -e 'try' \
                                    -e 'set p to POSIX path of (choose folder with prompt "Choose DESTINATION folder for symlinks")' \
                                    -e 'return p' \
                                    -e 'on error' \
                                    -e 'return ""' \
                                    -e 'end try')
                    if [[ -n "$destination" && -d "$destination" ]]; then
                        # Normalize path by removing trailing slash
                        destination="${destination%/}"
                    else
                        echo "❌ ${RE}No selection made.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi
                    ;;
                *)
                    # Process drag & drop destination input
                    destination="$(eval echo "$dest_input")"
                    
                    if [[ ! -d "$destination" ]]; then
                        echo "❌ ${RE}Destination is not a valid directory.${NC}"
                        echo -n "   Please try again. "
                        read -r -t 1 -n 1
                        continue
                    fi
                    ;;
            esac

            while true; do
                trap - SIGINT
                interrupted=false
                trap 'echo; interrupted=true' SIGINT
                if [ "$path_count" -gt 3 ]; then
                    set_terminal_height_to_2200p
                fi
                clear
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}🔗 Summary" "${GY}(Use A/Z to cycle menus)${NC}" "94"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                if [[ "$DisablePathPickerWhenPathsAreSaved_Create_Symlinks" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                    echo_justified "↩ Choose Destination" "Main Menu ↪"
                else
                    echo_justified "↩ Choose Destination" "Home [Path Picker] ↪"
                fi
                show_nav_prompt_with_AZ_not_centered
                echo "🔄 ${BO}Creating symlinks...${NC}"

                local processed_count=0
                local processed_failed=0
                # local symlink_count=0
                # local processed_skipped=0

                echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"
                # Create symlinks
                for source in "${paths_to_process[@]}"; do
                    sfilename=$(basename "$source")
                    dfilename=$(basename "$destination")
                    
                    sfilename_formatted="${BO}$sfilename${NC}"
                    if [ -d "$source" ]; then
                        sfilename_formatted="${CY}$sfilename/${NC}"
                    fi

                    if sudo ln -s "$source" "$destination/$sfilename" 2>/dev/null; then
                        echo "🔗 ${GR}sudo ln -s${NC} $sfilename_formatted → ${CY}$dfilename/${NC}"
                        ((processed_count++))
                    else
                        echo "❌ ${RE}Failed to create symlink for:${NC} $sfilename_formatted"
                        ((processed_failed++))
                    fi

                    if [[ "$interrupted" == "true" ]]; then
                        echo -n "🛑 ${RE}Interrupted.${NC} Showing summary..."
                        break
                    fi
                done
                break
            done

            trap - SIGINT
            interrupted=false
            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT

            echo
            echo "${BO}Results:${NC}"
            echo "${GR}────────────────────────────${NC}"
            echo "🛣️  Total paths found:     $path_count"
            if [ $processed_count -gt 0 ]; then
                echo "🔗 Total links ${GR}processed${NC}: $processed_count"
            else
                echo "🔗 ${GY}Total links processed: $processed_count${NC}"
            fi
            if [ $processed_failed -gt 0 ]; then
                echo "⚠️  Total links ${RE}failed${NC}:    $processed_failed"
            else
                echo "⚠️  ${GY}Total links failed:    $processed_failed${NC}"
            fi
            echo "${GR}────────────────────────────${NC}"
            if [ $processed_count -gt 0 ]; then
                echo
                echo "${BO}Let's link later${NC} 🦾" 
            fi
            echo
            if [[ "$DisablePathPickerWhenPathsAreSaved_Create_Symlinks" == "true" ]] && [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                read -rp "➡️  ${GR}Return to Main Menu? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                handle_navigation_input "$input"
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then 
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then 
                    continue
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                    return
                elif [[ $nav -eq $NAV_CONT ]]; then
                    return 0
                fi
            else
                read -rp "➡️  ${GR}Process another file? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                handle_navigation_input "$input"
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then 
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then 
                    continue
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                    return
                elif [[ $nav -eq $NAV_CONT ]]; then
                    break # back to Path Picker
                fi
            fi
        done     
    done
}
#====7==== ⚙️ macOS Preferences
function macos_preferences() {
    # Define preference commands with their active/inactive/reset actions
    if true; then    # only used here to quickly collapse array
        declare -a preference_commands=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🆕 [NEW for ${BL}macOS Tahoe 26]${NC}|"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🌑 Appearance: Enable dark mode on icons ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|AppleIconAppearanceTheme|RegularDark|||darkmode|"
                "🪟 Appearance: Enable tinted Liquid Glass ${BL}(Tahoe 26.1+)${NC}|NSGlobalDomain|NSGlassDiffusionSetting|true|false|false|writeResetValue|"
                "📁 Appearance: Disable 'Tint Folders Based On Tags' ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|AppleDisableTagBasedIconTinting|true|||delete|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🌑 ${GY}Appearance: Enable dark mode on icons (Tahoe 26+)${NC}|NSGlobalDomain|AppleIconAppearanceTheme|RegularDark|||darkmode|"
                "🪟 ${GY}Appearance: Enable tinted Liquid Glass (Tahoe 26.1+)${NC}|NSGlobalDomain|NSGlassDiffusionSetting|true|false|false|writeResetValue|"
                "📁 ${GY}Appearance: Disable 'Tint Folders Based On Tags' (Tahoe 26+)${NC}|NSGlobalDomain|AppleDisableTagBasedIconTinting|true|||delete|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 && "$MACOS_MINOR" -ge 4 ]]; then
            preference_commands+=(
                "🗜️  Archive Utility: Move archives to trash after expanding ${BL}(Tahoe 26.4+)${NC}|com.apple.archiveutility|dearchive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                "🗜️  Archive Utility: Move files to trash after archiving ${BL}(Tahoe 26.4+)${NC}|com.apple.archiveutility|archive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
            )
        
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🗜️  ${GY}Archive Utility: Move archives to trash after expanding (Tahoe 26.4+)${NC}|com.apple.archiveutility|dearchive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                "🗜️  ${GY}Archive Utility: Move files to trash after archiving (Tahoe 26.4+)${NC}|com.apple.archiveutility|archive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "📁 Finder: Shrink sidebar width to the minimum ${BL}(Tahoe 26+)${NC}|com.apple.finder|SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|"
                # "📏 Shrink sidebar width to the minimum (2 of 2) ${BL}(Tahoe 26+)${NC}|com.apple.finder|FK_SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|"
                "💬 Messages: Screen Unknown Senders ${BO}(FDA req. to read/write)${NC} ${BL}(Tahoe 26+)${NC}|com.apple.MobileSMS|FilterMessageRequests|true|false|false|writeResetValue|"
                "📋 Menu Bar: Never Hide Menu Bar In Fullscreen ${BL}(Tahoe 26+)${NC}|com.apple.controlcenter|AutoHideMenuBarOption|3|2||NevaHideMenuBarinTahoe|"
                "📋 Menu Bar: Show Menu Bar Background ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|SLSMenuBarUseBlurredAppearance|true|||delete|${GY}Shows or disables the menu bar's blurred appearance${NC}"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "📁 ${GY}Finder: Shrink sidebar width to the minimum (Tahoe 26+)${NC}|com.apple.finder|SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|"
                # "📏 ${GY}Shrink sidebar width to the minimum (2 of 2) (Tahoe 26+)${NC}|com.apple.finder|FK_SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|"
                "💬 ${GY}Messages: Screen Unknown Senders (FDA req. to read/write) (Tahoe 26+)${NC}|com.apple.MobileSMS|FilterMessageRequests|true|false|false|writeResetValue|"
                "📋 ${GY}Menu Bar: Never Hide Menu Bar In Fullscreen (Tahoe 26+)${NC}|com.apple.controlcenter|AutoHideMenuBarOption|3|2||NevaHideMenuBarinTahoe|"
                "📋 ${GY}Menu Bar: Show Menu Bar Background (Tahoe 26+)${NC}|NSGlobalDomain|SLSMenuBarUseBlurredAppearance|true|||delete|${GY}Shows or disables the menu bar's blurred appearance${NC}"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 && "$MACOS_MINOR" -ge 2 ]]; then
            preference_commands+=(
                "📋 Menu Bar: Show Timer in Menu Bar ${BL}(Tahoe 26.2+)${NC}|com.apple.controlcenter|Timer|16|0|0|-currentHost|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "📋 ${GY}Menu Bar: Show Timer in Menu Bar (Tahoe 26.2+)${NC}|com.apple.controlcenter|Timer|16|0|0|-currentHost|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🔑 Passwords: Disallow Contacting Websites ${BL}(Tahoe 26+)${NC}|com.apple.Passwords|WBSPasswordsAppBackgroundNetworkingEnabled|false|true|true|writeResetValue|${GY}Prevents network telemetry with websites from saved passwords. (This is how icons and names get shown)${NC}"
                "📞 Phone: Filter Unknown Callers ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|filterUnknownCallersAsNewCallers|true|false|true|writeResetValue|"
                "📞 Phone: Screen Unknown Callers ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|ReceptionistDisabled|false|true|false|writeResetValue|${GY}Toggles on 'Ask Reason for Calling'${NC}"
                "📞 Phone: Enable Hold Assist ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|HoldAssistDetectionEnabled|true|false|true|writeResetValue|"
                "📞 Phone: Enable Live Voicemail ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|CallScreeningDisabled|false|true|false|writeResetValue|"
                "✏️  Preview: Show Markup toolbar for images by default ${BL}(Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForImages|true|false|false|writeResetValue|"
                "✏️  Preview: Show Markup toolbar for PDFs by default ${BL}(Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForPDFs|true|false|false|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🔑 ${GY}Passwords: Disallow Contacting Websites (Tahoe 26+)${NC}|com.apple.Passwords|WBSPasswordsAppBackgroundNetworkingEnabled|false|true|true|writeResetValue|${GY}Prevents network telemetry with websites from saved passwords. (This is how icons and names get shown)${NC}"
                "📞 ${GY}Phone: Filter Unknown Callers (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|filterUnknownCallersAsNewCallers|true|false|true|writeResetValue|"
                "📞 ${GY}Phone: Screen Unknown Callers (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|ReceptionistDisabled|false|true|false|writeResetValue|${GY}Toggles on 'Ask Reason for Calling'${NC}"
                "📞 ${GY}Phone: Enable Hold Assist (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|HoldAssistDetectionEnabled|true|false|true|writeResetValue|"
                "📞 ${GY}Phone: Enable Live Voicemail (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|CallScreeningDisabled|false|true|false|writeResetValue|"
                "✏️  ${GY}Preview: Show Markup toolbar for images by default (Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForImages|true|false|false|writeResetValue|"
                "✏️  ${GY}Preview: Show Markup toolbar for PDFs by default (Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForPDFs|true|false|false|writeResetValue|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 && "$MACOS_MINOR" -ge 4 ]] || [[ "$MACOS_MAJOR" -le 15 ]]; then
            preference_commands+=(
                "🗂️  Safari: Disable compact tab layout ${MA}(Sequoia 15 & below)${NC} or ${BL}(Tahoe 26.4+)${NC}|com.apple.Safari|ShowStandaloneTabBar|true|false|true|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🗂️  ${GY}Safari: Disable compact tab layout (Sequoia 15 & below) or (Tahoe 26.4+)${NC}|com.apple.Safari|ShowStandaloneTabBar|true|false|true|writeResetValue|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🗂️  Safari: Show Color in Tab Bar ${BL}(Tahoe 26+)${NC}|com.apple.Safari|NeverUseBackgroundColorInToolbar|false|true|false|writeResetValue|${GY}(On by default)${NC}"
                "🔍 Spotlight: Disable all default results (except System Settings & Apps) ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Remove various apps/items|||ReduceSpotlightResultsInTahoe|${GY}Note that more apps may show up here later on once using them. In that case, this preference may inadvertently affect new apps that show up here. (Intended for fresh installs)${NC}"
                "🔍 Spotlight: Disable 'Show Related Content' ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Custom.relatedContents|||DisableSpotlightRelatedContent|"
                "🔍 Spotlight: Enable Clipboard Manager ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|PasteboardHistoryEnabled|true|false|false|writeResetValue|"
                "🔍 Spotlight: Increase Clipboard history from 8hrs to 7 days ${BL}(Tahoe 26.1+)${NC}|com.apple.Spotlight|PasteboardHistoryTimeout|604800|28800|28800|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🗂️  ${GY}Safari: Show Color in Tab Bar (Tahoe 26+)${NC}|com.apple.Safari|NeverUseBackgroundColorInToolbar|false|true|false|writeResetValue|${GY}(On by default)${NC}"
                "🔍 ${GY}Spotlight: Disable all default results (except System Settings & Apps) (Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Remove various apps/items|||ReduceSpotlightResultsInTahoe|${GY}Note that more apps may show up here later on once using them. In that case, this preference may inadvertently affect new apps that show up here. (Intended for fresh installs)${NC}"
                "🔍 ${GY}Spotlight: Disable 'Show Related Content' (Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Custom.relatedContents|||DisableSpotlightRelatedContent|"
                "🔍 ${GY}Spotlight: Enable Clipboard Manager (Tahoe 26+)${NC}|com.apple.Spotlight|PasteboardHistoryEnabled|true|false|false|writeResetValue|"
                "🔍 ${GY}Spotlight: Increase Clipboard history from 8hrs to 7 days (Tahoe 26.1+)${NC}|com.apple.Spotlight|PasteboardHistoryTimeout|604800|28800|28800|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🖱️  [Mouse]|"
            "🚫 Disable Natural Scrolling ${BO}(Requires Logging Out)${NC}|NSGlobalDomain|com.apple.swipescrolldirection|false|true|true|writeResetValue|"
            "🚀 Increase Tracking Speed beyond fastest setting ${BO}(Requires Restart)${NC}|NSGlobalDomain|com.apple.mouse.scaling|5|4|3.0|writeResetValue|"
            "🖱️  Enable secondary button (on bluetooth multi-touch mice)|com.apple.driver.AppleBluetoothMultitouch.mouse|MouseButtonMode|TwoButton|OneButton|OneButton|writeResetValue|"
            "🚫 Disable 'Shake mouse pointer to locate' ${BO}(Requires Logging Out)${NC}|NSGlobalDomain|CGDisableCursorLocationMagnification|true|false|true|writeResetValue|"
            "🚫 Disable the 'Mouse Keys' keyboard shortcut ${BO}(FDA req. to write changes)${NC}|com.apple.universalaccess|useMouseKeysShortcutKeys|true|false|true|DisableMouseKeys|${GY}Prevents 'Mouse Keys' from getting triggered when pressing the option key 5 times in a row.${NC}"
            # "🚫 Disable 'Mouse Keys'|com.apple.universalaccess|mouseDriver|true|false|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            # "GROUP|💻 [TrackPad - Built-In]|"
            "GROUP|💻 [TrackPad]|"
            "💨 Increase Tracking Speed|NSGlobalDomain|com.apple.trackpad.scaling|3|0.5|0.5|writeResetValue|${GY}Increases to fastest default setting${NC}"
            # "⚙️  Enable Tap to click|com.apple.AppleMultitouchTrackpad|Clicking|1|0||delete|Enables 'Tap to click' on built-in Trackpads"
            # "⚙️  Enable Tap to click (in login screen)|NSGlobalDomain|com.apple.mouse.tapBehavior|1|0||-currentHost|Enables 'Tap to click' on built-in Trackpads (in login screen)."
            "⚙️  Enable Tap To Click|NSGlobalDomain|com.apple.mouse.tapBehavior|1|0|0|-currentHost|"
            "⚙️  Enable Two-Finger Tap To Right Click AND Bottom Right Click ${BO}(Requires Logging Out)${NC}|Various|Various|true|false|false|Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click|${GY}Enables both of these settings. (Note that System Settings will show only 'Click in Bottom Right Corner' selected, but 'Click or Tap with Two Fingers' is also applied!)${NC}"
            # "⚙️  Enable secondary click|NSGlobalDomain|com.apple.trackpad.enableSecondaryClick|true|false||-currentHost|Enables bottom-right right-click on built-in Trackpads (in login screen)."
            # "⚙️  Enable two-finger tap to right-click|com.apple.AppleMultitouchTrackpad|TrackpadRightClick|true|false|||Enable two-finger right-click on built-in Trackpads"
            # "⚙️  Enable corner right-click (disables 'tap to right-click')|NSGlobalDomain|com.apple.trackpad.trackpadCornerClickBehavior|1|0||-currentHost|Enables corner right-click on built-in Trackpads (in login screen)."

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            # "GROUP|💻 [TrackPad - External/Bluetooth|"
            # "⚙️  Enable Tap to click|com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|1|0|||Enables 'Tap to click' on bluetooth Trackpads"
            # "⚙️  Enable two-finger tap to right-click|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadRightClick|1|0|||Enable two-finger right-click on bluetooth Trackpads"
            # "⚙️  Enable pinch-to-zoom|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadPinch|1|0|||Enables pinch-to-zoom on bluetooth Trackpads"
            # "⚙️  Enable corner right-click (disables 'tap to right-click')|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadCornerSecondaryClick|0|1|||Enables corner right-click on bluetooth Trackpads (disables tap to right click)"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|⌨️  [Keyboard]|"
            # "💨 Speed Up Initial Key Repeat Rate ${BO}(Requires logging out)${NC}|NSGlobalDomain|KeyRepeat|2|6|6|writeResetValue|${GY}Speeds up the repeat of pressed keys.${NC}"
            "💨 Increase Initial Key Repeat Rate beyond fastest setting ${BO}(Requires logging out)${NC}|NSGlobalDomain|KeyRepeat|1|2|6|writeResetValue|${GY}Speeds up the repeat of pressed keys. (A rate of '2' is the fastest setting in System Settings)${NC} "
            # "💨 Speed Up Delay Until Key Repeat ${BO}(Requires logging out)${NC}|NSGlobalDomain|InitialKeyRepeat|15|25|25|writeResetValue|${GY}Speeds up the delay until pressed keys are repeated.${NC}"
            "💨 Increase Delay Until Key Repeat beyond fastest setting ${BO}(Requires logging out)${NC}|NSGlobalDomain|InitialKeyRepeat|13|15|25|writeResetValue|${GY}Speeds up the delay until pressed keys are repeated. (A rate of '15' is the shortest setting in System Settings)${NC}"
            "↔️  Allow tab navigation across UI|NSGlobalDomain|AppleKeyboardUIMode|2|0|2|writeResetValue|${GY}Enables full keyboard access for all UI controls${NC}"
            "🚫 Disable auto-capitalization|NSGlobalDomain|NSAutomaticCapitalizationEnabled|false|true|true|writeResetValue|"
            "🚫 Disable auto-correct|NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|false|true|true|writeResetValue|"
            "🚫 Disable auto-period substitution|NSGlobalDomain|NSAutomaticPeriodSubstitutionEnabled|false|true|true|writeResetValue|"
            "😌 Fn/🌐 key Shows Emoji & Symbols ${BO}(Requires logging out)${NC}|com.apple.HIToolbox|AppleFnUsageType|2|3|2|KeyboardFunctionKey|${GY}(On by default now in recent macOS versions)${NC}"
            "🚫 Disable accent options when a key is held down ${BO}(Requires logging out)${NC}|NSGlobalDomain|ApplePressAndHoldEnabled|false|true|true|writeResetValue|"
            "🌐 Use F1, F2, etc. keys as standard function keys ${BO}(Requires logging out)${NC}|NSGlobalDomain|com.apple.keyboard.fnState|true|false|false|writeResetValue|${GY}When this option is selected, press the fn key to use the special features printed on each key.${NC}"


            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|⌨️  [Keyboard Shortcuts]|"
            "🌎 Global: Sets ⌥⌘ +L/R arrows to Show Previous/Next Tab|NSGlobalDomain|NSUserKeyEquivalents|'{\"Show Previous Tab\" = \"@~\\U2190\"; \"Show Next Tab\" = \"@~\\U2192\"}'|delete \"Show Next Tab\"; \"Show Previous Tab\"|delete \"Show Next Tab\"; \"Show Previous Tab\"|KeyboardShortcuts|${GY}Sets ⌥⌘ + left/right arrow keys to show next/previous tabs (supported in most apps).${NC} ${BO}This requires logging out to take effect${NC}"        
            "📁 Finder: Swaps the default shortcuts for Get Info and Show/Hide Inspector|com.apple.finder|NSUserKeyEquivalents|'{\"Get Info\" = \"@~i\"; \"Show Inspector\" = \"@i\"; \"Hide Inspector\" = \"@i\"}'|delete \"Get Info\"; \"Show Inspector\"; \"Hide Inspector\"|delete \"Get Info\"; \"Show Inspector\"; \"Hide Inspector\"|KeyboardShortcuts|${GY}Swaps default Get Info shortcut (⌘I) with Show/Hide Inspector shortcut (⌘⌥I). (Show Inspector refreshes the info panel once another file is selected, unlike Get Info)${NC}"
            "🔎 Preview: Sets ⌥⌘M to toggle the Markup Toolbar|com.apple.Preview|NSUserKeyEquivalents|'{\"Hide Markup Toolbar\" = \"@~m\"; \"Show Markup Toolbar\" = \"@~m\"}'|delete \"Hide Markup Toolbar\"; \"Show Markup Toolbar\"|delete \"Hide Markup Toolbar\"; \"Show Markup Toolbar\"|KeyboardShortcuts|"
            "📝 TextEdit: Swaps the default shortcuts for New and Show Fonts|com.apple.TextEdit|NSUserKeyEquivalents|'{\"New\" = \"@t\"; \"Show Fonts\" = \"@n\"}'|delete \"New\"; \"Show Fonts\"|delete \"New\"; \"Show Fonts\"|KeyboardShortcuts|${GY}For new documents and tabs, this will use ⌘T (like most apps) instead of ⌘N${NC}"
            "🔎 Find Any File: Swaps the default shortcuts for Rename and Reveal In Finder|org.tempel.findanyfile|NSUserKeyEquivalents|'{\"Rename\" = \"@r\"; \"Reveal in Finder\" = \"@e\"}'|delete \"Rename\"; \"Reveal in Finder\"|delete \"Rename\"; \"Reveal in Finder\"|KeyboardShortcuts|"
            "📦 Suspicious Package: Sets ⌥⌘ + L/R arrows for Show Previous/Next Tab|com.mothersruin.SuspiciousPackageApp|NSUserKeyEquivalents|'{\"Show Previous Tab\" = \"@~\\U2190\"; \"Show Next Tab\" = \"@~\\U2192\"}'|delete \"Show Next Tab\"; \"Show Previous Tab\"|delete \"Show Next Tab\"; \"Show Previous Tab\"|KeyboardShortcuts|"
            "📦 Suspicious Package: Sets ⌥⌘ + '[' or ']' for Previous/Next Tab in Package|com.mothersruin.SuspiciousPackageApp|NSUserKeyEquivalents|'{\"Next Tab in Package\" = \"@~\U005D\"; \"Previous Tab in Package\" = \"@~\U005B\"}'|delete \"Next Tab in Package\"; \"Previous Tab in Package\"|delete \"Next Tab in Package\"; \"Previous Tab in Package\"|KeyboardShortcuts|"
            "📦 Apparency: Sets ⌥⌘ + L/R arrows for Show Previous/Next Tab|com.mothersruin.Apparency|NSUserKeyEquivalents|'{\"Show Previous Tab\" = \"@~\\U2190\"; \"Show Next Tab\" = \"@~\\U2192\"}'|delete \"Show Next Tab\"; \"Show Previous Tab\"|delete \"Show Next Tab\"; \"Show Previous Tab\"|KeyboardShortcuts|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|💾 [Disks]|"
            "💾 Show internal hard disks on desktop|com.apple.finder|ShowHardDrivesOnDesktop|true|false|false|writeResetValue|"
            "💾 Show external hard disks on desktop|com.apple.finder|ShowExternalHardDrivesOnDesktop|true|false|false|writeResetValue|"
            "💾 Show removable media on desktop|com.apple.finder|ShowRemovableMediaOnDesktop|true|false|false|writeResetValue|${GY}(for legacy CDs, DVDs and iPods)${NC}"
            "💾 Show mounted servers on desktop|com.apple.finder|ShowMountedServersOnDesktop|true|false|false|writeResetValue|"
            "💾 Show all devices in Disk Utility|com.apple.DiskUtility|SidebarShowAllDevices|true|false|false|writeResetValue|${GY}Shows all devices instead of only volumes${NC}"
            "💾 Show APFS Snapshots in Disk Utility|com.apple.DiskUtility|WorkspaceShowAPFSSnapshots|true|false|false|writeResetValue|"
            "🚫 Disable new disk requests for Time Machine|com.apple.TimeMachine|DoNotOfferNewDisksForBackup|true|false|false|writeResetValue|"
            "🔄 Set Time Machine backup frequency to 'Manually'|/Library/Preferences/com.apple.TimeMachine|AutoBackup|false|true|true|writeResetValue|${GY}Setting this to 'manually' prevents Time Machine snapshots from taking up disk space${NC}"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|⚓️ [Dock]|"
            "🗑️  Wipe all app icons from Dock ${BO}(for fresh installs)${NC}|com.apple.dock|persistent-apps|-array|||delete|${GY}Activating this will wipe ALL dock icons.${NC}"
            "📏 Set Dock size to 38|com.apple.dock|tilesize|38|48|48|writeResetValue|"
            "⬅️  Position dock on left of screen (or bottom/right)|com.apple.dock|orientation|left|right|bottom|writeResetValue|${GY}Choosing Deactivate here will show the dock on the right${NC}"
            "⚡ Minimize windows using Scale effect instead of Genie|com.apple.dock|mineffect|scale|genie|genie|writeResetValue|"
            "📥 Minimize windows into their application icon|com.apple.dock|minimize-to-application|true|false|false|writeResetValue|"
            "🫥 Automatically hide and show the dock|com.apple.dock|autohide|true|false|false|writeResetValue|"
            "⚡ Make the dock appear faster|com.apple.dock|autohide-time-modifier|0.0|0.5|0.5|writeResetValue|${GY}Initial Auto-hide must be enabled${NC}"
            "⚡ Make the dock disappear faster|com.apple.dock|autohide-delay|0|0.2|0.2|writeResetValue|${GY}Initial Auto-hide must be enabled${NC}"
            "🏀 Animate opening applications|com.apple.dock|launchanim|true|false|true|writeResetValue|${GY}(On by default). Disabling this removes the bouncing icon indicator upon launch${NC}"
            "⚪️ Show indicator lights for open apps|com.apple.dock|show-process-indicators|true|false|true|writeResetValue|${GY}(On by default now in recent macOS versions)${NC}"
            "👻 Dim Dock Icons of Hidden Apps|com.apple.dock|showhidden|true|false|false|writeResetValue|${GY}Helps differentiate between apps that are hidden vs shown${NC}"
            "🚫 Disable Recent Items in Dock|com.apple.dock|show-recents|false|true|false|writeResetValue|"
            "💨 Speed Up Drag and Drop Spring Delay on Dock items|com.apple.dock|enable-spring-load-actions-on-all-items|false|true|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|⛶  [Hot Corners]|"
            "🚫 Disable the default bottom right 'Quick Note' Hot Corner|com.apple.dock|wvous-br-corner|1|14|14|writeResetValue|"
            "⏾  Enable the bottom right 'Put Display to Sleep' Hot Corner|com.apple.dock|wvous-br-corner|10|1|14|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🖥️  [Desktop, Widgets & Views]|"
        )
        if [[ "$MACOS_MAJOR" -ge 14 ]]; then
            preference_commands+=(
                "🚫 Disable 'click wallpaper to show Desktop' ${GY}${GR}(Sonoma 14+)${NC}|com.apple.WindowManager|EnableStandardClickToShowDesktop|false|true|true|writeResetValue|"
                # "🗑️  Wipe all widgets from Desktop ${GY}${GR}(Sonoma 14+)${NC} ${BO}(for fresh installs)${NC}|com.apple.notificationcenterui|widgets|-array|||WipeAllDesktopWidgets|"
                "🖥️  Show widgets on Desktop ${GY}${GR}(Sonoma 14+)${NC}|com.apple.WindowManager|StandardHideWidgets|false|true|true|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚫 ${GY}Disable 'click wallpaper to show Desktop' (Sonoma 14+)${NC}|com.apple.WindowManager|EnableStandardClickToShowDesktop|false|true|true|writeResetValue|"
                # "🗑️  ${GY}Wipe all widgets from Desktop (Sonoma 14+) (for fresh installs)${NC}|com.apple.notificationcenterui|widgets|-array|||WipeAllDesktopWidgets|"
                "🖥️  ${GY}Show widgets on Desktop (Sonoma 14+)${NC}|com.apple.WindowManager|StandardHideWidgets|false|true|true|writeResetValue|"
            )
        fi
        preference_commands+=(
            "ℹ️  Show item info for icons|$HOME/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:showItemInfo|true|false|false|Desktop_IconView_showItemInfo|"
            "ℹ️  Show item info below icons|$HOME/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:labelOnBottom|true|false|false|Desktop_IconView_labelOnBottom|${GY}(choosing Deactivate will show item info on the right, shifting icons to the left)${NC}"
            "🔤 Sort and arrange icons by name|$HOME/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:arrangeBy|name|none|none|Desktop_IconView_arrangeBy|${GY}If currently set to 'none', your arrangement will remain intact when choosing 'name', in case you wish to revert back. (Only removing .DS_Store files will forget your current arrangement)${NC}"
            "📏 Set icon text size to 14|$HOME/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:textSize|14.000000|16.000000|12.000000|Desktop_IconView_textSize|${GY}(choosing Deactivate will set the text size to 16)${NC}"
            "📏 Set icon size to 72|$HOME/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:iconSize|72.000000|84.000000|64.000000|Desktop_IconView_iconSize|${GY}(choosing Deactivate will set grid size to 84x84)${NC}"
            "📐 Set icon grid spacing to 100|$HOME/Library/Preferences/com.apple.finder.plist|:DesktopViewSettings:IconViewSettings:gridSpacing|100.000000|85.000000|54.000000|Desktop_IconView_gridSpacing|${GY}(choosing Deactivate will set grid spacing to 85)${NC}"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|⚙️  [System & UI]|"
            "📜 Always show scroll bars|NSGlobalDomain|AppleShowScrollBars|Always|Automatic|Automatic|writeResetValue|${GY}(instead of auto-hiding)${NC}"
            "📜 Click in the scroll bar to 'jump to the spot that's clicked'|NSGlobalDomain|AppleScrollerPagingBehavior|true|false|false|writeResetValue|${GY}Makes scrollbars jump to clicked position${NC}"
            "🗂️  Always prefer tabs when opening documents|NSGlobalDomain|AppleWindowTabbingMode|always|manual|manual|writeResetValue|"
            "⚠️  Always ask to keep changes when closing documents|NSGlobalDomain|NSCloseAlwaysConfirmsChanges|true|false|false|writeResetValue|"
            "🪟 Close windows when quitting an app|NSGlobalDomain|NSQuitAlwaysKeepsWindows|false|true|false|writeResetValue|${GY}When enabled, open documents and windows will be not restored when you re-open an application.${NC}"
            "🖱️  Double-clicking title bar zooms window|NSGlobalDomain|AppleActionOnDoubleClick|Maximize|Fill|Fill|writeResetValue|${GY}Sets 'window title bar double-clicking action' to Zoom instead of Fill${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            # Journal added
            preference_commands+=(
                "🧹 Clean Up Share Menu Extensions|com.apple.Sharing|SharingPeopleSuggestionsDisabled|true|false|false|DisableCertainShareExtensions|${GY}Activating this will disable the following items from the 'Share... context menu:${NC} ${YE}Add to Reading List, Notes, Add to Photos, Reminders, Save to Books, Contact Suggestions, Shortcuts, Freeform & Journal.${NC}"
            )
        elif [[ "$MACOS_MAJOR" -ge 13 ]]; then
            # Freeform and Contact Suggestions added + Shortcuts now appears in Share Menu
            preference_commands+=(
                "🧹 Clean Up Share Menu Extensions|com.apple.Sharing|SharingPeopleSuggestionsDisabled|true|false|false|DisableCertainShareExtensions|${GY}Activating this will disable the following items from the 'Share...' context menu:${NC} ${YE}Add to Reading List, Notes, Add to Photos, Reminders, Save to Books, Contact Suggestions, Shortcuts & Freeform.${NC}"
            )
        elif [[ "$MACOS_MAJOR" -ge 12 ]]; then
            # Shortcuts app exists, not in Share menu until 13
            preference_commands+=(
                "🧹 Clean Up Share Menu Extensions|pluginkit|Various-extensions|ignore|use|use|DisableCertainShareExtensions|${GY}Activating this will disable the following items from the 'Share' context menu:${NC} ${YE}Add to Reading List, Notes, Add to Photos, Reminders & Save to Books.${NC}"
            )
        else
            preference_commands+=(
                "🧹 Clean Up Share Menu Extensions|pluginkit|Various-extensions|ignore|use|use|DisableCertainShareExtensions|${GY}Activating this will disable the following items from the 'Share' context menu:${NC} ${YE}Add to Reading List, Notes, Add to Photos, Reminders & Save to Books.${NC}"
            )
        fi
        preference_commands+=(
            "📂 Expand Save Panels by default (1 of 2)|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode|true|false|false|writeResetValue|"
            "📂 Expand Save Panels by default (2 of 2)|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode2|true|false|false|writeResetValue|"
            "📂 Set List View for Open Panels by default (1 of 3)|NSGlobalDomain|NSNavPanelFileLastListModeForOpenModeKey|2|1|1|writeResetValue|"
            "📂 Set List View for Open Panels by default (2 of 3)|NSGlobalDomain|NSNavPanelFileListModeForOpenMode2|2|1|1|writeResetValue|"
            "📂 Set List View for Open Panels by default (3 of 3)|NSGlobalDomain|NavPanelFileListModeForOpenMode|2|1|1|writeResetValue|"
            "📂 Set List View for Save Panels by default (1 of 3)|NSGlobalDomain|NSNavPanelFileLastListModeForSaveModeKey|2|3|3|writeResetValue|"
            "📂 Set List View for Save Panels by default (2 of 3)|NSGlobalDomain|NSNavPanelFileListModeForSaveMode2|2|3|3|writeResetValue|"
            "📂 Set List View for Save Panels by default (3 of 3)|NSGlobalDomain|NavPanelFileListModeForSaveMode|2|3|3|writeResetValue|"
        )
        if [[ "$MACOS_MAJOR" -ge 11 ]] || [[ "$MACOS_MAJOR" -eq 10 && "$MACOS_MINOR" -ge 15 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out — Catalina & above
                preference_commands+=(
                    "🚫 ${GY}Disable Dashboard (macOS Mojave & below)${NC}|com.apple.dashboard|mcx-disabled|true|false|false|writeResetValue|${GY}Disables Dashboard and widgets.${NC}"
                )
            fi
        else
            # supported — Mojave (10.14) & below
            preference_commands+=(
                "🚫 Disable Dashboard ${YE}(macOS Mojave & below)${NC}|com.apple.dashboard|mcx-disabled|true|false|false|writeResetValue|${GY}Disables Dashboard and widgets.${NC}"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 11 ]] || [[ "$MACOS_MAJOR" -eq 10 && "$MACOS_MINOR" -ge 11 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out — El Capitan (10.11)+ blocked this via SIP
                preference_commands+=(
                    "🚫 ${GY}Disable Notification Center (OSX Yosemite & below)${NC}|launchctl|/System/Library/LaunchAgents/com.apple.notificationcenterui|unload|load||launchctl|${GY}Disables Notification Center on older macOS's${NC}"
                )
            fi
        else
            # supported — Mountain Lion (10.8) through Yosemite (10.10)
            preference_commands+=(
                "🚫 Disable Notification Center ${YE}(OSX Yosemite & below)${NC}|launchctl|/System/Library/LaunchAgents/com.apple.notificationcenterui|unload|load||launchctl|${GY}Disables Notification Center on older macOS's${NC}"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🪟 [Window Tiling]|${MA}(Sequoia 15+)${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            preference_commands+=(
                "🚫 Disable 'Drag windows to screen edges to tile' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTilingByEdgeDrag|false|true|true|writeResetValue|"
                "🚫 Disable 'Drag windows to menu bar to fill screen' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTopTilingByEdgeDrag|false|true|true|writeResetValue|"
                "🪟 Enable 'Hold ⌥ key while dragging windows to tile' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTilingOptionAccelerator|true|false|true|writeResetValue|"
                "🚫 Disable 'Tiled windows have margins' ${MA}(Sequoia 15+)${NC}|com.apple.WindowManager|EnableTiledWindowMargins|false|true|true|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚫 ${GY}Disable 'Drag windows to screen edges to tile' (Sequoia 15+)${NC}|com.apple.WindowManager|EnableTilingByEdgeDrag|false|true|true|writeResetValue|"
                "🚫 ${GY}Disable 'Drag windows to menu bar to fill screen' (Sequoia 15+)${NC}|com.apple.WindowManager|EnableTopTilingByEdgeDrag|false|true|true|writeResetValue|"
                "🪟 ${GY}Enable 'Hold ⌥ key while dragging windows to tile' (Sequoia 15+)${NC}|com.apple.WindowManager|EnableTilingOptionAccelerator|true|false|true|writeResetValue|"
                "🚫 ${GY}Disable 'Tiled windows have margins' (Sequoia 15+)${NC}|com.apple.WindowManager|EnableTiledWindowMargins|false|true|true|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🕹️  [Mission Control & Spaces]|"
            "🪟 Automatically rearrange Spaces based on most recent use|com.apple.dock|mru-spaces|true|false|true|writeResetValue|"
            "🪟 When switching to an app, switch to a Space with open windows for the app|NSGlobalDomain|AppleSpacesSwitchOnActivate|true|false|true|writeResetValue|"
            "🪟 Group windows by application|com.apple.dock|expose-group-apps|true|false|false|writeResetValue|"
            "🪟 Displays have separate Spaces ${BO}(Requires logging out)${BO}|com.apple.spaces|spans-displays|false|true|false|writeResetValue|"
        )
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            preference_commands+=(
                "🪟 Drag windows to top of screen to enter Mission Control ${MA}(Sequoia 15.1+)${NC}|com.apple.dock|enterMissionControlByTopWindowDrag|true|false|true|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🪟 ${GY}Drag windows to top of screen to enter Mission Control (Sequoia 15.1+)${NC}|com.apple.dock|enterMissionControlByTopWindowDrag|true|false|true|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|✨ [Appearance]|"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🌑 Enable dark mode on icons ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|AppleIconAppearanceTheme|RegularDark|||darkmode|"
                "🪟 Enable tinted Liquid Glass ${BL}(Tahoe 26.1+)${NC}|NSGlobalDomain|NSGlassDiffusionSetting|true|false|false|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🌑 ${GY}Enable dark mode on icons (Tahoe 26+)${NC}|NSGlobalDomain|AppleIconAppearanceTheme|RegularDark|||darkmode|"
                "🪟 ${GY}Enable tinted Liquid Glass (Tahoe 26.1+)${NC}|NSGlobalDomain|NSGlassDiffusionSetting|true|false|false|writeResetValue|"
            )
        fi
        preference_commands+=(
            "📏 Set sidebar icon size to small (in Finder/Settings)|NSGlobalDomain|NSTableViewDefaultSizeMode|1|2|2|writeResetValue|${GY}Sets sidebar icon size to small instead of medium in Finder/Settings${NC}"
            "🪟 Enable 'Reduce Transparency'|com.apple.universalaccess|reduceTransparency|true|false|false|ReduceTransparency|${GY}Reduces transparency on macoOS UI items${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🚫 Disable 'Tint Folders Based On Tags' ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|AppleDisableTagBasedIconTinting|true|||delete|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚫 ${GY}Disable 'Tint Folders Based On Tags' (Tahoe 26+)${NC}|NSGlobalDomain|AppleDisableTagBasedIconTinting|true|||delete|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🪄 [Animations]|"
            "🚫 Disable Automatic Window Animations|NSGlobalDomain|NSAutomaticWindowAnimationsEnabled|false|true|||${GY}Disables automatic window animations system-wide${NC}"
            "🚫 Disable Finder Info Window Animations|com.apple.finder|DisableAllAnimations|true|false|||${GY}Disables all Finder info window animations${NC}"
            "🚫 Disable QuickLook Animations|NSGlobalDomain|QLPanelAnimationDuration|0.0|0.25|||${GY}Disables QuickLook panel animations${NC}"
            "🚀 Speed Up Mission Control Animations|com.apple.dock|expose-animation-duration|0.1|0.5|||"
            "🚀 Speed Up Finder's Drag and Drop Spring Delay|NSGlobalDomain|com.apple.springing.delay|0.2|0.5|||${GY}Reduces spring delay for Finder drag and drop${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 14 ]]; then
            preference_commands+=(
                "🚫 Reduce Motion ${GY}${GR}(Sonoma 14+)${NC}|com.apple.universalaccess|reduceMotion|true|false|false|ReduceMotion|${GY}Reduces certain animations (i.e. the 'bubbly' spotlight search in Tahoe - but also affects mission control)${NC}"
                "🚫 Disable 'Auto-play animated images/GIFs' ${GY}${GR}(Sonoma 14+)${NC}|com.apple.Accessibility|ReduceMotionAutoplayAnimatedImagesEnabled|true|false|false|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚫 ${GY}Reduce Motion (Sonoma 14+)${NC}|com.apple.universalaccess|reduceMotion|true|false|false|ReduceMotion|${GY}Reduces certain animations (i.e. the 'bubbly' spotlight search in Tahoe - but also affects mission control)${NC}"
                "🚫 ${GY}Disable 'Auto-play animated images/GIFs' (Sonoma 14+)${NC}|com.apple.Accessibility|ReduceMotionAutoplayAnimatedImagesEnabled|true|false|false|writeResetValue|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🚫 ${GY}Disable Launchpad animation when opening/showing (Sequoia 15 & below)${NC}|com.apple.dock|springboard-show-duration|0|0.4|0.4|writeResetValue|"
                    "🚫 ${GY}Disable Launchpad animation when closing/hiding (Sequoia 15 & below)${NC}|com.apple.dock|springboard-hide-duration|0|0.4|0.4|writeResetValue|"
                    "🚫 ${GY}Disable Launchpad animation when swiping between pages (Sequoia 15 & below)${NC}|com.apple.dock|springboard-page-duration|0|0.4|0.4|writeResetValue|"
                )
            fi
        else
            preference_commands+=(
                "🚫 Disable Launchpad animation when opening/showing ${MA}(Sequoia 15 & below)${NC}|com.apple.dock|springboard-show-duration|0|0.4|0.4|writeResetValue|"
                "🚫 Disable Launchpad animation when closing/hiding ${MA}(Sequoia 15 & below)${NC}|com.apple.dock|springboard-hide-duration|0|0.4|0.4|writeResetValue|"
                "🚫 Disable Launchpad animation when swiping between pages ${MA}(Sequoia 15 & below)${NC}|com.apple.dock|springboard-page-duration|0|0.4|0.4|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📋 [Finder List View Options]|${GY}(Applies to all Finder, iCloud, and Trash list views)${NC}"
            "🗑️  Remove all .DS_Store files ${BO}(Resets all Finder views)${NC}||'find <directory> -name ".DS_Store" -type f -delete'|home folder|documents folder|root folder|Remove_All_DS_Store_Files|${GY}This may be necessary if Finder views do not change after setting some preferences. '.DS_Store' files take precedence over global .plists, so deleting them will ensure new global preferences are used. .DS_Store files will regenerate upon opening a Finder window, so ensure that all Finder windows are closed before removing .DS_Store files, as well as setting new preferences. (Try choosing Deactivate to test this for the Documents folder only)${NC}"
            "📋 Use List View by default|com.apple.finder|FXPreferredViewStyle|Nlsv|clmv|incv|writeResetValue|${GY}Sets Finder's default view to List View instead of Icon View. (choosing Deactivate will set this to column view)${NC}"
            "🧮 Enable Calculate All Sizes|$HOME/Library/Preferences/com.apple.finder.plist|:StandardViewSettings:ListViewSettings:calculateAllSizes|true|false|false|ListView_calculateAllSizes|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            # "GROUP|📋 [Finder List View Options]|"
            # "Set Custom List View Columns (All Finder Views)|$HOME/Library/Preferences/com.apple.finder.plist|:ListViewColumns|active|inactive|delete|ListViewColumns|Sets custom column configuration for all Finder list views (iCloud, Standard, Save Panels)"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📁 [Finder Icon View Options]|${GY}(Applies to all Finder, Save Dialogs, and iCloud icon views)${NC}"
            "🗑️  Remove all .DS_Store files ${BO}(Resets all Finder views)${NC}||'find <directory> -name ".DS_Store" -type f -delete'|home folder|documents folder|root folder|Remove_All_DS_Store_Files|${GY}This may be necessary if Finder views do not change after setting some preferences. '.DS_Store' files take precedence over global .plists, so deleting them will ensure new global preferences are used. .DS_Store files will regenerate upon opening a Finder window, so ensure that all Finder windows are closed before removing .DS_Store files, as well as setting new preferences. (Try choosing Deactivate to test this for the Documents folder only)${NC}"
            "📁 Use Icon View by default|com.apple.finder|FXPreferredViewStyle|icnv|Nlsv|incv|writeResetValue|${GY}Sets Finder's default view to Icon View. (choosing Deactivate will set this to list view)${NC}"
            "ℹ️  Show item info near icons|$HOME/Library/Preferences/com.apple.finder.plist|:StandardViewSettings:IconViewSettings:showItemInfo|true|false|false|IconView_variousSettings|"
            "⤵️  Show item info below icons|$HOME/Library/Preferences/com.apple.finder.plist|:StandardViewSettings:IconViewSettings:labelOnBottom|true|false|true|IconView_variousSettings|${GY}(choosing Deactivate will show item info on the right, shifting icons to the left)${NC}"
            "🔤 Sort and arrange icons by name|$HOME/Library/Preferences/com.apple.finder.plist|:StandardViewSettings:IconViewSettings:arrangeBy|name|none|none|IconView_variousSettings|${GY}If currently set to 'none', your arrangement will remain intact when choosing 'name', in case you wish to revert back. (Only removing .DS_Store files will forget your current arrangement)${NC}"
            "📏 Set icon text size to 12|$HOME/Library/Preferences/com.apple.finder.plist|:StandardViewSettings:IconViewSettings:textSize|12.000000|14.000000|12.000000|IconView_variousSettings|${GY}(choosing Deactivate will set the text size to 14)${NC}"
            "📏 Set icon size to 48|$HOME/Library/Preferences/com.apple.finder.plist|:StandardViewSettings:IconViewSettings:iconSize|48.000000|72.000000|64.000000|IconView_variousSettings|${GY}(choosing Deactivate will set the icon size to 72x72)${NC}"
            "📐 Set icon grid spacing to 29|$HOME/Library/Preferences/com.apple.finder.plist|:StandardViewSettings:IconViewSettings:gridSpacing|29.000000|43.000000|54.000000|IconView_variousSettings|${GY}(choosing Deactivate will set the grid spacing to 43)${NC}"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📁 [Finder]|"
            "🗂️  Always Show Tab Bar in Finder|com.apple.finder|NSWindowTabbingShoudShowTabBarKey-com.apple.finder.TBrowserWindow|true|false|false|writeResetValue|${GY}Shows the tab bar at the top of Finder windows by default${NC}"
            "🗂️  Open folders in tabs instead of new windows|com.apple.finder|FinderSpawnTab|true|false|false|writeResetValue|"
            "🏠 New Finder windows show the Desktop folder|com.apple.finder|NewWindowTarget|PfDe|PfHm|PfAF|writeResetValue|${GY}Sets new Finder windows to open the Desktop folder instead of Recents. (choosing Deactivate here will set it to the home folder)${NC}"
            # "🏠 Set Desktop folder path for new Finder windows|com.apple.finder|NewWindowTargetPath|file://${HOME}/Desktop/|file://${HOME}/|||Sets new Finder windows to open the Desktop folder"
            "🚫 Don't show Recent Tags in the Sidebar|com.apple.finder|ShowRecentTags|false|true|true|writeResetValue|"
            # "🚫 Don't show 'Recents' in the sidebar|com.apple.finder|PreferencesWindow.LastSelection|SDBR|SDBR|TAGS|writeResetValue|"
            "🛣️  Show Path Bar in Finder|com.apple.finder|ShowPathbar|true|false|false|writeResetValue|${GY}Shows the path bar at the bottom of Finder windows${NC}"
            "📊 Show Status Bar in Finder|com.apple.finder|ShowStatusBar|true|false|false|writeResetValue|${GY}Shows the status bar at the bottom of Finder windows${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # Tahoe 26+
                preference_commands+=(
                    "📏 Shrink sidebar width to the minimum ${BL}(Tahoe 26+)${NC}|com.apple.finder|SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|"
                    # "📏 Shrink sidebar width to the minimum (2 of 2) ${BL}(Tahoe 26+)${NC}|com.apple.finder|FK_SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|Shrinks sidebar width (in other views) to the minimum"
                    "📏 ${GY}Shrink sidebar width to the minimum (Sequoia 15 & below)${NC}|com.apple.finder|SidebarWidth|143|164|164|ShrinkSideBarInSequoiaAndBelow|"
                    # "📏 ${GY}Shrink sidebar width to the minimum (2 of 2) (Sequoia 15 & below)${NC}|com.apple.finder|FK_SidebarWidth|143|164|164|writeResetValue|Shrinks sidebar width (in other views) to the minimum"
                )
            else
                preference_commands+=(
                    "📏 Shrink sidebar width to the minimum ${BL}(Tahoe 26+)${NC}|com.apple.finder|SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|"
                    # "📏 Shrink sidebar width to the minimum (2 of 2) ${BL}(Tahoe 26+)${NC}|com.apple.finder|FK_SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|Shrinks sidebar width (in other views) to the minimum"
                )
            fi
        else
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # Sequoia 15 & below
                preference_commands+=(
                    "📏 ${GY}Shrink sidebar width to the minimum (Tahoe 26+)${NC}|com.apple.finder|SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|"
                    # "📏 ${GY}Shrink sidebar width to the minimum (2 of 2) (Tahoe 26+)${NC}|com.apple.finder|FK_SidebarWidth2|135|161|161|ShrinkSideBarInTahoe|Shrinks sidebar width (in other views) to the minimum"
                    "📏 Shrink sidebar width to the minimum ${MA}(Sequoia 15 & below)${NC}|com.apple.finder|SidebarWidth|143|164|164|ShrinkSideBarInSequoiaAndBelow|"
                    # "📏 Shrink sidebar width to the minimum (2 of 2) ${MA}(Sequoia 15 & below)${NC}|com.apple.finder|FK_SidebarWidth|143|164|164|writeResetValue|Shrinks sidebar width (in other views) to the minimum"
                )
            else
                preference_commands+=(
                    "📏 Shrink sidebar width to the minimum ${MA}(Sequoia 15 & below)${NC}|com.apple.finder|SidebarWidth|143|164|164|ShrinkSideBarInSequoiaAndBelow|"
                    # "📏 Shrink sidebar width to the minimum (2 of 2) ${MA}(Sequoia 15 & below)${NC}|com.apple.finder|FK_SidebarWidth|143|164|164|writeResetValue|Shrinks sidebar width (in other views) to the minimum"
                )
            fi
        fi
        preference_commands+=(
            "🏷️  Show all filename extensions|NSGlobalDomain|AppleShowAllExtensions|true|false|false|writeResetValue|${GY}Shows file extensions for all files${NC}"
            "🚫 Disable the warning when changing a file extension|com.apple.finder|FXEnableExtensionChangeWarning|false|true|true|writeResetValue|"
        )
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # Sequoia 15+
                preference_commands+=(
                    "🚫 Hide Warning before removing from iCloud Drive ${MA}(Sequoia 15+)${NC}|com.apple.bird|com.apple.clouddocs.unshared.moveOut.suppress|1|0|0|writeResetValue|"
                    "🚫 ${GY}Hide Warning before removing from iCloud Drive (Sonoma 14 & below)${NC}|com.apple.finder|FXEnableRemoveFromICloudDriveWarning|0|1|1|writeResetValue|"
                )
            else
                preference_commands+=(
                    "🚫 Hide Warning before removing from iCloud Drive ${MA}(Sequoia 15+)${NC}|com.apple.bird|com.apple.clouddocs.unshared.moveOut.suppress|1|0|0|writeResetValue|"
                )
            fi
        else
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # Sonoma 14 & below
                preference_commands+=(
                    "🚫 ${GY}Hide Warning before removing from iCloud Drive (Sequoia 15+)${NC}|com.apple.bird|com.apple.clouddocs.unshared.moveOut.suppress|1|0|0|writeResetValue|"
                    "🚫 Hide Warning before removing from iCloud Drive ${GY}${GR}(Sonoma 14 & below)${NC}|com.apple.finder|FXEnableRemoveFromICloudDriveWarning|0|1|1|writeResetValue|"
                )
            else
                preference_commands+=(
                    "🚫 Hide Warning before removing from iCloud Drive ${GY}${GR}(Sonoma 14 & below)${NC}|com.apple.finder|FXEnableRemoveFromICloudDriveWarning|0|1|1|writeResetValue|"
                )
            fi
        fi
        preference_commands+=(
            "🔍 Search the current folder when performing a search|com.apple.finder|FXDefaultSearchScope|SCcf|SCev|SCev|writeResetValue|${GY}Uses the current (focused) folder when performing a search${NC}"
            "📚 Show hidden User ~/Library folder by default|com.apple.FinderInfo|ShowLibrary|visible|hidden||chflags|${GY}Makes the User Library folder visible in Finder${NC}"
            "👻 Show hidden files (or toggle them with ⇧⌘.)|com.apple.finder|AppleShowAllFiles|true|false|false|writeResetValue|${GY}(You can also show them temporarily with ⇧⌘.)${NC}"
            # "🔍 Set Custom Get Info Pane Layout|com.apple.finder|FXInfoPanesExpanded|'{General=true;Comments=false;MetaData=true;Name=true;OpenWith=true;Preview=false;Privileges=true;}'|{}||defaults_dict|Sets Get Info pane expand/collapse"
            # "🔍 Set Custom Toolbar Items|com.apple.finder|NSToolbar Configuration Browser|'{\"TB Default Item Identifiers\"=(\"com.apple.finder.BACK\",\"com.apple.finder.SWCH\",NSToolbarSpaceItem,\"com.apple.finder.ARNG\",\"com.apple.finder.SHAR\",\"com.apple.finder.LABL\",\"com.apple.finder.ACTN\",NSToolbarSpaceItem,\"com.apple.finder.SRCH\");\"TB Display Mode\"=2;\"TB Icon Size Mode\"=1;\"TB Is Shown\"=1;\"TB Item Identifiers\"=(\"com.apple.finder.BACK\",\"com.apple.finder.loc \",\"com.apple.finder.AirD\",\"com.apple.finder.CNCT\",\"com.apple.finder.NFLD\",\"com.apple.finder.SHAR\",\"com.apple.finder.SWCH\",NSToolbarSpaceItem,\"com.apple.finder.ACTN\",NSToolbarSpaceItem,\"com.apple.finder.SRCH\");\"TB Size Mode\"=1;}'|{}||defaults_dict|Sets Finder toolbar"    
            
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|♿️ [Accessibility - Zoom]|⚠️  ${YE}(Terminal requires Full Disk Access to write changes)${NC}"
            "🔎 Use keyboard shortcuts to zoom|com.apple.universalaccess|closeViewHotkeysEnabled|true|false|false|UniversalAccessNeedsFDA|${GY}Enables global zoom functionality via hot keys${NC}"
            "🔎 Use trackpad gesture to zoom|com.apple.universalaccess|closeViewTrackpadGestureZoomEnabled|true|false|false|UniversalAccessNeedsFDA|"
            "🔎 Zoom Continuously with Pointer|com.apple.universalaccess|closeViewPanningMode|false|true|false|UniversalAccessNeedsFDA|"
        )
        if [[ "$MACOS_MAJOR" -ge 14 ]]; then
            preference_commands+=(
                "🔎 Zoom Each Display Independently ${GY}${GR}(Sonoma 14+)${NC}|com.apple.universalaccess|closeViewZoomIndividualDisplays|true|false|false|UniversalAccessNeedsFDA|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🔎 ${GY}Zoom Each Display Independently (Sonoma 14+)${NC}|com.apple.universalaccess|closeViewZoomIndividualDisplays|true|false|false|UniversalAccessNeedsFDA|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            preference_commands+=(
                "🔎 Show Zoomed Image While Screen Sharing ${MA}(Sequoia 15+)${NC}|com.apple.universalaccess|closeViewZoomScreenShareEnabledKey|true|false|false|UniversalAccessNeedsFDA|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🔎 ${GY}Show Zoomed Image While Screen Sharing (Sequoia 15+)${NC}|com.apple.universalaccess|closeViewZoomScreenShareEnabledKey|true|false|false|UniversalAccessNeedsFDA|"
            )
        fi
        preference_commands+=(
            "🔎 Follow keyboard focus 'Always'|com.apple.universalaccess|closeViewZoomFocusFollowModeKey|1|2|2|UniversalAccessNeedsFDA|${GY}Zoom always follows keyboard focus when typing${NC}"
            "🔎 Move screen image so focus item is centered|com.apple.universalaccess|closeViewZoomFocusMovement|false|true|true|UniversalAccessNeedsFDA|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📋 [Menu Bar]|${GY}(To prevent clutter, hide all and just use Control Center) 👍${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "📋 Show Menu Bar Background ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|SLSMenuBarUseBlurredAppearance|true|||delete|${GY}Shows or disables the menu bar's blurred appearance${NC}"
                    "🖥️  Never Hide Menu Bar In Fullscreen ${BL}(Tahoe 26+)${NC}|com.apple.controlcenter|AutoHideMenuBarOption|3|2||NevaHideMenuBarinTahoe|"
                    "🖥️  ${GY}Never Hide Menu Bar In Fullscreen (Sequoia 15 & below)${NC}|NSGlobalDomain|AppleMenuBarVisibleInFullscreen|true|false|false|writeResetValue|"
                )
            else
                preference_commands+=(
                    "📋 Show Menu Bar Background ${BL}(Tahoe 26+)${NC}|NSGlobalDomain|SLSMenuBarUseBlurredAppearance|true|||delete|${GY}Shows or disables the menu bar's blurred appearance${NC}"
                    "🖥️  Never Hide Menu Bar In Fullscreen ${BL}(Tahoe 26+)${NC}|com.apple.controlcenter|AutoHideMenuBarOption|3|2||NevaHideMenuBarinTahoe|"
                )
            fi
        else
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                preference_commands+=(
                    "📋 ${GY}Show Menu Bar Background (Tahoe 26+)${NC}|NSGlobalDomain|SLSMenuBarUseBlurredAppearance|true|||delete|${GY}Shows or disables the menu bar's blurred appearance${NC}"
                    "🖥️  ${GY}Never Hide Menu Bar In Fullscreen (Tahoe 26+)${NC}|com.apple.controlcenter|AutoHideMenuBarOption|3|2||NevaHideMenuBarinTahoe|"
                    "🖥️  Never Hide Menu Bar In Fullscreen ${MA}(Sequoia 15 & below)${NC}|NSGlobalDomain|AppleMenuBarVisibleInFullscreen|true|false|false|writeResetValue|"
                )
            else
                preference_commands+=(
                    "🖥️  Never Hide Menu Bar In Fullscreen ${MA}(Sequoia 15 & below)${NC}|NSGlobalDomain|AppleMenuBarVisibleInFullscreen|true|false|false|writeResetValue|"
                )
            fi
        fi
        preference_commands+=(
            # "🍱 Show Control Center in Menu Bar|com.apple.controlcenter|NSStatusItem Visible BentoBox|true|false|true|delete|Shows Control Center in the menu bar"
            # "🕒 Always show date in menu bar|com.apple.menuextra.clock|ShowDate|true|false|true|writeResetValue|"
            "🕒 Display the time with seconds|com.apple.menuextra.clock|ShowSeconds|true|false|false|writeResetValue|"
            "🔍 Show Spotlight in Menu Bar|com.apple.Spotlight|MenuItemHidden|0|1|0|-currentHost|"
            # "🔮 Show Siri in Menu Bar|com.apple.controlcenter|Siri|2|8|2|-currentHost|"
        )
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            preference_commands+=(
                "🔑 Show Passwords In Menu Bar ${MA}(Sequoia 15+)${NC}|com.apple.Passwords|EnableMenuBarExtra|true|false|false|PasswordManager|${GY}Please enable manually the first time in order to start the Passwords background item/service)${NC}"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🔑 ${GY}Show Passwords In Menu Bar (Sequoia 15+)${NC}|com.apple.Passwords|EnableMenuBarExtra|true|false|false|PasswordManager|${GY}Please enable manually the first time in order to start the Passwords background item/service)${NC}"
            )
        fi
        preference_commands+=(
            "🛜 Show WiFi in Menu Bar|com.apple.controlcenter|WiFi|2|8|8|-currentHost|"
            "🔵 Show Bluetooth in Menu Bar [Always]|com.apple.controlcenter|Bluetooth|2|8|8|-currentHost|"
            "🌀 Show AirDrop in Menu Bar [Always]|com.apple.controlcenter|AirDrop|2|8|8|-currentHost|"
            "📵 Show Focus in Menu Bar [Always]|com.apple.controlcenter|FocusModes|18|8|2|-currentHost|"
        )
        if [[ "$MACOS_MAJOR" -ge 26 && "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚀 ${GY}Show Stage Manager in Menu Bar [Always] (Sequoia 15 & below)${NC}|com.apple.controlcenter|StageManager|2|8|8|-currentHost|"
            )
        else
            preference_commands+=(
                "🚀 Show Stage Manager in Menu Bar [Always] ${MA}(Sequoia 15 & below)${NC}|com.apple.controlcenter|StageManager|2|8|8|-currentHost|"
            )
        fi
        preference_commands+=(
            "🖥️  Show Screen Mirroring in Menu Bar [Always]|com.apple.controlcenter|ScreenMirroring|18|8|2|-currentHost|"
            "🖥️  Show Display in Menu Bar [Always]|com.apple.controlcenter|Display|18|8|2|-currentHost|"
            "🔊 Show Sound in Menu Bar [Always]|com.apple.controlcenter|Sound|18|8|2|-currentHost|"
            "🚀 Show Now Playing in Menu Bar [Always]|com.apple.controlcenter|NowPlaying|18|8|2|-currentHost|"
            "♿️ Show Accessibility in Menu Bar|com.apple.controlcenter|AccessibilityShortcuts|3|9|9|-currentHost|"
            "📣 Show Music Recognition in Menu Bar|com.apple.controlcenter|MusicRecognition|6|12|12|-currentHost|"
            "🦻 Show Hearing in Menu Bar|com.apple.controlcenter|Hearing|2|8|8|-currentHost|"
            "🎤 Show Voice Control in Menu Bar|com.apple.controlcenter|VoiceControl|18|8|8|-currentHost|"
            "👤 Show Fast User Switching in Menu Bar|com.apple.controlcenter|UserSwitcher|2|8|8|-currentHost|"
        )
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            preference_commands+=(
                "⚡️ Show Low Power Mode in Menu Bar ${MA}(Sequoia 15+)${NC}|com.apple.controlcenter|EnergyModeModule|9|19|19|-currentHost|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "⚡️ ${GY}Show Low Power Mode in Menu Bar (Sequoia 15+)${NC}|com.apple.controlcenter|EnergyModeModule|9|19|19|-currentHost|"
            )
        fi
        preference_commands+=(
            "🔤 Show Text Input in Menu Bar|com.apple.TextInputMenu|visible|true|false|false|writeResetValue|"
            "⏳ Show Time Machine in Menu Bar|com.apple.systemuiserver|NSStatusItem Visible com.apple.menuextra.TimeMachine|true|false|false|Show_Time_Machine_Menu_Bar_Item|"
        )
        if [[ "$MACOS_MAJOR" -ge 26 && "$MACOS_MINOR" -ge 2 ]]; then
            preference_commands+=(
                "⏰ Show Timer in Menu Bar ${BL}(Tahoe 26.2+)${NC}|com.apple.controlcenter|Timer|16|0|0|-currentHost|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "⏰ ${GY}Show Timer in Menu Bar (Tahoe 26.2+)${NC}|com.apple.controlcenter|Timer|16|0|0|-currentHost|"
            )
        fi
        preference_commands+=(
            "⏳ Show VPN in Menu Bar|com.apple.systemuiserver|NSStatusItem Visible com.apple.menuextra.vpn|true|false|false|Show_VPN_Menu_Bar_Item|${GY}Must first be configured to appear. (System Settings > Network > VPN & Filters)${NC}"
            # "🚀 Show Shortcuts in Menu Bar|com.apple.controlcenter|NSStatusItem Visible Shortcuts|true|false|||"
            # "🎥 Show FaceTime in Menu Bar|com.apple.controlcenter|NSStatusItem Visible FaceTime|true|false|||"
            # "⛅️ Show Weather in Menu Bar ${MA}(macOS Sequoia 15+)${NC}|com.apple.controlcenter|Weather|2|8|8|-currentHost|"
            "🕹️  Show Remote Management in Menu Bar|/Library/Preferences/com.apple.RemoteManagement|LoadRemoteManagementMenuExtra|true|false|false|Remote_Management_Menu_Bar|${GY}Must first be enabled to appear. (System Settings > General > Sharing > Remote Management)${NC}"
            
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📋 [Menu Bar - For Laptops]|"
        )
        if [[ "$DEVICE_TYPE" == "laptop" ]]; then
            preference_commands+=(
                "🔋 Show Battery in Menu Bar|com.apple.controlcenter|Battery|3|9|9|-currentHost|"
                "💯 Show Battery Percentage in Menu Bar|com.apple.controlcenter|BatteryShowPercentage|1|0|0|-currentHost|"
                "⌨️  Show Keyboard Brightness in Menu Bar|com.apple.controlcenter|KeyboardBrightness|3|9|9|-currentHost|"
            )
        elif [[ "$DEVICE_TYPE" == "desktop" ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                preference_commands+=(
                    "🔋 ${GY}Show Battery in Menu Bar${NC}|com.apple.controlcenter|Battery|3|9|9|-currentHost|"
                    "💯 ${GY}Show Battery Percentage in Menu Bar${NC}|com.apple.controlcenter|BatteryShowPercentage|1|0|0|-currentHost|"
                    "⌨️  ${GY}Show Keyboard Brightness in Menu Bar${NC}|com.apple.controlcenter|KeyboardBrightness|3|9|9|-currentHost|"
                )
            fi
        else
            preference_commands+=(
                "🔋 Show Battery in Menu Bar|com.apple.controlcenter|Battery|3|9|9|-currentHost|"
                "💯 Show Battery Percentage in Menu Bar|com.apple.controlcenter|BatteryShowPercentage|1|0|0|-currentHost|"
                "⌨️  Show Keyboard Brightness in Menu Bar|com.apple.controlcenter|KeyboardBrightness|3|9|9|-currentHost|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📶 [Connectivity]|"
            "🚫 Disable Universal Control|com.apple.universalcontrol|Disable|1|delete|delete|-currentHost|"
            "🚫 Disable AirPlay Receiver|com.apple.controlcenter|AirplayReceiverEnabled|false|true|true|-currentHost|"
            "🚫 Prevent Photos from opening automatically when devices are plugged in|com.apple.ImageCapture|disableHotPlug|true|false|false|-currentHost|"
        )
        if [[ "$MACOS_MAJOR" -ge 11 ]] || [[ "$MACOS_MAJOR" -eq 10 && "$MACOS_MINOR" -ge 15 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out — Catalina (10.15)+ removed legacy AirDrop
                preference_commands+=(
                    "🌐 ${GY}Enable AirDrop over Ethernet (Mojave 10.14 & below)${NC}|com.apple.NetworkBrowser|BrowseAllInterfaces|true|false|false|writeResetValue|"
                )
            fi
        else
            # supported — Lion (10.7) through Mojave (10.14)
            preference_commands+=(
                "🌐 Enable AirDrop over Ethernet ${YE}(Mojave 10.14 & below)${NC}|com.apple.NetworkBrowser|BrowseAllInterfaces|true|false|false|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🔍 [Spotlight]|"
            # "🚫 Disable Indexing for Custom Items (When using FindAnyFile)|com.apple.spotlight|orderedItems|'{\"enabled\"=1;\"name\"=\"APPLICATIONS\";}' '\"{\"enabled\"=0;\"name\"=\"MENU_EXPRESSION\";}\" … (etc)’||defaults_array|Sets Spotlight orderedItems"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🚫 Disable 'Show Related Content' ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Custom.relatedContents|||DisableSpotlightRelatedContent|"
                "🚫 Disable all default results (except System Settings & Apps) ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Remove various Apps/Items|||ReduceSpotlightResultsInTahoe|${GY}Note that more apps may show up here later on once using them. In that case, this preference may inadvertently affect new apps that show up here. (Intended for fresh installs)${NC}"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚫 ${GY}Disable 'Show Related Content' (Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Custom.relatedContents|||DisableSpotlightRelatedContent|"
                "🚫 ${GY}Disable all default results (except System Settings & Apps) (Tahoe 26+)${NC}|com.apple.Spotlight|EnabledPreferenceRules|Remove various Apps/Items|||ReduceSpotlightResultsInTahoe|${GY}Note that more apps may show up here later on once using them. In that case, this preference may inadvertently affect new apps that show up here. (Intended for fresh installs)${NC}"
            )
        fi
        # if [[ "$MACOS_MAJOR" -lt 26 ]]; then
        #     preference_commands+=(
        #         "🚫 Disable all default results (except System Settings & Apps) ${MA}(Sequoia 15 & below)${NC}|com.apple.Spotlight|orderedItems|Various Apps/Items|||ReduceSpotlightResultsInSequoia|"    # not reliably working yet
        #     )
        # elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
        #     # grey out unsupported
        #     preference_commands+=(
        #         "🚫 ${GY}Disable all default results (except System Settings & Apps) (Sequoia 15 & below)${NC}|com.apple.Spotlight|orderedItems|Various Apps/Items|||ReduceSpotlightResultsInSequoia|"    # not reliably working yet
        #     )
        # fi
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            preference_commands+=(
                "🚫 Disable 'Help Apple Improve Search' ${MA}(Sequoia 15+)${NC}|com.apple.assistant.support|Search Queries Data Sharing Status|2|1|1|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚫 ${GY}Disable 'Help Apple Improve Search' (Sequoia 15+)${NC}|com.apple.assistant.support|Search Queries Data Sharing Status|2|1|1|writeResetValue|"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
            "🔍 Enable Clipboard Manager ${BL}(Tahoe 26+)${NC}|com.apple.Spotlight|PasteboardHistoryEnabled|true|false|false|writeResetValue|"
            "🔍 Increase Clipboard history from 8hrs to 7 days ${BL}(Tahoe 26.1+)${NC}|com.apple.Spotlight|PasteboardHistoryTimeout|604800|28800|28800|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
            "🔍 ${GY}Enable Clipboard Manager (Tahoe 26+)${NC}|com.apple.Spotlight|PasteboardHistoryEnabled|true|false|false|writeResetValue|"
            "🔍 ${GY}Increase Clipboard history from 8hrs to 7 days (Tahoe 26.1+)${NC}|com.apple.Spotlight|PasteboardHistoryTimeout|604800|28800|28800|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🔄 [Automatic Updates]|"
            # "OLD=🚫 Disable macOS Auto-Update|softwareupdate|schedule|off|on||sudo|"
            "🔄 Automatically Download macOS Updates|/Library/Preferences/com.apple.SoftwareUpdate|AutomaticDownload|true|false||SoftwareUpdates|"
            "🔄 Automatically Install macOS Updates|/Library/Preferences/com.apple.SoftwareUpdate|AutomaticallyInstallMacOSUpdates|true|false||SoftwareUpdates|"
            "🔄 Automatically Install Config Data|/Library/Preferences/com.apple.SoftwareUpdate|ConfigDataInstall|true|false||SoftwareUpdates|"
            "🔄 Automatically Install Critical Updates|/Library/Preferences/com.apple.SoftwareUpdate|CriticalUpdateInstall|true|false||SoftwareUpdates|"
        )
        if [[ "$MACOS_MAJOR" -lt 11 && "$MACOS_MINOR" -lt 15 ]]; then
            # works up until 10.14 Mojave. Stopped working in Catalina
            preference_commands+=(
                "🔄 Automatically Check for macOS Updates ${GY}${YE}(Mojave & below)${NC}|/Library/Preferences/com.apple.SoftwareUpdate|AutomaticCheckEnabled|true|false||SoftwareUpdates|"
            )
        else
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🔄 ${GY}Automatically Check for macOS Updates (Mojave & below)${NC}|/Library/Preferences/com.apple.SoftwareUpdate|AutomaticCheckEnabled|true|false||SoftwareUpdates|"
                )
            fi
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🤖 [Apple Intelligence]|(${BO}Req. Apple Silicon or ${MA}Sequoia 15.1+${NC})"
        )
        if [[ "$ARCH_TYPE" != "arm64" ]] || [[ "$MACOS_MAJOR" -le 14 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                preference_commands+=(
                    "🚫 ${GY}Disable Apple Intelligence${NC}|com.apple.CloudSubscriptionFeatures.optIn|Dynamic (check yours with 'defaults read com.apple.CloudSubscriptionFeatures.optIn')|false|true|false|disable_Apple_Intelligence|"
                )
            fi
        else
            preference_commands+=(
                "🚫 Disable Apple Intelligence|com.apple.CloudSubscriptionFeatures.optIn|Dynamic (check yours with 'defaults read com.apple.CloudSubscriptionFeatures.optIn')|false|true|false|disable_Apple_Intelligence|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🔑 [Passwords & AutoFill]|"
        )
        if [[ "$MACOS_MAJOR" -ge 15 ]]; then
            preference_commands+=(
                "🔑 Show Passwords In Menu Bar ${MA}(Sequoia 15+)${NC}|com.apple.Passwords|EnableMenuBarExtra|true|false|false|PasswordManager|${GY}Please enable manually the first time in order to start the Passwords background item/service)${NC}"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🔑 ${GY}Show Passwords In Menu Bar (Sequoia 15+)${NC}|com.apple.Passwords|EnableMenuBarExtra|true|false|false|PasswordManager|${GY}Please enable manually the first time in order to start the Passwords background item/service)${NC}"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🚫 Disallow Contacting Websites ${BL}(Tahoe 26+)${NC}|com.apple.Passwords|WBSPasswordsAppBackgroundNetworkingEnabled|false|true|true|writeResetValue|${GY}Prevents network telemetry with websites from saved passwords. (This is how icons and names get shown)${NC}"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚫 ${GY}Disallow Contacting Websites (Tahoe 26+)${NC}|com.apple.Passwords|WBSPasswordsAppBackgroundNetworkingEnabled|false|true|true|writeResetValue|${GY}Prevents network telemetry with websites from saved passwords. (This is how icons and names get shown)${NC}"
            )
        fi
        if [[ "$MACOS_MAJOR" -ge 14 ]]; then
            preference_commands+=(
                "🚮 Delete verification codes after use ${BO}(FDA req. to read/write)${NC} ${GY}${GR}(Sonoma 14+)${NC}|com.apple.MobileSMS|DeleteVerificationCodes|true|false|false|Auto_Fill_Passwords_DeleteVerificationCodes|${GY}Auotmatically deletes verifications codes in Messages and Mail after they are used.${NC}"
                # "🚮 Delete verification codes after use [2/2] ${MA}(Sequoia 15+)${NC}|com.apple.onetimepasscodes|DeleteVerificationCodes|true|false|false|Auto_Fill_Passwords_DeleteVerificationCodes|${GY}Auotmatically deletes verifications codes in Messages and Mail after they are used.${NC}"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🚮 ${GY}Delete verification codes after use (FDA req. to read/write) (Sonoma 14+)${NC}|com.apple.MobileSMS|DeleteVerificationCodes|true|false|false|Auto_Fill_Passwords_DeleteVerificationCodes|${GY}Auotmatically deletes verifications codes in Messages and Mail after they are used.${NC}"
                # "🚮 Delete verification codes after use [2/2] ${MA}(Sequoia 15+)${NC}|com.apple.onetimepasscodes|DeleteVerificationCodes|true|false|false|Auto_Fill_Passwords_DeleteVerificationCodes|${GY}Auotmatically deletes verifications codes in Messages and Mail after they are used.${NC}"
            )
        fi
        preference_commands+=(
            "🚫 Disable AutoFill Passwords and Passkeys ${BO}(FDA req. to read/write)${NC}|com.apple.Safari|AutoFillPasswords|false|true|false|DisableGlobalPasswordAutoFill|"
            "🚫 Disable AutoFill from iCloud Keychain/Passwords app ${BO}(FDA req. to read/write)${NC}|com.apple.Safari|AutoFillFromiCloudKeychain|false|true|false|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📝 [TextEdit]|"
            "🗂️  Always show Tab Bar in TextEdit|com.apple.TextEdit|NSWindowTabbingShoudShowTabBarKey-NSWindow-DocumentWindowController-DocumentWindowController-VT-FS|true|false|false|writeResetValue|"
            "📝 Create a new document by default when opening TextEdit|com.apple.TextEdit|NSShowAppCentricOpenPanelInsteadOfUntitledFile|false|true|false|writeResetValue|${GY}Opens a blank document immediately instead of the open files panel.${NC}"
            "📝 Use Plain Text Mode for TextEdit|com.apple.TextEdit|RichText|false|true|true|writeResetValue|${GY}Sets TextEdit to use Plain Text instead of Rich Text by default${NC}"
            "📂 Set Default Font Size in TextEdit to 14|com.apple.TextEdit|NSFixedPitchFontSize|14|12|11|writeResetValue|${GY}(Choosing Deactivate sets the font size to 12)${NC}"
            "📂 Expand Save Panel by Default (1 of 3)|com.apple.TextEdit|NSNavPanelExpandedStateForSaveMode|true|false|false|writeResetValue|"
            "📂 Expand Save Panel by Default (2 of 3)|com.apple.TextEdit|NSNavPanelExpandedStateForSaveMode2|true|false|false|writeResetValue|"
            "📂 Expand Save Panel by Default (3 of 3)|com.apple.TextEdit|NSNavPanelFileLastListModeForSaveModeKey|2|1|1|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|👾 [Terminal]|⚠️  ${YE}(Must quit Terminal afterwards to reflect changes)${NC}"
            "🗂️  Always show Tab Bar in Terminal|com.apple.Terminal|NSWindowTabbingShoudShowTabBarKey-TTWindow-TTWindowController-TTWindowController-VT-FS|true|false|false|writeResetValue|"
            "🪟 Sets 'Basic' as the startup profile|com.apple.Terminal|Startup Window Settings|Basic|Clear Dark|Clear Dark|writeResetValue|${GY}Sets the startup Terminal window to 'Basic' instead of 'Clear Dark'${NC}"
            "🪟 Sets 'Basic' as the default profile|com.apple.Terminal|Default Window Settings|Basic|Clear Dark|Clear Dark|writeResetValue|${GY}Sets the default Terminal window to 'Basic' instead of 'Clear Dark'${NC}"
            "⭐️ Use bright colors for bold text ${GY}(must enable manually)${NC}|com.apple.Terminal|UseBrightBold|true|false|reset|UseBrightBoldInTerminal|${GY}This will be applied to only the window profiles that are currently set as your default. Note: Making this Active will currently fail. Please enable manually. Deactivate, Reset to Default and displaying state/value works as expected.${NC}"
            "📂 Expand Save Panels by default in Terminal|com.apple.Terminal|NSNavPanelExpandedStateForSaveMode|true|false|false|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            # "GROUP|📊 [Activity Monitor]|"
            # "🔄 Set Update Frequency to 1 Sec|com.apple.ActivityMonitor|UpdatePeriod|1|2|5|writeResetValue|"
            # "🔄 Set Update Frequency to 1 Sec|com.apple.ActivityMonitor|UpdatePeriod|1|2|5|writeResetValue|"


            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📅 [Calendar]|"
            "🕛 Enable TimeZone Support|com.apple.iCal|TimeZone support enabled|true|false|false|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|💬 [Messages]|"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "💬 Screen Unknown Senders ${BO}(FDA req. to read/write)${NC} ${BL}(Tahoe 26+)${NC}|com.apple.MobileSMS|FilterMessageRequests|true|false|false|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "💬 ${GY}Screen Unknown Senders (FDA req. to read/write) (Tahoe 26+)${NC}|com.apple.MobileSMS|FilterMessageRequests|true|false|false|writeResetValue|"
            )
        fi
        preference_commands+=(
            "🚫 Disable Send Read Receipts|com.apple.imagent|Setting.EnableReadReceipts|false|true|true|DisableSendReadReceiptsIniMessage|"
            # "🚫 Disable Send Read Receipts 2 of 2|com.apple.imagent|Setting.GlobalReadReceiptsVersionID|2|1|1|DisableSendReadReceiptsIniMessage|"
            "💬 Disable Automatic Sharing|com.apple.SocialLayer|SharedWithYouEnabled|false|true|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🔎 [Preview]|"
            "🗂️  Always show Tab Bar in Preview|com.apple.Preview|NSWindowTabbingShoudShowTabBarKey-PVWindow-PVWindowController-PVWindowController-VT-FS|true|false|false|writeResetValue|"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "✏️  Show Markup toolbar for images by default ${BL}(Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForImages|true|false|false|writeResetValue|"
                "✏️  Show Markup toolbar for PDFs by default ${BL}(Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForPDFs|true|false|false|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "✏️  ${GY}Show Markup toolbar for images by default (Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForImages|true|false|false|writeResetValue|"
                "✏️  ${GY}Show Markup toolbar for PDFs by default (Tahoe 26+)${NC}|com.apple.Preview|PVMarkupToolbarVisibleForPDFs|true|false|false|writeResetValue|"
            )
        fi
        preference_commands+=(
            "📂 Expand Save Panels by default in Preview|com.apple.Preview|NSNavPanelExpandedStateForSaveMode|true|false|false|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📞 [Phone]|${BL}(Tahoe 26+)${NC}"
        )

        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "📞 Enable Hold Assist ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|HoldAssistDetectionEnabled|true|false|true|writeResetValue|"
                "📞 Enable Live Voicemail ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|CallScreeningDisabled|false|true|false|writeResetValue|"
                "📞 Screen Unknown Callers ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|ReceptionistDisabled|false|true|false|writeResetValue|${GY}Toggles on 'Ask Reason for Calling'${NC}"
                "📞 Filter Unknown Callers ${BL}(Tahoe 26+)${NC}|com.apple.TelephonyUtilities|filterUnknownCallersAsNewCallers|true|false|true|writeResetValue|"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "📞 ${GY}Enable Hold Assist (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|HoldAssistDetectionEnabled|true|false|true|writeResetValue|"
                "📞 ${GY}Enable Live Voicemail (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|CallScreeningDisabled|false|true|false|writeResetValue|"
                "📞 ${GY}Screen Unknown Callers (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|ReceptionistDisabled|false|true|false|writeResetValue|${GY}Toggles on 'Ask Reason for Calling'${NC}"
                "📞 ${GY}Filter Unknown Callers (Tahoe 26+)${NC}|com.apple.TelephonyUtilities|filterUnknownCallersAsNewCallers|true|false|true|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🎵 [Music]|"
            "🚫 Disable Sound Check/Normalization|com.apple.Music|optimizeSongVolume|false|true|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🗜️  [Archive Utility]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write)${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]] && [[ "$MACOS_MINOR" -ge 4 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🗑️  Move archives to trash after expanding ${BL}(Tahoe 26.4+)${NC}|com.apple.archiveutility|dearchive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    "🗑️  ${GY}Move archives to trash after expanding (Tahoe 26.3 & below)${NC}|com.apple.archiveutility|dearchive-move-after|~/.Trash|.|.|writeResetValue|"
                    "🗑️  Move files to trash after archiving ${BL}(Tahoe 26.4+)${NC}|com.apple.archiveutility|archive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    "🗑️  ${GY}Move files to trash after archiving (Tahoe 26.3 & below)${NC}|com.apple.archiveutility|archive-move-after|~/.Trash|.|.|writeResetValue|"
                )
            else
                # hide unsupported
                preference_commands+=(
                    "🗑️  Move archives to trash after expanding ${BL}(Tahoe 26.4+)${NC}|com.apple.archiveutility|dearchive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    # "🗑️  ${GY}Move archives to trash after expanding (Tahoe 26.3 & below)${NC}|com.apple.archiveutility|dearchive-move-after|~/.Trash|.|.|writeResetValue|"
                    "🗑️  Move files to trash after archiving ${BL}(Tahoe 26.4+)${NC}|com.apple.archiveutility|archive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    # "🗑️  ${GY}Move files to trash after archiving (Tahoe 26.3 & below)${NC}|com.apple.archiveutility|archive-move-after|~/.Trash|.|.|writeResetValue|"
                )
            fi
        else
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🗑️  ${GY}Move archives to trash after expanding (Tahoe 26.4+)${NC}|com.apple.archiveutility|dearchive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    "🗑️  Move archives to trash after expanding ${BL}(Tahoe 26.3 & below)${NC}|com.apple.archiveutility|dearchive-move-after|~/.Trash|.|.|writeResetValue|"
                    "🗑️  ${GY}Move files to trash after archiving (Tahoe 26.4+)${NC}|com.apple.archiveutility|archive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    "🗑️  Move files to trash after archiving ${BL}(Tahoe 26.3 & below)${NC}|com.apple.archiveutility|archive-move-after|~/.Trash|.|.|writeResetValue|"
                )
            else
                # hide unsupported
                preference_commands+=(
                    # "🗑️  ${GY}Move archives to trash after expanding (Tahoe 26.4+)${NC}|com.apple.archiveutility|dearchive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    "🗑️  Move archives to trash after expanding ${BL}(Tahoe 26.3 & below)${NC}|com.apple.archiveutility|dearchive-move-after|~/.Trash|.|.|writeResetValue|"
                    # "🗑️  ${GY}Move files to trash after archiving (Tahoe 26.4+)${NC}|com.apple.archiveutility|archive-move-after-location|MoveToTrash|UseSameFolder|UseSameFolder|NewArchiveUtilityDictIn26_4|"
                    "🗑️  Move files to trash after archiving ${BL}(Tahoe 26.3 & below)${NC}|com.apple.archiveutility|archive-move-after|~/.Trash|.|.|writeResetValue|"
                )
            fi
        fi
        preference_commands+=(
            "🚫 Don't reveal archives after expanding|com.apple.archiveutility|dearchive-reveal-after|false|true|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|📸 [Screen Capture]|"
            "🚫 Disable Screenshot border and shadow|com.apple.screencapture|disable-shadow|true|false|false|writeResetValue|${GY}Removes default border and shadow from screenshots${NC}"
            "🖼️  Set default Screenshot Format from PNG to JPG|com.apple.screencapture|type|jpg|png|png|writeResetValue|${GY}Note that although file size will be smaller, you will lose transparent backgrounds if choosing jpg${NC}"
            "🚫 Disable Screenshot Preview Thumbnails|com.apple.screencapture|show-thumbnail|false|true|true|writeResetValue|${GY}Disables screenshot preview thumbnails in order to save and appear on the desktop immediately${NC}"
            "🚫 Disable date and time in filenames|com.apple.screencapture|include-date|false|true|true|writeResetValue|"
            "🚫 Don't Show Mouse Pointer in Screenshots|com.apple.screencapture|showsCursor|false|true|false|writeResetValue|${GY}(Inactive by default)${NC}"
            "🎥 Show Mouse Clicks When Screen Recording|com.apple.screencapture|showsClicks|true|false|true|writeResetValue|${GY}(Inactive by default)${NC}"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🎥 [QuickTime Player]|"
            "🗂️  Always Show Tab Bar in QuickTime|com.apple.QuickTimePlayerX|NSWindowTabbingShoudShowTabBarKey-NSWindow-MGDocumentWindowController-MGDocumentWindowController-VT-FS|true|false|false|writeResetValue|"
            "▶️  Auto-play videos when opened with QuickTime Player|com.apple.QuickTimePlayerX|MGPlayMovieOnOpen|true|false|false|writeResetValue|"
            "✨ Set Audio/Movie Recording Quality to 'Maximum' in QuickTime|com.apple.QuickTimePlayerX|MGRecordingCompressionPresetIdentifier|MGCompressionPresetMaximumQuality|MGCompressionPresetHighQuality|MGCompressionPresetHighQuality|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🌐 [Safari - General]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write)${NC}"
            "🗂️  Always Show Tab Bar in Safari|com.apple.Safari|AlwaysShowTabBar|1|0|0|writeResetValue|"
            "🌐 Show Overlay Status Bar|com.apple.Safari|ShowOverlayStatusBar|true|false|false|writeResetValue|"
            "⭐️ Show Favorites Bar|com.apple.Safari|ShowFavoritesBar-v2|true|false|false|writeResetValue|"
            "🎞️  Safari opens with all windows from last session|com.apple.Safari|AlwaysRestoreSessionAtLaunch|true|false|false|writeResetValue|"
            "🌐 New windows open with Empty Page|com.apple.Safari|NewWindowBehavior|1|4|4|writeResetValue|"
            "🌐 New tabs open with Empty Page|com.apple.Safari|NewTabBehavior|1|4|4|writeResetValue|"
            "🚫 Disable Auto-Opening of 'Safe' Downloads|com.apple.Safari|AutoOpenSafeDownloads|false|true|false|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🌐 [Safari - Tabs]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write)${NC}"
            "🗂️  Close Tabs Manually|com.apple.Safari|CloseTabsAutomatically|false|true|false|writeResetValue|${GY}(On by default)${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 26 ]]; then
            preference_commands+=(
                "🗂️  Show Color in Tab Bar ${BL}(Tahoe 26+)${NC}|com.apple.Safari|NeverUseBackgroundColorInToolbar|false|true|false|writeResetValue|${GY}(On by default)${NC}"
            )
        elif [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
            # grey out unsupported
            preference_commands+=(
                "🗂️  ${GY}Show Color in Tab Bar (Tahoe 26+)${NC}|com.apple.Safari|NeverUseBackgroundColorInToolbar|false|true|false|writeResetValue|${GY}(On by default)${NC}"
            )
        fi
        preference_commands+=(
            "🌐 Always show website titles in tabs|com.apple.Safari|EnableNarrowTabs|false|true|true|writeResetValue|"
            "🗂️  Command + Click opens a link in a new tab|com.apple.Safari|CommandClickMakesTabs|true|false|true|writeResetValue|${GY}(On by default)${NC}"
            "🚫 Don't make new tabs or windows active on command + click|com.apple.Safari|OpenNewTabsInFront|false|true|false|writeResetValue|"
        )
        if [[ "$MACOS_MAJOR" -eq 26 && "$MACOS_MINOR" -le 3 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🚫 ${GY}Disable compact tab layout (Sequoia 15 & below) or (Tahoe 26.4+)${NC}|com.apple.Safari|ShowStandaloneTabBar|true|false|true|writeResetValue|"
                )
            fi
        else
            # Sequoia ≤ 15 (supported) or Tahoe 26.4+ (supported)
            preference_commands+=(
                "🚫 Disable compact tab layout ${MA}(Sequoia 15 & below)${NC} or ${BL}(Tahoe 26.4+)${NC}|com.apple.Safari|ShowStandaloneTabBar|true|false|true|writeResetValue|"
            )
        fi
        preference_commands+=(
            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🌐 [Safari - AutoFill]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write)${NC}"
            "🚫 Disable AutoFill Contacts|com.apple.Safari|AutoFillFromAddressBook|false|true|true|writeResetValue|"
        )
        if [[ "$MACOS_MAJOR" -ge 26 && "$MACOS_MINOR" -ge 4 ]] || [[ "$MACOS_MAJOR" -ge 15 && "$MACOS_MINOR" -ge 7 && "$MACOS_PATCH" -ge 5 ]]; then
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🚫 Disable AutoFill User Names & Passwords ${MA}(Sequoia 15.7.5+${NC}/${BL}Tahoe 26.4+)${NC}|com.apple.Safari|AutoFillPasswordsInSafari|false|true|true|DisableSafariPasswordAutoFillInTahoe26_4|${GY}Disables AutoFill in Safari only. (As of Sequoia 15.7.5/Tahoe 26.4, AutoFill in other apps is now controlled via the AutoFill preference under '🔑 [Passwords & AutoFill] - or System Settings > General > AutoFill & Passwords > AutoFill Passwords and Passkeys)${NC}"
                    "🚫 ${GY}Disable AutoFill User Names & Passwords (Sequoia 15.7.4 & below/Tahoe 26.3 & below)${NC}|com.apple.Safari|AutoFillPasswords|false|true|true|DisableSafariPasswordAutoFillInTahoe26_3AndBelow|${GY}Disables AutoFill in Safari and other apps.${NC}"
                )
            else
                # hide unsupported
                preference_commands+=(
                    "🚫 Disable AutoFill User Names & Passwords ${MA}(Sequoia 15.7.5+${NC}/${BL}Tahoe 26.4+)${NC}|com.apple.Safari|AutoFillPasswordsInSafari|false|true|true|DisableSafariPasswordAutoFillInTahoe26_4|${GY}Disables AutoFill in Safari only. (As of Sequoia 15.7.5/Tahoe 26.4, AutoFill in other apps is now controlled via the AutoFill preference under '🔑 [Passwords & AutoFill] - or System Settings > General > AutoFill & Passwords > AutoFill Passwords and Passkeys)${NC}"
                    # "🚫 ${GY}Disable AutoFill User Names & Passwords (Sequoia 15.7.4 & below)/(Tahoe 26.3 & below)${NC}|com.apple.Safari|AutoFillPasswords|false|true|true|DisableSafariPasswordAutoFillInTahoe26_3AndBelow|${GY}Disables AutoFill in Safari and other apps.${NC}"
                )
            fi
        else
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🚫 ${GY}Disable AutoFill User Names & Passwords (Sequoia 15.7.5+/Tahoe 26.4+)${NC}|com.apple.Safari|AutoFillPasswordsInSafari|false|true|true|DisableSafariPasswordAutoFillInTahoe26_4|${GY}Disables AutoFill in Safari only. (As of Sequoia 15.7.5/Tahoe 26.4, AutoFill in other apps is now controlled via the AutoFill preference under '🔑 [Passwords & AutoFill] - or System Settings > General > AutoFill & Passwords > AutoFill Passwords and Passkeys)${NC}"
                    "🚫 Disable AutoFill User Names & Passwords ${MA}(Sequoia 15.7.4 & below${NC}/${BL}Tahoe 26.3 & below)${NC}|com.apple.Safari|AutoFillPasswords|false|true|true|DisableSafariPasswordAutoFillInTahoe26_3AndBelow|${GY}Disables AutoFill in Safari and other apps.${NC}"
                )
            else
                # hide unsupported
                preference_commands+=(
                    # "🚫 ${GY}Disable AutoFill User Names & Passwords (Sequoia 15.7.5+/Tahoe 26.4+)${NC}|com.apple.Safari|AutoFillPasswordsInSafari|false|true|true|DisableSafariPasswordAutoFillInTahoe26_4|${GY}Disables AutoFill in Safari only. (As of Sequoia 15.7.5/Tahoe 26.4, AutoFill in other apps is now controlled via the AutoFill preference under '🔑 [Passwords & AutoFill] - or System Settings > General > AutoFill & Passwords > AutoFill Passwords and Passkeys)${NC}"
                    "🚫 Disable AutoFill User Names & Passwords ${MA}(Sequoia 15.7.4 & below${NC}/${BL}Tahoe 26.3 & below)${NC}|com.apple.Safari|AutoFillPasswords|false|true|true|DisableSafariPasswordAutoFillInTahoe26_3AndBelow|${GY}Disables AutoFill in Safari and other apps.${NC}"
                )
            fi
        fi
        preference_commands+=(
            "🚫 Disable AutoFill Credit Cards|com.apple.Safari|AutoFillCreditCardData|false|true|true|writeResetValue|"
            "🚫 Disable AutoFill Other Forms|com.apple.Safari|AutoFillMiscellaneousForms|false|true|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🌐 [Safari - Search]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write)${NC}"
            "🔎 Use DuckDuckGo as default search provider in ALL Browsing|com.apple.Safari|SearchProviderShortName|DuckDuckGo|Google|Google|writeResetValue|"
            "🔎 Private Search Engine Uses Normal Search Engine|com.apple.Safari|PrivateSearchEngineUsesNormalSearchEngineToggle|true|false|true|writeResetValue|"
            "🚫 Disable Search Engine Suggestions|com.apple.Safari|SuppressSearchSuggestions|true|false|false|writeResetValue|"
            "🚫 Disable Safari Suggestions|com.apple.Safari|UniversalSearchEnabled|false|true|true|writeResetValue|"
            "🚫 Disable Previously Visited Website Suggestions|com.apple.Safari|WebsiteSpecificSearchEnabled|false|true|true|writeResetValue|"
            "🚫 Disable Preload Top Hit in the background|com.apple.Safari|PreloadTopHit|false|true|true|writeResetValue|"
            "🚫 Disable Favorites Suggestions|com.apple.Safari|ShowFavoritesUnderSmartSearchField|false|true|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🌐 [Safari - Security]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write)${NC}"
            "🔒 Enable Safe Browsing|com.apple.Safari.SafeBrowsing|SafeBrowsingEnabled|true|false|true|writeResetValue|${GY}(On by default)${NC}"
            "⚠️  Warn when visiting a fraudulent website|com.apple.Safari|WarnAboutFraudulentWebsites|true|false|true|writeResetValue|${GY}(On by default)${NC}"
            # "🌐 Enable JavaScript (1 of 2)|com.apple.Safari|WebKitJavaScriptEnabled|true|false|true|writeResetValue|${GY}(On by default)${NC}"
            # "🌐 Enable JavaScript (2 of 2)|com.apple.Safari|WebKitPreferences.javaScriptEnabled|true|false|true|writeResetValue|${GY}(On by default)${NC}"
        )
        if [[ "$MACOS_MAJOR" -ge 13 ]]; then
            preference_commands+=(
                "🌐 Warn before connecting to a website over HTTP ${YE}(macOS Ventura & above)${NC}|com.apple.Safari|UseHTTPSOnly|true|false|false|writeResetValue|"
            )
        else
            if [[ "$HideIncompatible_macOS_Preferences" == "false" ]]; then
                # grey out unsupported
                preference_commands+=(
                    "🌐 ${GY}Warn before connecting to a website over HTTP (macOS Ventura & above)${NC}|com.apple.Safari|UseHTTPSOnly|true|false|false|writeResetValue|"
                )
            fi
        fi
        preference_commands+=(
            # "🌐 Prevent cross-site tracking (1 of 3)|com.apple.Safari|BlockStoragePolicy|2|1|2|writeResetValue|${GY}(On by default)${NC}"
            # "🌐 Prevent cross-site tracking (2 of 3)|com.apple.Safari|WebKitPreferences.storageBlockingPolicy|true|false|true|writeResetValue|${GY}(On by default)${NC}"
            # "🌐 Prevent cross-site tracking (3 of 3)|com.apple.Safari|WebKitStorageBlockingPolicy|true|false|true|writeResetValue|${GY}(On by default)${NC}"
            "🕵️‍♂️  Require password to view locked tabs in Private Browsing|com.apple.Safari|PrivateBrowsingRequiresAuthentication|true|false|false|writeResetValue|"
            "🚫 Disallow Websites To Send Notifications|com.apple.Safari|CanPromptForPushNotifications|false|true|true|writeResetValue|"

            # Array Format
            # Header: "GROUP|Title|Subtext"
            # Prefs.: "Display Name|Domain|Key|Active Value|Inactive Value|Reset Value|Handler|Notes"
            "GROUP|🌐 [Safari - Advanced]|⚠️  ${YE}(Terminal requires Full Disk Access to read/write)${NC}"
            "🌐 Show full website URL in address bar|com.apple.Safari|ShowFullURLInSmartSearchField|true|false|false|writeResetValue|"
            "🕵️‍♂️  Use advanced tracking and fingerprinting protection in ALL browsing|com.apple.Safari|EnableEnhancedPrivacyInRegularBrowsing|true|false|false|writeResetValue|${GY}The default is set to Private Browsing only.${NC} ${YE}(Note that this setting is prone to verification issues for certain websites)${NC}"
            "🚫 Disallow privacy-preserving measurement of ad effectiveness|com.apple.Safari|WebKitPreferences.privateClickMeasurementEnabled|false|true|true|writeResetValue|"
            "🛠  Show features for web developers|com.apple.Safari.SandboxBroker|ShowDevelopMenu|true|false|false|writeResetValue|Enables Safari's Developer menu"
        )
    fi
    # Save original full array for filtering operations
    local original_preference_commands_full=("${preference_commands[@]}")

    # Helper function to get GROUP pattern for a category choice
    # Maps user choice (1-41) to category index (0-40) and returns GROUP title pattern
    get_group_pattern_for_category() {
        local user_choice=$1
        local category_index=$((user_choice - 1))
        
        case $category_index in
            0) echo "🆕 [NEW for ${BL}macOS Tahoe 26]${NC}" ;;
            1) echo "🖱️  [Mouse]" ;;
            2) echo "💻 [TrackPad]" ;;
            3) echo "⌨️  [Keyboard]" ;;
            4) echo "⌨️  [Keyboard Shortcuts]" ;;
            5) echo "💾 [Disks]" ;;
            6) echo "⚓️ [Dock]" ;;
            7) echo "⛶  [Hot Corners]" ;;
            8) echo "🖥️  [Desktop, Widgets & Views]" ;;
            9) echo "⚙️  [System & UI]" ;;
            10) echo "🪟 [Window Tiling]" ;;
            11) echo "🕹️  [Mission Control & Spaces]" ;;
            12) echo "✨ [Appearance]" ;;
            13) echo "🪄 [Animations]" ;;
            14) echo "📋 [Finder List View Options]" ;;
            15) echo "📁 [Finder Icon View Options]" ;;
            16) echo "📁 [Finder]" ;;
            17) echo "♿️ [Accessibility - Zoom]" ;;
            18) echo "📋 [Menu Bar]" ;;
            19) echo "📋 [Menu Bar - For Laptops]" ;;
            20) echo "📶 [Connectivity]" ;;
            21) echo "🔍 [Spotlight]" ;;
            22) echo "🔄 [Automatic Updates]" ;;
            23) echo "🤖 [Apple Intelligence]" ;;
            24) echo "🔑 [Passwords & AutoFill]" ;;
            25) echo "📝 [TextEdit]" ;;
            26) echo "👾 [Terminal]" ;;
            27) echo "📅 [Calendar]" ;;
            28) echo "💬 [Messages]" ;;
            29) echo "🔎 [Preview]" ;;
            30) echo "📞 [Phone]" ;;
            31) echo "🎵 [Music]" ;;
            32) echo "🗜️  [Archive Utility]" ;;
            33) echo "📸 [Screen Capture]" ;;
            34) echo "🎥 [QuickTime Player]" ;;
            35) echo "🌐 [Safari - General]" ;;
            36) echo "🌐 [Safari - Tabs]" ;;
            37) echo "🌐 [Safari - AutoFill]" ;;
            38) echo "🌐 [Safari - Search]" ;;
            39) echo "🌐 [Safari - Security]" ;;
            40) echo "🌐 [Safari - Advanced]" ;;
            *) echo "" ;;
        esac
    }
    # Helper function to filter preferences by category
    # Takes user choice (0-41) and returns filtered array
    filter_preferences_by_category() {
        local user_choice=$1
        local filtered_array=()
        local in_target_group=false
        local group_pattern=""
        local source_array=("${original_preference_commands_full[@]}")
        
        # If choice is 0, return all preferences (no filtering)
        if [[ $user_choice -eq 0 ]]; then
            # Return all preferences by copying the original full array
            filtered_array=("${source_array[@]}")
            printf '%s\n' "${filtered_array[@]}"
            return
        fi
        
        # Get the GROUP pattern for this category
        group_pattern=$(get_group_pattern_for_category "$user_choice")
        
        if [[ -z "$group_pattern" ]]; then
            # Invalid choice, return empty array
            return
        fi
        
        # Iterate through original full array to find matching group
        for pref in "${source_array[@]}"; do
            # Check if this is a GROUP marker
            if [[ "$pref" == GROUP\|* ]]; then
                IFS='|' read -r _ group_title _ <<< "$pref"
                # Check if this matches our target group
                if [[ "$group_title" == "$group_pattern" ]]; then
                    in_target_group=true
                    filtered_array+=("$pref")
                elif [[ "$in_target_group" == true ]]; then
                    # We've hit the next group, stop collecting
                    break
                fi
            elif [[ "$in_target_group" == true ]]; then
                # We're in the target group, add this preference
                filtered_array+=("$pref")
            fi
        done
        
        # Output the filtered array (one item per line for array assignment)
        printf '%s\n' "${filtered_array[@]}"
    }
    # Helper function to get current preference state
    get_preference_current_state() {
        local domain="$1"
        local key="$2"
        local handler="$3"
        local active_val="$4"
        local inactive_val="$5"

        case "$handler" in
            KeyboardShortcuts)
                # Generic handler for keyboard shortcuts - parse active_val to check state
                # active_val format: '{"Key1" = "value1"; "Key2" = "value2"}'
                
                local all_match=true
                local any_exist=false
                
                # Parse the dictionary string to extract expected key-value pairs
                local dict_content=$(echo "$active_val" | sed "s/^'{\"//" | sed "s/}'$//" | sed 's/"; "/";/g')
                
                # Split by semicolon and process each pair (bash 3.2 compatible)
                local pairs=$(echo "$dict_content" | sed 's/; */;/g')
                local IFS_SAVE="$IFS"
                IFS=';'
                for pair in $pairs; do
                    IFS="$IFS_SAVE"
                    if [[ -n "$pair" ]]; then
                        # Extract key and expected value: "Key" = "value"
                        local item_key=$(echo "$pair" | sed 's/^"//' | sed 's/" = .*$//')
                        local expected_value=$(echo "$pair" | sed 's/^[^=]*= "//' | sed 's/"$//')
                        
                        if [[ -n "$item_key" ]] && [[ -n "$expected_value" ]]; then
                            # Check if this key exists - use more precise pattern with word boundary
                            local full_line=$(defaults read "$domain" "$key" 2>/dev/null | grep -E "^[[:space:]]*(\")?${item_key}(\")?[[:space:]]*=" || echo "")

                            if [[ -n "$full_line" ]]; then
                                any_exist=true
                                # Extract the value from the matched line
                                local current_value=$(echo "$full_line" | sed 's/.*= "\(.*\)";/\1/')

                                # Normalize backslashes for comparison
                                local norm_current=$(echo "$current_value" | sed 's/\\\\/\\/g')
                                local norm_expected=$(echo "$expected_value" | sed 's/\\\\/\\/g')

                                # Normalize Unicode escape sequences to actual characters for specific domain
                                # macOS reads back Unicode escapes as actual characters, so we need to convert
                                # the expected value (which may contain \U####) to match what macOS returns
                                if [[ "$domain" == "com.mothersruin.SuspiciousPackageApp" ]]; then
                                    norm_expected=$(echo "$norm_expected" | sed 's/\\U005B/[/g' | sed 's/\\U005D/]/g')
                                fi
                                
                                if [[ "$norm_current" != "$norm_expected" ]]; then
                                    all_match=false
                                fi
                            else
                                all_match=false
                            fi
                            
                            # # Check if this key exists
                            # local current_value=$(defaults read "$domain" "$key" 2>/dev/null | grep "\"$item_key\"" | sed 's/.*= "\(.*\)";/\1/' || echo "")
                            # local key_exists=$(defaults read "$domain" "$key" 2>/dev/null | grep "\"$item_key\"" || echo "")
                            
                            # if [[ -n "$key_exists" ]]; then
                            #     any_exist=true
                            #     # Normalize backslashes for comparison
                            #     local norm_current=$(echo "$current_value" | sed 's/\\\\/\\/g')
                            #     local norm_expected=$(echo "$expected_value" | sed 's/\\\\/\\/g')
                                
                            #     if [[ "$norm_current" != "$norm_expected" ]]; then
                            #         all_match=false
                            #     fi
                            # else
                            #     all_match=false
                            # fi
                        fi
                    fi
                    IFS=';'
                done
                IFS="$IFS_SAVE"
                
                # Check results
                if [[ "$all_match" == "true" ]] && [[ "$any_exist" == "true" ]]; then
                    echo "active"
                    return
                elif [[ "$any_exist" == "true" ]]; then
                    echo "custom"
                    return
                else
                    echo "inactive"
                    return
                fi
                ;;
            Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click)
                # Handle trackpad tap to right click
                if  [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
                    [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick)" == "1" ]] &&
                    [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior)" == "1" ]] &&
                    [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.enableSecondaryClick)" == "1" ]] &&
                    [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
                    [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadRightClick)" == "1" ]]; then
                    echo "active"
                    return
                else
                    if  [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "0" ]] &&
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
                ;;
            ExpandTextEditSavePanels)
                # Handle ExpandTextEditSavePanels
                if  [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode)" == "1" ]] &&
                    [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode2)" == "1" ]]; then
                    echo "true"
                    return
                else
                    if  [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode)" == "0" ]] &&
                        [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode2)" == "0" ]]; then
                        echo "false"
                        return
                    else
                        echo "custom"
                        return
                    fi
                fi
                ;;
            Show_Time_Machine_Menu_Bar_Item)
                # Handle Time Machine menu bar item
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
                ;;
            Show_VPN_Menu_Bar_Item)
                # Handle VPN menu bar item
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
                ;;
            disable_Apple_Intelligence)
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
                ;;
            DisableSpotlightRelatedContent)
                if [[ "$MACOS_MAJOR" -ge 26 ]]; then
                    if defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null | grep -q "Custom.relatedContents"; then
                        echo "active"
                        return
                    else
                        echo "inactive"
                        return
                    fi
                else
                    echo "not set"
                    return
                fi
                ;;
            DisableMouseKeys)
                # Read both related settings
                local shortcut_val
                local ignore_val
                shortcut_val=$(defaults read com.apple.universalaccess useMouseKeysShortcutKeys 2>/dev/null || echo "")
                ignore_val=$(defaults read com.apple.universalaccess mouseDriverIgnoreTrackpad 2>/dev/null || echo "")

                # Normalize to lowercase strings
                shortcut_val=$(echo "$shortcut_val" | tr '[:upper:]' '[:lower:]')
                ignore_val=$(echo "$ignore_val" | tr '[:upper:]' '[:lower:]')

                # Map numeric/YES/NO representations to booleans
                if [[ "$shortcut_val" == "1" || "$shortcut_val" == "yes" ]]; then
                    shortcut_val="true"
                elif [[ "$shortcut_val" == "0" || "$shortcut_val" == "no" ]]; then
                    shortcut_val="false"
                fi

                if [[ "$ignore_val" == "1" || "$ignore_val" == "yes" ]]; then
                    ignore_val="true"
                elif [[ "$ignore_val" == "0" || "$ignore_val" == "no" ]]; then
                    ignore_val="false"
                fi

                # Both false  => preference is "active" (Mouse Keys disabled)
                # Both true   => preference is "inactive" (Mouse Keys enabled)
                # Mixed/other => "custom"
                if [[ "$shortcut_val" == "false" && "$ignore_val" == "false" ]]; then
                    echo "active"
                    return
                elif [[ "$shortcut_val" == "true" && "$ignore_val" == "true" ]]; then
                    echo "inactive"
                    return
                else
                    echo "custom"
                    return
                fi
                ;;
            ReduceSpotlightResultsInTahoe)
                local spotlight_prefs=$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null)
                
                # Check if ALL the expected disabled items are present (reduced state is active)
                if echo "$spotlight_prefs" | grep -q "com.apple.AppStore" && \
                echo "$spotlight_prefs" | grep -q "com.apple.iBooksX" && \
                echo "$spotlight_prefs" | grep -q "com.apple.calculator" && \
                echo "$spotlight_prefs" | grep -q "com.apple.iCal" && \
                echo "$spotlight_prefs" | grep -q "com.apple.AddressBook" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Dictionary" && \
                echo "$spotlight_prefs" | grep -q "com.apple.mail" && \
                echo "$spotlight_prefs" | grep -q "com.apple.MobileSMS" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Notes" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Photos" && \
                echo "$spotlight_prefs" | grep -q "com.apple.podcasts" && \
                echo "$spotlight_prefs" | grep -q "com.apple.reminders" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Safari" && \
                echo "$spotlight_prefs" | grep -q "com.apple.shortcuts" && \
                echo "$spotlight_prefs" | grep -q "com.apple.tips" && \
                echo "$spotlight_prefs" | grep -q "com.apple.VoiceMemos" && \
                echo "$spotlight_prefs" | grep -q "System.documents" && \
                echo "$spotlight_prefs" | grep -q "System.files" && \
                echo "$spotlight_prefs" | grep -q "System.folders" && \
                echo "$spotlight_prefs" | grep -q "System.iphoneApps" && \
                echo "$spotlight_prefs" | grep -q "System.menuItems"; then
                    
                    # Now verify that System Settings and Apps are NOT disabled (not in the array)
                    if ! echo "$spotlight_prefs" | grep -q "com.apple.systempreferences" && \
                    ! echo "$spotlight_prefs" | grep -q "System.applications"; then
                        echo "active"
                        return
                    else
                        echo "custom"
                        return
                    fi
                else
                    # Check if it's the fully inactive state (no app/system identifiers)
                    if ! echo "$spotlight_prefs" | grep -q "com.apple.AppStore" && \
                    ! echo "$spotlight_prefs" | grep -q "com.apple.iBooksX" && \
                    ! echo "$spotlight_prefs" | grep -q "System.files" && \
                    ! echo "$spotlight_prefs" | grep -q "System.folders"; then
                        echo "inactive"
                        return
                    else
                        echo "custom"
                        return
                    fi
                fi
                ;;
            ReduceSpotlightResultsInSequoia)
                local ordered_items=$(defaults read com.apple.Spotlight orderedItems 2>/dev/null)
                
                # If key doesn't exist, return default
                if [[ -z "$ordered_items" ]]; then
                    echo "default"
                    return
                fi
                
                # Check if APPLICATIONS and SYSTEM_PREFS are enabled, and all others are disabled
                # Use grep to find specific patterns in the output
                local apps_enabled=false
                local system_prefs_enabled=false
                local other_items_disabled=true
                
                # Helper function to check if an item is enabled
                # We'll look for the item name and check if enabled is 1/true in the same dictionary block
                check_item_enabled() {
                    local item_name="$1"
                    local context=$(echo "$ordered_items" | grep -A 10 -B 2 "$item_name" | head -15)
                    if echo "$context" | grep -qE "(enabled[[:space:]]*=[[:space:]]*(1|true|TRUE))"; then
                        return 0
                    fi
                    return 1
                }
                
                # Check APPLICATIONS
                if check_item_enabled "APPLICATIONS"; then
                    apps_enabled=true
                fi
                
                # Check SYSTEM_PREFS
                if check_item_enabled "SYSTEM_PREFS"; then
                    system_prefs_enabled=true
                fi
                
                # Check other items - they should all be disabled
                # List of items that should be disabled (excluding APPLICATIONS and SYSTEM_PREFS)
                local items_to_check=("MENU_EXPRESSION" "CONTACT" "MENU_CONVERSION" "MENU_DEFINITION" \
                                    "DOCUMENTS" "EVENT_TODO" "DIRECTORIES" "FONTS" "IMAGES" "MESSAGES" \
                                    "MOVIES" "MUSIC" "MENU_OTHER" "PDF" "PRESENTATIONS" \
                                    "MENU_SPOTLIGHT_SUGGESTIONS" "SPREADSHEETS" "TIPS" "BOOKMARKS" "SOURCE")
                
                for item in "${items_to_check[@]}"; do
                    if check_item_enabled "$item"; then
                        other_items_disabled=false
                        break
                    fi
                done
                
                # Check if state matches desired configuration
                if [[ "$apps_enabled" == true ]] && [[ "$system_prefs_enabled" == true ]] && [[ "$other_items_disabled" == true ]]; then
                    echo "active"
                    return
                else
                    # Check if it's the default state (all items enabled or key doesn't exist)
                    # If APPLICATIONS and SYSTEM_PREFS are enabled but we found other enabled items, it's custom
                    if [[ "$apps_enabled" == true ]] && [[ "$system_prefs_enabled" == true ]] && [[ "$other_items_disabled" == false ]]; then
                        echo "custom"
                        return
                    elif [[ "$apps_enabled" == false ]] || [[ "$system_prefs_enabled" == false ]]; then
                        # If APPLICATIONS or SYSTEM_PREFS are disabled, it's likely inactive/default
                        echo "inactive"
                        return
                    else
                        echo "custom"
                        return
                    fi
                fi
                ;;
            "DisableCertainShareExtensions")
                # Handle Share Extensions
                local extensions=(
                    # Items that exist on all macOS versions supported
                    "com.apple.share.System.add-to-safari-reading-list"
                    # "com.apple.CloudSharingUI.CopyLink"    # keep as is
                    "com.apple.Notes.SharingExtension"
                    "com.apple.share.System.add-to-iphoto"
                    "com.apple.news.openinnews"
                    "com.apple.reminders.sharingextension"
                    "com.apple.iBooksX.SharingExtension"
                    # "com.apple.CloudSharingUI.CreateiCloudLinkExtension"    # keep as is
                )
                # Version-specific additions
                # if [[ "$MACOS_MAJOR" -ge 12 ]]; then
                #     # Monterey+
                #     extensions+=(
                #         # "com.apple.shortcuts.Run-Workflow"    # Shortcuts app exists, not in Share menu until 13
                #     )
                # fi
                if [[ "$MACOS_MAJOR" -ge 13 ]]; then
                    # Ventura+
                    extensions+=(
                        "com.apple.shortcuts.Run-Workflow"    # Now appears in Share Menu
                        "com.apple.freeform.sharingextension"    # Freeform added
                    )
                fi
                if [[ "$MACOS_MAJOR" -ge 26 ]]; then
                    # Tahoe+
                    extensions+=(
                        "com.apple.journal.JournalShareExtension"    # Journal added
                    )
                fi

                local ignored_count=0
                local enabled_count=0
                local present_count=0

                for ext in "${extensions[@]}"; do
                    # -m -A  : all known plugins (ignored or not)
                    # -m     : only plugins that are currently active/enabled
                    local all_output
                    all_output=$(pluginkit -m -A -i "$ext" 2>/dev/null)

                    # Extension not installed on this system — skip it entirely
                    [[ -z "$all_output" ]] && continue

                    present_count=$((present_count + 1))

                    local active_output
                    active_output=$(pluginkit -m -i "$ext" 2>/dev/null)

                    if [[ -n "$active_output" ]]; then
                        enabled_count=$((enabled_count + 1))
                    else
                        ignored_count=$((ignored_count + 1))
                    fi
                done

                # ── Also account for the SharingPeopleSuggestions pref on macOS 13+ ──
                if [[ "$MACOS_MAJOR" -ge 13 ]]; then
                    present_count=$((present_count + 1))
                    local pref_val
                    pref_val=$(defaults read com.apple.Sharing SharingPeopleSuggestionsDisabled 2>/dev/null)
                    if [[ "$pref_val" == "1" ]]; then
                        ignored_count=$((ignored_count + 1))
                    else
                        # key missing (default) or explicitly 0 → suggestions are enabled
                        enabled_count=$((enabled_count + 1))
                    fi
                fi

                # ── Determine combined state ──
                if [[ $present_count -eq 0 ]]; then
                    echo "unknown"
                elif [[ $ignored_count -eq $present_count ]]; then
                    echo "active"      # all disabled  → feature is "on"
                elif [[ $enabled_count -eq $present_count ]]; then
                    echo "inactive"    # all enabled   → feature is "off"
                else
                    echo "custom"      # mixed
                fi
                ;;
            NewArchiveUtilityDictIn26_4)
                local result=$(defaults read $domain $key 2>/dev/null | awk '/Selection/ {print $3}' | tr -d '";')
                if [[ "$result" == "MoveToTrash" ]]; then
                    echo "active"
                elif [[ "$result" == "UseSameFolder" ]]; then
                    echo "inactive"
                else
                    echo "not set"
                fi
                return
                ;;
            ListViewColumns)
                # Handle ListViewColumns settings - check all locations
                local plist_file="$HOME/Library/Preferences/com.apple.finder.plist"
                local all_match=true
                local any_exist=false
                
                # Check all 3 base locations (each has 2 formats: ExtendedListViewSettingsV2 and ListViewSettings)
                local locations=(
                    ":ICloudViewSettings"
                    ":StandardViewSettings"
                    ":FK_StandardViewSettings"
                )
                
                for location in "${locations[@]}"; do
                    if check_list_view_columns_state "$plist_file" "$location"; then
                        any_exist=true
                    else
                        # Check if columns exist at all (even if not matching)
                        local array_exists=$(/usr/libexec/PlistBuddy -c "Print ${location}:ExtendedListViewSettingsV2:columns" "$plist_file" 2>/dev/null | head -1)
                        if [[ -n "$array_exists" ]] && [[ "$array_exists" != *"Doesn't Exist"* ]]; then
                            any_exist=true
                            all_match=false
                        else
                            all_match=false
                        fi
                    fi
                done
                
                if [[ "$all_match" == "true" ]] && [[ "$any_exist" == "true" ]]; then
                    echo "active"
                    return
                elif [[ "$any_exist" == "true" ]]; then
                    echo "custom"
                    return
                else
                    echo "default"
                    return
                fi
                ;;
            ListView_calculateAllSizes)
                # Handle ListView settings - read all relevant paths using PlistBuddy
                local plist_file="$domain"
                local plist_paths=(
                    ":ICloudViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":ICloudViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_iCloudListViewSettingsV2:calculateAllSizes"
                    ":StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":StandardViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_DefaultListViewSettingsV2:calculateAllSizes"
                    ":FK_StandardViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":TrashViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":TrashViewSettings:ListViewSettings:calculateAllSizes"
                )
                
                local total=${#plist_paths[@]}
                local active_count=0
                local inactive_count=0
                local missing_count=0
                local custom_count=0
                
                # Normalize reference values once
                local norm_active=$(echo "$active_val" | tr '[:upper:]' '[:lower:]')
                local norm_inactive=$(echo "$inactive_val" | tr '[:upper:]' '[:lower:]')
                if [[ "$norm_active" == "1" || "$norm_active" == "yes" ]]; then
                    norm_active="true"
                elif [[ "$norm_active" == "0" || "$norm_active" == "no" ]]; then
                    norm_active="false"
                fi
                if [[ "$norm_inactive" == "1" || "$norm_inactive" == "yes" ]]; then
                    norm_inactive="true"
                elif [[ "$norm_inactive" == "0" || "$norm_inactive" == "no" ]]; then
                    norm_inactive="false"
                fi
                
                for plist_path in "${plist_paths[@]}"; do
                    local plist_output
                    plist_output=$(/usr/libexec/PlistBuddy -c "Print $plist_path" "$plist_file" 2>&1)
                    local plist_exit=$?
                    
                    if [[ $plist_exit -ne 0 ]] || [[ -z "$plist_output" ]] || [[ "$plist_output" == *"Doesn't Exist"* ]] || [[ "$plist_output" == *"Will Create"* ]]; then
                        missing_count=$((missing_count + 1))
                        continue
                    fi
                    
                    local norm_current=$(echo "$plist_output" | tr '[:upper:]' '[:lower:]')
                    if [[ "$norm_current" == "1" || "$norm_current" == "yes" ]]; then
                        norm_current="true"
                    elif [[ "$norm_current" == "0" || "$norm_current" == "no" ]]; then
                        norm_current="false"
                    fi
                    
                    if [[ "$norm_current" == "$norm_active" ]]; then
                        active_count=$((active_count + 1))
                    elif [[ "$norm_current" == "$norm_inactive" ]]; then
                        inactive_count=$((inactive_count + 1))
                    else
                        custom_count=$((custom_count + 1))
                    fi
                done
                
                if [[ $missing_count -eq $total ]]; then
                    echo "default"
                    return
                fi
                
                if [[ $active_count -eq $total ]]; then
                    echo "active"
                    return
                fi
                
                if [[ $inactive_count -eq $total ]] && [[ $missing_count -eq 0 ]]; then
                    echo "inactive"
                    return
                fi
                
                echo "custom"
                return
                ;;
            IconView_variousSettings)
                # Handle IconView settings - read from plist using PlistBuddy
                # Determine which setting is being requested from the key suffix
                local target_path="$key"
                local setting_name="${target_path##*:}"
                local plist_file="$domain"
                
                # Map setting name to all relevant plist paths (Finder, Save dialogs, iCloud)
                local plist_paths=()
                case "$setting_name" in
                    showItemInfo)
                        plist_paths=(
                            ":StandardViewSettings:IconViewSettings:showItemInfo"
                            ":FK_StandardViewSettings:IconViewSettings:showItemInfo"
                            ":ICloudViewSettings:IconViewSettings:showItemInfo"
                        )
                        ;;
                    labelOnBottom)
                        plist_paths=(
                            ":StandardViewSettings:IconViewSettings:labelOnBottom"
                            ":FK_StandardViewSettings:IconViewSettings:labelOnBottom"
                            ":ICloudViewSettings:IconViewSettings:labelOnBottom"
                        )
                        ;;
                    arrangeBy)
                        plist_paths=(
                            ":StandardViewSettings:IconViewSettings:arrangeBy"
                            ":FK_StandardViewSettings:IconViewSettings:arrangeBy"
                            ":ICloudViewSettings:IconViewSettings:arrangeBy"
                        )
                        ;;
                    textSize)
                        plist_paths=(
                            ":StandardViewSettings:IconViewSettings:textSize"
                            ":FK_StandardViewSettings:IconViewSettings:textSize"
                            ":ICloudViewSettings:IconViewSettings:textSize"
                        )
                        ;;
                    iconSize)
                        plist_paths=(
                            ":StandardViewSettings:IconViewSettings:iconSize"
                            ":FK_StandardViewSettings:IconViewSettings:iconSize"
                            ":ICloudViewSettings:IconViewSettings:iconSize"
                        )
                        ;;
                    gridSpacing)
                        plist_paths=(
                            ":StandardViewSettings:IconViewSettings:gridSpacing"
                            ":FK_StandardViewSettings:IconViewSettings:gridSpacing"
                            ":ICloudViewSettings:IconViewSettings:gridSpacing"
                        )
                        ;;
                    *)
                        echo "unknown"
                        return
                        ;;
                esac
                
                local total=${#plist_paths[@]}
                local active_count=0
                local inactive_count=0
                local missing_count=0
                local custom_count=0
                
                # Normalize reference values once
                local norm_active=$(echo "$active_val" | tr '[:upper:]' '[:lower:]')
                local norm_inactive=$(echo "$inactive_val" | tr '[:upper:]' '[:lower:]')
                if [[ "$norm_active" == "1" || "$norm_active" == "yes" ]]; then
                    norm_active="true"
                elif [[ "$norm_active" == "0" || "$norm_active" == "no" ]]; then
                    norm_active="false"
                fi
                if [[ "$norm_inactive" == "1" || "$norm_inactive" == "yes" ]]; then
                    norm_inactive="true"
                elif [[ "$norm_inactive" == "0" || "$norm_inactive" == "no" ]]; then
                    norm_inactive="false"
                fi
                
                for plist_path in "${plist_paths[@]}"; do
                    local plist_output
                    plist_output=$(/usr/libexec/PlistBuddy -c "Print $plist_path" "$plist_file" 2>&1)
                    local plist_exit=$?
                    
                    if [[ $plist_exit -ne 0 ]] || [[ -z "$plist_output" ]] || [[ "$plist_output" == *"Doesn't Exist"* ]] || [[ "$plist_output" == *"Will Create"* ]]; then
                        missing_count=$((missing_count + 1))
                        continue
                    fi
                    
                    local norm_current=$(echo "$plist_output" | tr '[:upper:]' '[:lower:]')
                    if [[ "$norm_current" == "1" || "$norm_current" == "yes" ]]; then
                        norm_current="true"
                    elif [[ "$norm_current" == "0" || "$norm_current" == "no" ]]; then
                        norm_current="false"
                    fi
                    
                    if [[ "$norm_current" == "$norm_active" ]]; then
                        active_count=$((active_count + 1))
                    elif [[ "$norm_current" == "$norm_inactive" ]]; then
                        inactive_count=$((inactive_count + 1))
                    else
                        custom_count=$((custom_count + 1))
                    fi
                done
                
                if [[ $missing_count -eq $total ]]; then
                    echo "default"
                    return
                fi
                
                if [[ $active_count -eq $total ]]; then
                    echo "active"
                    return
                fi
                
                if [[ $inactive_count -eq $total ]] && [[ $missing_count -eq 0 ]]; then
                    echo "inactive"
                    return
                fi
                
                echo "custom"
                return
                ;;
            Desktop_IconView_showItemInfo|Desktop_IconView_labelOnBottom|Desktop_IconView_arrangeBy|Desktop_IconView_textSize|Desktop_IconView_iconSize|Desktop_IconView_gridSpacing)
                # Handle Desktop IconView settings - read from plist using PlistBuddy
                # Extract the PlistBuddy path from key (format: :DesktopViewSettings:IconViewSettings:showItemInfo)
                local plist_path="$key"
                # Read value and capture both stdout and exit code
                local plist_output=$(/usr/libexec/PlistBuddy -c "Print $plist_path" "$domain" 2>&1)
                local plist_exit=$?
                local current_val=""
                
                # Check if command succeeded and output is valid
                if [[ $plist_exit -eq 0 ]] && [[ -n "$plist_output" ]] && [[ "$plist_output" != *"Doesn't Exist"* ]] && [[ "$plist_output" != *"Will Create"* ]]; then
                    current_val="$plist_output"
                else
                    # Key doesn't exist or error occurred
                    current_val=""
                fi
                
                if [[ -z "$current_val" ]]; then
                    echo "default"
                    return
                fi
                
                # Values are now stored directly (no extraction needed)
                local active_val_extracted="$active_val"
                local inactive_val_extracted="$inactive_val"
                
                # Normalize values for comparison
                # Handle boolean values (true/false/1/0/YES/NO) and numeric values
                local norm_current=$(echo "$current_val" | tr '[:upper:]' '[:lower:]')
                local norm_active=$(echo "$active_val_extracted" | tr '[:upper:]' '[:lower:]')
                local norm_inactive=$(echo "$inactive_val_extracted" | tr '[:upper:]' '[:lower:]')
                
                # Check if this is a numeric setting (textSize, iconSize, gridSpacing)
                local is_numeric=false
                if [[ "$handler" == "Desktop_IconView_textSize" || "$handler" == "Desktop_IconView_iconSize" || "$handler" == "Desktop_IconView_gridSpacing" ]]; then
                    is_numeric=true
                fi
                
                # Normalize boolean representations (only for boolean/string settings)
                if [[ "$is_numeric" == "false" ]]; then
                    if [[ "$norm_current" == "1" || "$norm_current" == "yes" ]]; then
                        norm_current="true"
                    elif [[ "$norm_current" == "0" || "$norm_current" == "no" ]]; then
                        norm_current="false"
                    fi
                    if [[ "$norm_active" == "1" || "$norm_active" == "yes" ]]; then
                        norm_active="true"
                    elif [[ "$norm_active" == "0" || "$norm_active" == "no" ]]; then
                        norm_active="false"
                    fi
                    if [[ "$norm_inactive" == "1" || "$norm_inactive" == "yes" ]]; then
                        norm_inactive="false"
                    elif [[ "$norm_inactive" == "0" || "$norm_inactive" == "no" ]]; then
                        norm_inactive="false"
                    fi
                fi
                
                # Compare values
                if [[ "$norm_current" == "$norm_active" ]]; then
                    echo "active"
                    return
                elif [[ "$norm_current" == "$norm_inactive" ]]; then
                    echo "inactive"
                    return
                else
                    echo "custom"
                    return
                fi
                ;;
            key_equivalents|defaults_dict|defaults_array|plistbuddy)
                # Complex payload types: treat as custom to avoid brittle deep comparisons
                echo "custom"
                return
                ;;
            UseBrightBoldInTerminal)
                # if [[ "$handler" == "UseBrightBoldInTerminal" ]]; then
                #     # Check a specific Window Setting 
                #     # value=$(/usr/libexec/PlistBuddy -c "Print :'Window Settings':Basic:UseBrightBold" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null)
                    
                #     # Check if used for ANY Window Setting
                #     value=$(defaults read com.apple.Terminal | grep -q "UseBrightBold = 1" && echo "true" || echo "false")
                    
                #     if [[ "$value" == "false" ]]; then
                #         echo "inactive"
                #     elif [[ "$value" == "true" ]] ; then
                #         echo "active"
                #     else
                #         echo "default"
                #     fi
                #     return
                # fi
                
                default_profile=$(defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null)
                startup_profile=$(defaults read com.apple.Terminal "Startup Window Settings" 2>/dev/null)

                for profile in "$default_profile" "$startup_profile"; do
                    [[ -z "$profile" ]] && continue
                    value=$(/usr/libexec/PlistBuddy -c "Print :'Window Settings':'$profile':UseBrightBold" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null)
                    case "$value" in
                        true)  echo "active";  return ;;
                        false) echo "inactive"; return ;;
                    esac
                done
                echo "default"
                return
                ;;
            sudo)
                echo "unknown"
                return
                ;;
            chflags)
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
                ;;
            launchctl)
                echo "unknown"
                return
                ;;
        esac

        # Handle special cases that return large amounts of data
        if [[ "$domain" == "com.apple.dock" && "$key" == "persistent-apps" ]]; then
            # Count the number of apps currently in the Dock (excluding Finder)
            local app_count=$(defaults read "$domain" "$key" 2>/dev/null \
                | grep "file-label" 2>/dev/null \
                | wc -l 2>/dev/null \
                | xargs || echo "0")

            app_count=${app_count:-0}    # Ensure it's not empty
            local total_app_count=$((app_count + 1))    # Add 1 for the Finder Dock icon

            # Output updated count including Finder
            if [[ "$total_app_count" -gt 1 ]]; then
                # echo "$total_app_count app(s) currently in Dock"
                echo "inactive"
            else
                # echo "All apps removed (except for Finder)"
                echo "active"
            fi
            return
        fi

        if [[ "$handler" == "-currentHost" ]]; then
            local current_value=$(defaults -currentHost read "$domain" "$key" 2>/dev/null || echo "not set")
            if [[ -z "$current_value" ]]; then
                echo "default"
                return
            fi
        else
            local current_value=$(defaults read "$domain" "$key" 2>/dev/null || echo "")
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
        local handler="$3"
        
        case "$handler" in
            KeyboardShortcuts)
                # Generic handler for keyboard shortcuts - display current values
                # Parse active_val to know which keys to look for
                
                local value_parts=()
                
                # Parse the dictionary string to extract expected keys
                local dict_content=$(echo "$active_val" | sed "s/^'{\"//" | sed "s/}'$//" | sed 's/"; "/";/g')
                
                # Split by semicolon and process each pair (bash 3.2 compatible)
                local pairs=$(echo "$dict_content" | sed 's/; */;/g')
                local IFS_SAVE="$IFS"
                IFS=';'
                for pair in $pairs; do
                    IFS="$IFS_SAVE"
                    if [[ -n "$pair" ]]; then
                        # Extract key: "Key" = "value"
                        local item_key=$(echo "$pair" | sed 's/^"//' | sed 's/" = .*$//')
                        
                        if [[ -n "$item_key" ]]; then
                            # Use more precise pattern to match the exact key
                            local full_line=$(defaults read "$domain" "$key" 2>/dev/null | grep -E "^[[:space:]]*(\")?${item_key}(\")?[[:space:]]*=" || echo "")
                            
                            if [[ -n "$full_line" ]]; then
                                # Extract the value from the matched line
                                local current_value=$(echo "$full_line" | sed 's/.*= "\(.*\)";/\1/')
                                
                                if [[ -n "$current_value" ]]; then
                                    value_parts+=("\"$item_key\" = \"$current_value\"")
                                else
                                    value_parts+=("\"$item_key\" (exists)")
                                fi
                            fi
                        fi
                        
                        #     local current_value=$(defaults read "$domain" "$key" 2>/dev/null | grep "\"$item_key\"" | sed 's/.*= "\(.*\)";/\1/' || echo "")
                        #     local key_exists=$(defaults read "$domain" "$key" 2>/dev/null | grep "\"$item_key\"" || echo "")
                            
                        #     if [[ -n "$key_exists" ]]; then
                        #         if [[ -n "$current_value" ]]; then
                        #             value_parts+=("\"$item_key\" = \"$current_value\"")
                        #         else
                        #             value_parts+=("\"$item_key\" (exists)")
                        #         fi
                        #     fi
                        # fi
                    fi
                    IFS=';'
                done
                IFS="$IFS_SAVE"
                
                if [[ ${#value_parts[@]} -eq 0 ]]; then
                    echo "Not set"
                else
                    # Join with " & " separator
                    local IFS=" & "
                    echo "${value_parts[*]}"
                fi
                return
                ;;
            Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click)
                # Handle trackpad tap to right click
                if  [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
                    [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick)" == "1" ]] &&
                    [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior)" == "1" ]] &&
                    [[ "$(defaults -currentHost read NSGlobalDomain com.apple.trackpad.enableSecondaryClick)" == "1" ]] &&
                    [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick)" == "2" ]] &&
                    [[ "$(defaults read com.apple.AppleMultitouchTrackpad TrackpadRightClick)" == "1" ]]; then
                    echo "true"
                    return
                else
                    if  [[ "$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick)" == "0" ]] &&
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
                ;;
            ExpandTextEditSavePanels)
                # Handle ExpandTextEditSavePanels
                if  [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode)" == "1" ]] &&
                    [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode2)" == "1" ]]; then
                    echo "true"
                    return
                else
                    if  [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode)" == "0" ]] &&
                        [[ "$(defaults read com.apple.TextEdit NSNavPanelExpandedStateForSaveMode2)" == "0" ]]; then
                        echo "false"
                        return
                    else
                        echo "custom"
                        return
                    fi
                fi
                ;;
            Show_Time_Machine_Menu_Bar_Item)
                # Handle Time Machine menu bar item
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
                ;;
            Show_VPN_Menu_Bar_Item)
                # Handle VPN menu bar item
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
                ;;
            disable_Apple_Intelligence)
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
                ;;
            DisableSpotlightRelatedContent)
                if [[ "$MACOS_MAJOR" -ge 26 ]]; then
                    # Get the raw output
                    local value=$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null)

                    # Check if it contains "Custom.relatedContents"
                    if echo "$value" | grep -q "Custom.relatedContents"; then
                        echo "true"
                        return
                    else
                        echo "false" 
                        return
                    fi
                else
                    echo "N/A" 
                    return
                fi
                ;;
            DisableMouseKeys)
                # Read both related settings
                local shortcut_val
                local ignore_val
                shortcut_val=$(defaults read com.apple.universalaccess useMouseKeysShortcutKeys 2>/dev/null || echo "")
                ignore_val=$(defaults read com.apple.universalaccess mouseDriverIgnoreTrackpad 2>/dev/null || echo "")

                # Normalize to lowercase strings
                shortcut_val=$(echo "$shortcut_val" | tr '[:upper:]' '[:lower:]')
                ignore_val=$(echo "$ignore_val" | tr '[:upper:]' '[:lower:]')

                # Map numeric/YES/NO representations to booleans
                if [[ "$shortcut_val" == "1" || "$shortcut_val" == "yes" ]]; then
                    shortcut_val="true"
                elif [[ "$shortcut_val" == "0" || "$shortcut_val" == "no" ]]; then
                    shortcut_val="false"
                fi

                if [[ "$ignore_val" == "1" || "$ignore_val" == "yes" ]]; then
                    ignore_val="true"
                elif [[ "$ignore_val" == "0" || "$ignore_val" == "no" ]]; then
                    ignore_val="false"
                fi

                # Both false  => preference is "active" (Mouse Keys disabled)
                # Both true   => preference is "inactive" (Mouse Keys enabled)
                # Mixed/other => "custom"
                if [[ "$shortcut_val" == "false" && "$ignore_val" == "false" ]]; then
                    echo "true"
                    return
                elif [[ "$shortcut_val" == "true" && "$ignore_val" == "true" ]]; then
                    echo "false"
                    return
                else
                    echo "custom"
                    return
                fi
                ;;
            ReduceSpotlightResultsInTahoe)
                local spotlight_prefs=$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null)
                
                # Check if ALL the expected disabled items are present
                if echo "$spotlight_prefs" | grep -q "com.apple.AppStore" && \
                echo "$spotlight_prefs" | grep -q "com.apple.iBooksX" && \
                echo "$spotlight_prefs" | grep -q "com.apple.calculator" && \
                echo "$spotlight_prefs" | grep -q "com.apple.iCal" && \
                echo "$spotlight_prefs" | grep -q "com.apple.AddressBook" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Dictionary" && \
                echo "$spotlight_prefs" | grep -q "com.apple.mail" && \
                echo "$spotlight_prefs" | grep -q "com.apple.MobileSMS" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Notes" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Photos" && \
                echo "$spotlight_prefs" | grep -q "com.apple.podcasts" && \
                echo "$spotlight_prefs" | grep -q "com.apple.reminders" && \
                echo "$spotlight_prefs" | grep -q "com.apple.Safari" && \
                echo "$spotlight_prefs" | grep -q "com.apple.shortcuts" && \
                echo "$spotlight_prefs" | grep -q "com.apple.tips" && \
                echo "$spotlight_prefs" | grep -q "com.apple.VoiceMemos" && \
                echo "$spotlight_prefs" | grep -q "System.documents" && \
                echo "$spotlight_prefs" | grep -q "System.files" && \
                echo "$spotlight_prefs" | grep -q "System.folders" && \
                echo "$spotlight_prefs" | grep -q "System.iphoneApps" && \
                echo "$spotlight_prefs" | grep -q "System.menuItems"; then
                    
                    # Now verify that System Settings and Apps are NOT disabled (not in the array)
                    if ! echo "$spotlight_prefs" | grep -q "com.apple.systempreferences" && \
                    ! echo "$spotlight_prefs" | grep -q "System.applications"; then
                        echo "true"
                        return
                    else
                        echo "custom"
                        return
                    fi
                else
                    # Check if it's the fully inactive state (no app/system identifiers except maybe Custom.relatedContents)
                    if ! echo "$spotlight_prefs" | grep -q "com.apple.AppStore" && \
                    ! echo "$spotlight_prefs" | grep -q "com.apple.iBooksX" && \
                    ! echo "$spotlight_prefs" | grep -q "System.files"; then
                        echo "false"
                        return
                    else
                        echo "custom"
                        return
                    fi
                fi
                ;;
            ReduceSpotlightResultsInSequoia)
                local ordered_items=$(defaults read com.apple.Spotlight orderedItems 2>/dev/null)
                
                # If key doesn't exist, return false (inactive/default)
                if [[ -z "$ordered_items" ]]; then
                    echo "false"
                    return
                fi
                
                # Check if APPLICATIONS and SYSTEM_PREFS are enabled, and all others are disabled
                local apps_enabled=false
                local system_prefs_enabled=false
                local other_items_disabled=true
                
                # Helper function to check if an item is enabled
                check_item_enabled() {
                    local item_name="$1"
                    local context=$(echo "$ordered_items" | grep -A 10 -B 2 "$item_name" | head -15)
                    if echo "$context" | grep -qE "(enabled[[:space:]]*=[[:space:]]*(1|true|TRUE))"; then
                        return 0
                    fi
                    return 1
                }
                
                # Check APPLICATIONS
                if check_item_enabled "APPLICATIONS"; then
                    apps_enabled=true
                fi
                
                # Check SYSTEM_PREFS
                if check_item_enabled "SYSTEM_PREFS"; then
                    system_prefs_enabled=true
                fi
                
                # Check other items - they should all be disabled
                local items_to_check=("MENU_EXPRESSION" "CONTACT" "MENU_CONVERSION" "MENU_DEFINITION" \
                                    "DOCUMENTS" "EVENT_TODO" "DIRECTORIES" "FONTS" "IMAGES" "MESSAGES" \
                                    "MOVIES" "MUSIC" "MENU_OTHER" "PDF" "PRESENTATIONS" \
                                    "MENU_SPOTLIGHT_SUGGESTIONS" "SPREADSHEETS" "TIPS" "BOOKMARKS" "SOURCE")
                
                for item in "${items_to_check[@]}"; do
                    if check_item_enabled "$item"; then
                        other_items_disabled=false
                        break
                    fi
                done
                
                # Return value based on state
                if [[ "$apps_enabled" == true ]] && [[ "$system_prefs_enabled" == true ]] && [[ "$other_items_disabled" == true ]]; then
                    echo "true"
                    return
                else
                    echo "false"
                    return
                fi
                ;;
            NewArchiveUtilityDictIn26_4)
                local result=$(defaults read $domain $key 2>/dev/null | awk '/Selection/ {print $3}' | tr -d '";')
                if [[ "$result" == "MoveToTrash" ]]; then
                    echo "active"
                elif [[ "$result" == "UseSameFolder" ]]; then
                    echo "inactive"
                else
                    if [[ -n "$result" ]]; then
                        echo "$result"
                    else
                        echo "not set"
                    fi
                fi
                return
                ;;
            ListViewColumns)
                # Handle ListViewColumns settings - show summary of current column configurations
                local plist_file="$HOME/Library/Preferences/com.apple.finder.plist"
                local locations=(
                    "iCloud:ExtendedListViewSettingsV2|:ICloudViewSettings"
                    "iCloud:ListViewSettings|:ICloudViewSettings"
                    "Standard:ExtendedListViewSettingsV2|:StandardViewSettings"
                    "Standard:ListViewSettings|:StandardViewSettings"
                    "Save Panels:ExtendedListViewSettingsV2|:FK_StandardViewSettings"
                    "Save Panels:ListViewSettings|:FK_StandardViewSettings"
                )
                local summary=""
                local match_count=0
                local exist_count=0
                
                for location_info in "${locations[@]}"; do
                    IFS='|' read -r location_name location_path <<< "$location_info"
                    if check_list_view_columns_state "$plist_file" "$location_path"; then
                        summary="${summary}${location_name}: ✅ configured\n"
                        ((match_count++))
                        ((exist_count++))
                    else
                        local array_exists=$(/usr/libexec/PlistBuddy -c "Print ${location_path}:ExtendedListViewSettingsV2:columns" "$plist_file" 2>/dev/null | head -1)
                        if [[ -n "$array_exists" ]] && [[ "$array_exists" != *"Doesn't Exist"* ]]; then
                            summary="${summary}${location_name}: ⚠️  custom (not matching)\n"
                            ((exist_count++))
                        else
                            summary="${summary}${location_name}: ❌ default\n"
                        fi
                    fi
                done
                
                if [[ $match_count -eq 6 ]]; then
                    echo -e "All locations configured correctly:\n${summary}"
                elif [[ $exist_count -gt 0 ]]; then
                    echo -e "Some locations customized:\n${summary}"
                else
                    echo -e "All locations at default:\n${summary}"
                fi
                return
                ;;
            ListView_calculateAllSizes)
                # Handle ListView settings - read all relevant paths using PlistBuddy
                local plist_file="$domain"
                local locations=(
                    "     iCloud (Extended)  |:ICloudViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    "     iCloud (ListView)  |:ICloudViewSettings:ListViewSettings:calculateAllSizes"
                    "     iCloud (Dialogs)   |:FK_iCloudListViewSettingsV2:calculateAllSizes"
                    "     Finder (Extended)  |:StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    "     Finder (ListView)  |:StandardViewSettings:ListViewSettings:calculateAllSizes"
                    "     Finder (FKDefault) |:FK_DefaultListViewSettingsV2:calculateAllSizes"
                    "     Finder (FKStandard)|:FK_StandardViewSettings:ListViewSettings:calculateAllSizes"
                    "     Finder (FKStandard)|:FK_StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    "     Trash  (Extended)  |:TrashViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    "     Trash  (ListView)  |:TrashViewSettings:ListViewSettings:calculateAllSizes"
                )
                
                local summary=""
                local total=${#locations[@]}
                local active_count=0
                local inactive_count=0
                local missing_count=0
                
                for location_info in "${locations[@]}"; do
                    IFS='|' read -r location_name plist_path <<< "$location_info"
                    local plist_output
                    plist_output=$(/usr/libexec/PlistBuddy -c "Print $plist_path" "$plist_file" 2>&1)
                    local plist_exit=$?
                    
                    if [[ $plist_exit -ne 0 ]] || [[ -z "$plist_output" ]] || [[ "$plist_output" == *"Doesn't Exist"* ]] || [[ "$plist_output" == *"Will Create"* ]]; then
                        summary="${summary}${location_name}: ❌ default (not set)\n"
                        missing_count=$((missing_count + 1))
                        continue
                    fi
                    
                    local norm_current=$(echo "$plist_output" | tr '[:upper:]' '[:lower:]')
                    if [[ "$norm_current" == "1" || "$norm_current" == "yes" ]]; then
                        norm_current="true"
                    elif [[ "$norm_current" == "0" || "$norm_current" == "no" ]]; then
                        norm_current="false"
                    fi
                    
                    if [[ "$norm_current" == "true" ]]; then
                        summary="${summary}${location_name}: ✅ true\n"
                        active_count=$((active_count + 1))
                    elif [[ "$norm_current" == "false" ]]; then
                        summary="${summary}${location_name}: ❌ false\n"
                        inactive_count=$((inactive_count + 1))
                    else
                        summary="${summary}${location_name}: ⚠️  custom (${plist_output})\n"
                    fi
                done
                
                if [[ $active_count -eq $total ]]; then
                    echo -e "All locations set to true:\n${summary}"
                elif [[ $missing_count -eq $total ]]; then
                    echo -e "All locations at default:\n${summary}"
                else
                    echo -e "Current values:\n${summary}"
                fi
                return
                ;;
            IconView_variousSettings)
                # Handle IconView settings - read from plist using PlistBuddy
                local plist_file="$domain"
                local target_path="$key"
                local setting_name="${target_path##*:}"
                
                local locations=(
                    "          Finder Windows|:StandardViewSettings:IconViewSettings:${setting_name}"
                    "          Save Dialogs  |:FK_StandardViewSettings:IconViewSettings:${setting_name}"
                    "          iCloud Drive  |:ICloudViewSettings:IconViewSettings:${setting_name}"
                )
                
                # Normalize reference values (can be bool, string, or numeric)
                local norm_active=$(echo "$active_val" | tr '[:upper:]' '[:lower:]')
                local norm_inactive=$(echo "$inactive_val" | tr '[:upper:]' '[:lower:]')
                if [[ "$norm_active" == "1" || "$norm_active" == "yes" ]]; then
                    norm_active="true"
                elif [[ "$norm_active" == "0" || "$norm_active" == "no" ]]; then
                    norm_active="false"
                fi
                if [[ "$norm_inactive" == "1" || "$norm_inactive" == "yes" ]]; then
                    norm_inactive="true"
                elif [[ "$norm_inactive" == "0" || "$norm_inactive" == "no" ]]; then
                    norm_inactive="false"
                fi
                
                local summary=""
                local total=${#locations[@]}
                local active_count=0
                local inactive_count=0
                local missing_count=0
                
                for location_info in "${locations[@]}"; do
                    IFS='|' read -r location_name plist_path <<< "$location_info"
                    local plist_output
                    plist_output=$(/usr/libexec/PlistBuddy -c "Print $plist_path" "$plist_file" 2>&1)
                    local plist_exit=$?
                    
                    if [[ $plist_exit -ne 0 ]] || [[ -z "$plist_output" ]] || [[ "$plist_output" == *"Doesn't Exist"* ]] || [[ "$plist_output" == *"Will Create"* ]]; then
                        summary="${summary}${location_name}: ❌ default (not set)\n"
                        missing_count=$((missing_count + 1))
                        continue
                    fi
                    
                    local norm_current=$(echo "$plist_output" | tr '[:upper:]' '[:lower:]')
                    if [[ "$norm_current" == "1" || "$norm_current" == "yes" ]]; then
                        norm_current="true"
                    elif [[ "$norm_current" == "0" || "$norm_current" == "no" ]]; then
                        norm_current="false"
                    fi
                    
                    if [[ -n "$active_val" && "$norm_current" == "$norm_active" ]]; then
                        # Matches the defined "active" value
                        summary="${summary}${location_name}: ✅ active   (${plist_output})\n"
                        active_count=$((active_count + 1))
                    elif [[ -n "$inactive_val" && "$norm_current" == "$norm_inactive" ]]; then
                        # Matches the defined "inactive" value
                        summary="${summary}${location_name}: ❌ inactive (${plist_output})\n"
                        inactive_count=$((inactive_count + 1))
                    else
                        # Anything else is treated as custom
                        summary="${summary}${location_name}: ⚠️  custom   (${plist_output})\n"
                    fi
                done
                
                if [[ $missing_count -eq $total ]]; then
                    echo -e "All locations at default:\n${summary}"
                else
                    echo -e "Current values:\n${summary}"
                fi
                return
                ;;
            Desktop_IconView_showItemInfo|Desktop_IconView_labelOnBottom|Desktop_IconView_arrangeBy|Desktop_IconView_textSize|Desktop_IconView_iconSize|Desktop_IconView_gridSpacing)
                # Handle Desktop IconView settings - read from plist using PlistBuddy
                local plist_path="$key"
                # Read value and capture both stdout and exit code
                local plist_output=$(/usr/libexec/PlistBuddy -c "Print $plist_path" "$domain" 2>&1)
                local plist_exit=$?
                local current_val=""
                
                # Check if command succeeded and output is valid
                if [[ $plist_exit -eq 0 ]] && [[ -n "$plist_output" ]] && [[ "$plist_output" != *"Doesn't Exist"* ]] && [[ "$plist_output" != *"Will Create"* ]]; then
                    current_val="$plist_output"
                else
                    current_val="not set"
                fi
                echo "$current_val"
                return
                ;;
            key_equivalents|defaults_dict|defaults_array|plistbuddy)
                # Complex payload types: don't try to print giant dicts/arrays; indicate custom
                echo "custom"
                return
                ;;
            UseBrightBoldInTerminal)
                # # Check a specific Window Setting 
                # # value=$(/usr/libexec/PlistBuddy -c "Print :'Window Settings':Basic:UseBrightBold" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null)
                
                # # Check if used for ANY Window Setting
                # value=$(defaults read com.apple.Terminal | grep -q "UseBrightBold = 1" && echo "true" || echo "false")

                # if [[ "$value" == "false" ]]; then
                #     echo "false"
                # elif [[ "$value" == "true" ]] ; then
                #     echo "true"
                # else
                #     echo "not set"
                # fi
                # return
                
                default_profile=$(defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null)
                startup_profile=$(defaults read com.apple.Terminal "Startup Window Settings" 2>/dev/null)

                # Check active profiles only; prefer Default Window Settings
                for profile in "$default_profile" "$startup_profile"; do
                    [[ -z "$profile" ]] && continue
                    value=$(/usr/libexec/PlistBuddy -c "Print :'Window Settings':'$profile':UseBrightBold" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null)
                    case "$value" in
                        true)  echo "true";  return ;;
                        false) echo "false"; return ;;
                    esac
                done
                echo "not set"
                return
                ;;
            sudo)
                echo "sudo command - cannot read current value"
                return
                ;;
            chflags)
                if [[ "$key" == "ShowLibrary" ]]; then
                    # if [[ -d ~/Library ]] && [[ "$(ls -la ~/ | grep Library | grep hidden)" ]]; then
                    if [[ -d ~/Library ]] && [[ $(ls -lOd ~/Library 2>/dev/null | awk '{print $5}') == *"hidden"* ]]; then
                        echo "hidden"
                        return
                    else
                        echo "visible"
                        return
                    fi
                fi
                echo "unknown"
                return
                ;;
            launchctl)
                echo "launchctl command - cannot read current value"
                return
                ;;
        esac
        
        # Handle special cases that return large amounts of data
        if [[ "$domain" == "com.apple.dock" && "$key" == "persistent-apps" ]]; then
            # Count the number of apps currently in the Dock (excluding Finder)
            local app_count=$(defaults read "$domain" "$key" 2>/dev/null \
                | grep "file-label" 2>/dev/null \
                | wc -l 2>/dev/null \
                | xargs || echo "0")

            app_count=${app_count:-0}    # Ensure it's not empty
            local total_app_count=$((app_count + 1))    # Add 1 for the Finder Dock icon

            # Output updated count including Finder
            if [[ "$total_app_count" -gt 1 ]]; then
                echo "$total_app_count apps currently in Dock"
            else
                echo "All apps removed (except for Finder)"
            fi
            return
        fi
        
        if [[ "$handler" == "-currentHost" ]]; then
            local current_value=$(defaults -currentHost read "$domain" "$key" 2>/dev/null || echo "not set")
            # Limit output length for very long values
            if [[ ${#current_value} -gt 50 ]]; then
                echo "${current_value:0:47}..."
            else
                echo "$current_value"
            fi
            return
        else
            local current_value=$(defaults read "$domain" "$key" 2>/dev/null || echo "not set")
            # Limit output length for very long values
            if [[ ${#current_value} -gt 50 ]]; then
                echo "${current_value:0:47}..."
            else
                echo "$current_value"
            fi
        fi
    }
    # Helper: write defaults with correct handler based on value (bash 3.2 compatible)
    # This auto-detects the value type (bool, int, float, string) 
    write_defaults_typed() {
        local domain="$1"
        local key="$2"
        local value="$3"
        local handler="$4"

        # Determine if we need -currentHost flag
        local host_flag=""
        if [[ "$handler" == *"-currentHost"* ]]; then
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
    # only used to easily collapse all unused code below
    if true; then
        :
        # # Helper function to find column index by identifier in ExtendedListViewSettingsV2 array
        # find_column_index_by_identifier() {
        #     local plist_file="$1"
        #     local base_path="$2"
        #     local identifier="$3"
            
        #     # Try to find the column by checking each index (0-20 should be enough)
        #     local idx=0
        #     while [ $idx -lt 20 ]; do
        #         local found_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:${idx}:identifier" "$plist_file" 2>/dev/null)
        #         if [[ -z "$found_id" ]] || [[ "$found_id" == *"Doesn't Exist"* ]]; then
        #             break
        #         fi
        #         if [[ "$found_id" == "$identifier" ]]; then
        #             echo "$idx"
        #             return 0
        #         fi
        #         idx=$((idx + 1))
        #     done
        #     echo "-1"
        #     return 1
        # }
        # # Helper function to update or add a column in ExtendedListViewSettingsV2 array format
        # update_array_column() {
        #     local plist_file="$1"
        #     local base_path="$2"
        #     local identifier="$3"
        #     local ascending="$4"
        #     local width="$5"
        #     local visible="$6"
        #     local desired_index="$7"  # Desired position (0-5 for our 6 columns)
            
        #     # Find if column already exists
        #     local existing_idx=$(find_column_index_by_identifier "$plist_file" "$base_path" "$identifier")
            
        #     if [[ "$existing_idx" != "-1" ]]; then
        #         # Column exists, update it
        #         /usr/libexec/PlistBuddy -c "Set ${base_path}:ExtendedListViewSettingsV2:columns:${existing_idx}:ascending bool $ascending" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Set ${base_path}:ExtendedListViewSettingsV2:columns:${existing_idx}:width integer $width" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Set ${base_path}:ExtendedListViewSettingsV2:columns:${existing_idx}:visible bool $visible" "$plist_file" 2>/dev/null || true
        #     else
        #         # Column doesn't exist, need to add it
        #         # First, ensure the columns array exists
        #         local array_exists=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns" "$plist_file" 2>/dev/null | head -1)
        #         if [[ -z "$array_exists" ]] || [[ "$array_exists" == *"Doesn't Exist"* ]]; then
        #             /usr/libexec/PlistBuddy -c "Add ${base_path}:ExtendedListViewSettingsV2:columns array" "$plist_file" 2>/dev/null || true
        #         fi
                
        #         # Find the current array size
        #         local array_size=0
        #         while [ $array_size -lt 20 ]; do
        #             local test_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:${array_size}:identifier" "$plist_file" 2>/dev/null)
        #             if [[ -z "$test_id" ]] || [[ "$test_id" == *"Doesn't Exist"* ]]; then
        #                 break
        #             fi
        #             array_size=$((array_size + 1))
        #         done
                
        #         # Insert at desired_index, but if array is smaller, append
        #         local insert_idx=$desired_index
        #         if [[ $insert_idx -gt $array_size ]]; then
        #             insert_idx=$array_size
        #         fi
                
        #         # For now, just append to end (safer than inserting in middle)
        #         # PlistBuddy doesn't easily support inserting at specific index
        #         insert_idx=$array_size
                
        #         # Add the column dictionary
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ExtendedListViewSettingsV2:columns:${insert_idx}:identifier string $identifier" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ExtendedListViewSettingsV2:columns:${insert_idx}:ascending bool $ascending" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ExtendedListViewSettingsV2:columns:${insert_idx}:width integer $width" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ExtendedListViewSettingsV2:columns:${insert_idx}:visible bool $visible" "$plist_file" 2>/dev/null || true
        #     fi
        # }
        # # Helper function to update or add a column in ListViewSettings dictionary format
        # update_dict_column() {
        #     local plist_file="$1"
        #     local base_path="$2"
        #     local identifier="$3"
        #     local index="$4"
        #     local ascending="$5"
        #     local width="$6"
        #     local visible="$7"
            
        #     # Check if columns dict exists
        #     local dict_exists=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ListViewSettings:columns" "$plist_file" 2>/dev/null | head -1)
        #     if [[ -z "$dict_exists" ]] || [[ "$dict_exists" == *"Doesn't Exist"* ]]; then
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ListViewSettings:columns dict" "$plist_file" 2>/dev/null || true
        #     fi
            
        #     # Check if this column exists
        #     local col_exists=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ListViewSettings:columns:${identifier}:identifier" "$plist_file" 2>/dev/null)
            
        #     if [[ -n "$col_exists" ]] && [[ "$col_exists" != *"Doesn't Exist"* ]]; then
        #         # Column exists, update it
        #         /usr/libexec/PlistBuddy -c "Set ${base_path}:ListViewSettings:columns:${identifier}:index integer $index" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Set ${base_path}:ListViewSettings:columns:${identifier}:ascending bool $ascending" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Set ${base_path}:ListViewSettings:columns:${identifier}:width integer $width" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Set ${base_path}:ListViewSettings:columns:${identifier}:visible bool $visible" "$plist_file" 2>/dev/null || true
        #     else
        #         # Column doesn't exist, add it
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ListViewSettings:columns:${identifier}:identifier string $identifier" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ListViewSettings:columns:${identifier}:index integer $index" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ListViewSettings:columns:${identifier}:ascending bool $ascending" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ListViewSettings:columns:${identifier}:width integer $width" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Add ${base_path}:ListViewSettings:columns:${identifier}:visible bool $visible" "$plist_file" 2>/dev/null || true
        #     fi
        # }
        # # Helper function to set List View columns configuration
        # # Preserves existing columns and only updates the 6 target columns
        # set_list_view_columns() {
        #     local plist_file="$1"
        #     local base_path="$2"  # e.g., ":ICloudViewSettings" or ":StandardViewSettings"
        #     local action="$3"      # "set" or "delete"
            
        #     if [[ "$action" == "delete" ]]; then
        #         # Delete columns from both formats to restore defaults
        #         /usr/libexec/PlistBuddy -c "Delete ${base_path}:ExtendedListViewSettingsV2:columns" "$plist_file" 2>/dev/null || true
        #         /usr/libexec/PlistBuddy -c "Delete ${base_path}:ListViewSettings:columns" "$plist_file" 2>/dev/null || true
        #         return
        #     fi
            
        #     # Update ExtendedListViewSettingsV2:columns (array format)
        #     # name: index=0, ascending=true, width=456, visible=true
        #     update_array_column "$plist_file" "$base_path" "name" "true" "456" "true" "0"
            
        #     # dateAdded: index=1, ascending=false, width=75, visible=true
        #     update_array_column "$plist_file" "$base_path" "dateAdded" "false" "75" "true" "1"
            
        #     # dateModified: index=2, ascending=false, width=75, visible=true
        #     update_array_column "$plist_file" "$base_path" "dateModified" "false" "75" "true" "2"
            
        #     # size: index=3, ascending=false, width=75, visible=true
        #     update_array_column "$plist_file" "$base_path" "size" "false" "75" "true" "3"
            
        #     # version: index=4, ascending=true, width=75, visible=true
        #     update_array_column "$plist_file" "$base_path" "version" "true" "75" "true" "4"
            
        #     # kind: index=5, ascending=true, width=143, visible=true
        #     update_array_column "$plist_file" "$base_path" "kind" "true" "143" "true" "5"
            
        #     # Update ListViewSettings:columns (dictionary format)
        #     # name: index=0, ascending=true, width=456, visible=true
        #     update_dict_column "$plist_file" "$base_path" "name" "0" "true" "456" "true"
            
        #     # dateAdded: index=1, ascending=false, width=75, visible=true
        #     update_dict_column "$plist_file" "$base_path" "dateAdded" "1" "false" "75" "true"
            
        #     # dateModified: index=2, ascending=false, width=75, visible=true
        #     update_dict_column "$plist_file" "$base_path" "dateModified" "2" "false" "75" "true"
            
        #     # size: index=3, ascending=false, width=75, visible=true
        #     update_dict_column "$plist_file" "$base_path" "size" "3" "false" "75" "true"
            
        #     # version: index=4, ascending=true, width=75, visible=true
        #     update_dict_column "$plist_file" "$base_path" "version" "4" "true" "75" "true"
            
        #     # kind: index=5, ascending=true, width=143, visible=true
        #     update_dict_column "$plist_file" "$base_path" "kind" "5" "true" "143" "true"
        # }
        # # Helper function to check if List View columns match desired configuration
        # check_list_view_columns_state() {
        #     local plist_file="$1"
        #     local base_path="$2"  # e.g., ":ICloudViewSettings" or ":StandardViewSettings"
            
        #     # Check ExtendedListViewSettingsV2 format (array)
        #     local array_exists=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns" "$plist_file" 2>/dev/null | head -1)
        #     if [[ -z "$array_exists" ]] || [[ "$array_exists" == *"Doesn't Exist"* ]]; then
        #         return 1  # Columns don't exist
        #     fi
            
        #     # Check if we have at least 6 columns by trying to access index 5
        #     local test_column=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:5:identifier" "$plist_file" 2>/dev/null)
        #     if [[ -z "$test_column" ]] || [[ "$test_column" == *"Doesn't Exist"* ]]; then
        #         return 1  # Not enough columns (need at least 6, index 0-5)
        #     fi
            
        #     # Verify each column matches desired configuration
        #     # name: index=0, ascending=true, width=456, visible=true
        #     local name_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:0:identifier" "$plist_file" 2>/dev/null)
        #     local name_asc=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:0:ascending" "$plist_file" 2>/dev/null)
        #     local name_wid=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:0:width" "$plist_file" 2>/dev/null)
        #     local name_vis=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:0:visible" "$plist_file" 2>/dev/null)
        #     if [[ "$name_id" != "name" ]] || [[ "$name_asc" != "true" ]] || [[ "$name_wid" != "456" ]] || [[ "$name_vis" != "true" ]]; then
        #         return 1
        #     fi
            
        #     # dateAdded: index=1, ascending=false, width=75, visible=true
        #     local dateadd_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:1:identifier" "$plist_file" 2>/dev/null)
        #     local dateadd_asc=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:1:ascending" "$plist_file" 2>/dev/null)
        #     local dateadd_wid=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:1:width" "$plist_file" 2>/dev/null)
        #     local dateadd_vis=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:1:visible" "$plist_file" 2>/dev/null)
        #     if [[ "$dateadd_id" != "dateAdded" ]] || [[ "$dateadd_asc" != "false" ]] || [[ "$dateadd_wid" != "75" ]] || [[ "$dateadd_vis" != "true" ]]; then
        #         return 1
        #     fi
            
        #     # dateModified: index=2, ascending=false, width=75, visible=true
        #     local datemod_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:2:identifier" "$plist_file" 2>/dev/null)
        #     local datemod_asc=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:2:ascending" "$plist_file" 2>/dev/null)
        #     local datemod_wid=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:2:width" "$plist_file" 2>/dev/null)
        #     local datemod_vis=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:2:visible" "$plist_file" 2>/dev/null)
        #     if [[ "$datemod_id" != "dateModified" ]] || [[ "$datemod_asc" != "false" ]] || [[ "$datemod_wid" != "75" ]] || [[ "$datemod_vis" != "true" ]]; then
        #         return 1
        #     fi
            
        #     # size: index=3, ascending=false, width=75, visible=true
        #     local size_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:3:identifier" "$plist_file" 2>/dev/null)
        #     local size_asc=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:3:ascending" "$plist_file" 2>/dev/null)
        #     local size_wid=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:3:width" "$plist_file" 2>/dev/null)
        #     local size_vis=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:3:visible" "$plist_file" 2>/dev/null)
        #     if [[ "$size_id" != "size" ]] || [[ "$size_asc" != "false" ]] || [[ "$size_wid" != "75" ]] || [[ "$size_vis" != "true" ]]; then
        #         return 1
        #     fi
            
        #     # version: index=4, ascending=true, width=75, visible=true
        #     local version_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:4:identifier" "$plist_file" 2>/dev/null)
        #     local version_asc=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:4:ascending" "$plist_file" 2>/dev/null)
        #     local version_wid=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:4:width" "$plist_file" 2>/dev/null)
        #     local version_vis=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:4:visible" "$plist_file" 2>/dev/null)
        #     if [[ "$version_id" != "version" ]] || [[ "$version_asc" != "true" ]] || [[ "$version_wid" != "75" ]] || [[ "$version_vis" != "true" ]]; then
        #         return 1
        #     fi
            
        #     # kind: index=5, ascending=true, width=143, visible=true
        #     local kind_id=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:5:identifier" "$plist_file" 2>/dev/null)
        #     local kind_asc=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:5:ascending" "$plist_file" 2>/dev/null)
        #     local kind_wid=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:5:width" "$plist_file" 2>/dev/null)
        #     local kind_vis=$(/usr/libexec/PlistBuddy -c "Print ${base_path}:ExtendedListViewSettingsV2:columns:5:visible" "$plist_file" 2>/dev/null)
        #     if [[ "$kind_id" != "kind" ]] || [[ "$kind_asc" != "true" ]] || [[ "$kind_wid" != "143" ]] || [[ "$kind_vis" != "true" ]]; then
        #         return 1
        #     fi
            
        #     return 0  # All columns match
        # }
    fi
    # Helper function to apply preference change
    apply_preference_change() {
        local domain="$1"
        local key="$2"
        local value="$3"
        local handler="$4"
        local action="$5"
        
        echo
        case "$domain" in
            com.apple.Safari|com.apple.universalaccess|com.apple.archiveutility|com.apple.MobileSMS)
                if [[ "$full_disk_access" == "false" ]]; then
                    # exit early
                    echo "⚠️  ${BO}${YE}Warning: ${NC}Terminal does not have full disk access to write these prefs...${NC}"
                    echo "   Please return to the macOS Preferences main menu to grant Terminal permission."
                    read -r -t 4 -n 1
                    echo
                    return 1
                fi
            ;;
        esac
        # echo "${YE}Applying $action for $key...${NC}"
        echo "${YE}Applying changes...${NC}"  

        # Handles handler cases
        case "$handler" in
            "delete")
                # For delete handler, we need to handle active/inactive differently
                # Active/inactive should use defaults write, only reset should use defaults delete
                if [[ "$action" == "active" || "$action" == "inactive" ]]; then
                    # Use the provided value for active/inactive with proper typing
                    write_defaults_typed "$domain" "$key" "$value" "$handler"
                else
                    # Use delete for reset to default
                    defaults delete "$domain" "$key" 2>/dev/null || true
                fi
                read -r -t 1 -n 1
                ;;
            *"-currentHost"*)
                # Handle currentHost handlers - write with proper typing for active/inactive
                if [[ "$domain" == "com.apple.Spotlight" ]]; then
                    if [[ "$action" == "active" ]]; then
                        defaults -currentHost write com.apple.Spotlight MenuItemHidden -bool false 2>/dev/null || true
                        defaults write com.apple.Spotlight "NSStatusItem VisibleCC Item-0" -bool true 2>/dev/null || true
                    elif [[ "$action" == "inactive" ]]; then
                        defaults -currentHost write com.apple.Spotlight MenuItemHidden -bool true 2>/dev/null || true
                        defaults delete com.apple.Spotlight "NSStatusItem VisibleCC Item-0" 2>/dev/null || true
                    fi
                # elif [[ "$key" == "Siri" ]]; then
                #     if [[ "$action" == "active" ]]; then
                #         defaults -currentHost write com.apple.Siri StatusMenuVisible -bool true 2>/dev/null || true
                #     elif [[ "$action" == "inactive" ]]; then
                #         defaults -currentHost write com.apple.Siri StatusMenuVisible -bool false 2>/dev/null || true                        
                #     fi
                elif [[ "$domain" == "com.apple.universalcontrol" ]]; then
                    # Disable Universal Control
                    if [[ "$action" == "active" ]]; then
                        write_defaults_typed "$domain" "$key" "$value" "$handler"
                    elif [[ "$action" == "inactive" ]]; then
                        defaults -currentHost delete "$domain" "$key"
                    fi
                else
                    # Write the inactive value with -currentHost flag (write_defaults_typed handles the flag automatically)
                    write_defaults_typed "$domain" "$key" "$value" "$handler"
                fi
                ;;
            "KeyboardShortcuts")
                # Generic handler for keyboard shortcuts - works with any domain
                # active_val format: '{"Key1" = "value1"; "Key2" = "value2"}'
                # inactive_val format: delete "Key1" & "Key2"
                
                if [[ "$action" == "active" ]]; then
                    # Parse the dictionary string to extract key-value pairs
                    # Remove outer quotes and braces, then split by semicolon
                    local dict_content=$(echo "$value" | sed "s/^'{\"//" | sed "s/}'$//" | sed 's/"; "/";/g')
                    
                    # Split by semicolon and process each pair (bash 3.2 compatible)
                    local pairs=$(echo "$dict_content" | sed 's/; */;/g')
                    local IFS_SAVE="$IFS"
                    IFS=';'
                    for pair in $pairs; do
                        IFS="$IFS_SAVE"
                        if [[ -n "$pair" ]]; then
                            # Extract key and value: "Key" = "value"
                            local item_key=$(echo "$pair" | sed 's/^"//' | sed 's/" = .*$//')
                            local item_value=$(echo "$pair" | sed 's/^[^=]*= "//' | sed 's/"$//')
                            
                            if [[ -n "$item_key" ]] && [[ -n "$item_value" ]]; then
                                # Remove escape sequences from value for defaults write
                                item_value=$(echo "$item_value" | sed 's/\\\\/\\/g')
                                defaults write "$domain" "$key" -dict-add "$item_key" "$item_value"
                            fi
                        fi
                        IFS=';'
                    done
                    IFS="$IFS_SAVE"
                    # Add domain to custommenu.apps array if not already present
                    if ! defaults read com.apple.universalaccess com.apple.custommenu.apps 2>/dev/null | grep -q "$domain"; then
                        defaults write com.apple.universalaccess com.apple.custommenu.apps -array-add "$domain"
                    fi
                elif [[ "$action" == "inactive" ]]; then
                    # Parse delete list: delete "Key1"; "Key2"; "Key3"
                    # Remove 'delete ' prefix, then use semicolon as separator
                    local delete_list=$(echo "$value" | sed 's/^delete //' | sed 's/"; *"/|/g' | sed 's/^"//' | sed 's/"$//')
                    
                    # Determine plist file path based on domain
                    local plist_file
                    if [[ "$domain" == "NSGlobalDomain" ]]; then
                        plist_file="$HOME/Library/Preferences/.GlobalPreferences.plist"
                    else
                        plist_file="$HOME/Library/Preferences/${domain}.plist"
                    fi

                    # Delete each item using PlistBuddy (works for all domains)
                    local IFS_SAVE="$IFS"
                    IFS='|'
                    for item in $delete_list; do
                        IFS="$IFS_SAVE"
                        if [[ -n "$item" ]]; then
                            # Escape spaces for PlistBuddy
                            local escaped_item=$(echo "$item" | sed 's/ /\\ /g')
                            /usr/libexec/PlistBuddy -c "Delete :${key}:${escaped_item}" "$plist_file" 2>/dev/null || true
                        fi
                        IFS='|'
                    done
                    IFS="$IFS_SAVE"
                    # for item in $delete_list; do
                    #     # Remove quotes if present
                    #     item=$(echo "$item" | sed 's/^"//' | sed 's/"$//')
                    #     if [[ -n "$item" ]]; then
                    #         # Try defaults delete first, fallback to PlistBuddy for Finder
                    #         if [[ "$domain" == "com.apple.finder" ]]; then
                    #             local plist_file="$HOME/Library/Preferences/com.apple.finder.plist"
                    #             /usr/libexec/PlistBuddy -c "Delete :NSUserKeyEquivalents:${item}" "$plist_file" 2>/dev/null || true
                    #         else
                    #             defaults delete "$domain" "$key" "$item" 2>/dev/null || true
                    #         fi
                    #     fi
                    # done
                    killall cfprefsd 2>/dev/null || true
                fi
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
                
                # Clear the .DS_Store files
                # sudo rm /.DS_Store
                # find ~ -name .DS_Store -type f -delete

                # Refresh cfprefsd & Finder to reflect Finder plist changes
                killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                sleep 1
                ;;
            "darkmode")
                if [[ "$action" == "active" ]]; then
                    defaults write NSGlobalDomain AppleIconAppearanceTheme RegularDark 2>/dev/null || true
                    sleep 1
                    killall Finder 2>/dev/null || true
                    killall Dock 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults delete NSGlobalDomain AppleIconAppearanceTheme 2>/dev/null || true
                    sleep 1
                    killall Finder 2>/dev/null || true
                    killall Dock 2>/dev/null || true
                fi
                ;;
            "ReduceMotion")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.Accessibility ReduceMotionEnabled -bool true 2>/dev/null || true
                    defaults write com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.Accessibility ReduceMotionEnabled -bool false 2>/dev/null || true
                    defaults write com.apple.universalaccess reduceMotion -bool false 2>/dev/null || true
                    echo
                    echo "⚠️  ${YE}Note: Spotlight Search animations may require a restart to regain full functionality again.${NC}"
                    read -r -t 2 -n 1
                fi
                ;;
            "ReduceTransparency")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.universalaccess reduceTransparency -bool true 2>/dev/null || true
                    defaults write com.apple.Accessibility EnhancedBackgroundContrastEnabled -bool true 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.universalaccess reduceTransparency -bool false 2>/dev/null || true
                    defaults write com.apple.Accessibility EnhancedBackgroundContrastEnabled -bool false 2>/dev/null || true
                fi
                ;;
            "DisableMouseKeys")
                if [[ "$action" == "active" ]]; then
                    # Active: ensure both underlying settings are false (Mouse Keys disabled)
                    defaults write com.apple.universalaccess useMouseKeysShortcutKeys -bool false 2>/dev/null || true
                    defaults write com.apple.universalaccess mouseDriverIgnoreTrackpad -bool false 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    # Inactive: restore both settings to true (Mouse Keys enabled / default behavior)
                    defaults write com.apple.universalaccess useMouseKeysShortcutKeys -bool true 2>/dev/null || true
                    defaults write com.apple.universalaccess mouseDriverIgnoreTrackpad -bool true 2>/dev/null || true
                fi
                ;;
            "ShrinkSideBarInTahoe")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.finder SidebarWidth2 -int 135 2>/dev/null || true
                    defaults write com.apple.finder FK_SidebarWidth2 -int 135 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.finder SidebarWidth2 -int 161 2>/dev/null || true
                    defaults write com.apple.finder FK_SidebarWidth2 -int 161 2>/dev/null || true
                fi
                ;;
            "ShrinkSideBarInSequoiaAndBelow")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.finder SidebarWidth -int 143 2>/dev/null || true
                    defaults write com.apple.finder FK_SidebarWidth -int 143 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.finder SidebarWidth -int 164 2>/dev/null || true
                    defaults write com.apple.finder FK_SidebarWidth -int 164 2>/dev/null || true
                fi
                ;;
            "NevaHideMenuBarinTahoe")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.controlcenter AutoHideMenuBarOption -int 3 2>/dev/null || true
                    defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true 2>/dev/null || true
                    sleep 1
                    # killall Finder 2>/dev/null || true
                    # killall Dock 2>/dev/null || true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.controlcenter AutoHideMenuBarOption -int 2 2>/dev/null || true
                    defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false 2>/dev/null || true
                    sleep 1
                    # killall Finder 2>/dev/null || true
                    # killall Dock 2>/dev/null || true
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
                read -r -t 2 -n 1
                ;;
            "Show_Time_Machine_Menu_Bar_Item")
                # Handle Time Machine Menu Bar item
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.TimeMachine" -bool true

                    # Check if TimeMachine is already in menuExtras before adding
                    if ! /usr/libexec/PlistBuddy -c "Print :menuExtras" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null | grep -q "TimeMachine"; then
                        /usr/libexec/PlistBuddy -c "Add :menuExtras: string '/System/Library/CoreServices/Menu Extras/TimeMachine.menu'" ~/Library/Preferences/com.apple.systemuiserver.plist 2>/dev/null
                    fi 
                elif [[ "$action" == "inactive" ]]; then
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
                killall cfprefsd 2>/dev/null || true
                read -r -t 1 -n 1
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
                elif [[ "$action" == "inactive" ]]; then
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
                killall cfprefsd 2>/dev/null || true
                read -r -t 1 -n 1
                ;;
            "PasswordManager")
                # Handle Password Menu Bar item
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.Passwords EnableMenuBarExtra -bool true
                    defaults write com.apple.Passwords.MenuBarExtra "NSStatusItem Visible Item-0" -bool true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.Passwords EnableMenuBarExtra -bool false
                    defaults write com.apple.Passwords.MenuBarExtra "NSStatusItem Visible Item-0" -bool false
                fi
                read -r -t 1 -n 1
                ;;
            "Auto_Fill_Passwords_DeleteVerificationCodes")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.onetimepasscodes DeleteVerificationCodes -bool true
                    defaults write com.apple.MobileSMS DeleteVerificationCodes -bool true
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.onetimepasscodes DeleteVerificationCodes -bool false
                    defaults write com.apple.MobileSMS DeleteVerificationCodes -bool false
                fi
                ;;
            "DisableGlobalPasswordAutoFill")
            if [[ "$action" == "active" ]]; then
                    defaults write com.apple.Safari AutoFillPasswords -bool false
                    defaults write com.apple.Safari AutoFillFromiCloudKeychain -bool false
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.Safari AutoFillPasswords -bool true
                    defaults write com.apple.Safari AutoFillFromiCloudKeychain -bool true
                fi
                ;;
            "DisableSafariPasswordAutoFillInTahoe26_4")
                # New key introduced affecting only Safari instead of global AutoFill
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.Safari AutoFillPasswordsInSafari -bool false
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.Safari AutoFillPasswordsInSafari -bool true
                fi
                ;;
            "DisableSafariPasswordAutoFillInTahoe26_3AndBelow")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.Safari AutoFillPasswords -bool false
                    defaults write com.apple.Safari AutoFillFromiCloudKeychain -bool false
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.Safari AutoFillPasswords -bool true
                    defaults write com.apple.Safari AutoFillFromiCloudKeychain -bool true
                fi
                ;;
            "disable_Apple_Intelligence")
                if [[ "$ARCH_TYPE" != "arm64" ]]; then
                    echo
                    echo "${BO}This requires an Apple Silicon machine.${NC}"
                    echo
                    read -r -t 1 -n 1
                    return 1
                elif [[ "$MACOS_MAJOR" -le 14 ]]; then
                    echo
                    echo "${BO}This requires macOS Sequoia 15+ or later.${NC}"
                    read -r -t 1 -n 1
                    echo
                    return 1
                # # this is dependent on being signed with an Apple ID
                # elif [[ "$DEVICE_TYPE" == "vm" ]]; then
                #     echo
                #     echo "${BO}Apple Intelligence may not be avilable on virtual machines.${NC}"
                #     read -r -t 1 -n 1
                #     echo
                #     return 1
                fi
                # Handle Apple Intelligence
                if [[ "$action" == "active" ]]; then
                    for key in $(defaults read com.apple.CloudSubscriptionFeatures.optIn 2>/dev/null | grep -E "^\s+[0-9]+ = 1;" | awk '{print $1}'); do
                        defaults write com.apple.CloudSubscriptionFeatures.optIn "$key" -bool false
                    done
                elif [[ "$action" == "inactive" ]]; then
                    for key in $(defaults read com.apple.CloudSubscriptionFeatures.optIn 2>/dev/null | grep -E "^\s+[0-9]+ = 0;" | awk '{print $1}'); do
                        defaults write com.apple.CloudSubscriptionFeatures.optIn "$key" -bool true
                    done
                fi
                ;;
            "DisableSpotlightRelatedContent")
                if [[ "$MACOS_MAJOR" -ge 26 ]]; then
                    # if [[ "$action" == "active" ]]; then
                    #     # add in "Custom.relatedContents" to be excluded
                    #     defaults write com.apple.Spotlight EnabledPreferenceRules -array "Custom.relatedContents"
                    # elif [[ "$action" == "inactive" ]]; then
                    #     defaults write com.apple.Spotlight EnabledPreferenceRules -array
                    # fi
                    
                    # Read current array into a variable
                    local current_array=$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null)
                    
                    if [[ "$action" == "active" ]]; then
                        # Add "Custom.relatedContents" if not already present
                        if ! echo "$current_array" | grep -q "Custom.relatedContents"; then
                            # Get all current items except Custom.relatedContents, then add it
                            items=$(echo "$current_array" | grep -o '"[^"]*"' | grep -v "Custom.relatedContents" | tr '\n' ' ')
                            defaults write com.apple.Spotlight EnabledPreferenceRules -array "Custom.relatedContents" $items
                        fi
                    else
                        # Remove "Custom.relatedContents" by rebuilding array without it
                        items=$(echo "$current_array" | grep -o '"[^"]*"' | grep -v "Custom.relatedContents" | tr '\n' ' ')
                        if [[ -n "$items" ]]; then
                            defaults write com.apple.Spotlight EnabledPreferenceRules -array $items
                        else
                            defaults write com.apple.Spotlight EnabledPreferenceRules -array
                        fi
                    fi
                else
                    echo
                    echo "${BO}This requires macOS Tahoe 26+${NC}"
                    read -r -t 1 -n 1
                    return 1
                fi
                ;;
            "ReduceSpotlightResultsInTahoe")
                local current_array=$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null)
                
                if [[ "$action" == "active" ]]; then
                    # Check if Custom.relatedContents is present
                    if echo "$current_array" | grep -q "Custom.relatedContents"; then
                        # Preserve Custom.relatedContents
                        defaults write com.apple.Spotlight EnabledPreferenceRules -array \
                            "Custom.relatedContents" \
                            "com.apple.AppStore" \
                            "com.apple.iBooksX" \
                            "com.apple.calculator" \
                            "com.apple.iCal" \
                            "com.apple.AddressBook" \
                            "com.apple.Dictionary" \
                            "com.apple.mail" \
                            "com.apple.MobileSMS" \
                            "com.apple.Notes" \
                            "com.apple.Photos" \
                            "com.apple.podcasts" \
                            "com.apple.reminders" \
                            "com.apple.Safari" \
                            "com.apple.shortcuts" \
                            "com.apple.tips" \
                            "com.apple.VoiceMemos" \
                            "System.documents" \
                            "System.files" \
                            "System.folders" \
                            "System.iphoneApps" \
                            "System.menuItems"
                    else
                        # No Custom.relatedContents to preserve
                        defaults write com.apple.Spotlight EnabledPreferenceRules -array \
                            "com.apple.AppStore" \
                            "com.apple.iBooksX" \
                            "com.apple.calculator" \
                            "com.apple.iCal" \
                            "com.apple.AddressBook" \
                            "com.apple.Dictionary" \
                            "com.apple.mail" \
                            "com.apple.MobileSMS" \
                            "com.apple.Notes" \
                            "com.apple.Photos" \
                            "com.apple.podcasts" \
                            "com.apple.reminders" \
                            "com.apple.Safari" \
                            "com.apple.shortcuts" \
                            "com.apple.tips" \
                            "com.apple.VoiceMemos" \
                            "System.documents" \
                            "System.files" \
                            "System.folders" \
                            "System.iphoneApps" \
                            "System.menuItems"
                    fi
                else
                    # Remove all app/system items but preserve Custom.relatedContents if present
                    if echo "$current_array" | grep -q "Custom.relatedContents"; then
                        defaults write com.apple.Spotlight EnabledPreferenceRules -array "Custom.relatedContents"
                    else
                        defaults write com.apple.Spotlight EnabledPreferenceRules -array
                    fi
                fi
                ;;
            "ReduceSpotlightResultsInSequoia")
                return 1
                # if [[ "$action" == "active" ]]; then
                # method 1
                    # # Set orderedItems with only APPLICATIONS and SYSTEM_PREFS enabled
                    # defaults write com.apple.Spotlight orderedItems -array \
                    #     '{"enabled" = 1;"name" = "APPLICATIONS";}' \
                    #     '{"enabled" = 0;"name" = "MENU_EXPRESSION";}' \
                    #     '{"enabled" = 0;"name" = "CONTACT";}' \
                    #     '{"enabled" = 0;"name" = "MENU_CONVERSION";}' \
                    #     '{"enabled" = 0;"name" = "MENU_DEFINITION";}' \
                    #     '{"enabled" = 0;"name" = "DOCUMENTS";}' \
                    #     '{"enabled" = 0;"name" = "EVENT_TODO";}' \
                    #     '{"enabled" = 0;"name" = "DIRECTORIES";}' \
                    #     '{"enabled" = 0;"name" = "FONTS";}' \
                    #     '{"enabled" = 0;"name" = "IMAGES";}' \
                    #     '{"enabled" = 0;"name" = "MESSAGES";}' \
                    #     '{"enabled" = 0;"name" = "MOVIES";}' \
                    #     '{"enabled" = 0;"name" = "MUSIC";}' \
                    #     '{"enabled" = 0;"name" = "MENU_OTHER";}' \
                    #     '{"enabled" = 0;"name" = "PDF";}' \
                    #     '{"enabled" = 0;"name" = "PRESENTATIONS";}' \
                    #     '{"enabled" = 0;"name" = "MENU_SPOTLIGHT_SUGGESTIONS";}' \
                    #     '{"enabled" = 0;"name" = "SPREADSHEETS";}' \
                    #     '{"enabled" = 1;"name" = "SYSTEM_PREFS";}' \
                    #     '{"enabled" = 0;"name" = "TIPS";}' \
                    #     '{"enabled" = 0;"name" = "BOOKMARKS";}'

                #     # method 2
                
                #     # Modify orderedItems in-place with PlistBuddy (preserve structure, order, and
                #     # item set). Replacing the whole array via defaults write can cause the Spotlight
                #     # pane in System Settings to go blank on Sequoia—e.g. if SOURCE or other
                #     # extra/unknown categories are written, or the plist format changes.
                #     local plist="$HOME/Library/Preferences/com.apple.Spotlight.plist"

                #     # Guard: orderedItems must already exist.
                #     # Open System Settings → Spotlight once to create it if missing.
                #     local name
                #     name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:0:name" "$plist" 2>/dev/null)
                #     if [[ -z "$name" ]] || [[ "$name" == *"Does Not Exist"* ]]; then
                #         echo "⚠️  ${YE}Spotlight orderedItems not found."
                #         echo "   Open System Settings → Spotlight once to create it, then try again.${NC}"
                #         read -r -t 3 -n 1
                #         return 1
                #     fi

                #     # Modify enabled flags in-place. Never replaces the array, so system-specific
                #     # categories like SOURCE (added by Xcode/CLT) are preserved as-is.
                #     local idx=0
                #     while true; do
                #         name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:${idx}:name" "$plist" 2>/dev/null)
                #         if [[ -z "$name" || "$name" == *"Does Not Exist"* ]]; then
                #             break
                #         fi

                #         # boolean method
                #         if [[ "$name" == "APPLICATIONS" || "$name" == "SYSTEM_PREFS" ]]; then
                #             /usr/libexec/PlistBuddy -c "Set :orderedItems:${idx}:enabled bool true" "$plist" 2>/dev/null || true
                #         else
                #             /usr/libexec/PlistBuddy -c "Set :orderedItems:${idx}:enabled bool false" "$plist" 2>/dev/null || true
                #         fi

                #         idx=$((idx + 1))
                #     done

                #     # Flush cfprefsd cache first (PlistBuddy writes direct to disk, bypassing it),
                #     # then restart mds/Spotlight so they pick up the updated prefs from disk.
                #     killall cfprefsd 2>/dev/null || true
                #     sleep 0.5
                #     killall mds 2>/dev/null || true
                #     killall Spotlight 2>/dev/null || true
                # else
                #     # # For inactive, delete the key to restore defaults
                #     # defaults delete com.apple.Spotlight orderedItems 2>/dev/null || true

                #     local plist="$HOME/Library/Preferences/com.apple.Spotlight.plist"
                #     # Re-enable all categories in-place rather than deleting the key.
                #     # Deleting the key forces macOS to regenerate it, which can be unreliable
                #     # on Sequoia and may drop system-specific categories like SOURCE.
                #     local name
                #     name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:0:name" "$plist" 2>/dev/null)
                #     if [[ -z "$name" || "$name" == *"Does Not Exist"* ]]; then
                #         return 0
                #     fi

                #     local idx=0
                #     while true; do
                #         name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:${idx}:name" "$plist" 2>/dev/null)
                #         [[ -z "$name" || "$name" == *"Does Not Exist"* ]] && break
                #         /usr/libexec/PlistBuddy -c "Set :orderedItems:${idx}:enabled bool true" "$plist" 2>/dev/null || true
                #         idx=$((idx + 1))
                #     done

                #     killall cfprefsd 2>/dev/null || true
                #     sleep 0.5
                #     killall mds 2>/dev/null || true
                #     killall Spotlight 2>/dev/null || true
                
                #     # method 3

                #     local plist="$HOME/Library/Preferences/com.apple.Spotlight.plist"

                #     local name
                #     name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:0:name" "$plist" 2>/dev/null)
                #     if [[ -z "$name" || "$name" == *"Does Not Exist"* ]]; then
                #         echo "⚠️  ${YE}Spotlight orderedItems not found."
                #         echo "   Open System Settings → Spotlight once to create it, then try again.${NC}"
                #         read -r -t 3 -n 1
                #         return 1
                #     fi

                #     # Kill cfprefsd and Spotlight BEFORE writing so cfprefsd can't race
                #     # against PlistBuddy and flush its stale in-memory cache back to disk.
                #     # Launchd restarts cfprefsd automatically; the new instance reads from disk.
                #     killall Spotlight  2>/dev/null || true
                #     killall cfprefsd   2>/dev/null || true
                #     sleep 0.5

                #     local idx=0
                #     while true; do
                #         name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:${idx}:name" "$plist" 2>/dev/null)
                #         [[ -z "$name" || "$name" == *"Does Not Exist"* ]] && break
                #         if [[ "$name" == "APPLICATIONS" || "$name" == "SYSTEM_PREFS" ]]; then
                #             /usr/libexec/PlistBuddy -c "Set :orderedItems:${idx}:enabled bool true"  "$plist" 2>/dev/null || true
                #         else
                #             /usr/libexec/PlistBuddy -c "Set :orderedItems:${idx}:enabled bool false" "$plist" 2>/dev/null || true
                #         fi
                #         idx=$((idx + 1))
                #     done

                #     # Restart mds so it picks up the updated category list from disk
                #     killall mds 2>/dev/null || true

                # else
                #     local plist="$HOME/Library/Preferences/com.apple.Spotlight.plist"

                #     local name
                #     name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:0:name" "$plist" 2>/dev/null)
                #     [[ -z "$name" || "$name" == *"Does Not Exist"* ]] && return 0

                #     killall Spotlight  2>/dev/null || true
                #     killall cfprefsd   2>/dev/null || true
                #     sleep 0.5

                #     local idx=0
                #     while true; do
                #         name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:${idx}:name" "$plist" 2>/dev/null)
                #         [[ -z "$name" || "$name" == *"Does Not Exist"* ]] && break
                #         /usr/libexec/PlistBuddy -c "Set :orderedItems:${idx}:enabled bool true" "$plist" 2>/dev/null || true
                #         idx=$((idx + 1))
                #     done

                #     killall mds 2>/dev/null || true
                # fi
                # :
                ;;
            "Remote_Management_Menu_Bar")
                # Handle Remote Management Menu Bar
                    # Only show warning if sudo credentials aren't cached
                if ! sudo -n true 2>/dev/null; then
                    echo "📝 This requires sudo privileges. Please type your admin password then press enter."
                fi
                if [[ "$action" == "active" ]]; then
                    sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist LoadRemoteManagementMenuExtra -bool true
                elif [[ "$action" == "inactive" ]]; then
                    sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist LoadRemoteManagementMenuExtra -bool false
                fi
                ;;
            "DisableSendReadReceiptsIniMessage")
                # Handle Password Menu Bar item
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.imagent Setting.EnableReadReceipts -bool false
                    defaults write com.apple.imagent Setting.GlobalReadReceiptsVersionID -int 2
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.imagent Setting.EnableReadReceipts -bool true
                    defaults write com.apple.imagent Setting.GlobalReadReceiptsVersionID -int 1
                fi
                ;;
            "DisableCertainShareExtensions")
                # Handle Share Extensions
                local extensions=(
                    # Items that exist on all macOS versions supported
                    "com.apple.share.System.add-to-safari-reading-list"
                    # "com.apple.CloudSharingUI.CopyLink"    # keep as is
                    "com.apple.Notes.SharingExtension"
                    "com.apple.share.System.add-to-iphoto"
                    "com.apple.news.openinnews"
                    "com.apple.reminders.sharingextension"
                    "com.apple.iBooksX.SharingExtension"
                    # "com.apple.CloudSharingUI.CreateiCloudLinkExtension"    # keep as is
                )
                # Version-specific additions
                # if [[ "$MACOS_MAJOR" -ge 12 ]]; then
                #     # Monterey+
                #     extensions+=(
                #         # "com.apple.shortcuts.Run-Workflow"    # Shortcuts app exists, not in Share menu until 13
                #     )
                # fi
                if [[ "$MACOS_MAJOR" -ge 13 ]]; then
                    # Ventura+
                    extensions+=(
                        "com.apple.shortcuts.Run-Workflow"    # Now appears in Share Menu
                        "com.apple.freeform.sharingextension"    # Freeform added
                    )
                fi
                if [[ "$MACOS_MAJOR" -ge 26 ]]; then
                    # Tahoe+
                    extensions+=(
                        "com.apple.journal.JournalShareExtension"    # Journal added
                    )
                fi

                if [[ "$action" == "active" ]]; then
                    # Disable each extension
                    for ext in "${extensions[@]}"; do
                        # echo "Disabling: $ext"
                        pluginkit -e ignore -i "$ext"
                    done
                    # Also disable Contact Suggestions via its plist (if on Ventura 13 or later)
                    if [[ "$MACOS_MAJOR" -ge 13 ]]; then
                        defaults write com.apple.Sharing SharingPeopleSuggestionsDisabled -bool true
                        # echo "Share extensions disabled successfully"
                    fi
                elif [[ "$action" == "inactive" ]]; then
                    # Enable each extension
                    for ext in "${extensions[@]}"; do
                        # echo "Enabling: $ext"
                        pluginkit -e use -i "$ext"
                    done
                    # Also enable Contact Suggestions via its plist (if on Ventura 13 or later)
                    if [[ "$MACOS_MAJOR" -ge 13 ]]; then
                        defaults write com.apple.Sharing SharingPeopleSuggestionsDisabled -bool false
                        # echo "Share extensions enabled successfully"
                    fi
                fi
                ;;
            "KeyboardFunctionKey")
                if [[ "$action" == "active" ]]; then
                    defaults write com.apple.HIToolbox AppleFnUsageType -int 2
                    defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool false
                elif [[ "$action" == "inactive" ]]; then
                    defaults write com.apple.HIToolbox AppleFnUsageType -int 3
                    defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool true
                fi
                ;;
            "NewArchiveUtilityDictIn26_4")
                if [[ "$action" == "active" ]]; then
                    defaults write "$domain" "$key" -dict "Selection" "MoveToTrash"
                elif [[ "$action" == "inactive" ]]; then
                    defaults write "$domain" "$key" -dict "Selection" "UseSameFolder"
                fi
                ;;
            "UseBrightBoldInTerminal")
                # Not reliably setting UseBrightBold to true
                if [[ "$action" == "active" ]]; then
                    return 1
                fi

                default_profile=$(defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null)
                startup_profile=$(defaults read com.apple.Terminal "Startup Window Settings" 2>/dev/null)
                profiles_to_update=()
                [[ -n "$default_profile" ]] && profiles_to_update+=("$default_profile")
                [[ -n "$startup_profile" && "$startup_profile" != "$default_profile" ]] && profiles_to_update+=("$startup_profile")

                if [[ "$action" == "active" ]]; then
                    bool_val="true"
                elif [[ "$action" == "inactive" ]]; then
                    bool_val="false"
                fi

                failed=false
                for profile in "${profiles_to_update[@]}"; do
                    /usr/libexec/PlistBuddy -c "Set :'Window Settings':'$profile':UseBrightBold bool $bool_val" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null
                    result=$(/usr/libexec/PlistBuddy -c "Print :'Window Settings':'$profile':UseBrightBold" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null)
                    [[ "$result" != "$bool_val" ]] && failed=true
                done

                [[ "$failed" == "true" ]] && return 1
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
                read -r -t 1 -n 1
                ;;
            "ListViewColumns")
                # Handle ListViewColumns settings - set or delete columns in all locations
                local plist_file="$domain"
                if [[ "$action" == "active" ]]; then
                    # Set columns in all 3 base locations
                    set_list_view_columns "$plist_file" ":ICloudViewSettings" "set"
                    set_list_view_columns "$plist_file" ":StandardViewSettings" "set"
                    set_list_view_columns "$plist_file" ":FK_StandardViewSettings" "set"
                elif [[ "$action" == "inactive" ]]; then
                    # Delete columns from all locations
                    set_list_view_columns "$plist_file" ":ICloudViewSettings" "delete"
                    set_list_view_columns "$plist_file" ":StandardViewSettings" "delete"
                    set_list_view_columns "$plist_file" ":FK_StandardViewSettings" "delete"
                fi
                
                # Clear the .DS_Store files
                # sudo rm /.DS_Store
                # find ~ -name .DS_Store -type f -delete

                # Refresh cfprefsd & Finder to reflect Finder plist changes
                killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                read -r -t 1 -n 1
                ;;
            "Remove_All_DS_Store_Files")
                if [[ "$action" == "home folder" ]]; then
                    echo
                    echo "${GY}This may take several seconds to find all '.DS_Store' files${NC}"
                    read -r -t 1 -n 1
                    find $HOME -name ".DS_Store" -type f -delete 2>/dev/null
                    echo
                    echo "✅ ${GR}Done${NC}"
                elif [[ "$action" == "documents folder" ]]; then
                    echo
                    echo "${GY}This may take several seconds to find all '.DS_Store' files${NC}"
                    find $HOME/Documents -name ".DS_Store" -type f -delete 2>/dev/null
                    echo
                    echo "✅ ${GR}Done${NC}"
                # elif [[ "$action" == "root folder" ]]; then
                #     echo "${BO}Please enter password if prompted${NC}"
                #     sleep 1
                #     echo "${GY}This can take 10-30 seconds to find all '.DS_Store' files${NC}"
                #     sleep 1
                    # sudo find / -name ".DS_Store" -type f -delete 2>/dev/null
                    # echo "✅ ${GR}Done${NC}"
                    # DS_Store_result=$?
                    # if [[ $DS_Store_result == "0" ]]; then
                    #     echo "✅ ${GR}Done${NC}"
                    # else
                    #     echo "✅ ${GR}Done${NC}"
                    # fi
                fi
                read -r -t 1 -n 1
                echo "${BO}=== Go ahead and set your preferences now ===${NC}"
                read -r -t 1 -n 1
                echo
                ;;
            "IconView_variousSettings")
                # Handle IconView settings across Finder, Save Dialogs, and iCloud
                local plist_file="$domain"
                local setting_path="$key"
                local setting_name="${setting_path##*:}"
                
                # Determine plist paths for this setting
                local plist_paths=(
                    ":StandardViewSettings:IconViewSettings:${setting_name}"
                    ":FK_StandardViewSettings:IconViewSettings:${setting_name}"
                    ":ICloudViewSettings:IconViewSettings:${setting_name}"
                )
                
                # Determine PlistBuddy type for this setting
                local plist_type="string"
                case "$setting_name" in
                    showItemInfo|labelOnBottom)
                        plist_type="bool"
                        ;;
                    arrangeBy)
                        plist_type="string"
                        ;;
                    textSize|iconSize|gridSpacing)
                        plist_type="real"
                        ;;
                esac
                
                for plist_path in "${plist_paths[@]}"; do
                    /usr/libexec/PlistBuddy -c "Set $plist_path $value" "$plist_file" 2>/dev/null || \
                    /usr/libexec/PlistBuddy -c "Add $plist_path $plist_type $value" "$plist_file" 2>/dev/null || true
                done
                
                # Refresh cfprefsd & Finder to reflect Finder plist changes
                killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                read -r -t 1 -n 1
                ;;
            "ListView_calculateAllSizes")
                # Handle ListView settings across all Finder/iCloud/Trash list views
                local plist_file="$domain"
                local plist_paths=(
                    ":ICloudViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":ICloudViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_iCloudListViewSettingsV2:calculateAllSizes"
                    ":StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":StandardViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_DefaultListViewSettingsV2:calculateAllSizes"
                    ":FK_StandardViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":TrashViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":TrashViewSettings:ListViewSettings:calculateAllSizes"
                )
                
                for plist_path in "${plist_paths[@]}"; do
                    /usr/libexec/PlistBuddy -c "Set $plist_path $value" "$plist_file" 2>/dev/null || \
                    /usr/libexec/PlistBuddy -c "Add $plist_path bool $value" "$plist_file" 2>/dev/null || true
                done
                
                # Clear the .DS_Store files
                # sudo rm /.DS_Store
                # find ~ -name .DS_Store -type f -delete

                # Refresh cfprefsd & Finder to reflect Finder plist changes
                killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                read -r -t 1 -n 1
                ;;
            "Desktop_IconView_showItemInfo"|"Desktop_IconView_labelOnBottom"|"Desktop_IconView_arrangeBy"|"Desktop_IconView_textSize"|"Desktop_IconView_iconSize"|"Desktop_IconView_gridSpacing")
                # Handle Desktop IconView settings using PlistBuddy
                # Determine type based on handler (bool/string/real)
                local plist_file="$domain"
                local plist_path="$key"
                local plist_type="string"
                case "$handler" in
                    Desktop_IconView_showItemInfo|Desktop_IconView_labelOnBottom)
                        plist_type="bool"
                        ;;
                    Desktop_IconView_arrangeBy)
                        plist_type="string"
                        ;;
                    Desktop_IconView_textSize|Desktop_IconView_iconSize|Desktop_IconView_gridSpacing)
                        plist_type="real"
                        ;;
                esac

                /usr/libexec/PlistBuddy -c "Set $plist_path $value" "$plist_file" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Add $plist_path $plist_type $value" "$plist_file" 2>/dev/null || true
                
                # Clear the .DS_Store files
                # sudo rm /.DS_Store
                # find ~ -name .DS_Store -type f -delete

                # Refresh cfprefsd & Finder to reflect Finder plist changes
                killall cfprefsd 2>/dev/null || true

                # Refresh Finder to reflect Finder plist changes
                killall Finder 2>/dev/null || true
                read -r -t 1 -n 1
                ;;
            "key_equivalents")
                # Write a full NSUserKeyEquivalents dictionary blob as-is
                # Expect value to be a valid plist-style dict string: '{"Menu Item"="@~i"; ... }'
                defaults write "$domain" "$key" "$value"
                read -r -t 1 -n 1
                ;;
            "defaults_dict")
                # Write complex dict payloads (e.g., Finder panes/toolbar)
                defaults write "$domain" "$key" "$value"
                read -r -t 1 -n 1
                ;;
            "defaults_array")
                # Write an array payload. Allow multiple dict items passed in value.
                # If value already contains properly quoted items, use eval to expand them.
                eval "defaults write \"$domain\" \"$key\" -array $value"
                read -r -t 1 -n 1
                ;;
            "SoftwareUpdates")
                if [[ "$domain" == "/Library/Preferences/com.apple.SoftwareUpdate" ]]; then
                    sudo defaults write "$domain" "$key" -bool "$value"
                fi
                ;;
            "sudo")
                if [[ "$key" == "schedule" ]]; then
                    if [[ "$action" == "active" ]]; then
                        sudo softwareupdate --schedule on
                    else
                        sudo softwareupdate --schedule off
                    fi
                fi
                ;;
            "launchctl")
                # No defaults write; handled in restart block
                read -r -t 1 -n 1
                ;;
            *)
                write_defaults_typed "$domain" "$key" "$value" "$handler"
                ;;
        esac

        # Restart affected services
        case "$domain" in
            "com.apple.dock")
                killall Dock 2>/dev/null || true
                echo "${YE}Restarted Dock...${NC}"
                ;;
            "com.apple.finder")
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                    # killall cfprefsd 2>/dev/null || true
                fi
                killall Finder 2>/dev/null || true
                echo "${YE}Restarted Finder...${NC}"
                ;;
            "com.apple.bird")
                killall Finder 2>/dev/null || true
                echo "${YE}Restarted Finder...${NC}"
                ;;
            "com.apple.screencapture")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                ;;
            "com.apple.controlcenter")
                if [[ "$domain" == "com.apple.Spotlight" ]]; then
                    killall Spotlight 2>/dev/null || true
                    echo "${YE}Restarted Spotlight...${NC}"
                # elif [[ "$key" == "Siri" ]]; then
                #     killall Siri 2>/dev/null || true
                # elif [[ "$key" == "Weather" ]]; then
                #     killall weatherd 2>/dev/null || true
                #     killall WeatherMenu 2>/dev/null || true
                fi
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter...${NC}"
                ;;
            "com.apple.WindowManager")
                killall WindowManager 2>/dev/null || true
                echo "${YE}Restarted WindowManager...${NC}"
                ;;
            "com.apple.menuextra.clock")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter...${NC}"
                ;;
            "com.apple.Accessibility")
                killall UniversalAccessApp 2>/dev/null || true
                killall universalaccessd 2>/dev/null || true
                if [[ "$handler" == "ReduceMotion" ]]; then
                    killall Spotlight 2>/dev/null || true
                    killall corespotlightd 2>/dev/null || true
                    killall spotlightknowledged 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                    killall ControlCenter 2>/dev/null || true
                    killall WindowServer 2>/dev/null || true
                    killall Dock 2>/dev/null || true
                    killall cfprefsd 2>/dev/null || true
                fi
                echo "${YE}Restarted Services...${NC}"
                # echo "👤 ${BO}Note: Please log out for this to take effect.${NC}"
                ;;
            "com.apple.universalaccess")
                killall UniversalAccessApp 2>/dev/null || true
                killall universalaccessd 2>/dev/null || true
                # killall UniversalAccessAuthWarning 2>/dev/null || true
                # killall "System Preferences" 2>/dev/null
                if [[ "$handler" == "ReduceTransparency" ]]; then
                    killall Dock 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                    killall ControlCenter 2>/dev/null || true
                    killall Finder 2>/dev/null || true
                    killall cfprefsd 2>/dev/null || true
                fi
                echo "${YE}Restarted Services...${NC}"
                ;;
            "com.apple.systemuiserver")
                # killall ControlCenter 2>/dev/null || true
                killall SystemUIServer 2>/dev/null || true
                ;;
            "com.apple.universalcontrol")
                if [[ "$key" == "Spotlight" ]]; then
                    killall Spotlight 2>/dev/null || true
                    echo "${YE}Restarted Spotlight...${NC}"
                fi
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter...${NC}"
                ;;
            "NSGlobalDomain")
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall Finder 2>/dev/null || true
                    echo "${YE}Restarted Finder...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                    # killall cfprefsd 2>/dev/null || true
                else
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                fi
                ;;
            "DisableSpotlightRelatedContent")
                killall Spotlight 2>/dev/null || true
                echo "${YE}Restarted Spotlight...${NC}"
                ;;
            "com.apple.Safari")
                killall Safari 2>/dev/null || true
                echo "${YE}Restarted Safari...${NC}"
                ;;
            "com.apple.MobileSMS")
                killall Messages 2>/dev/null || true
                echo "${YE}Restarted Messages...${NC}"
                killall imagent 2>/dev/null || true
                echo "${YE}Restarted imagent...${NC}"
                ;;
            "com.apple.imagent")
                killall Messages 2>/dev/null || true
                echo "${YE}Restarted Messages...${NC}"
                killall imagent 2>/dev/null || true
                echo "${YE}Restarted imagent...${NC}"
                ;;
            "com.apple.Passwords")
                killall Passwords 2>/dev/null || true
                echo "${YE}Restarted Passwords...${NC}"
                killall PasswordsMenuBarExtra 2>/dev/null || true
                echo "${YE}Restarted PasswordsMenuBarExtra...${NC}"
                ;;
            "com.apple.TextEdit")
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                    # killall cfprefsd 2>/dev/null || true
                fi
                killall TextEdit 2>/dev/null || true
                echo "${YE}Restarted TextEdit...${NC}"
                ;;
            "com.apple.SocialLayer")
                killall sociallayerd 2>/dev/null || true
                echo "${YE}Restarted SocialLayer...${NC}"
                ;;
            "com.apple.archiveutility")
                killall "Archive Utility" 2>/dev/null || true
                echo "${YE}Restarted Archive Utility...${NC}"
                ;;
            "com.apple.Preview")
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                fi
                killall Preview 2>/dev/null || true
                echo "${YE}Restarted Preview...${NC}"
                ;;
            "com.apple.Terminal")
                echo "${BO}Please quit Terminal.app for changes to take effect...${NC}"
                read -r -t 2 -n 1
                # killall Terminal 2>/dev/null || true
                # echo "${YE}Restarted Terminal...${NC}"
                ;;
        esac
        
        # echo "${GR}✅ $action completed successfully!${NC}"
        # echo "${GR}✅ Done!${NC}"        
        # sleep 0.5
    }
    # Helper function to reset preference to default
    reset_preference_to_default() {
        local domain="$1"
        local key="$2"
        local reset_val="$3"
        local handler="$4"
        
        echo
        case "$domain" in
            com.apple.Safari|com.apple.universalaccess|com.apple.archiveutility|com.apple.MobileSMS)
                if [[ "$full_disk_access" == "false" ]]; then
                    # exit early
                    echo "⚠️  ${BO}${YE}Warning: ${NC}Terminal does not have full disk access to write these prefs...${NC}"
                    echo "   Please return to the macOS Preferences main menu to grant Terminal permission."
                    read -r -t 4 -n 1
                    echo
                    return 1
                fi
            ;;
        esac
        # echo "${YE}Resetting $key to default...${NC}"
        echo "${YE}Applying changes...${NC}"  
        
        # Handles handler cases
        case "$handler" in
            "delete")
                defaults delete "$domain" "$key" 2>/dev/null || true
                ;;
            *"-currentHost"*)
                # Handle currentHost handlers
                if [[ -n "$reset_val" ]]; then
                    if [[ "$reset_val" == "delete" ]]; then
                        # Delete with -currentHost flag
                        defaults -currentHost delete "$domain" "$key" 2>/dev/null || true
                    else
                        if [[ "$domain" == "com.apple.Spotlight" ]]; then
                            defaults -currentHost write com.apple.Spotlight MenuItemHidden -bool false 2>/dev/null || true
                            defaults write com.apple.Spotlight "NSStatusItem VisibleCC Item-0" -bool true 2>/dev/null || true
                        # elif [[ "$key" == "Siri" ]]; then
                        #     defaults -currentHost write com.apple.Siri StatusMenuVisible -bool false 2>/dev/null || true
                        else
                            # Write the reset_val with -currentHost flag (write_defaults_typed handles the flag automatically)
                            write_defaults_typed "$domain" "$key" "$reset_val" "$handler"
                        fi
                    fi
                fi
                ;;
            "writeResetValue")
                # Write the reset_val using write_defaults_typed
                # This handles preferences that need to be reset to a specific value
                write_defaults_typed "$domain" "$key" "$reset_val" "$handler"
                ;;
            "KeyboardShortcuts")
                # Generic handler for keyboard shortcuts reset - works with any domain
                # reset_val format: delete "Key1" & "Key2"
                
                # Parse delete list: delete "Key1" & "Key2"
                # local delete_list=$(echo "$reset_val" | sed 's/^delete //' | sed 's/ & / /g')
                local delete_list=$(echo "$reset_val" | sed 's/^delete //' | sed 's/"; *"/|/g' | sed 's/^"//' | sed 's/"$//')
                
                # Determine plist file path based on domain
                local plist_file
                if [[ "$domain" == "NSGlobalDomain" ]]; then
                    plist_file="$HOME/Library/Preferences/.GlobalPreferences.plist"
                else
                    plist_file="$HOME/Library/Preferences/${domain}.plist"
                fi

                # Delete each item using PlistBuddy (works for all domains)
                local IFS_SAVE="$IFS"
                IFS='|'
                for item in $delete_list; do
                    IFS="$IFS_SAVE"
                    if [[ -n "$item" ]]; then
                        # Escape spaces for PlistBuddy
                        local escaped_item=$(echo "$item" | sed 's/ /\\ /g')
                        /usr/libexec/PlistBuddy -c "Delete :${key}:${escaped_item}" "$plist_file" 2>/dev/null || true
                    fi
                    IFS='|'
                done
                IFS="$IFS_SAVE"

                # Delete each item
                # for item in $delete_list; do
                #     # Remove quotes if present
                #     item=$(echo "$item" | sed 's/^"//' | sed 's/"$//')
                #     if [[ -n "$item" ]]; then
                #         # Try defaults delete first, fallback to PlistBuddy for Finder
                #         if [[ "$domain" == "com.apple.finder" ]]; then
                #             local plist_file="$HOME/Library/Preferences/com.apple.finder.plist"
                #             /usr/libexec/PlistBuddy -c "Delete :NSUserKeyEquivalents:${item}" "$plist_file" 2>/dev/null || true
                #         else
                #             defaults delete "$domain" "$key" "$item" 2>/dev/null || true
                #         fi
                #     fi
                # done
                killall cfprefsd 2>/dev/null || true
                sleep 1
                ;;
            "darkmode")
                defaults delete NSGlobalDomain AppleIconAppearanceTheme 2>/dev/null || true
                sleep 1
                killall Finder 2>/dev/null || true
                killall Dock 2>/dev/null || true
                ;;
            "UniversalAccessNeedsFDA")
                write_defaults_typed "$domain" "$key" "$reset_val" "$handler"
                ;;
            "ReduceMotion")
                defaults write com.apple.Accessibility ReduceMotionEnabled -bool false 2>/dev/null || true
                defaults write com.apple.universalaccess reduceMotion -bool false 2>/dev/null || true
                echo
                echo "⚠️  ${YE}Note: Spotlight Search animations may require a restart to regain full functionality again."
                read -r -t 2 -n 1
                ;;
            "ReduceTransparency")
                defaults write com.apple.universalaccess reduceTransparency -bool false 2>/dev/null || true
                defaults write com.apple.Accessibility EnhancedBackgroundContrastEnabled -bool false 2>/dev/null || true
                ;;
            "DisableMouseKeys")
                # Reset both underlying settings to their default/expected enabled state
                defaults write com.apple.universalaccess useMouseKeysShortcutKeys -bool true 2>/dev/null || true
                defaults write com.apple.universalaccess mouseDriverIgnoreTrackpad -bool true 2>/dev/null || true
                ;;
            "ShrinkSideBarInTahoe")
                defaults write com.apple.finder SidebarWidth2 -int 161 2>/dev/null || true
                defaults write com.apple.finder FK_SidebarWidth2 -int 161 2>/dev/null || true
                ;;
            "ShrinkSideBarInSequoiaAndBelow")
                defaults write com.apple.finder SidebarWidth -int 164 2>/dev/null || true
                defaults write com.apple.finder FK_SidebarWidth -int 164 2>/dev/null || true
                ;;
            "Two_Finger_Tap_To_Right_Click_AND_Bottom_Right_Click")
                defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 0
                defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool false
                defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 0
                defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool false
                defaults write com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick -int 0
                defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool false
                echo "👤 ${BO}Note: Please log out for this to take effect.${NC}"
                read -r -t 2 -n 1
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
                killall cfprefsd 2>/dev/null || true
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
                killall cfprefsd 2>/dev/null || true
                ;;
            "PasswordManager")
                defaults write com.apple.Passwords EnableMenuBarExtra -bool false
                defaults write com.apple.Passwords.MenuBarExtra "NSStatusItem Visible Item-0" -bool false
                read -r -t 1 -n 1
                ;;
            "Auto_Fill_Passwords_DeleteVerificationCodes")
                defaults write com.apple.onetimepasscodes DeleteVerificationCodes -bool false
                defaults write com.apple.MobileSMS DeleteVerificationCodes -bool false
                ;;
            "DisableGlobalPasswordAutoFill")
                defaults write com.apple.Safari AutoFillPasswords -bool true
                defaults write com.apple.Safari AutoFillFromiCloudKeychain -bool true
                ;;
            "DisableSafariPasswordAutoFillInTahoe26_4")
                # New key introduced affecting only Safari instead of global AutoFill
                defaults write com.apple.Safari AutoFillPasswordsInSafari -bool true
                ;;
            "DisableSafariPasswordAutoFillInTahoe26_3AndBelow")
                defaults write com.apple.Safari AutoFillPasswords -bool true
                defaults write com.apple.Safari AutoFillFromiCloudKeychain -bool true
                ;;
            "DisableSpotlightRelatedContent")
                # defaults write com.apple.Spotlight EnabledPreferenceRules -array
                
                # Read current array into a variable
                local current_array=$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null)
                
                # Remove "Custom.relatedContents" by rebuilding array without it
                items=$(echo "$current_array" | grep -o '"[^"]*"' | grep -v "Custom.relatedContents" | tr '\n' ' ')
                if [[ -n "$items" ]]; then
                    defaults write com.apple.Spotlight EnabledPreferenceRules -array $items
                else
                    defaults write com.apple.Spotlight EnabledPreferenceRules -array
                fi
                ;;
            "ReduceSpotlightResultsInTahoe")
                local current_array=$(defaults read com.apple.Spotlight EnabledPreferenceRules 2>/dev/null)
                
                # Remove all app/system items but preserve Custom.relatedContents if present
                if echo "$current_array" | grep -q "Custom.relatedContents"; then
                    defaults write com.apple.Spotlight EnabledPreferenceRules -array "Custom.relatedContents"
                else
                    defaults write com.apple.Spotlight EnabledPreferenceRules -array
                fi
                ;;
            "ReduceSpotlightResultsInSequoia")
                return 1
                # method 1

                # # Reset to default by deleting the orderedItems key
                # defaults delete com.apple.Spotlight orderedItems 2>/dev/null || true


                # # method 2

                # # # For inactive, delete the key to restore defaults
                # # defaults delete com.apple.Spotlight orderedItems 2>/dev/null || true

                # local plist="$HOME/Library/Preferences/com.apple.Spotlight.plist"
                # # Re-enable all categories in-place rather than deleting the key.
                # # Deleting the key forces macOS to regenerate it, which can be unreliable
                # # on Sequoia and may drop system-specific categories like SOURCE.
                # local name
                # name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:0:name" "$plist" 2>/dev/null)
                # if [[ -z "$name" || "$name" == *"Does Not Exist"* ]]; then
                #     return 0
                # fi

                # local idx=0
                # while true; do
                #     name=$(/usr/libexec/PlistBuddy -c "Print :orderedItems:${idx}:name" "$plist" 2>/dev/null)
                #     [[ -z "$name" || "$name" == *"Does Not Exist"* ]] && break
                #     /usr/libexec/PlistBuddy -c "Set :orderedItems:${idx}:enabled bool true" "$plist" 2>/dev/null || true
                #     idx=$((idx + 1))
                # done

                # killall cfprefsd 2>/dev/null || true
                # sleep 0.5
                # killall mds 2>/dev/null || true
                # killall Spotlight 2>/dev/null || true
                # :
                ;;
            "Remote_Management_Menu_Bar")
                # Only show warning if sudo credentials aren't cached
                if ! sudo -n true 2>/dev/null; then
                    echo "📝 This requires sudo privileges. Please type your admin password, then press enter."
                fi
                if sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist LoadRemoteManagementMenuExtra -bool false; then
                    :
                else
                    echo "⚠️ ${BO}Could not reset Remote Management Menu Bar icon.${NC}"
                fi
                ;;
            "DisableSendReadReceiptsIniMessage")
                defaults write com.apple.imagent Setting.EnableReadReceipts -bool true
                defaults write com.apple.imagent Setting.GlobalReadReceiptsVersionID -int 1
                ;;
            "DisableCertainShareExtensions")
                # Handle Share Extensions
                local extensions=(
                    # Items that exist on all macOS versions supported
                    "com.apple.share.System.add-to-safari-reading-list"
                    # "com.apple.CloudSharingUI.CopyLink"    # keep as is
                    "com.apple.Notes.SharingExtension"
                    "com.apple.share.System.add-to-iphoto"
                    "com.apple.news.openinnews"
                    "com.apple.reminders.sharingextension"
                    "com.apple.iBooksX.SharingExtension"
                    # "com.apple.CloudSharingUI.CreateiCloudLinkExtension"    # keep as is
                )
                # Version-specific additions
                # if [[ "$MACOS_MAJOR" -ge 12 ]]; then
                #     # Monterey+
                #     extensions+=(
                #         # "com.apple.shortcuts.Run-Workflow"    # Shortcuts app exists, not in Share menu until 13
                #     )
                # fi
                if [[ "$MACOS_MAJOR" -ge 13 ]]; then
                    # Ventura+
                    extensions+=(
                        "com.apple.shortcuts.Run-Workflow"    # Now appears in Share Menu
                        "com.apple.freeform.sharingextension"    # Freeform added
                    )
                fi
                if [[ "$MACOS_MAJOR" -ge 26 ]]; then
                    # Tahoe+
                    extensions+=(
                        "com.apple.journal.JournalShareExtension"    # Journal added
                    )
                fi
                
                # Enable each extension
                for ext in "${extensions[@]}"; do
                    # echo "Enabling: $ext"
                    # pluginkit -e default -i "$ext"
                    pluginkit -e use -i "$ext"
                done
                # Also enable Contact Suggestions via the plist
                if [[ "$MACOS_MAJOR" -ge 13 ]]; then
                    defaults write com.apple.Sharing SharingPeopleSuggestionsDisabled -bool false
                    # echo "Share extensions enabled successfully"
                fi
                ;;
            "KeyboardFunctionKey")
                defaults write com.apple.HIToolbox AppleFnUsageType -int 3
                defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool true
                ;;
            "NewArchiveUtilityDictIn26_4")
                defaults write "$domain" "$key" -dict "Selection" "UseSameFolder"
                ;;
            "UseBrightBoldInTerminal")
                default_profile=$(defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null)
                startup_profile=$(defaults read com.apple.Terminal "Startup Window Settings" 2>/dev/null)
                profiles_to_update=()
                [[ -n "$default_profile" ]] && profiles_to_update+=("$default_profile")
                [[ -n "$startup_profile" && "$startup_profile" != "$default_profile" ]] && profiles_to_update+=("$startup_profile")

                if [[ "$reset_val" == "reset" ]]; then
                    bool_val="false"
                fi

                failed=false
                for profile in "${profiles_to_update[@]}"; do
                    /usr/libexec/PlistBuddy -c "Set :'Window Settings':'$profile':UseBrightBold bool $bool_val" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null
                    result=$(/usr/libexec/PlistBuddy -c "Print :'Window Settings':'$profile':UseBrightBold" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null)
                    [[ "$result" != "$bool_val" ]] && failed=true
                done

                [[ "$failed" == "true" ]] && return 1
                ;;
            "chflags")
                if [[ "$key" == "ShowLibrary" ]]; then
                    chflags hidden ~/Library 2>/dev/null || true
                fi
                ;;
            "ListViewColumns")
                # Handle ListViewColumns settings reset - delete columns from all locations
                local plist_file="$domain"
                set_list_view_columns "$plist_file" ":ICloudViewSettings" "delete"
                set_list_view_columns "$plist_file" ":StandardViewSettings" "delete"
                set_list_view_columns "$plist_file" ":FK_StandardViewSettings" "delete"
                
                # Clear the .DS_Store files
                # sudo rm /.DS_Store
                # find ~ -name .DS_Store -type f -delete

                # Refresh cfprefsd & Finder to reflect Finder plist changes
                # killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                sleep 1
                ;;
            "Remove_All_DS_Store_Files")
                echo
                echo "${BO}Please enter password if prompted, as this requires sudo privileges${NC}"
                echo "${GY}This can take 10-30 seconds to find all '.DS_Store' files${NC}"
                sudo find / -name ".DS_Store" -type f -delete 2>/dev/null
                echo
                echo "✅ ${GR}Done${NC}"
                # DS_Store_result=$?
                # if [[ $DS_Store_result == "0" ]]; then
                #     echo "✅ ${GR}Done${NC}"
                # else
                #     echo "✅ ${GR}Done${NC}"
                # fi
                echo "${BO}=== Go ahead and set your preferences now ===${NC}"
                sleep 1
                echo
                ;;
            "IconView_variousSettings")
                # Handle IconView settings reset across Finder, Save Dialogs, and iCloud
                local plist_file="$domain"
                local setting_path="$key"
                local setting_name="${setting_path##*:}"
                
                local plist_paths=(
                    ":StandardViewSettings:IconViewSettings:${setting_name}"
                    ":FK_StandardViewSettings:IconViewSettings:${setting_name}"
                    ":ICloudViewSettings:IconViewSettings:${setting_name}"
                )
                
                local plist_type="string"
                case "$setting_name" in
                    showItemInfo|labelOnBottom)
                        plist_type="bool"
                        ;;
                    arrangeBy)
                        plist_type="string"
                        ;;
                    textSize|iconSize|gridSpacing)
                        plist_type="real"
                        ;;
                esac
                
                for plist_path in "${plist_paths[@]}"; do
                    /usr/libexec/PlistBuddy -c "Set $plist_path $reset_val" "$plist_file" 2>/dev/null || \
                    /usr/libexec/PlistBuddy -c "Add $plist_path $plist_type $reset_val" "$plist_file" 2>/dev/null || true
                done
                killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                sleep 1
                ;;
            "ListView_calculateAllSizes")
                # Handle ListView settings reset across all Finder/iCloud/Trash list views
                local plist_file="$domain"
                local plist_paths=(
                    ":ICloudViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":ICloudViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_iCloudListViewSettingsV2:calculateAllSizes"
                    ":StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":StandardViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_DefaultListViewSettingsV2:calculateAllSizes"
                    ":FK_StandardViewSettings:ListViewSettings:calculateAllSizes"
                    ":FK_StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":TrashViewSettings:ExtendedListViewSettingsV2:calculateAllSizes"
                    ":TrashViewSettings:ListViewSettings:calculateAllSizes"
                )
                
                for plist_path in "${plist_paths[@]}"; do
                    /usr/libexec/PlistBuddy -c "Set $plist_path $reset_val" "$plist_file" 2>/dev/null || \
                    /usr/libexec/PlistBuddy -c "Add $plist_path bool $reset_val" "$plist_file" 2>/dev/null || true
                done
                
                # Clear the .DS_Store files
                # sudo rm /.DS_Store
                # find ~ -name .DS_Store -type f -delete

                # Refresh cfprefsd & Finder to reflect Finder plist changes
                killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                sleep 1
                ;;
            "Desktop_IconView_showItemInfo"|"Desktop_IconView_labelOnBottom"|"Desktop_IconView_arrangeBy"|"Desktop_IconView_textSize"|"Desktop_IconView_iconSize"|"Desktop_IconView_gridSpacing")
                # Handle Desktop IconView settings reset using PlistBuddy
                local plist_file="$domain"
                local plist_path="$key"
                local plist_type="string"
                case "$handler" in
                    Desktop_IconView_showItemInfo|Desktop_IconView_labelOnBottom)
                        plist_type="bool"
                        ;;
                    Desktop_IconView_arrangeBy)
                        plist_type="string"
                        ;;
                    Desktop_IconView_textSize|Desktop_IconView_iconSize|Desktop_IconView_gridSpacing)
                        plist_type="real"
                        ;;
                esac

                /usr/libexec/PlistBuddy -c "Set $plist_path $reset_val" "$plist_file" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Add $plist_path $plist_type $reset_val" "$plist_file" 2>/dev/null || true
                
                # Clear the .DS_Store files
                # sudo rm /.DS_Store
                # find ~ -name .DS_Store -type f -delete

                # Refresh cfprefsd & Finder to reflect Finder plist changes
                killall cfprefsd 2>/dev/null || true
                killall Finder 2>/dev/null || true
                sleep 1
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
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                    # killall cfprefsd 2>/dev/null || true
                fi
                killall Finder 2>/dev/null || true
                echo "${YE}Restarted Finder...${NC}"
                ;;
            "com.apple.bird")
                killall Finder 2>/dev/null || true
                echo "${YE}Restarted Finder...${NC}"
                ;;
            "com.apple.screencapture")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                ;;
            "com.apple.controlcenter")
                if [[ "$domain" == "com.apple.Spotlight" ]]; then
                    killall Spotlight 2>/dev/null || true
                    echo "${YE}Restarted Spotlight...${NC}"
                # elif [[ "$key" == "Siri" ]]; then
                #     killall Siri 2>/dev/null || true
                # elif [[ "$key" == "Weather" ]]; then
                #     killall weatherd 2>/dev/null || true
                #     killall WeatherMenu 2>/dev/null || true
                fi
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter...${NC}"
                ;;
            "com.apple.WindowManager")
                killall WindowManager 2>/dev/null || true
                echo "${YE}Restarted WindowManager...${NC}"
                ;;
            "com.apple.menuextra.clock")
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter...${NC}"
                ;;
            "com.apple.Accessibility")
                killall UniversalAccessApp 2>/dev/null || true
                killall universalaccessd 2>/dev/null || true
                if [[ "$handler" == "ReduceMotion" ]]; then
                    killall Spotlight 2>/dev/null || true
                    killall corespotlightd 2>/dev/null || true
                    killall spotlightknowledged 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                    killall ControlCenter 2>/dev/null || true
                    killall WindowServer 2>/dev/null || true
                    killall Dock 2>/dev/null || true
                    killall cfprefsd 2>/dev/null || true
                fi
                echo "${YE}Restarted Services...${NC}"
                # echo "👤 ${BO}Note: Please log out for this to take effect.${NC}"
                ;;
            "com.apple.universalaccess")
                killall UniversalAccessApp 2>/dev/null || true
                killall universalaccessd 2>/dev/null || true
                # killall UniversalAccessAuthWarning 2>/dev/null || true
                # killall "System Preferences" 2>/dev/null
                if [[ "$handler" == "ReduceTransparency" ]]; then
                    killall Dock 2>/dev/null || true
                    killall SystemUIServer 2>/dev/null || true
                    killall ControlCenter 2>/dev/null || true
                    killall Finder 2>/dev/null || true
                    killall cfprefsd 2>/dev/null || true
                fi
                echo "${YE}Restarted Services...${NC}"
                ;;
            "com.apple.systemuiserver")
                # killall ControlCenter 2>/dev/null || true
                killall SystemUIServer 2>/dev/null || true
                ;;
            "com.apple.universalcontrol")
                if [[ "$key" == "Spotlight" ]]; then
                    killall Spotlight 2>/dev/null || true
                    echo "${YE}Restarted Spotlight...${NC}"
                fi
                killall SystemUIServer 2>/dev/null || true
                echo "${YE}Restarted SystemUIServer...${NC}"
                killall ControlCenter 2>/dev/null || true
                echo "${YE}Restarted ControlCenter...${NC}"
                ;;
            "NSGlobalDomain")
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall Finder 2>/dev/null || true
                    echo "${YE}Restarted Finder...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                    # killall cfprefsd 2>/dev/null || true 
                else
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                fi
                ;;
            "DisableSpotlightRelatedContent")
                killall Spotlight 2>/dev/null || true
                echo "${YE}Restarted Spotlight...${NC}"
                ;;
            "com.apple.Safari")
                killall Safari 2>/dev/null || true
                echo "${YE}Restarted Safari...${NC}"
                ;;
            "com.apple.MobileSMS")
                killall Messages 2>/dev/null || true
                echo "${YE}Restarted Messages...${NC}"
                killall imagent 2>/dev/null || true
                echo "${YE}Restarted imagent...${NC}"
                ;;
            "com.apple.imagent")
                killall Messages 2>/dev/null || true
                echo "${YE}Restarted Messages...${NC}"
                killall imagent 2>/dev/null || true
                echo "${YE}Restarted imagent...${NC}"
                ;;
            "com.apple.Passwords")
                killall Passwords 2>/dev/null || true
                echo "${YE}Restarted Passwords...${NC}"
                killall PasswordsMenuBarExtra 2>/dev/null || true
                echo "${YE}Restarted PasswordsMenuBarExtra...${NC}"
                ;;
            "com.apple.TextEdit")
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                    # killall cfprefsd 2>/dev/null || true
                fi
                killall TextEdit 2>/dev/null || true
                echo "${YE}Restarted TextEdit...${NC}"
                ;;
            "com.apple.SocialLayer")
                killall sociallayerd 2>/dev/null || true
                echo "${YE}Restarted SocialLayer...${NC}"
                ;;
            "com.apple.archiveutility")
                killall "Archive Utility" 2>/dev/null || true
                echo "${YE}Restarted Archive Utility...${NC}"
                ;;
            "com.apple.Preview")
                if [[ "$handler" == "KeyboardShortcuts" ]]; then
                    killall UniversalAccessApp 2>/dev/null || true
                    killall universalaccessd 2>/dev/null || true
                    echo "${YE}Restarted UniversalAccess...${NC}"
                    killall SystemUIServer 2>/dev/null || true
                    echo "${YE}Restarted SystemUIServer...${NC}"
                fi
                killall Preview 2>/dev/null || true
                echo "${YE}Restarted Preview...${NC}"
                ;;
            "com.apple.Terminal")
                echo "${BO}Please quit Terminal.app for changes to take effect...${NC}"
                read -r -t 1 -n 1
                # killall Terminal 2>/dev/null || true
                # echo "${YE}Restarted Terminal...${NC}"
                ;;
        esac
        
        # echo "${GR}✅ Reset back to default${NC}"
        # sleep 0.5
    }

    # Loop 1 - Show Info
    while true; do
        trap 'return' SIGINT
        resize_terminal 110 30
        clear
        display_macos_preferences_header
        echo "${GR}"
        echo_centered "This function allows you to view & change over 260 macOS preferences!"
        echo_centered "Some of which can only be done using terminal commands."
        echo "${NC}"
        echo_centered "Simply choose a category > preference > action."
        echo_centered "Actions include ${GR}Activate${NC}, ${RE}Deactivate${NC} or ${GY}Reset to Default${NC}"
        echo "${GR}"
        echo_centered "Preferences that are incompatible with your system will be${NC} ${GY}greyed out${NC}${GR}."
        echo_centered "These can also be hidden via Settings > Manage Preferences > 'Hide incompatible prefs...'"
        # echo "${NC}${GR}"
        # echo_centered "You can also skip back or forward through preferences & categories"
        # echo_centered "by using the${NC} ${BL}A${NC}${GR} or ${BL}Z${NC} ${GR}keys${NC}"
        echo "${NC}"
        echo_centered "${BO}For best results, please QUIT all other open applications${NC}"
        # echo
        echo_centered "───────────────────────────────────────────────────────────────────────────────────" 
        echo_centered "${YE}Note:${NC} ${YE}Terminal may request access to other apps to check current preference states.${NC}"
        echo_centered "${GY}This is required to display the current states of the following apps:${NC}"
        echo_centered "${BO}Music, Preview, QuickTime & TextEdit${NC}"
        echo
        echo_centered "${GY}Additionally, Terminal requires Full Disk Access to read/write preferences for:${NC}"
        echo_centered "${BO}Accessibility, Archive Utility, Messages & Safari${NC}"
        echo_centered "───────────────────────────────────────────────────────────────────────────────────"
        echo_centered "${GY}Some changes may require logging out or restarting to take effect.${NC}"
        # show_nav_prompt_for_categories_centered
        show_nav_prompt_with_AZ_centered
        echo_n_centered "➡️  ${GR}Press Enter to continue (or ${BL}nav${NC} ${GR}choice):${NC} "
        read -r input
        handle_navigation_input "$input"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then 
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            break
        elif [[ $nav -eq $NAV_REFRESH ]]; then 
            continue 
        elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
            return
        fi

        full_disk_access=$(test -r "$HOME/Library/Mail" > /dev/null 2>&1 && echo "true" || echo "false")
        
        if [[ "$full_disk_access" == "false" ]]; then
            while true; do
                trap - SIGINT
                interrupted=false
                trap 'echo; echo_n_centered "🛑 ${RE}Interrupted.${NC} Press Enter to go back a step: "; interrupted=true; continue 2' SIGINT
                resize_terminal 110 30
                # Function to test if Terminal has Full Disk Access
                has_full_disk_access() {
                    # Example: reading ~/Library/Mail requires FDA
                    test -r "$HOME/Library/Mail"

                }
                
                clear
                display_macos_preferences_header
                echo
                echo_centered "⚠️  ${BO}${YE}Full Disk Access not granted.${NC}"    
                echo
                echo_centered "${GY}This is required to read/write some preferences.${NC}"
                echo
                echo_centered "${GR}Would you like to grant Terminal full disk access now?${NC}"
                echo
                echo
                echo_centered "${BO}Choose an option:${NC}"
                echo
                echo_centered "1) ${GR}Yes${NC} (Open System Settings for me)"
                if [[ "$DisableTerminalResizing_Horizonal" == "true" ]]; then
                    echo "2) ${RE}No${NC}  (Continue anyway)"
                else
                    echo "                                     2) ${RE}No${NC}  (Continue anyway)"
                fi
                echo
                show_nav_prompt_with_AZ_centered
                echo_n_centered "➡️  ${GR}Select 1 or 2 (or ${BL}nav${NC} ${GR}choice):${NC} "
                read -r input
                handle_navigation_input "$input"
                nav=$?
                if [[ $nav -eq $NAV_QUIT ]]; then 
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    continue 2
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue 
                elif handle_main_menu_AZ_navigation_input "$input" "$main_menu_choice"; then
                    return
                fi

                case $input in
                    1)
                        # Close System Preferences/Settings first before opening it again
                        # echo
                        # echo "🚪 ${GR}Quitting System Preferences/Settings...${NC}"
                        # osascript -e 'tell application "System Preferences" to quit'
                        # sleep 1

                        # echo "${GR}Openning System Preferences/Settings...${NC}"
                        echo
                        # prompt to allow Terminal Full Disk Access
                        open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

                        # Wait until Terminal is granted Full Disk Access

                        # Wait until Terminal is granted Full Disk Access
                        max_wait_seconds=60  # e.g. 2 minutes
                        start_time=$(date +%s)

                        # echo "🔑 ${GR}Waiting (up to ${max_wait_seconds}s) for Terminal to have Full Disk Access...${NC}"
                        echo_centered "🔑 ${GR}Waiting for Terminal to have Full Disk Access...${NC}"

                        while ! has_full_disk_access; do
                            current_time=$(date +%s)
                            elapsed=$(( current_time - start_time ))
                            if [ "$elapsed" -ge "$max_wait_seconds" ]; then
                                echo
                                echo_centered "⏱️  ${YE}Timeout waiting for Full Disk Access. Continuing without it.${NC}"
                                break
                            fi
                            read -r -t 2 -n 1
                        done

                        if has_full_disk_access; then
                            full_disk_access=true
                            echo
                            echo_centered "✅ ${GR}Terminal has Full Disk Access.${NC}"
                        else
                            full_disk_access=false
                        fi

                        # echo "🔑 ${GR}Waiting until Terminal has Full Disk Access...${NC}"

                        # until has_full_disk_access; do
                        #     sleep 0.5
                        # done

                        # full_disk_access=true

                        # echo
                        # echo "✅ ${GR}Terminal has Full Disk Access.${NC}"

                        # echo "🚪 ${GR}Quitting System Preferences/Settings...${NC}"

                        osascript -e 'tell application "System Preferences" to quit'
                        # echo
                        # echo "✅ ${BO}Ready${NC}"
                        read -r -t 1 -n 1
                        break
                        ;;
                    2)
                        # full_disk_access=false
                        # echo
                        # echo "❌ ${RE}Skipping${NC} "
                        # read -r -t 1 -n 1
                        break
                        ;;
                    *)
                        # echo
                        echo_n_centered "❌ ${RE}Invalid choice.${NC} "
                        read -r -t 1 -n 1
                        continue
                        ;;
                esac
            done            
        fi
        
        # Loop 2 - Pick a category (or View All using '0')
        while true; do
            trap - SIGINT
            interrupted=false
            trap 'echo; echo_n_centered "🛑 ${RE}Interrupted.${NC} Press Enter to go back a step: "; interrupted=true; break' SIGINT
            resize_terminal 110 30
            clear
            # full_disk_access=$(test -r "$HOME/Library/Mail" > /dev/null 2>&1 && echo "true" || echo "false")
            display_macos_preferences_header
            # echo_centered "$system_info_for_display"
            echo
            echo_centered "${BO}Select a preference category:${NC}"
            echo
            # Total number of category menu items (including "Show All" option)
            local total_category_menu_items=42
            # Total number of actual categories (excluding "Show All")
            local total_categories=$((total_category_menu_items - 1))
            
            # Function to get menu item by index (simulates array access)
            # Contains only the array categories
            get_preference_categories() {
                local index=$1
                case $index in
                    0) echo " 1) 🆕 ${CY}NEW for${NC} ${BL}macOS Tahoe 26${NC}" ;;
                    1) echo " 2) 🖱️  ${CY}Mouse${NC}" ;;
                    2) echo " 3) 💻 ${CY}TrackPad${NC}" ;;
                    3) echo " 4) ⌨️  ${CY}Keyboard${NC}" ;;
                    4) echo " 5) ⌨️  ${CY}Keyboard Shortcuts${NC}" ;;
                    5) echo " 6) 💾 ${CY}Disks${NC}" ;;
                    6) echo " 7) ⚓️ ${CY}Dock${NC}" ;;
                    7) echo " 8) ⛶  ${CY}Hot Corners${NC}" ;;
                    8) echo " 9) 🖥️  ${CY}Desktop, Widgets & Views${NC}" ;;
                    9) echo "10) ⚙️  ${CY}System & UI${NC}" ;;
                    10) echo "11) 🪟 ${CY}Window Tiling${NC}" ;;
                    11) echo "12) 🕹️  ${CY}Mission Control & Spaces${NC}" ;;
                    12) echo "13) ✨ ${CY}Appearance${NC}" ;;
                    13) echo "14) 🪄 ${CY}Animations${NC}" ;;
                    14) echo "15) 📋 ${CY}Finder List View Options${NC}" ;;
                    15) echo "16) 📁 ${CY}Finder Icon View Options${NC}" ;;
                    16) echo "17) 📁 ${CY}Finder${NC}" ;;
                    17) echo "18) ♿️ ${CY}Accessibility - Zoom${NC}" ;;
                    18) echo "19) 📋 ${CY}Menu Bar${NC}" ;;
                    19) echo "20) 📋 ${CY}Menu Bar - For Laptops${NC}" ;;
                    20) echo "21) 📶 ${CY}Connectivity${NC}" ;;
                    21) echo "22) 🔍 ${CY}Spotlight${NC}" ;;
                    22) echo "23) 🔄 ${CY}Automatic Updates${NC}" ;;
                    23) echo "24) 🤖 ${CY}Apple Intelligence${NC}" ;;
                    24) echo "25) 🔑 ${CY}Passwords & AutoFill${NC}" ;;
                    25) echo "26) 📝 ${CY}TextEdit${NC}" ;;
                    26) echo "27) 👾 ${CY}Terminal${NC}" ;;
                    27) echo "28) 📅 ${CY}Calendar${NC}" ;;
                    28) echo "29) 💬 ${CY}Messages${NC}" ;;
                    29) echo "30) 🔎 ${CY}Preview${NC}" ;;
                    30) echo "31) 📞 ${CY}Phone${NC}" ;;
                    31) echo "32) 🎵 ${CY}Music${NC}" ;;
                    32) echo "33) 🗜️  ${CY}Archive Utility${NC}" ;;
                    33) echo "34) 📸 ${CY}Screen Capture${NC}" ;;
                    34) echo "35) 🎥 ${CY}QuickTime Player${NC}" ;;
                    35) echo "36) 🌐 ${CY}Safari - General${NC}" ;;
                    36) echo "37) 🌐 ${CY}Safari - Tabs${NC}" ;;
                    37) echo "38) 🌐 ${CY}Safari - AutoFill${NC}" ;;
                    38) echo "39) 🌐 ${CY}Safari - Search${NC}" ;;
                    39) echo "40) 🌐 ${CY}Safari - Security${NC}" ;;
                    40) echo "41) 🌐 ${CY}Safari - Advanced${NC}";;
                    41) echo " 0) 📋 ${CY}Show All Preferences${NC}" ;;
                    *) echo "" ;;
                esac
            }

            # Simple three-column layout (bash 3.2 compatible)
            # update num_items as needed
            display_three_column_preference_categories() {
                local num_items=$total_category_menu_items
                local items_per_col=$(( (num_items + 2) / 3 ))  # Ceiling division: (40+2)/3 = 14
                # change width between columns here
                local col2_start=37
                local col3_start=75
                
                for ((i=0; i<items_per_col; i++)); do
                    local col1_index=$i
                    local col2_index=$((i + items_per_col))
                    local col3_index=$((i + items_per_col * 2))
                    
                    local col1_item=""
                    local col2_item=""
                    local col3_item=""
                    
                    # Get column 1 item
                    if [[ $col1_index -lt $num_items ]]; then
                        col1_item=$(get_preference_categories $col1_index)
                    fi
                    
                    # Get column 2 item
                    if [[ $col2_index -lt $num_items ]]; then
                        col2_item=$(get_preference_categories $col2_index)
                    fi
                    
                    # Get column 3 item
                    if [[ $col3_index -lt $num_items ]]; then
                        col3_item=$(get_preference_categories $col3_index)
                    fi
                    
                    # Print column 1
                    printf "%s" " $col1_item"
                    
                    # Move to column 2 and print
                    if [[ -n "$col2_item" ]]; then
                        printf '\033[%dG' $col2_start
                        printf "%s" "   $col2_item"
                    fi
                    
                    # Move to column 3 and print
                    if [[ -n "$col3_item" ]]; then
                        printf '\033[%dG' $col3_start
                        printf "%s" "   $col3_item"
                    fi
                    
                    printf "\n"
                done
            }

            display_three_column_preference_categories
            echo
            show_nav_prompt_for_categories_centered
            echo_n_centered "➡️  ${GR}Enter your choice (or ${BL}nav${NC} ${GR}choice):${NC} "
            read -r cat_choice
            handle_navigation_input "$cat_choice"
            nav=$?
            if   [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                break
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue 
            fi

            # Navigate to previous/next category
            case "$cat_choice" in
                a|A) cat_choice=41 ;;
                z|Z) cat_choice=1 ;;
            esac

            # Initialize caching flag
            local use_caching=false
            
            # Save cat_choice to a persistent variable for display purposes
            selected_category_choice="$cat_choice"
            
            case $cat_choice in
                0) 
                    # Show all preferences - restore full array and use caching
                    preference_commands=("${original_preference_commands_full[@]}")
                    use_caching=true
                    # Continue to display loop below
                    ;;
                1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31|32|33|34|35|36|37|38|39|40|41)
                    # Filter preferences by category - skip caching for faster display
                    preference_commands=()
                    while IFS= read -r line; do
                        [[ -n "$line" ]] && preference_commands+=("$line")
                    done < <(filter_preferences_by_category "$cat_choice")
                    use_caching=false
                    # Continue to display loop below
                    ;;
                *) 
                    echo_n_centered "❌ ${RE}Invalid choice.${NC} Please try again. "
                    read -r -t 1 -n 1
                    continue
                    ;;
            esac

            # Build global navigation arrays from the full preferences list (once)
            if [[ ${#global_pref_indices[@]} -eq 0 ]]; then
                global_pref_indices=()
                global_pref_groups=()
                global_pref_groups_subtext=()
                local g_idx
                local g_pref
                local g_group_title
                local g_group_subtext
                local g_current_group=""
                local g_current_group_subtext=""

                for g_idx in "${!original_preference_commands_full[@]}"; do
                    g_pref="${original_preference_commands_full[$g_idx]}"
                    # Handle group headers (format: GROUP|Title|Subtext)
                    if [[ "$g_pref" == GROUP\|* ]]; then
                        IFS='|' read -r _ g_group_title g_group_subtext <<< "$g_pref"
                        g_current_group="$g_group_title"
                        g_current_group_subtext="$g_group_subtext"
                        continue
                    fi

                    global_pref_indices+=("$g_idx")
                    global_pref_groups+=("$g_current_group")
                    global_pref_groups_subtext+=("$g_current_group_subtext")
                done

                global_pref_max_choice=${#global_pref_indices[@]}
            fi

            # Loop 3 - Display all preferences with current state
            while true; do
                full_disk_access=$(test -r "$HOME/Library/Mail" > /dev/null 2>&1 && echo "true" || echo "false")

                # echo "Display all preferences with current state (Loop 2)"
                if [[ "$use_caching" == "true" ]]; then
                    trap - SIGINT
                    interrupted=false
                    trap 'interrupted=true; break' SIGINT
                    resize_terminal 110 30
                    set_terminal_height_to_2200p
                    clear
                    echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                    echo "${BO}0) Show All Preferences${NC}       ${CY}Legend: ✅ ${GR}Active${NC} | ❌ ${RE}Inactive${NC} | ❔ ${GY}Default/Not Set${NC}"
                    echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                    echo_justified "↩ Preference Categories" "Show All Preferences [Cached Display] ↪${NC}" "110"
                    echo
                    if [[ "$HideIncompatible_macOS_Preferences" == "true" ]]; then
                        echo "${GR}Available preferences:${NC}                ${GY}[Incompatible preferences hidden]${NC}"
                    else
                        echo "${GR}Available preferences:${NC}"
                    fi
                else
                    trap - SIGINT
                    interrupted=false
                    trap 'interrupted=true; break' SIGINT
                    resize_terminal 110 30
                    clear

                    local i=1
                    local visible_indices=()
                    local idx
                    local current_group=""
                    # local current_group_subtext=""

                    for idx in "${!preference_commands[@]}"; do
                        local pref="${preference_commands[$idx]}"
                        # Handle group headers (format: GROUP|Title|Subtext)
                        if [[ "$pref" == GROUP\|* ]]; then
                            IFS='|' read -r _ group_title group_subtext <<< "$pref"
                            current_group="$group_title"   # <- track group
                            # current_group_subtext="$group_subtext"   # <- track group's subtext
                            continue
                        fi
                    done

                    echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                    # echo "${BO}$current_group${NC}"
                    # Use selected_category_choice if set, otherwise fall back to cat_choice
                    local display_cat_choice="${selected_category_choice:-$cat_choice}"
                    # local category_position="${BO}[$display_cat_choice/$total_categories]${NC}"
                    local category_position="[$display_cat_choice/$total_categories]"
                    if [[ -n "$group_subtext" ]]; then
                        printf "%-3s %s %s\n" "$category_position" "${BO}$group_title${NC}" "$group_subtext"
                    else
                        printf "%-3s %s\n" "$category_position" "${BO}$group_title${NC}"
                    fi
                    echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                    echo "↩ Preference categories       ${CY}Legend: ✅ ${GR}Active${NC} | ❌ ${RE}Inactive${NC} | ❔ ${GY}Default/Not Set${NC}        Preference Actions ↪"
                    echo
                    if [[ "$HideIncompatible_macOS_Preferences" == "true" ]]; then
                        echo "${GR}Available preferences:${NC}                ${GY}[Incompatible preferences hidden]${NC}"
                    else
                        echo "${GR}Available preferences:${NC}"
                    fi
                fi

                local i=1
                local visible_indices=()
                local preference_states=()  # Cache the states for fast mode
                local idx
                local current_group=""
                local current_group_subtext=""

                for idx in "${!preference_commands[@]}"; do
                    local pref="${preference_commands[$idx]}"
                    # Handle group headers (format: GROUP|Title|Subtext)
                    if [[ "$pref" == GROUP\|* ]]; then
                        IFS='|' read -r _ group_title group_subtext <<< "$pref"
                        current_group="$group_title"   # <- track group
                        current_group_subtext="$group_subtext"   # <- track group's subtext
                        echo
                        # echo "${BO}$group_title${NC}"
                        if [[ -n "$group_subtext" ]]; then
                            echo "${BO}$group_title${NC} $group_subtext"
                        else
                            echo "${BO}$group_title${NC}"
                        fi
                        continue
                    fi

                    IFS='|' read -r name domain key active_val inactive_val reset_val handler notes <<< "$pref"

                    # Get FRESH state (this is the slow part)
                    local current_state=$(get_preference_current_state "$domain" "$key" "$handler" "$active_val" "$inactive_val")
                    preference_states[$((i-1))]="$current_state"  # Cache it

                    local status_icon="❔ ${GY}[Default/Not Set]${NC}"
                    if [[ "$current_state" == "active" ]]; then
                        status_icon="✅ ${GR}[Active]${NC}"
                    elif [[ "$current_state" == "inactive" ]]; then
                        status_icon="❌ ${RE}[Inactive]${NC}"
                    fi

                    printf "%2d) %s %s\n" "$i" "$name" "$status_icon"
                    visible_indices[$((i-1))]="$idx"
                    visible_groups[$((i-1))]="$current_group"   # store group title
                    visible_groups_subtext[$((i-1))]="$current_group_subtext"   # store group subtext
                    ((i++))
                done
                
                # Conditional caching based on use_caching flag
                if [[ "$use_caching" == "true" ]]; then
                    # Show all: Use caching step for better performance with large array
                    show_nav_prompt_not_centered
                    echo -e "➡️  ${GR}Press Enter to first cache results (or ${BL}nav${NC} ${GR}choice):${NC}"
                    echo -e "   ${GY}This allows for faster loading time at the next step.${NC}"
                    echo -e "   ${GY}Come back here to refresh at any time by pressing 'b'.${NC}"

                    # Check if interrupted before showing caching prompt
                    if [[ "$interrupted" == "true" ]]; then
                        echo
                        echo "🛑 ${RE}Interrupted.${NC}"
                        echo "   Press B + Enter to go back a step."
                        echo "   or Press Enter to continue (with limited selections)."
                        echo "   ${GY}Note that preferences greater than${NC} ${BO}$(($i-1))${NC} ${GY}will not be selectable in the cached display now,"
                        echo "   however, you can select option${NC} ${BO}$(($i-1))${NC} ${GY}and then use the A/Z keys to see preferences beyond this${NC} 👍 "
                    fi

                    read -rp "" choice
                    handle_navigation_input "$choice"
                    nav=$?
                    if   [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue 
                    fi
                fi
                
                # else
                #     :
                    # Category selection: Skip caching step, go directly to fast mode
                    # preference_states array is already populated from the display above
                # fi

                # Loop 4 - Fast Mode - Uses cached states if user chooses '0' to display all prefs
                while true; do
                    if [[ "$use_caching" == "true" ]]; then
                        trap - SIGINT
                        interrupted=false
                        full_disk_access=$(test -r "$HOME/Library/Mail" > /dev/null 2>&1 && echo "true" || echo "false")
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back a step: "; interrupted=true; break' SIGINT
                        resize_terminal 110 30  # re-position if coming back from Settings
                        set_terminal_height_to_2200p  # re-position if coming back from Settings
                        clear
                        # echo "Fast Mode (Loop 3) - Uses cached states"
                        echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "${BO}0) Show All Preferences${NC}       ${CY}Legend: ✅ ${GR}Active${NC} | ❌ ${RE}Inactive${NC} | ❔ ${GY}Default/Not Set${NC}      ${BK}🔒 ${RE}[Cached Display]${NC}"
                        echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "↩ Show All Preferences [Uncached Display]" "Preference Actions ↪${NC}" "110"
                        echo
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
                                    echo "${BO}$group_title${NC} ${BK}🔒 ${RE}[Cached]${NC} $group_subtext"
                                else
                                    echo "${BO}$group_title${NC} ${BK}🔒 ${RE}[Cached]${NC}"
                                fi
                                continue
                            fi
                            
                            IFS='|' read -r name domain key active_val inactive_val reset_val handler notes <<< "$pref"
                            
                            # Use CACHED state (no fresh calls)
                            local cached_state="${preference_states[$((display_i-1))]}"
                            local status_icon="❔ ${GY}[Default/Not Set]${NC}"
                            if [[ "$cached_state" == "active" ]]; then
                                status_icon="✅ ${GR}[Active]${NC}"
                            elif [[ "$cached_state" == "inactive" ]]; then
                                status_icon="❌ ${RE}[Inactive]${NC}"
                            fi
                            
                            printf "%2d) %s %s\n" "$display_i" "$name" "$status_icon"
                            ((display_i++))
                        done
                    fi

                    # echo "Main Choice Selection (Loop 4)"
                    local max_choice=${#visible_indices[@]}

                    if [[ "$use_caching" == "true" ]]; then
                        echo
                        echo -e "🔒 ${RE}Displaying cached results${NC} ${BO}[Press${NC} ${GR}B ${NC}${BO}to refresh]${NC}"
                        echo -e "   ${GY}(Updated statuses will always be shown in the next or previous section)${NC}"
                        show_nav_prompt_not_centered
                    else
                        show_nav_prompt_for_categories_not_centered
                        # Check if interrupted before showing caching prompt
                        if [[ "$interrupted" == "true" ]]; then
                            echo "🛑 ${RE}Interrupted.${NC}"
                            echo "   Press B + Enter to go back a step."
                            echo "   or Press Enter to continue (with limited selections)."
                            echo "   ${GY}Note that preferences greater than${NC} ${BO}$(($i-1))${NC} ${GY}will not be selectable here,"
                            echo "   however, you can select option${NC} ${BO}$(($i-1))${NC} ${GY}and then use the A/Z keys to see preferences beyond this${NC} 👍 "
                            echo
                        fi

                        trap - SIGINT
                        interrupted=false
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back a step: "; interrupted=true; break 2' SIGINT
                    fi

                    read -rp "➡️  ${GR}Select a preference${NC} (1-$max_choice) ${GR}(or ${BL}nav${NC} ${GR}choice):${NC} " choice

                    # Support group/category-level navigation here:
                    # - In category mode (use_caching == false), 'a'/'z' cycle through categories (1-41) and refresh this view.
                    if [[ "$use_caching" != "true" ]]; then
                        case "$choice" in
                            a|A|z|Z)
                                # Start from the current category choice
                                if [[ "$cat_choice" =~ ^[0-9]+$ ]] && [[ $cat_choice -ge 1 ]] && [[ $cat_choice -le 41 ]]; then
                                    local new_cat="$cat_choice"
                                else
                                    local new_cat=1
                                fi

                                if [[ "$choice" == "a" || "$choice" == "A" ]]; then
                                    ((new_cat--))
                                    if [[ $new_cat -lt 1 ]]; then
                                        new_cat=41
                                    fi
                                else
                                    ((new_cat++))
                                    if [[ $new_cat -gt 41 ]]; then
                                        new_cat=1
                                    fi
                                fi

                                cat_choice="$new_cat"
                                selected_category_choice="$new_cat"

                                # Rebuild the filtered preferences for the new category
                                preference_commands=()
                                while IFS= read -r line; do
                                    [[ -n "$line" ]] && preference_commands+=("$line")
                                done < <(filter_preferences_by_category "$cat_choice")

                                # Restart from the outer display loop with the updated category
                                continue 2
                                ;;
                        esac
                    fi

                    handle_navigation_input "$choice"
                    nav=$?
                    if   [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        if [[ "$use_caching" == "true" ]]; then
                            echo
                            echo "${BO}Refresh all results or back to categories?${NC}"
                            echo " 1) ${RE}Refresh results${NC}"
                            echo " 2) ${CY}Return to categories${NC}"
                            echo " ${GR}⮑${NC}  ${GR}Stay on this page${NC}"
                            echo
                            read -rp "➡️  ${GR}Select option (or ${BL}nav${NC} ${GR}choice):${NC} " returnchoice
                            handle_navigation_input "$returnchoice"
                            nav=$?
                            if   [[ $nav -eq $NAV_QUIT ]]; then
                                return
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                break 2
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            fi

                            case $returnchoice in
                                1) break ;;
                                2) break 2 ;;
                                *) continue ;;
                            esac
                        else
                            break 2
                        fi
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        if [[ "$use_caching" == "true" ]]; then
                            continue
                        else
                            continue 2
                        fi
                    fi

                    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $max_choice ]]; then
                        local arr_idx="${visible_indices[$((choice-1))]}"
                        local current_group="${visible_groups[$((choice-1))]}"   # <- grab group here
                        local current_group_subtext="${visible_groups_subtext[$((choice-1))]}"   # <- grab group's subtext here
                        local selected_pref="${preference_commands[$arr_idx]}"
                        IFS='|' read -r name domain key active_val inactive_val reset_val handler notes <<< "$selected_pref"

                        # Map this selected preference into the global navigation index
                        global_pref_choice_index=-1
                        local gi
                        local global_idx
                        for gi in "${!global_pref_indices[@]}"; do
                            global_idx="${global_pref_indices[$gi]}"
                            if [[ "${original_preference_commands_full[$global_idx]}" == "$selected_pref" ]]; then
                                global_pref_choice_index=$gi
                                break
                            fi
                        done
                        global_pref_max_choice=${#global_pref_indices[@]}
                    else
                        echo -n "❌ ${RE}Invalid choice.${NC} Please choose 1-$max_choice. "
                        read -r -t 1 -n 1
                        if [[ "$use_caching" == "true" ]]; then
                            continue
                        else
                            continue 2
                        fi
                    fi

                    # Loop 5 - Show Individual Preference States/Options
                    while true; do
                        trap - SIGINT
                        interrupted=false
                        full_disk_access=$(test -r "$HOME/Library/Mail" > /dev/null 2>&1 && echo "true" || echo "false")
                        if [[ "$use_caching" == "true" ]]; then
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back a step: "; interrupted=true; break' SIGINT
                        else
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back a step: "; interrupted=true; break 2' SIGINT
                        fi
                        resize_terminal 110 30
                        clear
                        # echo " Main Choice Selection (Loop 5)"
                        echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        if [[ -n "$current_group_subtext" ]]; then
                            echo "${BO}$current_group${NC} $current_group_subtext"
                        else
                            echo "${BO}$current_group${NC}"
                        fi
                        echo "${GR}══════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"

                        # Determine display index for this preference:
                        # - In 'Show All' mode (use_caching == true), keep global numbering
                        # - In category/filtered mode (use_caching == false), show index within the current group
                        local display_choice
                        local group_position=""
                        if [[ "$use_caching" == "true" ]]; then
                            if [[ ${#global_pref_indices[@]} -gt 0 && $global_pref_choice_index -ge 0 ]]; then
                                # Position is the global position in the entire array (1-based)
                                local position_global=$((global_pref_choice_index + 1))
                                # Total is the total number of all preferences (excluding GROUP entries)
                                local total_all_preferences=$global_pref_max_choice
                                group_position="[$position_global/$total_all_preferences]"
                                
                                # For display, keep global numbering
                                display_choice=$position_global
                            else
                                display_choice=$choice
                            fi
                        else
                            if [[ ${#global_pref_indices[@]} -gt 0 && $global_pref_choice_index -ge 0 ]]; then
                                local g="$global_pref_choice_index"
                                local grp_name="${global_pref_groups[$g]}"

                                # Walk backwards to find the first index of this group
                                local first_idx_in_group=$g
                                local j=$g
                                while [[ $j -gt 0 && "${global_pref_groups[$((j-1))]}" == "$grp_name" ]]; do
                                    ((j--))
                                    first_idx_in_group=$j
                                done

                                # Walk forwards to find the last index of this group
                                local last_idx_in_group=$g
                                j=$((g + 1))
                                while [[ $j -lt $global_pref_max_choice && "${global_pref_groups[$j]}" == "$grp_name" ]]; do
                                    last_idx_in_group=$j
                                    ((j++))
                                done

                                # Position within group is (g - first_idx_in_group + 1)
                                display_choice=$((g - first_idx_in_group + 1))
                                # Total count in group is (last_idx_in_group - first_idx_in_group + 1)
                                local total_in_group=$((last_idx_in_group - first_idx_in_group + 1))
                                group_position="[$display_choice/$total_in_group]"
                            else
                                display_choice=$choice
                            fi
                        fi

                        if [[ -n "$group_position" ]]; then
                            printf "%-3s %s %s\n" "$group_position" "$name"
                            # printf "%-3s %s %s\n" "$display_choice)" "$name" "$group_position"
                        else
                            printf "%-3s %s\n" "$display_choice)" "$name"
                        fi
                        echo "${GR}──────────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
                        if [[ -n "$notes" ]]; then
                            echo "$notes"
                        fi
                        echo
                        
                        # Show current state
                        local current_state=$(get_preference_current_state "$domain" "$key" "$handler" "$active_val" "$inactive_val")
                        local current_value=$(get_preference_current_value "$domain" "$key" "$handler")
                        
                        echo "${BO}Current State:${NC} ${GY}(refreshes automatically)${NC}"
                        if [[ "$current_state" == "active" ]]; then
                            echo "  State:  ✅ ${GR}Active${NC}"
                        elif [[ "$current_state" == "inactive" ]]; then
                            echo "  State:  ❌ ${RE}Inactive${NC}"
                        else
                            echo "  State:  ❔ ${GY}Default/Not Set${NC}"
                        fi
                        
                        if [[ -n "$current_value" ]]; then
                            echo "  Value:  $current_value"
                            echo "  Key:    $key"
                            echo "  Domain: $domain"
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

                        echo
                        # Display actions
                        echo "${BO}Available actions:${NC}"
                        echo " 1) ✅ ${GR}Activate${NC} (sets to: "$active_val")"
                        echo " 2) ❌ ${RE}Deactivate${NC} (sets to: "$inactive_val")"
                        if [[ -n "$reset_val" ]]; then
                            echo " 3) 🔄 ${GY}Reset to Default${NC} (sets to: "$reset_val")"
                        fi
                        show_nav_prompt_for_preferences_not_centered
                        read -rp "➡️  ${GR}Select action (or ${BL}nav${NC} ${GR}choice):${NC} " action_choice
                        handle_navigation_input "$action_choice"
                        nav=$?
                        if [[ $nav -eq $NAV_QUIT ]]; then
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            if [[ "$use_caching" == "true" ]]; then
                                set_terminal_height_to_2200p
                                break
                            else
                                break 2
                            fi
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue 
                        fi

                        # Loop 6 - Apply Actions (and then refresh state by breaking back out to Loop 5
                        while true; do
                            case $action_choice in
                                1)
                                    if apply_preference_change "$domain" "$key" "$active_val" "$handler" "active"; then
                                        echo "✅ ${GR}Preference activated successfully!${NC}"
                                        echo "🔄 Refreshing state..."
                                        read -r -t 1 -n 1
                                    else
                                        if [[ "$handler" == "UseBrightBoldInTerminal" ]]; then
                                            echo "❌ ${RE}Failed to activate preference.${NC}"
                                            echo "   ${YE}This cannot be activated while Terminal is in use.${NC}"
                                            echo "   ${YE}Please toggle on manually${NC}"
                                            read -r -t 3 -n 1
                                        else
                                            echo "❌ ${RE}Failed to activate preference.${NC}"
                                            echo "   Please try again..."
                                            read -r -t 1 -n 1
                                        fi
                                    fi
                                    break
                                    ;;
                                2)
                                    if apply_preference_change "$domain" "$key" "$inactive_val" "$handler" "inactive"; then
                                        echo "✅ ${GR}Preference deactivated successfully!${NC}"
                                        echo "🔄 Refreshing state..."
                                        read -r -t 1 -n 1
                                    else
                                        echo "❌ ${RE}Failed to deactivate preference.${NC}"
                                        echo "   Please try again..."
                                        read -r -t 1 -n 1
                                    fi
                                    break
                                    ;;
                                3)
                                    if [[ -n "$reset_val" ]]; then
                                        if reset_preference_to_default "$domain" "$key" "$reset_val" "$handler"; then
                                            echo "✅ ${GR}Preference reset successfully!${NC}"
                                            echo "🔄 Refreshing state..."
                                            read -r -t 1 -n 1
                                        else
                                            echo "❌ ${RE}Failed to reset preference.${NC}"
                                            echo "   Please try again..."
                                            read -r -t 1 -n 1
                                        fi
                                    else
                                        echo -n "❌ ${BO}Reset not available for this preference.${NC} "
                                        read -r -t 1 -n 1
                                    fi
                                    break
                                    ;;
                                a|A)
                                    # Navigate to previous preference (global, group-aware, with wrap)
                                    if [[ ${#global_pref_indices[@]} -eq 0 ]] || [[ $global_pref_choice_index -lt 0 ]]; then
                                        echo -n "❌ ${RE}Navigation is unavailable for this preference.${NC} "
                                        read -r -t 1 -n 1
                                        break
                                    fi

                                    # Move to previous global index with wrap-around
                                    if [[ $global_pref_choice_index -eq 0 ]]; then
                                        global_pref_choice_index=$((global_pref_max_choice - 1))
                                    else
                                        # Determine current group
                                        current_group="${global_pref_groups[$global_pref_choice_index]}"
                                        # current_group_subtext="${global_pref_groups[$global_pref_choice_index]}"
                                        # Look at the previous entry
                                        local prev_idx=$((global_pref_choice_index - 1))
                                        if [[ "${global_pref_groups[$prev_idx]}" == "$current_group" ]]; then
                                            # Same group: just move back one
                                            global_pref_choice_index=$prev_idx
                                        else
                                            # Different group: jump to the LAST preference of the previous group
                                            local prev_group="${global_pref_groups[$prev_idx]}"
                                            local first_idx_in_prev_group=$prev_idx

                                            # Walk backwards to find the first index of prev_group
                                            local j=$prev_idx
                                            while [[ $j -ge 0 && "${global_pref_groups[$j]}" == "$prev_group" ]]; do
                                                first_idx_in_prev_group=$j
                                                ((j--))
                                            done

                                            # Now walk forward from first_idx_in_prev_group to find the last index of prev_group
                                            local last_idx_in_prev_group=$first_idx_in_prev_group
                                            j=$((first_idx_in_prev_group + 1))
                                            while [[ $j -lt $global_pref_max_choice && "${global_pref_groups[$j]}" == "$prev_group" ]]; do
                                                last_idx_in_prev_group=$j
                                                ((j++))
                                            done

                                            global_pref_choice_index=$last_idx_in_prev_group
                                        fi
                                    fi

                                    # Load the new preference from the global arrays
                                    local global_idx="${global_pref_indices[$global_pref_choice_index]}"
                                    selected_pref="${original_preference_commands_full[$global_idx]}"
                                    current_group="${global_pref_groups[$global_pref_choice_index]}"
                                    current_group_subtext="${global_pref_groups_subtext[$global_pref_choice_index]}"
                                    IFS='|' read -r name domain key active_val inactive_val reset_val handler notes <<< "$selected_pref"

                                    # For display purposes, use 1-based global index
                                    choice=$((global_pref_choice_index + 1))
                                    break  # Refresh Loop 5 with new preference
                                    ;;
                                z|Z)
                                    # Navigate to next preference (global, group-aware, with wrap)
                                    if [[ ${#global_pref_indices[@]} -eq 0 ]] || [[ $global_pref_choice_index -lt 0 ]]; then
                                        echo -n "❌ ${RE}Navigation is unavailable for this preference.${NC} "
                                        read -r -t 1 -n 1
                                        break
                                    fi

                                    # Move to next global index with wrap-around
                                    if [[ $global_pref_choice_index -eq $((global_pref_max_choice - 1)) ]]; then
                                        global_pref_choice_index=0
                                    else
                                        # Determine current group
                                        current_group="${global_pref_groups[$global_pref_choice_index]}"
                                        # current_group_subtext="${global_pref_groups[$global_pref_choice_index]}"

                                        # Look at the next entry
                                        local next_idx=$((global_pref_choice_index + 1))
                                        if [[ "${global_pref_groups[$next_idx]}" == "$current_group" ]]; then
                                            # Same group: just move forward one
                                            global_pref_choice_index=$next_idx
                                        else
                                            # Different group: jump to the FIRST preference of the next group
                                            local next_group=""
                                            local j=$next_idx

                                            # Find the first index that belongs to a different group
                                            while [[ $j -lt $global_pref_max_choice ]]; do
                                                if [[ "${global_pref_groups[$j]}" != "$current_group" ]]; then
                                                    next_group="${global_pref_groups[$j]}"
                                                    break
                                                fi
                                                ((j++))
                                            done

                                            if [[ -z "$next_group" ]]; then
                                                # No next group found; wrap to the very first preference
                                                global_pref_choice_index=0
                                            else
                                                # We already have the first index of the next group in j
                                                global_pref_choice_index=$j
                                            fi
                                        fi
                                    fi

                                    # Load the new preference from the global arrays
                                    local global_idx="${global_pref_indices[$global_pref_choice_index]}"
                                    selected_pref="${original_preference_commands_full[$global_idx]}"
                                    current_group="${global_pref_groups[$global_pref_choice_index]}"
                                    current_group_subtext="${global_pref_groups_subtext[$global_pref_choice_index]}"
                                    IFS='|' read -r name domain key active_val inactive_val reset_val handler notes <<< "$selected_pref"

                                    # For display purposes, use 1-based global index
                                    choice=$((global_pref_choice_index + 1))
                                    break  # Refresh Loop 5 with new preference
                                    ;;
                                *)
                                    echo -n "❌ ${RE}Invalid choice.${NC} "
                                    read -r -t 1 -n 1
                                    break
                                    ;;
                            esac
                        done    
                    done
                done    
            done
        done
    done
}
#====8==== 🕹️ Command Center
function command_center() {
    while true; do
        trap - SIGINT
        interrupted=false
        trap 'echo; return' SIGINT
        resize_terminal 95 24
        clear
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "${BO}8) 🕹️  Command Center${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "96"
        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo_justified "↩ Main Menu" "TBD ↪"
        show_nav_prompt_with_AZ_centered
        echo_centered "$system_info_for_display"
        echo
        echo "${BO}Choose an option:${NC}"
        echo " 1) 🛠️  ${GR}Settings${NC}"
        echo " 2) 🛣️  ${GR}Path Picker${NC}"
        echo " 3) 📚 ${GR}Resources${NC}"
        echo " 4) ⬆️  ${GR}Upgrade OneCommand${NC}"
        echo " 5) 🔐 ${GR}Enable Sudo Keep-Alive${NC} $([ -n "$_sudo_keepalive_pid" ] && echo "✅ ${GR}[Active]${NC}" || echo "❌ ${GY}[Inactive]${NC}")"
        echo " 6) 📋 ${GR}Show Command-Line Options${NC}"
        echo
        read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " choice
        if [[ "$choice" == "s" ]] || [[ "$choice" == "S" ]]; then 
            choice="1"
        elif [[ "$choice" == "p" ]] || [[ "$choice" == "P" ]]; then 
            choice="2"
        fi
        handle_navigation_input "$choice"
        nav=$?
        if [[ $nav -eq $NAV_QUIT ]]; then
            return 0
        elif [[ $nav -eq $NAV_BACK ]]; then
            return 0
        elif [[ $nav -eq $NAV_REFRESH ]]; then 
            continue
        elif handle_main_menu_AZ_navigation_input "$choice" "$main_menu_choice"; then
            return
        fi
        # fi

        local came_from_command_center_settings=""
        local came_from_command_center_path_picker=""
        
        case $choice in
            1)
                # Settings
                came_from_command_center_settings=true
                quick_settings
                came_from_command_center_settings=false
                handle_navigation_input "$choice" # handle $choice in settings
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then 
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    continue
                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                    continue
                elif [[ $nav -eq $NAV_CONT ]]; then 
                    continue
                fi
                ;;
            2) 
                came_from_command_center_path_picker=true
                quick_picker
                came_from_command_center_path_picker=false
                came_from_command_center_main_menu=false
                handle_navigation_input "$input" # handle $input in path picker
                nav=$?
                if   [[ $nav -eq $NAV_QUIT ]]; then
                    return 0
                elif [[ $nav -eq $NAV_BACK ]]; then
                    continue
                elif [[ $nav -eq $NAV_REFRESH ]]; then
                    continue
                elif [[ $nav -eq $NAV_CONT ]]; then 
                    continue
                fi
                ;;
            3)
                while true; do
                    trap - SIGINT
                    interrupted=false
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                    clear
                    echo "${GR}════════════${GR}╗${NC}"
                    echo "${BO}📚 Resources${GR}║${NC}"
                    echo "${GR}════════════${GR}╝${NC}"
                    echo_justified "↩ Home [Command Center]" "TBD ↪"
                    show_nav_prompt_centered

                    echo "${BO}Choose an option:${NC}"
                    echo " 1) ℹ️  ${GR}About OneCommand${NC} 🔗 ${GY}Link${NC}"
                    echo " 2) 🔄 ${GR}Check for Updates${NC} 🔗 ${GY}Link${NC}"
                    echo " 3) 📝 ${GR}Release Notes${NC} 🔗 ${GY}Link${NC}"
                    echo " 4) 📧 ${GR}Report a Bug or Request a Feature${NC} 🔗 ${GY}Link${NC}"
                    echo " 5) 🎗️  ${GR}Show Support${NC} 🔗 ${GY}Link${NC}"
                    echo " 6) 📱 ${GR}Recommended macOS Apps${NC}"
                    echo
                    read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        break
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    fi

                    case $choice in
                        1)
                            open https://shop.ryansummer.com/p/onecommand/#oc-introduction
                            ;;
                        2)
                            # Check for updates
                            open https://shop.ryansummer.com/p/onecommand
                            ;;
                        3)
                            # Open Release Notes
                            open https://shop.ryansummer.com/onecommand-lite-release-notes/
                            ;;
                        4)
                            # Report a Bug or Request a Feature
                            open https://shop.ryansummer.com/contact/
                            ;;
                        5)
                            # Show Support
                            open https://www.paypal.com/donate/?hosted_button_id=JE5YDUS7N8QQ2
                            ;;
                        6)
                            # Recommended macOS Apps
                            while true; do
                                trap - SIGINT
                                interrupted=false
                                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                                clear
                                echo "${GR}═════════════════════════${GR}╗${NC}"
                                echo "${BO}📱 Recommended macOS Apps${GR}║${NC}"
                                echo "${GR}═════════════════════════${GR}╝${NC}"
                                echo "↩ Resources"
                                show_nav_prompt_centered
                                echo "${BO}Check out these apps/developers!${NC}"
                                echo
                                echo "🔗 ${BO}Links:${NC}"
                                echo " 1) ${GR}Little Snitch${NC}"
                                echo " 2) ${GR}Objective-See (various apps)${NC}"
                                echo " 3) ${GR}Suspicious Package & Apparency${NC}"
                                echo " 4) ${GR}Find Any File${NC}"
                                echo " 5) ${GR}UTM (Apple Silicon only)${NC}"
                                echo " 6) ${GR}Titanium Software${NC}"
                                echo " 7) ${GR}Keyboard Maestro${NC}"
                                echo " 8) ${GR}Macs Fan Control${NC}"
                                echo " 9) ${GR}Pearcleaner${NC}"
                                echo "10) ${GR}EtreCheckPro${NC}"
                                echo
                                read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                                handle_navigation_input "$choice"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    break
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                fi

                                case $choice in
                                    1)
                                        open https://www.obdev.at/products/littlesnitch/index.html
                                        ;;
                                    2)
                                        open https://objective-see.org
                                        ;;
                                    3)
                                        open https://www.mothersruin.com/software/Apparency/
                                        read -r -t 1 -n 1
                                        open https://www.mothersruin.com/software/SuspiciousPackage/
                                        ;;
                                    4)
                                        open https://findanyfile.app
                                        ;;
                                    5)
                                        open https://mac.getutm.app
                                        ;;
                                    6)
                                        open https://titanium-software.fr/en/index.html
                                        ;;
                                    7)
                                        open https://www.keyboardmaestro.com/main/
                                        ;;
                                    8)
                                        open https://crystalidea.com/macs-fan-control/download
                                        ;;
                                    9)
                                        open https://itsalin.com/appInfo/?id=pearcleaner
                                        ;;
                                    10)
                                        open https://etrecheck.com/en/index.html
                                        ;;
                                    *)
                                        echo -n "❌ ${RE}Invalid choice.${NC} "
                                        read -r -t 1 -n 1
                                        continue
                                        ;;
                                esac
                            done
                            ;;
                        *)
                            echo -n "❌ ${RE}Invalid choice.${NC} "
                            read -r -t 1 -n 1
                            ;;
                    esac
                done
                ;;
            4)    
                # Upgrade OneCommand
                while true; do
                    trap - SIGINT
                    interrupted=false
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                    clear
                    echo "${GR}═════════════════════${GR}╗${NC}"
                    echo "${BO}⬆️  Upgrade OneCommand${GR}║${NC}"
                    echo "${GR}═════════════════════${GR}╝${NC}"
                    echo_justified "↩ Home [Command Center]" "Upgrade ↪"
                    show_nav_prompt_centered
                    echo_centered "${GY}This option simply removes quarantine and makes the new script executable.${NC}"
                    echo_centered "${GY}At the end, you'll have the option to open the new script and exit this one.${NC}"
                    echo
                    echo "${GR}Please provide your new 'OneCommand.command' file.${NC}"
                    echo
                    echo "${BO}Path Picker Options:${NC} ${GY}(or use drag & drop)${NC}"
                    echo " 1) 📂 ${GR}Reveal Finder${NC} ${GY}(for Drag & Drop)${NC}"
                    echo " 2) 📄 ${GR}Choose file  ${NC} ${GY}(via Finder dialog)${NC}"
                    echo
                    echo "⬇️  ${GR}Drag & drop it onto this window, then press Enter.${NC}"
                    echo "   ${GY}Tip: You can also press ⌥⌘C to copy it as a pathname${NC}"
                    echo
                    read -rp "" input
                    handle_navigation_input "$input"
                    nav=$?
                    if   [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then 
                        continue 2
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    fi

                    # Handle Path Picker Options (all input methods flow into paths_to_process)
                    local paths_to_process=()

                    case "$input" in
                        1) open /System/Library/CoreServices/Finder.app; continue ;;
                        2)
                            # Open Finder open panel (for files)
                            local selected_path=$(osascript \
                                -e 'try' \
                                -e 'set theFile to choose file with prompt "Choose your old OneCommand.command file" of type {"command", "public.unix-executable"}' \
                                -e 'return POSIX path of theFile' \
                                -e 'on error' \
                                -e 'return ""' \
                                -e 'end try')
                            if [[ -n "$selected_path" ]]; then
                                selected_path="${selected_path%/}"
                                paths_to_process=("$selected_path")
                            else
                                echo "❌ ${RE}No selection made.${NC}"
                                echo -n "   Please try again. "
                                read -r -t 1 -n 1
                                continue
                            fi
                            ;;
                        /)
                            echo "❌ ${RE}The root directory cannot be chosen.${NC}"
                            echo -n "   Please provide another path. "
                            read -r -t 3 -n 1
                            continue
                            ;;
                        *)
                            # Process drag & drop input to handle escaped spaces and quoted paths
                            eval "set -- $input"

                            local arg_count=$#

                            if [[ "$arg_count" -eq 0 ]]; then
                                echo "❌ ${RE}No paths provided.${NC}"
                                echo -n "   Please try again. "
                                read -r -t 1 -n 1
                                continue
                            fi

                            if [[ "$arg_count" -gt 1 ]]; then
                                echo "❌ ${RE}Only one file can be provided.${NC}"
                                echo -n "   Please try again. "
                                read -r -t 1 -n 1
                                continue
                            fi

                            if [[ ! -e "$1" ]]; then
                                echo "❌ ${RE}File not found.${NC}"
                                echo -n "   Please try again. "
                                read -r -t 1 -n 1
                                continue
                            fi

                            paths_to_process=("$1")
                            ;;
                    esac

                    # Validate the file is a OneCommand script
                    if ! grep -q "OneCommand" "$paths_to_process" 2>/dev/null || \
                    ! grep -q "bash" "$paths_to_process" 2>/dev/null ; then
                        echo
                        echo "❌ ${RE}Invalid file.${NC}"
                        echo -n "Please provide a valid OneCommand.command script. "
                        read -r -t 2 -n 1
                        continue
                    fi

                    # EXECUTION BLOCK
                    while true; do
                        trap - SIGINT
                        interrupted=false
                        trap 'echo; echo "🛑 ${RE}Interrupted.${NC}"; interrupted=true; break' SIGINT
                        clear
                        echo "${GR}═══════════════${GR}╗${NC}"
                        echo "${BO}🔄 Upgrading...${GR}║${NC}"
                        echo "${GR}═══════════════${GR}╝${NC}"
                        echo_justified "↩ Home [Path Picker]" "Restart OneCommand"
                        show_nav_prompt_centered
                        
                        local apply_recursively=true
                        local processed_count=0
                        local processed_failed=0
                        local processed_skipped=0

                        echo "🔄 ${GR}Attempting to remove quarantine and make script executable...${NC}"
                        echo

                        # Iterate over paths in queue to be processed
                        for path in "${paths_to_process[@]}"; do
                            if [ -e "$path" ]; then
                                local name=${path##*/}
                                local display_name="🛠️  ${BO}${name}${NC}"

                                execute_remove_quarantine

                                if sudo chmod +x "$path" 2>/dev/null; then
                                    echo "✅ ${GR}chmod +x${NC} $display_name"
                                    ((processed_count++))
                                else
                                    echo "❌ ${RE}chmod +x${NC} $display_name"
                                    ((processed_failed++))
                                fi
                            fi
                        done

                        echo

                        if [ $processed_count -eq 2 ]; then
                            echo "✅ ${GR}Done!${NC}"
                        else
                            trap - SIGINT
                            interrupted=false
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; break' SIGINT
                            
                            if [ $processed_failed -gt 0 ]; then
                                echo "⚠️  ${YE}Some tasks have failed.${NC}"
                            elif [ $processed_skipped -gt 0 ]; then
                                echo "⚠️  ${YE}Some tasks were skipped.${NC}"
                            fi
                            echo
                            read -rp "➡️  ${GR}Continue anyway? Press Enter or r/R to retry (or ${BL}nav${NC} ${GR}choice):${NC} " input
                            handle_navigation_input "$input"
                            nav=$?
                            if   [[ $nav -eq $NAV_QUIT ]]; then 
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                break
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            elif [[ $input == "r" ]] || [[ $input == "R" ]]; then
                                continue
                            fi
                        fi

                        trap - SIGINT
                        interrupted=false
                        trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT

                        echo
                        read -rp "➡️  ${GR}Open the new version and exit this one? Press Enter (or ${BL}nav${NC} ${GR}choice):${NC} " input
                        handle_navigation_input "$input"
                        nav=$?
                        if   [[ $nav -eq $NAV_QUIT ]]; then 
                            return 0
                        elif [[ $nav -eq $NAV_BACK ]]; then
                            continue 2
                        elif [[ $nav -eq $NAV_REFRESH ]]; then 
                            continue 2
                        elif [[ $nav -eq $NAV_CONT ]]; then
                            echo
                            echo "👋 ${BO}Goodbye"
                            echo
                            read -r -t 1 -n 1
                            open "$path"
                            clear
                            exit 0
                        fi
                    done
                done
                ;;
            5)
                came_from_command_center_path_picker=true
                if [[ -n "$_sudo_keepalive_pid" ]]; then
                    disable_sudo_keepalive
                    echo -n "🔒 ${GY}Sudo keep-alive disabled.${NC} "
                else
                    if enable_sudo_keepalive; then
                        echo -n "🔓 ${GR}Sudo keep-alive enabled.${NC} "
                    else
                        echo -n "❌ ${RE}Authentication failed.${NC} "
                    fi
                fi
                came_from_command_center_path_picker=false
                read -r -t 1 -n 1
                continue
                ;;
            6)
                resize_terminal 95 27
                clear
                show_help
                ;;
            *)
                echo -n "❌ ${RE}Invalid choice.${NC} "
                read -r -t 1 -n 1
                ;;
        esac
    done
}
#====9==== 🛠️ Settings
quick_settings() {
    while true; do
        if [[ -z "$current_sub_menu_choice" ]]; then
            trap - SIGINT
            interrupted=false
            trap 'echo; return' SIGINT
            resize_terminal 95 24
            clear
            if [[ "$used_keyboard_shortcut_s" == "true" ]]; then
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}🛠️  Settings${NC} ${BK}${RE}[Quick Settings]${NC}" "${GY}(Use B/Q/^C to jump back to previous menu)${NC}" "96"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Previous Menu" "${GY}(Use A/Z to cycle between options 1-3)${NC}"
                echo
                echo_centered "${BL}⮑ ${NC} Continue | ${BL}A${NC} Previous | ${BL}Z${NC} Next | ${BL}B/Q/^C${NC} Exit Quick Settings"
                echo
                echo_centered "$system_info_for_display"
                echo
                if [[ "$DisableWelcomeText_QuickMenus" == "false" ]]; then
                    echo_centered "${GR}Welcome to Quick Settings${NC}"
                    echo
                    echo_centered "${BO}Instant access to settings at any time, in any menu.${NC}"
                    echo_centered "${BO}Without ever losing your place.${NC}"
                    echo
                fi
            elif [[ "$came_from_main_menu" == "true" ]]; then
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}9) 🛠️  Settings${NC}" "${GY}(Use A/Z to cycle menus)${NC}" "96"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Main Menu" "TBD ↪"
                show_nav_prompt_with_AZ_for_settings_centered
                echo_centered "$system_info_for_display"
                echo
            elif [[ "$came_from_command_center_settings" == "true" ]]; then
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}🛠️  Settings${NC}" "${GY}(Use A/Z to cycle between options 1-3)${NC}" "96"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home [Command Center]" "TBD ↪"
                show_nav_prompt_with_AZ_for_settings_centered
                echo_centered "$system_info_for_display"
                echo
            else # came from somewhere else
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "${BO}🛠️  Settings${NC}" "" "96"
                echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                echo_justified "↩ Home" "TBD ↪"
                show_nav_prompt_with_AZ_for_settings_centered
                echo_centered "$system_info_for_display"
                echo
            fi
            echo "${BO}Choose an option:${NC}"
            echo " 1) 🔧 ${GR}Manage Preferences${NC} ($(_count_saved_prefs) Set)"
            echo " 2) 💾 ${GR}Manage Saved Paths${NC} (${#saved_paths_to_process[@]} Saved)"
            echo " 3) 📋 ${GR}Show All Saved Data${NC}"
            echo " 4) 🗑️  ${GR}Clear All Saved Data${NC}"
            echo " 5) 🔐 ${GR}Enable Sudo Keep-Alive${NC} $([ -n "$_sudo_keepalive_pid" ] && echo "✅ ${GR}[Active]${NC}" || echo "❌ ${GY}[Inactive]${NC}")"
            echo
            read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " sub_menu_choice

            choice="$sub_menu_choice" # store $choice to be checked in Command Center

            handle_navigation_input "$sub_menu_choice"
            nav=$?
            if [[ $nav -eq $NAV_QUIT ]]; then
                return 0
            elif [[ $nav -eq $NAV_BACK ]]; then
                return 0
            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                continue
            elif [[ "$came_from_main_menu" == "true" ]]; then
                if handle_main_menu_AZ_navigation_input "$sub_menu_choice" "$main_menu_choice"; then
                    return
                fi
            fi

            case $sub_menu_choice in
                a|A)
                    sub_menu_choice=3
                    ;;
                z|Z)
                    sub_menu_choice=1
                    ;;
            esac
        else
            # Use the pending choice from A/Z navigation
            sub_menu_choice="$current_sub_menu_choice"
            current_sub_menu_choice=""
        fi

        case $sub_menu_choice in
            1)
                # Manage Preferences
                while true; do
                    trap - SIGINT
                    interrupted=false
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                    if [[ "$DisableTerminalResizing_Vertical" == "false" ]]; then
                        resize_terminal 95 37
                    else
                        resize_terminal 95
                    fi
                    clear
                    if [[ "$used_keyboard_shortcut_s" == "true" ]]; then
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "1) 🔧 ${BO}Manage Preferences${NC} ${BK}${RE}[Quick Settings]${NC}" "${GY}(Use A/Z to cycle between options 1-3)${NC}" "94"
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "↩ Settings"
                        show_nav_prompt_with_AZ_for_quick_settings_centered
                    else
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "1) 🔧 ${BO}Manage Preferences${NC}" "${GY}(Use A/Z to cycle between options 1-3)${NC}" "94"
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "↩ Settings"
                        show_nav_prompt_with_AZ_for_settings_centered
                    fi

                    echo_centered "${BO}Choose a preference to toggle it on ✅ or off ❌:${NC}"
                    echo

                    # Helper: print a pref row with a human-readable label
                    _show_pref_row_as_choices() {
                        local key="$1" label="$2" num="$3"
                        local val
                        val=$(load_pref "$key")
                        [[ -z "$val" ]] && val="false"  # not in file = default

                        local val_text
                        if [[ "$val" == "true" ]]; then
                            # val_text="${RE}true${NC}"
                            val_text="✅"
                        else
                            # val_text="${GR}false${NC} ${GY}(Default)${NC}"
                            val_text="❌ ${GY}(Default)${NC}"
                        fi
                        
                        # local col_width=77
                        # local dot_count=$(( col_width - ${#label} ))
                        # [[ $dot_count -lt 3 ]] && dot_count=3
                        # local dots
                        # dots=$(printf '%*s' "$dot_count" '' | tr ' ' '.')

                        # The %-Ns padding keeps the two columns aligned.
                        # Adjust the number if labels get longer
                        # printf "%2s) %s ${GY}%s${NC} %s\n" "$num" "$label" "$dots" "$val_text"
                        printf "%2s) %s %s\n" "$num" "$label" "$val_text"
                    }

                    # _show_pref_row_as_choices treats a missing key the same as false — so prefs that were never explicitly set still 
                    # show their current default state rather than appearing blank

                    echo "${GR}Path Picker 'don't ask again' Prompts:${NC}"
                    _show_pref_row_as_choices "DontAskAgainAbout_SavingPaths_Path_Picker" "Don't ask about saving paths (N/A in Quick Picker)" "1"
                    _show_pref_row_as_choices "DontAskAgainAbout_OverwritingPaths_Path_Picker" "Don't ask about overwriting saved paths (always skip) - (N/A in Quick Picker)" "2"
                    echo "${GR}Path Picker Menu:${NC}"
                    _show_pref_row_as_choices "DisablePathPickerWhenPathsAreSaved_Quick_Stats" "Skip menu while paths are saved in Quick Stats" "3"
                    _show_pref_row_as_choices "DisablePathPickerWhenPathsAreSaved_Create_Symlinks" "Skip menu while paths are saved in Create Symlink" "4"
                    echo "${GR}Terminal Window Auto-Resize:${NC}"
                    _show_pref_row_as_choices "DisableTerminalResizing_Horizonal" "Disable Resizing [Horizontal]" "5"
                    _show_pref_row_as_choices "DisableTerminalResizing_Vertical" "Disable Resizing [Vertical]" "6"
                    echo "${GR}Text Effects:${NC}"
                    _show_pref_row_as_choices "DisableBlinkingText" "Disable Blinking Text" "7"
                    _show_pref_row_as_choices "DisableColoredText" "Disable Colored Text" "8"
                    echo "${GR}Saved Paths:${NC}"
                    _show_pref_row_as_choices "DisableSavedPathEncryption" "Disable Encryption" "9"
                    echo "${GR}Sudo Keep-Alive:${NC}"
                    echo "10) Enable for the current session (will prompt for your password) $([ -n "$_sudo_keepalive_pid" ] && echo "✅" || echo "❌ ${GY}(Inactive)${NC}")"
                    _show_pref_row_as_choices "SudoKeepAliveOnStartUp" "Enable At Startup" "11"
                    echo "${GR}Miscellaneous:${NC}"
                    _show_pref_row_as_choices "DisableWelcomeText_QuickMenus" "Disable Welcome text in Quick Menus" "12"
                    _show_pref_row_as_choices "HideIncompatible_macOS_Preferences" "Hide incompatible prefs in macOS Preferences" "13"
                    echo
                    echo "14) ${RE}Reset All To Default${NC}"
                    # Future pref groups just add a heading + rows here

                    # When adding future preference groups (non-dontaskagain ones),
                    # just add a new heading and more _show_pref_row_as_choices calls above

                    echo
                    read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        continue 2
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    elif handle_sub_menu_AZ_navigation_input "$choice" "$sub_menu_choice" 1 3; then
                        break
                    fi

                    case $choice in
                        1)  
                            _toggle_pref "DontAskAgainAbout_SavingPaths_Path_Picker"
                            ;;
                        2)  
                            _toggle_pref "DontAskAgainAbout_OverwritingPaths_Path_Picker"
                            ;;
                        3)  
                            _toggle_pref "DisablePathPickerWhenPathsAreSaved_Quick_Stats"
                            ;;
                        4)  
                            _toggle_pref "DisablePathPickerWhenPathsAreSaved_Create_Symlinks"
                            ;;
                        5)
                            _toggle_pref "DisableTerminalResizing_Horizonal"
                            ;;
                        6)
                            _toggle_pref "DisableTerminalResizing_Vertical"
                            ;;
                        7)
                            _toggle_pref "DisableBlinkingText"
                            if [[ "$DisableBlinkingText" == "true" ]]; then
                                BK=""
                            else
                                BK=$'\033[5m'
                            fi
                            ;;
                        8)
                            _toggle_pref "DisableColoredText"
                            if [[ "$DisableColoredText" == "true" ]]; then
                                # NC=""
                                BO=""
                                DM=""
                                RE=""
                                GR=""
                                YE=""
                                BL=""
                                MA=""
                                CY=""
                                GR=""
                                GY=""
                            else
                                # NC=$'\033[0m'
                                BO=$'\033[1m'
                                DM=$'\033[2m'
                                RE=$'\033[1;31m'
                                GR=$'\033[1;32m'
                                YE=$'\033[1;33m'
                                BL=$'\033[1;34m'
                                MA=$'\033[1;35m'
                                CY=$'\033[1;36m'
                                GR=$'\033[1;32m'
                                GY="${BO}${DM}"
                            fi
                            ;;
                        9)
                            _toggle_pref "DisableSavedPathEncryption"
                            # Re-save paths file immediately to convert to new format
                            save_paths_to_file
                            ;;

                        10)
                            if [[ -n "$_sudo_keepalive_pid" ]]; then
                                disable_sudo_keepalive
                                echo -n "🔒 ${GY}Sudo keep-alive disabled.${NC} "
                            else
                                enable_sudo_keepalive
                                echo -n "🔓 ${GR}Sudo keep-alive enabled.${NC} "
                            fi
                            read -r -t 1 -n 1
                            ;;
                        11)
                            _toggle_pref "SudoKeepAliveOnStartUp"
                            ;;
                        12)
                            _toggle_pref "DisableWelcomeText_QuickMenus"
                            ;;
                        13)
                            _toggle_pref "HideIncompatible_macOS_Preferences"
                            if [[ "$main_menu_choice" == "7" ]]; then
                                echo -n "   ${YE}Note: Must leave macOS Preferences for this to take effect...${NC} "
                                read -r -t 3 -n 1
                            fi
                            ;;
                        14)
                            trap - SIGINT
                            trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                            echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                            echo "✋ ${BO}Are you sure you want to reset all preferences to default?${NC}"
                            echo
                            read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                            handle_navigation_input "$choice"
                            nav=$?
                            if [[ $nav -eq $NAV_QUIT ]]; then
                                return 0
                            elif [[ $nav -eq $NAV_BACK ]]; then
                                continue
                            elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                continue
                            elif handle_sub_menu_AZ_navigation_input "$choice" "$sub_menu_choice" 1 3; then
                                break
                            fi

                            case $choice in
                                y|Y)
                                    # reset_all_prefs_to_default
                                    reset_all_prefs
                                    echo -n "✅ ${GR}All Preferences Reset.${NC} "
                                    read -r -t 1 -n 1
                                    ;;
                                *)
                                    :
                                    # echo -n "❌ ${RE}Cancelled.${NC} "
                                    ;;
                            esac
                            ;;
                        *)
                            echo -n "❌ ${RE}Invalid choice.${NC} "
                            read -r -t 1 -n 1
                            continue 
                            ;;
                    esac
                done
                ;;
            2)
                # Manage saved paths
                while true; do
                    trap - SIGINT
                    interrupted=false
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                    resize_terminal 95 24
                    if [[ "${#saved_paths_to_process[@]}" -gt 3 ]]; then
                        set_terminal_height_to_2200p
                    fi
                    clear
                    if [[ "$used_keyboard_shortcut_s" == "true" ]]; then
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "2) 💾 ${BO}Manage Saved Paths${NC} ${BK}${RE}[Quick Settings]${NC}" "${GY}(Use A/Z to cycle between options 1-3)${NC}" "94"
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "↩ Settings"
                        show_nav_prompt_with_AZ_for_quick_settings_centered
                    else
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "2) 💾 ${BO}Manage Saved Paths${NC}" "${GY}(Use A/Z to cycle between options 1-3)${NC}" "94"
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "↩ Settings"
                        show_nav_prompt_with_AZ_for_settings_centered
                    fi

                    echo "${BO}Saved Paths:${NC}"
                    echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"
                    if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                        for saved_path in "${saved_paths_to_process[@]}"; do
                            if [[ -e "$saved_path" ]]; then
                                local name="${saved_path##*/}"
                                local display_name=""

                                if [ -L "$saved_path" ]; then
                                    # echo "parent is a link"
                                    local target
                                    target=$(readlink "$path" 2>/dev/null)
                                    
                                    if [ -n "$target" ]; then
                                        # echo "parent link target points to something"
                                        if [ -d "$saved_path" ]; then
                                            # echo "parent link target points to a dir"
                                            display_name="🔗 ${MA}${name}/${NC} → 📂 ${CY}${target}/${NC}"
                                        elif [ -f "$saved_path" ]; then
                                            # echo "parent link target points to a file"
                                            display_name="🔗 ${MA}${name}${NC} → 📄 ${BO}${target}${NC}"
                                        else
                                            # echo "parent link target is broken"
                                            display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ${GY}${target}${NC}"
                                        fi
                                    else
                                        # echo "parent link target does not point to anything (edge case)"
                                        display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ..."
                                    fi
                                elif [ -d "$saved_path" ]; then
                                    # echo "parent is a directory"
                                    display_name="📂 ${CY}${name}/${NC}"
                                elif [ -f "$saved_path" ]; then
                                    # echo "parent is a file or alias"
                                    display_name="📄 ${BO}${name}${NC}"
                                else
                                    # Other type
                                    display_name="📄 ${name}"
                                fi
                                echo "$display_name"
                                echo "${GY}'$saved_path'${NC}"
                            else
                                echo "⚠️  ${YE}Saved path no longer exists:${NC}"
                                echo "${BO}${saved_path##*/}${NC}"
                                echo "${GY}'$saved_path'${NC}"
                                echo
                                read -rp "➡️  ${GR}Press any key to continue (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                                handle_navigation_input "$choice"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    continue 2
                                elif [[ "$choice" == "s" ]] || [[ "$choice" == "S" ]]; then 
                                    return 0
                                fi
                                continue 2
                            fi
                        done
                    else
                        echo "${GR}None${NC}"
                    fi
                    echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"
                    echo
                    echo "Choose an option:"
                    echo " 1) ${GR}Save New Paths${NC}"
                    if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                        echo " 2) ${RE}Clear All Saved Paths${NC}"
                    fi
                    echo
                    read -rp "➡️  ${GR}Select an option (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_BACK ]]; then
                        continue 2
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    elif handle_sub_menu_AZ_navigation_input "$choice" "$sub_menu_choice" 1 3; then
                        break
                    fi

                    case $choice in
                        1) 
                            while true; do
                                trap - SIGINT
                                trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                                came_from_settings_manage_saved_paths_path_picker=true
                                quick_picker
                                came_from_settings_manage_saved_paths_path_picker=false
                                [[ -n "$input" ]] && choice="$input" # check $input in path picker
                                handle_navigation_input "$choice"
                                nav=$?
                                if [[ $nav -eq $NAV_QUIT ]]; then
                                    return 0
                                elif [[ $nav -eq $NAV_BACK ]]; then
                                    continue 2
                                elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                    continue
                                # elif handle_sub_menu_AZ_navigation_input "$input" "$sub_menu_choice" 1 3; then
                                #     break 2
                                fi
                                continue 2
                            done
                            ;;
                        2)
                            if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                                while true; do
                                    trap - SIGINT
                                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                                    echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                                    echo "⚠️  ${RE}Are you sure you want to clear and forget $this_or_these saved $path_or_paths/$item_or_items?:${NC}"
                                    echo
                                    read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                                    handle_navigation_input "$choice"
                                    nav=$?
                                    if [[ $nav -eq $NAV_QUIT ]]; then
                                        return 0
                                    elif [[ $nav -eq $NAV_BACK ]]; then
                                        continue 2
                                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                                        continue 2
                                    elif handle_sub_menu_AZ_navigation_input "$choice" "$sub_menu_choice" 1 3; then
                                        break 2
                                    fi

                                    case $choice in
                                        y|Y)
                                            clear_saved_path_data
                                            # echo -n "✅ ${GR}Cleared all saved paths.${NC} "
                                            # read -r -t 1 -n 1
                                            ;;
                                    esac
                                    continue 2
                                done
                            else
                                echo -n "❌ ${YE}No saved paths exists.${NC} "
                                read -r -t 1 -n 1
                                continue
                            fi
                            ;;
                        *)
                            echo -n "❌ ${RE}Invalid choice.${NC} "
                            read -r -t 1 -n 1
                            continue
                            ;;
                    esac
                done
                ;;
            3)
                # Show All Saved Data
                while true; do
                    trap - SIGINT
                    interrupted=false
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue 2' SIGINT
                    resize_terminal 95 24
                    set_terminal_height_to_2200p
                    clear
                    if [[ "$used_keyboard_shortcut_s" == "true" ]]; then
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "3) 📋 ${BO}All Saved Data${NC} ${BK}${RE}[Quick Settings]${NC}" "${GY}(Use A/Z to cycle between options 1-3)${NC}" "94"
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "↩ Settings"
                        show_nav_prompt_with_AZ_for_quick_settings_centered
                    else
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo_justified "3) 📋 ${BO}All Saved Data${NC}" "${GY}(Use A/Z to cycle between options 1-3)${NC}" "94"
                        echo "${GR}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
                        echo "↩ Settings"
                        show_nav_prompt_with_AZ_for_settings_centered
                    fi

                    # Show Preferences
                    echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"
                    echo_justified "${BO}Saved Preferences:${NC}" "${GY}~/.OneCommand/preferences.conf${NC}"
                    echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"

                    # Helper: print a pref row with a human-readable label
                    _show_pref_row_for_display() {
                        local key="$1" label="$2"
                        local val
                        val=$(load_pref "$key")
                        [[ -z "$val" ]] && val="false"

                        local val_text
                        if [[ "$val" == "true" ]]; then
                            # val_text="${RE}true${NC}"
                            val_text="✅"
                        else
                            # val_text="${GR}false${NC} ${GY}(Default)${NC}"
                            val_text="❌ ${GY}(Default)${NC}"
                        fi

                        # local col_width=79
                        # local dot_count=$(( col_width - ${#label} ))
                        # [[ $dot_count -lt 3 ]] && dot_count=3
                        # local dots
                        # dots=$(printf '%*s' "$dot_count" '' | tr ' ' '.')

                        # printf "  %s ${GY}%s${NC} %s\n" "$label" "$dots" "$val_text"
                        printf "  %s %s\n" "$label" "$val_text"
                    }

                    # _show_pref_row_for_display treats a missing key the same as false — so prefs that were never explicitly set still 
                    # show their current default state rather than appearing blank

                    echo "${GR}Path Picker 'don't ask again' Prompts:${NC}"
                    _show_pref_row_for_display "DontAskAgainAbout_SavingPaths_Path_Picker" "Don't ask about saving paths (N/A in Quick Picker)"
                    _show_pref_row_for_display "DontAskAgainAbout_OverwritingPaths_Path_Picker" "Don't ask about overwriting saved paths (always skip) - (N/A in Quick Picker)"
                    echo "${GR}Path Picker Menu:${NC}"
                    _show_pref_row_for_display "DisablePathPickerWhenPathsAreSaved_Quick_Stats" "Skip menu while paths are saved in Quick Stats"
                    _show_pref_row_for_display "DisablePathPickerWhenPathsAreSaved_Create_Symlinks" "Skip menu while paths are saved in Create Symlink"
                    echo "${GR}Terminal Window Auto-Resize:${NC}"
                    _show_pref_row_for_display "DisableTerminalResizing_Horizonal" "Disable Resizing [Horizontal]"
                    _show_pref_row_for_display "DisableTerminalResizing_Vertical" "Disable Resizing [Vertical]"
                    echo "${GR}Text Effects:${NC}"
                    _show_pref_row_for_display "DisableBlinkingText" "Disable Blinking Text"
                    _show_pref_row_for_display "DisableColoredText" "Disable Colored Text"
                    echo "${GR}Saved Paths:${NC}"
                    _show_pref_row_for_display "DisableSavedPathEncryption" "Disable Encryption"
                    echo "${GR}Sudo Keep-Alive:${NC}"
                    echo "  Enable for the current session $([ -n "$_sudo_keepalive_pid" ] && echo "✅" || echo "❌ ${GY}(Inactive)${NC}")"
                    _show_pref_row_for_display "SudoKeepAliveOnStartUp" "Enable At Startup"
                    echo "${GR}Miscellaneous:${NC}"
                    _show_pref_row_for_display "DisableWelcomeText_QuickMenus" "Disable Welcome text in Quick Menus"
                    _show_pref_row_for_display "HideIncompatible_macOS_Preferences" "Hide incompatible prefs in macOS Preferences"

                    # Future pref groups just add a heading + rows here

                    # When adding future preference groups (non-dontaskagain ones),
                    # just add a new heading and more _show_pref_row_for_display calls above

                    echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"
                    echo_justified "${BO}Saved Paths:${NC}" "${GY}~/.OneCommand/saved_paths.enc${NC}"
                    echo "${GR}───────────────────────────────────────────────────────────────────────────────────────────────${NC}"
                    if [[ "${#saved_paths_to_process[@]}" -gt 0 ]]; then
                        for saved_path in "${saved_paths_to_process[@]}"; do
                            if [[ -e "$saved_path" ]]; then
                                local name="${saved_path##*/}"
                                local display_name=""

                                if [ -L "$saved_path" ]; then
                                    # echo "parent is a link"
                                    local target
                                    target=$(readlink "$path" 2>/dev/null)
                                    
                                    if [ -n "$target" ]; then
                                        # echo "parent link target points to something"
                                        if [ -d "$saved_path" ]; then
                                            # echo "parent link target points to a dir"
                                            display_name="🔗 ${MA}${name}/${NC} → ${CY}${target}/${NC}"
                                        elif [ -f "$saved_path" ]; then
                                            # echo "parent link target points to a file"
                                            display_name="🔗 ${MA}${name}${NC} → ${BO}${target}${NC}"
                                        else
                                            # echo "parent link target is broken"
                                            display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ${GY}${target}${NC}"
                                        fi
                                    else
                                        # echo "parent link target does not point to anything (edge case)"
                                        display_name="🔗 ${MA}${name}${NC} ⛓️‍💥  ..."
                                    fi
                                elif [ -d "$saved_path" ]; then
                                    # echo "parent is a directory"
                                    display_name="📂 ${CY}${name}/${NC}"
                                elif [ -f "$saved_path" ]; then
                                    # echo "parent is a file or alias"
                                    display_name="📄 ${BO}${name}${NC}"
                                else
                                    # Other type
                                    display_name="📄 ${name}"
                                fi
                                echo "$display_name"
                                echo "${GY}'$saved_path'${NC}"
                            fi
                        done
                    else
                        echo "${GR}None${NC}"
                    fi
                    echo
                    read -rp "➡️  ${GR}Press any key to continue (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    elif handle_sub_menu_AZ_navigation_input "$choice" "$sub_menu_choice" 1 3; then
                        break
                    fi
                    continue 2
                done
                ;;
            4)
                # Clear All Saved Data
                if [[ -d "$HOME/.OneCommand" ]] && [[ -n "$(ls -A "$HOME/.OneCommand/" 2>/dev/null)" ]]; then
                    trap - SIGINT
                    trap 'echo; echo -n "🛑 ${RE}Interrupted.${NC} Press Enter to go back: "; interrupted=true; continue' SIGINT
                    echo "───────────────────────────────────────────────────────────────────────────────────────────────"
                    echo "${BO}Are you sure?${NC} ${RE}This cannot be undone.${NC}"
                    echo
                    read -rp "➡️  ${GR}Type${NC} [y/Y] ${GR}or any key to cancel (or ${BL}nav${NC} ${GR}choice):${NC} " choice
                    handle_navigation_input "$choice"
                    nav=$?
                    if [[ $nav -eq $NAV_QUIT ]]; then
                        return 0
                    elif [[ $nav -eq $NAV_REFRESH ]]; then 
                        continue
                    fi

                    case $choice in
                        y|Y)
                            reset_all_prefs
                            clear_saved_path_data
                            rm -rf "$HOME/.OneCommand" 2>/dev/null
                            if [[ -d "$HOME/.OneCommand" ]] && [[ -n "$(ls -A "$HOME/.OneCommand/" 2>/dev/null)" ]]; then
                                rm -rf "$HOME/.OneCommand" 2>/dev/null
                            fi
                            echo -n "✅ ${GR}All Data Cleared.${NC} "
                            read -r -t 1 -n 1
                            ;;
                        *)
                            :
                            # echo -n "❌ ${RE}Cancelled.${NC} "
                            ;;
                    esac
                    # read -r -t 1 -n 1
                else
                    echo -n "✅ ${BO}All data already cleared.${NC} "
                    read -r -t 1 -n 1
                fi
                ;;
            5)
                if [[ -n "$_sudo_keepalive_pid" ]]; then
                    disable_sudo_keepalive
                    echo -n "🔒 ${GY}Sudo keep-alive disabled.${NC} "
                else
                    if enable_sudo_keepalive; then
                        echo -n "🔓 ${GR}Sudo keep-alive enabled.${NC} "
                    else
                        echo -n "❌ ${RE}Authentication failed.${NC} "
                    fi
                fi
                read -r -t 1 -n 1
                continue
                ;;
            *)
                echo -n "❌ ${RE}Invalid choice.${NC} "
                read -r -t 1 -n 1
                continue
                ;;
        esac
    done
}
# --- Main entry point ---------------------------------------------------------
main() {
    if [[ $# -gt 0 ]]; then
        local arg="$1"
        case "$arg" in
            0|qs)
                quick_stats
                ;;
            1|st|networkquality|speedtest)
                speed_test
                ;;
            2|am|top)
                top_activity_monitor
                ;;
            3|si|sysinfo|info|sp)
                system_information
                ;;
            4|isr|icloud|cloudd)
                icloud_sync_refresh
                ;;
            5|diu|hdiutil)
                disk_image_utility
                ;;
            6|cs|ln|symlink)
                create_symlink
                ;;
            7|mp|prefs|defaults)
                macos_preferences
                ;;
            8|cc)
                command_center
                ;;
            9|s|settings)
                quick_settings
                ;;
            --help|-h)
                resize_terminal 95 27
                clear
                show_help
                exit 0
                ;;
            *)
                echo
                echo "❌ Unknown argument: '$arg'"
                echo "   Run with --help or -h to see valid options."
                echo "   Falling back to main menu..."
                read -r -t 3 -n 1 2>/dev/null
                ;;
        esac
        main_menu
    else
        main_menu
    fi
}
show_help() {
    {
        display_OneCommand_header_for_95px
        echo_centered "${BP}Usage: OneCommand.command [choice]${BP}"
        echo
        echo_centered "  ${GR}Skip the main menu and jump directly to a task.${NC}"
        echo
        echo_centered "  ${BO}Pass either the menu number or alias:${NC}"
        echo
        local i
        for i in $(seq 0 $((MAIN_MENU_ITEMS_TOTAL - 1))); do
            local label aliases full_alias dot_count dots
            label=$(get_menu_item "$i")
            aliases=$(get_menu_aliases "$i")

            # Pad single-digit numbers so slashes align
            if [[ $i -lt 10 ]]; then
                full_alias=" $i / $aliases"
            else
                full_alias="$i / $aliases"
            fi

            # Dot-fill to fixed column width
            local col_width=48
            dot_count=$(( col_width - ${#full_alias} ))
            [[ $dot_count -lt 3 ]] && dot_count=3
            dots=$(printf '%*s' "$dot_count" '' | tr ' ' '.')

            printf "  %s ${GY}%s${NC} %s\n" "$full_alias" "$dots" "$label"
        done
        echo
        echo_centered "${GY}[q to exit]${NC}"
        echo
    } | less -R
}
# --- Initialize Preferences and Defs. ----------------------------------------
load_all_prefs  # overrides defaults if prefs file exists
load_paths_from_file  # populates saved_paths_to_process
prune_paths
set_plurality_for_saved_paths_to_process
if [[ "$DisableColoredText" == "true" ]]; then
    # NC=""
    BO=""
    DM=""
    RE=""
    GR=""
    YE=""
    BL=""
    MA=""
    CY=""
    GR=""
    GY=""
fi
[[ "$DisableBlinkingText" == "true" ]] && BK=""
if ! sudo -n true 2>/dev/null; then
    if [[ "$SudoKeepAliveOnStartUp" == "true" ]]; then
        resize_terminal 95 24
        clear
        display_OneCommand_header_for_95px
        echo
        echo_centered "🔐 ${GR}Sudo Keep-Alive On Startup is enabled.${NC}"
        echo
        echo_centered "${BO}↙️  Please authenticate${NC}"
        echo
        echo
        if enable_sudo_keepalive; then
            :
        else
            echo
            echo_centered "❌ ${RE}Authentication failed${NC}"
            echo
            echo_n_centered "${GR}⮑ ${NC} ${BO}Continuing without Sudo Keep-Alive.${NC} "
            read -r -t 1 -n 1
        fi
    sleep 0.2
    fi
fi
# ensure any persistent sudo background process is always cleaned up, even on crashes or ^C
trap 'disable_sudo_keepalive; exit' EXIT SIGINT SIGTERM
# Script entry point
main "$@"
# intentionally left blank