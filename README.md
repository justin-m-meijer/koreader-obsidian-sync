# KOReader → Obsidian Sync — Setup Guide

Sync your KOReader highlights and annotations directly into your Obsidian vault over WiFi. No cloud service required — your KOReader connects straight to Obsidian on your computer.

---

## How it works

```
KOReader (phone / e-reader)
        │  WiFi
        ▼
Obsidian plugin (your computer)  →  Markdown file per book  →  Your vault
```

The Obsidian plugin runs a small local HTTP server. KOReader connects to it and sends your highlights. Each book gets its own Markdown file in a folder of your choice.

---

## Part 1 — Install the Obsidian plugin

### Step 1 — Copy the plugin files

1. Open your Obsidian vault folder in Finder / Explorer
2. Navigate to `.obsidian/plugins/` (create the `plugins` folder if it doesn't exist)
3. Create a new folder called `koreader-sync`
4. From the downloaded zip, copy these three files into that folder:
   - `main.js`
   - `manifest.json`
   - `styles.css`

Your folder should look like this:
```
<your vault>/.obsidian/plugins/koreader-sync/
    main.js
    manifest.json
    styles.css
```

### Step 2 — Enable the plugin

1. Open Obsidian
2. Go to **Settings → Community plugins**
3. Turn off **Restricted mode** if it is on
4. Find **KOReader Sync** in the list and toggle it **on**

### Step 3 — Configure the plugin

1. Go to **Settings → KOReader Sync**
2. Set the **Sync folder** — this is where your book notes will be created (e.g. `Books` or `KOReader`)
3. Set a **Username** and **Password** — you will enter the same values in KOReader (default: `koreader` / `koreader`)
4. Note the **port number** shown (default: `7777`)
5. Click **Start server** — the status should change to *Running*

### Step 4 — Find your computer's IP address

KOReader needs to know where to connect. Find your local IP address:

- **Mac**: System Settings → Wi-Fi → Details → IP Address (e.g. `192.168.1.50`)
- **Windows**: Run `ipconfig` in Command Prompt → look for *IPv4 Address*
- **Linux**: Run `ip addr` → look for your WiFi interface address

> **Tip:** Both your computer and your KOReader device must be on the **same WiFi network**.

---

## Part 2 — Install the KOReader plugin

### Step 1 — Copy the plugin to your device

Connect your device to your computer via USB and copy the `obsidian-sync.koplugin` folder (from the zip) into KOReader's plugins directory:

| Device | Path |
|---|---|
| Android | `Internal storage/koreader/plugins/` |
| PocketBook | `applications/koreader/plugins/` |
| Kobo | `.adds/koreader/plugins/` |
| Kindle | `koreader/plugins/` |

The result should look like:
```
<koreader>/plugins/obsidian-sync.koplugin/
    _meta.lua
    main.lua
```

### Step 2 — Restart KOReader

Fully close and reopen KOReader so it loads the new plugin.

### Step 3 — Configure the KOReader plugin

1. Open any book in KOReader
2. Tap the **menu** (top of screen) → **⋮ More tools** → **Obsidian Sync** → **Configure server…**
3. Enter the three settings one screen at a time:
   - **Server URL** — `http://<your computer's IP>:7777` (e.g. `http://192.168.1.50:7777`)
   - **Username** — same as set in Obsidian (default: `koreader`)
   - **Password** — same as set in Obsidian (default: `koreader`)
4. Tap **Save** on the last screen

---

## Part 3 — Sync your first book

1. Make sure your computer has Obsidian open with the server running
2. Make sure KOReader is on the same WiFi network
3. Open a book in KOReader
4. Tap **menu → More tools → Obsidian Sync → Sync this book now**
5. You should see a brief confirmation message

A Markdown file named **Book Title - Author.md** will appear in your chosen Obsidian folder containing all your highlights and notes.

---

## Part 4 — Auto-sync (optional)

You can have KOReader sync automatically without tapping anything.

### Every N pages

1. Go to **menu → More tools → Obsidian Sync → Auto-sync by pages: off**
2. Enter a number (e.g. `10` to sync every 10 pages)
3. Tap **Save**

The label in the menu will update to show the current interval. Set it back to `0` to disable.

### On sleep / screen-off

1. Go to **menu → More tools → Obsidian Sync → Auto-sync on sleep**
2. Tap to toggle it **on** (a checkmark appears)

KOReader will silently sync whenever you put the device to sleep.

> **Note:** Auto-sync only runs if WiFi is already connected. It will never interrupt you to ask for a WiFi password.

---

## The Markdown output

Each book gets one file. It is created on first sync and updated on every subsequent sync without losing edits you make in Obsidian.

```markdown
# The Pragmatic Programmer - David Thomas

**Author:** David Thomas
**Progress:** 42%
**Last synced:** 2026-03-01 20:30

---

## Highlights & Notes

### Page 12
> "Provide options, don't make lame excuses."

### Page 47
> "It is not enough to know that something is broken — you need to understand *why*."
📝 This applies so well to debugging sessions.

### Page 103
> "Don't live with broken windows."
```

---

## Troubleshooting

**"Sync failed" or no response**
- Check that the Obsidian server is running (Settings → KOReader Sync → status shows *Running*)
- Confirm both devices are on the same WiFi network
- Double-check the IP address in KOReader — it changes if you reconnect to WiFi

**"Auth failed (401)"**
- Username and password in KOReader must match exactly what you set in Obsidian

**Annotations missing from the sync**
- Sync while the book is still open — annotations are read from live memory
- Make sure you have at least saved or navigated away from a highlight before syncing

**Plugin not showing in KOReader menu**
- Confirm the folder is named exactly `obsidian-sync.koplugin` (no typos)
- Confirm both `_meta.lua` and `main.lua` are inside it
- Fully close and reopen KOReader (not just go to home screen)

**Auto-sync crashes (older plugin version)**
- Make sure you are using the latest version from the zip — earlier versions had a crash bug on Android that has been fixed

---

## Supported devices

| Platform | Supported |
|---|---|
| Android (phone / tablet) | ✅ |
| PocketBook | ✅ |
| Kobo | ✅ |
| Kindle (jailbroken with KOReader) | ✅ |
| Obsidian on Windows / Mac / Linux | ✅ (desktop only) |

## Support

If this is useful to you, you can support my work with a [donation through PayPal](https://www.paypal.com/donate?hosted_button_id=UNBDNLN8MSC88).

---

## License

Licensed under the [Mozilla Public License 2.0](LICENSE). You may use, change and share it, also
commercially. If you distribute a changed version of these files, those files must stay under the
MPL 2.0 and their source must be available.
