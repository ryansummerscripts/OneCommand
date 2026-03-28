<h1 align="center">
OneCommand
</h1>

<div align="center">
	<img width="892" height="480" alt="OneCommand" src="https://github.com/user-attachments/assets/5f12e0a7-3d91-4db8-950c-fcd094afbd7b" />
</div>

<div align="center">
	<img width="892" height="480" alt="OneCommandLite" src="https://github.com/user-attachments/assets/cbb28c12-7967-4017-b7c9-83e2c5c7596e" />
</div>

<hr>

<h3 align="center">
<br>One command to rule them all<br>
</h3>

<p align="center">
Available as a free (Lite) version here on github or a paid (Full) version available <a href="https://shop.ryansummer.com/p/onecommand/">here</a>
</p>

<p align="center">
<strong>Latest Versions:</strong><br>v2.1 (Full)<br>SHA-256: b6dddfd38b0d2a46dc20e4b7a8a637b3695a8b6b5660dd240c9050b1b67b3fc9
</p>

<p align="center">
<a href="https://shop.ryansummer.com/onecommand-release-notes/"><strong>Release Notes</strong></a>
</p>

<p align="center">
<br>v2.1 (Lite)<br>SHA-256: af4d81b5927f155648a1099c687be1d909c8a00c94eacda973bae38b1dd87b4b
</p>

<p align="center">
<a href="https://shop.ryansummer.com/onecommand-lite-release-notes/"><strong>Release Notes</strong></a>
</p>

<p align="center">
Tested on:
</p>

<p align="center">
✅ macOS Monterey 12 through Tahoe 26.4<br>✅ Intel &amp; Apple Silicon<br>
</p>

<p align="center">
<strong>For more screenshots, see <a href="https://app.box.com/s/vfbb2dk8ygluafnicis16u54j8xg3eqh">here</a></strong>
</p>

<hr>

<h3>Contents</h3>

<ul>
    <li>ℹ️ <a href="#oc-introduction">Introduction</a></li>
    <li>🧼 <a href="#oc-removing-quarantine">Removing Quarantine</a></li>
    <li>▶️ <a href="#oc-running-instructions">Running Instructions</a></li>
    <li>⬆️ <a href="#oc-upgrading-one-command">Upgrading OneCommand</a></li>
    <li>📥 <a href="#oc-storage">Storing OneCommand</a></li>
</ul>

<hr>

<div id="oc-introduction"></div>

<h1 align="center">ℹ️</h1>

<h2 align="center">Introduction</h2>

<p>
<strong>OneCommand</strong> is a menu-driven command line tool that runs in macOS's Terminal app, giving you access to powerful system features that are hidden, missing, or simply inaccessible through the GUI or App Store apps.
</p>
<p>
macOS has a wealth of capability locked behind the Terminal - but recalling and managing hundreds of commands isn't practical for most people.
</p>
<p>
OneCommand solves this by wrapping over 500 commands into a single, navigable interface that feels approachable whether you've never opened Terminal before or use it every day.
</p>
<p>
It bridges the gap between casual users and power users, replacing the need to remember syntax with an intuitive, keyboard-driven experience - without ever leaving the Terminal.
</p>

<p>Here are some of its main features:</p>

<p><strong>Core Functionality</strong></p>

<ul>
    <li><strong>File Management</strong>: Manage/view quarantine, code signatures, extended attributes, permissions, binary architectures, create symlinks</li>
    <li><strong>Privacy &amp; Security</strong>: Generate file hashes, audit file types, manage the TCC database, manage the system's hosts file, test a machine's isolation/exposure status</li>
    <li><strong>System Utilities</strong>: DNS management, network testing, system information, manage Time Machine snapshots, monitor system activity</li>
    <li><strong>macOS Preferences</strong>: Configure various default system settings and behaviors</li>
    <li><strong>Diff Tracker</strong>: Track changes to the file system, preference files, websites, compare file differences</li>
    <li><strong>Disk Image Tools</strong>: Create/resize disk images and make macOS installers</li>
    <li><strong>Package Management</strong>: Batch-install .pkg files</li>
    <li><strong>Settings</strong>: Manage all preferences and data saved by OneCommand</li>
    <li><strong>Path Picker</strong>: Dedicated global prompt for providing file paths</li>
</ul>

<p><strong>Architecture</strong></p>

<ul>
    <li>Interactive menu-driven interface with <strong>navigation controls</strong></li>
    <li>Modular function-based design with <strong>24+ utility functions</strong></li>
    <li><strong>Color-coded output</strong> using ANSI escape sequences</li>
    <li>Error handling and <strong>interruption support</strong></li>
    <li>Support for <strong>drag-and-drop</strong> or <strong>Finder-dialog</strong> file operations</li>
    <li>Persistent file-path and preference storage across sessions</li>
