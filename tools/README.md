# Optional Everloot updates on Windows

Keep the two PowerShell scripts together in a folder outside WoW's `AddOns`
directory. Open Windows PowerShell 5.1 in that folder and run the updater with
the path to your installed RicoLoot addon.

```powershell
.\RicoLoot-Everloot-Updater.ps1 -AddonDirectory 'C:\Games\World of Warcraft\_forever_\Interface\AddOns\RicoLoot'
```

The updater creates `RicoLootEverloot` beside `RicoLoot`. The local cache
survives WowUp releases, and the updater keeps the last validated snapshot if
a download fails. Fully restart WoW after creating the cache and make sure
**RicoLoot Everloot Cache** is enabled in the AddOns list. After later updates,
use `/reload` to load the new data and comparison. You can repeat the updater
manually or run the same command daily through Windows Task Scheduler.

## Fetch from the game

Start the companion with your `_forever_` directory. It runs in the background
for the current Windows session. If you already run an older RicoLoot
companion, stop that copy and disable its startup entry before switching.

```powershell
.\RicoLoot-Sync-Companion.ps1 -Mode Start -GameDirectory 'C:\Games\World of Warcraft\_forever_'
```

In WoW, open `/rl` and choose **Database → Fetch latest**. RicoLoot reloads
the interface to save the request. When the companion reports completion,
choose **Reload & view** in **Database** to see the comparison. Run
`.\RicoLoot-Sync-Companion.ps1 -Mode Stop` from the same folder to stop it.

The helper reads the RicoLoot request marker locally. It fetches public
[Everloot](https://everloot.app) data and leaves your personal observations and
item goals in WoW's SavedVariables. Everloot data is licensed under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
