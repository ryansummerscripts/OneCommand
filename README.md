# OneCommand
One command to rule them all

<div align="center">
<img width="745" height="495" alt="OneCommand_v1 0_(Full)" src="https://github.com/user-attachments/assets/09456e63-6667-434d-a13f-216a90431c69" />
</div>
<div align="center">
<img width="745" height="495" alt="OneCommand_v1 0_(Lite)" src="https://github.com/user-attachments/assets/5bd110cb-a7de-4537-bb75-c7561a7d22bc" />
</div>

------------------------------------------

Tested on:

✅ macOS Monterey 12 through Tahoe 26

✅ Intel & Apple Silicon

------------------------------------------

ℹ️ **Introduction:**

**OneCommand** is a macOS utility script that provides a comprehensive set of
system administration and file management tools through an interactive
terminal interface. Containing over 250+ commands in one, its purpose is to help automate tasks and control macOS in ways that can't easily (or sometimes at all) be done through a GUI.

**Core Functionality**
  - **File Security & Permissions:** Remove quarantine flags, change permissions,
    modify ownership
  - **Code Signing:** Sign applications and bundles with ad-hoc signatures
  - **Hash Generation:** Generate SHA256 hashes for files and bundles
  - **Package Management:** Batch install .pkg files
  - **Disk Image Tools:** Create/resize disk images and make macOS installers
  - **System Utilities:** DNS management, network testing, system information
  - **macOS Preferences:** Configure various default system settings and behaviors
  - **Difference Tracker:** Track differences/changes to the file system
    

**Architecture**
  - **Interactive menu-driven interface with navigation controls**
  - **Modular function-based design with 20 utility functions**
  - **Color-coded output using ANSI escape sequences**
  - **Error handling and interruption support**
  - **Support for drag-and-drop file operation**
    

**Key Design Patterns**
  - **Global navigation system** (back/continue/interrupt/quit)
  - **Consistent error handling and retry mechanisms**
  - **Automatic Terminal window resizing when displaying large output**
  - **Modular function organization with clear separation of concerns**
  - **User-friendly prompts and status reporting**

------------------------------------------

**De-Quarantining & signing OneCommand**

By default, macOS quarantines unsigned files downloaded from the internet. If this command script cannot be opened simply by double-clicking it, you can remove its quarantine attributes & sign it.

<div align="center">
<img width="260" height="262" alt="GateKeeper msg" src="https://github.com/user-attachments/assets/6514ecfc-1317-4998-8d92-fa53b482b18b" />
</div>

1. Copy the command below inside the "quotes" (including the space at the end of prep):
```
function prep() {
    for file in "$@"; do
        sudo xattr -cr "$file"
        sudo xattr -r -d com.apple.quarantine "$file"
        sudo codesign --force --deep --sign - "$file"
	sudo chmod +x "$file" 
    done
}

prep 
```

2. Paste the command into Terminal, drag and drop the "OneCommand.command" file onto the Terminal window, then press Enter.

Example:
```
function prep() {
    for file in "$@"; do
        sudo xattr -cr "$file"
        sudo xattr -r -d com.apple.quarantine "$file"
        sudo codesign --force --deep --sign - "$file"
	sudo chmod +x "$file" 
    done
}

prep /Users/YOURUSERNAME/Downloads/OneCommand.command
```

3. Type your password and hit Enter (password will be invisible).
4. The command file should now open as usual simply by double clicking it.

------------------------------------------

**Why do you need to do this?**

Chat GPT says:

To sign and notarize in a way that bypasses Gatekeeper, you must enroll in the Apple Developer Program, which costs $99 USD per year.

Facts:
- Free Apple IDs can code sign ad-hoc (codesign -s -) or with a personal signing certificate, but those signatures are not trusted by Gatekeeper. They will not clear quarantine.

- Only Developer ID Application/Installer certificates issued through a paid Developer Program account can produce binaries and packages that are trusted system-wide outside the Mac App Store.

- Notarization (Apple scanning and stapling a ticket to your binary/package) also requires a paid Developer ID. Without notarization, even a valid Developer ID signature will trigger warnings on modern macOS versions.

- Distribution without paying Apple: You can still share scripts, packages, or apps, but users must manually bypass quarantine (right-click → Open, strip with xattr, or allow via Privacy & Security).

So: free = always quarantined, user has to override. Paid developer = can notarize, quarantine cleared automatically.

------------------------------------------

▶️ Running Instructions:

Simply double click the command file. It will then open Terminal and display the Main Menu. Choose a number, press Enter to continue, and follow the on screen instructions.

· To go back a step in any function/menu item, press B + Enter.

· To return to the main menu at any point, press Q + Enter.

· To interrupt any output or password prompts, press ^C (Control + C).

· To exit the script, press ^C at the Main Menu.

Feel free and drop the .command file in your Applications folder, drag it to the dock, or even pin it directly to Finder by command + dragging it (Notice the 🛠️).

<div align="center">
  <img width="536" height="344" alt="PinToDock" src="https://github.com/user-attachments/assets/4fabe1c2-16c3-43b8-bd79-d705dd29272b" />
</div>