</ul>

<p><strong>Key Design Patterns</strong></p>

<ul>
    <li>Global navigation system (continue/back/previous/next/stop/path picker/settings/quit)</li>
    <li>Consistent error handling and retry mechanisms</li>
    <li>Automatic Terminal window resizing when displaying large output</li>
    <li>User-friendly prompts and status reporting</li>
</ul>

<hr>

<div id="oc-removing-quarantine"></div>

<h1 align="center">🧼</h1>

<h2 align="center">Removing Quarantine</h2>

<p>
By default, macOS flags &amp; quarantines unsigned files downloaded from the internet, preventing this from being ran simply by double clicking it. <em>(Sorry, we are not yet in the Apple Developer program)</em>
</p>

<div align="center">
<img src="https://media.sellfy.store/images/EbcIl29G/mpuE/gatekeeper_msg.png">
</div>

<p>
If you wish to run it by double clicking it, you can remove the quarantine attribute as well as give it the necessary permissions.
</p>

<p align="center">
<em><strong>(See <a href="#oc-upgrading-one-command">below</a> for instructions on upgrading to a newer version of OneCommand)</strong></em>
</p>

<p>1. Copy the command below inside the quotes (including the space at the end of "prep "):</p>

```
function prep() {
    for file in "$@"; do
        sudo xattr -d com.apple.quarantine "$file"
        sudo chmod +x "$file"
    done
}

prep 
```

<p>2. Paste the command into Terminal and drag and drop the .command file onto the Terminal window, then press Enter.</p>

<p>Example:</p>

```
function prep() {
    for file in "$@"; do
        sudo xattr -d com.apple.quarantine "$file"
        sudo chmod +x "$file"
    done
}

prep /Users/YOURUSERNAME/Downloads/OneCommand.command
```

<p>3. Type your password and hit Enter again (password will be invisible).</p>
<p>4. The command file should now open as usual when double clicking it.</p>

<hr>

<div id="oc-running-instructions"></div>

<h1 align="center">▶️</h1>

<h2 align="center">Running Instructions</h2>

<p>
Simply double click the command file. It will then open Terminal and display the Main Menu. Choose a number, press <strong>Enter</strong> to continue, and follow the on-screen prompts.
</p>

<p>Some of the navigation controls include:</p>

<ul>
    <li><strong>B:</strong> <strong>Go back</strong> a step in any menu.</li>
    <li><strong>Q:</strong> <strong>Return</strong> to the main menu at any point.</li>
    <li><strong>^C:</strong> <strong>Interrupt/Stop</strong> any output or password prompts or <strong>exit the script</strong> when at the Main Menu <em>(also used to go back in most cases)</em>.</li>
    <li><strong>A/Z:</strong> Navigate to the <strong>next</strong> or <strong>previous</strong> menu/option (where available).</li>
    <li><strong>S:</strong> Quickly jump in and out of <strong>Settings</strong> while preserving your current location</li>
    <li><strong>P:</strong> Quickly jump in and out of <strong>Path Picker</strong> while preserving your current location</li>
</ul>

<hr>

<div id="oc-upgrading-one-command"></div>

<h1 align="center">⬆️</h1>

<h2 align="center">Upgrading OneCommand</h2>

<p align="center">
If you already downloaded OneCommand, you'll no longer need to manually paste the <a href="#oc-removing-quarantine">remove quarantine</a> command above when downloading a new version. You can simply use the built-in upgrade option to automate this process by doing the following:
</p>

<p>1. Choose the menu item: <strong>🕹️ Command Center</strong>.</p>
<p>2. Select option 4: <strong>⬆️ Upgrade OneCommand</strong>.</p>
<p>3. Provide your new OneCommand.command file, press Enter, type password, and Enter again.</p>
<p>4. Done. Press Enter to launch the new OneCommand file.</p>

<hr>

<div id="oc-storage"></div>

<h1 align="center">📥</h1>

<h2 align="center">Storage</h2>

<p align="center">
You can store the 'OneCommand.command' file (or its entire folder), virtually anywhere you'd like.
</p>

<p align="center">Here are some common examples:</p>

<ul>
    <li>Applications folder</li>
    <li>Desktop</li>
    <li>Drag it to the Dock</li>
    <li>iCloud Drive</li>
    <li>Pin it directly to Finder <em>(by command + dragging it - notice the 🛠️ below)</em></li>
</ul>

<div align="center">
<img src="https://media.sellfy.store/images/EbcIl29G/eaSS/pintodock.png">
</div>

<hr>

<p align="center">
If you have any issues, suggestions or feedback, don't hesitate to <a href="https://shop.ryansummer.com/contact/">reach out</a>.
</p>

<p align="center">Enjoy!</p>

<hr>
