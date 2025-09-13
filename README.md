# OneCommand
One command to rule them all

![Screenshot 2025-09-12 at 9 38 05 PM](https://github.com/user-attachments/assets/aeb89a1a-dad9-443a-af41-dc567bd01105)

------------------------------------------

**About One Command**

This user friendly Terminal script contains over 250+ commands in one! It's purpose to help automate tasks and control macOS in ways that can't easily (or sometimes at all) be done through a GUI.

------------------------------------------

**De-Quarantining & signing OneCommand**

By default, macOS quarantines unsigned files downloaded from the internet. If this command script cannot be opened simply by double-clicking it, you can remove its quarantine attributes & sign it.


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

Done!

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
