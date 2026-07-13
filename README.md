# RadioExt - Fork
A mod for CP2077 that allows for the addition of radio stations.

## Fork specific changelog

## Breaking Changes

- **RED4ext SDK v1 API**: The native plugin now targets the v1 namespace
  (`RED4ext::v1::Sdk`, `RED4ext::v1::PluginHandle`, `RED4ext::v1::GameState`,
  `RED4ext::v1::EMainReason`). Users must build against the latest RED4ext
  SDK; older SDK versions will fail to compile.
- **C++20 required**: The C++ source now uses `std::bit_cast`, `<concepts>`,
  and other C++20 features pulled in transitively via the RED4ext SDK
  headers. C++17 builds will no longer compile.

---

## Build System

- **Added `CMakeLists.txt`**: Configures the plugin as a C++20 shared
  library, links the RED4ext SDK via `add_subdirectory` and FMOD Core via
  an imported `FMOD::Core` target, and outputs `RadioExt.dll` with the
  correct name and suffix.
- **Added `package.bat`**: One-shot Windows batch script that copies the
  built DLL, FMOD runtime, Lua modules, and metadata into a versioned zip
  ready for distribution. The archive name is derived from
  `metadata.json`'s `displayName` field.
- **Updated `.gitignore`**: Excludes the local `build/` directory and
  user-specific `CMakeLists.txt` overrides.

---

## Native Plugin (`src/main.cpp`, `src/SoundLoadData.hpp`)

- **Ported to RED4ext SDK v1 API**: All SDK types now use the `v1` namespace.
  `GetModuleFileName` switched to its wide-character variant
  `GetModuleFileNameW` to match the SDK's string conventions.
- **Default-initialized `SoundLoadData`**: Every field (`sound`, `startPos`,
  `volume`, `fade`, `play`) now has a default initializer so that
  `new SoundLoadData` no longer leaves the `sound` pointer
  indeterminate. The struct also gained an include guard, explicit
  `<cstdint>`/`<string>` includes, and a forward declaration of
  `FMOD::Sound` to keep the header lightweight.
- **Channel ID normalization**: A new `NormalizeChannelId` helper maps the
  Lua-side sentinel `-1` (vehicle radio) to internal slot `0` and clamps
  every other value to `[0, ChannelCount]`. This eliminates the
  out-of-bounds array access that occurred when `Play`, `SetVolume`,
  `Stop`, or `SetChannelTransform` received an unnormalized channel ID.
- **Vector conversion helper**: The duplicated axis-remapping logic in
  `SetChannelTransform` and `SetListenerTransform` was extracted into a
  single `ToFmodVector` helper.
- **FMOD error handling**: `createStream` failures no longer mark the
  channel slot as playing with a null sound pointer; `playSound` failures
  release the sound handle and clear the slot instead of leaving a dangling
  channel; `getOpenState` failures now `continue` the loop instead of
  acting on an uninitialized state value. Previously-active channels are
  stopped before a new sound starts on the same slot to prevent overlap.
- **Leak fixes**: `GetSongLength` now releases the temporary `FMOD::Sound`
  used for length probing. `Play` releases any previously-loading sound on
  the slot before overwriting it. `OnRunningExit` releases every sound
  handle, nullifies every channel/load pointer after stop/delete, and
  guards against double-free.
- **Modernized constants**: The `#define RADIOEXT_VERSION`, `#define CHANNELS`,
  and `#define MAX_LOAD_ATTEMPTS` macros were replaced with `constexpr`
  variables (`RadioExtVersion`, `ChannelCount`, `MaxLoadAttempts`).
- **Internal linkage**: All file-scope globals, helpers, and native
  function implementations were moved into an anonymous namespace. Only
  the five RED4ext-required exports (`Main`, `Query`, `Supports`,
  `RegisterTypes`, `PostRegisterTypes`) retain external linkage.

---

## Station Loading (`modules/radioManager.lua`, `modules/radioStation.lua`)

- **Per-station error isolation**: Each station's `radio:load()` call is
  now wrapped in `pcall`. A single malformed station no longer aborts the
  entire `loadRadios` loop, which previously caused all subsequently-listed
  stations to vanish from the radio wheel.
- **Metadata validation and migration**: `backwardsCompatibility` now
  validates every required field and repairs it in place:
  - `streamInfo.isStream` is coerced to a boolean when it is `nil` or a
    string (`"true"`/`"false"`) — this was the root cause of the
    "one stream station makes all other stations disappear" bug, because a
    non-boolean `isStream` caused the station to be treated as file-based,
    crashed `startRadioSimulation` on an empty shuffle bag, and aborted the
    load loop.
  - `streamInfo.streamURL`, `customIcon.useCustom`, `customIcon.inkAtlasPath`,
    `customIcon.inkAtlasPart` are filled with safe defaults when missing.
  - `displayName`, `fm`, `volume`, and `icon` are type-checked and coerced
    or reset to defaults (`fm` and `volume` accept numeric strings).
  - The metadata file is now written at most once per load instead of up
    to three times.
- **Empty-shuffle-bag guard**: `startRadioSimulation` checks
  `#self.shuffelBag == 0` before accessing `shuffelBag[1]` and returns
  early with a dormant `currentSong` instead of throwing
  `attempt to index nil`. The per-tick callback gained the same guard
  after `generateShuffelBag`.
- **Short-song crash fix**: `math.random(self.currentSong.length - 15)`
  now clamps its argument to at least `1`, preventing the
  `bad argument #1 to 'random' (interval is empty)` crash on songs shorter
  than 16 seconds.
- **No-songs fallback**: A file-based station with zero songs no longer
  enters the simulation; it appears in the list but plays silence, with a
  warning printed to the console.
- **Load logging**: `loadRadios` now prints a summary line per station
  (`Found N station folder(s)`, `Loaded station "..." (FM x, N song(s),
  type: stream|file, index: N)`, `Successfully loaded N/M station(s)`)
  and a hint when `isStream` is `false` but a `streamURL` is present.
- **Correct song count in logs**: The per-station log line previously
  reported `0 song(s)` for every station because it used `#songs` on a
  string-keyed table (Lua's length operator returns 0 for non-sequence
  tables). It now uses `#r.songs`, the integer-keyed array built by
  `radioStation:load`.
- **Module-scoped `radio` table**: `radio = {}` was changed to
  `local radio = {}` to stop polluting `_G` and avoid collisions with
  other mods that define a global `radio` table.

---

## Audio Engine (`modules/utils/audioEngine.lua`)

- **Per-channel rate limiting**: The previous single global cooldown
  dropped every `playFile` call within 1 second of the previous one,
  regardless of channel — this silently broke rapid station switching and
  simultaneous multi-radio activation. The limiter now tracks
  `lastPlayedByChannel[id]` so each channel has its own 1-second window.
- **Nil-safe volume calculation**: `getAdjustedVolume` tolerates a `nil`
  `GetPlayer()` (early init, between sessions) and a `nil`
  `GameSettings.Get` result, falling back to `100` for the volume
  multiplier. The `GetMountedVehicle` call is now wrapped in `pcall`.
- **Cooldown reset on stop**: `audio.stopAudio` clears the per-channel
  cooldown so the next `playFile` on that channel is not artificially
  delayed.

---

## Vehicle and Physical Radio Logic

- **Nil-safe vehicle access** (`modules/vehicle/radioManagerV.lua`,
  `modules/vehicle/observersV.lua`): `GetMountedVehicle(GetPlayer())` is
  cached into a local and nil-checked before any blackboard or
  `ToggleRadioReceiver` call. The `HandleVehicleRadioStationChanged`
  override only writes `evt.radioIndex` when a custom station is actually
  active, fixing a nil-index crash on vanilla stations. The
  `OnRadioToggleEvent` else-branch falls through to the vanilla handler
  when no vehicle is mounted.
- **Nil-safe custom-station lookups** (`modules/physical/observersP.lua`):
  The `PlayGivenStation`, `SetupStationLogo`, and `TurnOn` observers now
  nil-check `radios[active - 13]` before using it, so a stale save-game
  referencing a removed custom station no longer crashes the UI.
- **Reliable empty-table check** (`modules/physical/radioManagerP.lua`):
  The physical-radio update loop now uses `next(self.radioObjects) == nil`
  instead of `#self.radioObjects == 0`. The `#` operator is undefined on
  tables with integer-key gaps, which appear whenever a physical radio is
  removed mid-session via `TurnOffDevice`.
- **Nil-safe station sort** (`modules/vehicle/observersV.lua`):
  `GetRadioStations` now falls back to `0` when `tonumber(radio.fm)`
  returns `nil`, skips stations whose TweakDB record is missing, and uses
  a nil-safe comparator in `table.sort`.

---

## Utility Modules

- **`config.lua`**: `loadFile` returns `nil` instead of crashing when the
  file cannot be opened, is empty, or contains invalid JSON (wrapped
  `json.decode` in `pcall`). `saveFile` returns a boolean and wraps
  `json.encode` in `pccall`. The previous `local config = json.decode(...)`
  shadowing of the module table was removed.
- **`utils.lua`**: `miscUtils` and the `result` local in `split` are now
  scoped with `local`. `removeItem` no-ops when the value is not found —
  previously it called `table.remove(tab, nil)` which silently deleted
  the last element of the table, corrupting station playlists.
  `getIndex` now `break`s on the first match.
- **`init.lua`**: Version comparison now parses dotted version strings into
  numeric component arrays instead of doing a lexicographic compare (which
  considered `"0.10.0" < "0.9.0"`). `onShutdown` and `onUpdate` nil-guard
  `self.radioManager` and `self.radioManager.managerV` so an early-aborted
  init does not crash the shutdown or per-frame update handlers.
- **`Cron.lua`**: Updated to upstream `psiberx/cp2077-cet-kit` v1.0.3. The
  old forward-iterating `ipairs` + `i = i - 1` pattern silently skipped
  every other timer when one was removed mid-iteration; the new version
  uses a `halted`-flag + backwards prune pass.
- **`GameUI.lua`**: Updated to upstream v1.2.3. Adds the
  `MenuScenario_Credits*` scenarios, renames engine event observer hooks
  to match modern Cyberpunk 2077 versions (`OnSavesReady` →
  `OnSavesForLoadReady`, `OnSwitchToCredits` → `OnCreditsPicker`,
  `OnToggleFastTravelAvailabilityOnMapRequest` →
  `OnUpdateFastTravelPointRecordRequest`), and removes obsolete
  `type(request) ~= 'userdata'` workarounds.
- **`GameSettings.lua`**: Updated to upstream. Adds `SetGroupBool`,
  `ExportVars`, and `ImportVars` helpers; `ExportTo` drops the unused
  `keyBinds` parameter; `Import` no longer auto-calls `Confirm`.

---

## Logging

- Every station load prints a one-line summary with display name, FM
  frequency, song count, station type, and assigned index.
- Stream stations print their configured URL on load.
- Station activation and deactivation print the station name, channel,
  current song, and playback position (or URL for streams).
- Malformed metadata prints a warning naming the offending field and the
  coerced fallback value.
- A hint line fires when `isStream` is `false` but a `streamURL` is
  present, suggesting the user flip `isStream` to `true`.
- Load failures print the underlying Lua error message instead of a
  generic "make sure the file is valid" string.

---

## Compatibility

- The `metadata.json` schema is unchanged; existing station packs continue
  to work without modification. Malformed fields are repaired in place on
  first load.
- The CET-facing `RadioExt.*` API (function names, parameter order, types)
  is unchanged.
- The DLL export surface (`Main`, `Query`, `Supports`, `RegisterTypes`,
  `PostRegisterTypes`) is unchanged.
- The folder layout under
  `bin/x64/plugins/cyber_engine_tweaks/mods/radioExt/` and
  `red4ext/plugins/RadioExt/` is unchanged.
- The 13-vanilla-station convention and the `-1` vehicle / `1..N`
  physical channel convention are preserved.


## How to use:

- Have the latest version of the game installed
- Download and install [CET](https://github.com/yamashi/CyberEngineTweaks), latest version
- Download and install [Red4Ext](https://github.com/WopsS/RED4ext), latest version
- Download and install the mod from [here](https://github.com/justarandomguyintheinternet/CP77_radioExt/releases)

## Creating a new station:

### Prerequisites
- Everything from the [How to use](#how-to-use) section
- A text editor with syntax highlighting for editing JSON files (e.g. Sublime Text or VSCode), do **not** skip this, as most issues related to creating stations come from improperly edited JSON files.

### Folder Structure
- First you will need to find the installation directory of your game
- Next, navigate to the radioExt folder: `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt`
- In the radioExt folder you will see two items that will be important later: The template `metadata.json` file, and the `radios` folder
	```
	├── radioExt
		└── metadata.json <-- Template file
		└── radios
			└── ...
	```
- Each station is a folder inside the `radios` folder, containing a `metadata.json` file, which contains the information regarding the station
- So to create a new radio station firstly create a new folder inside the `radios` folder, and name it something unique (Like your station's name)
- Next, copy and paste the template `metadata.json` file from the mods root folder and paste it into your station's folder (The folder you created in the previous step)
- The folder structure should now look as follows:
	```
	├── radioExt
		└── radios
			└── folderForYourStation
				└── metadata.json
	```

### Adding Songs
- To add songs to your station, simply copy the song files into your station's folder
- Supported formats are: `.mp3`, `.wav`, `.ogg`, `.flac`, `.mp2`, `.wax`, `.wma`
- Keep in mind that the songs file names are being used as song names in-game, so keep them clean
- If you want to use a web audio stream instead of files shipped with your station, refer to the [Web Streams](#web-streams) section

### Metadata File

- The `metadata.json` file of your stations defines its properties such as the name, icon and more.
- Open it with any text editor that has **syntax highlighting for JSON files**, do **not** skip this, as most issues related to creating stations come from improperly edited JSON files.
- If your `metadata.json` file is missing any properties that have been added in an update of the mod, simply run the game once with the updated version of the mod installed, as that will add the missing fields automatically
- For properties that use strings (Such as `displayName`) any [reserved characters](https://www.lambdatest.com/free-online-tools/json-escape) need to properly escaped, again any half decent text editor will let you know if you missed any.

#### Basic Properties
- `displayName`: This controls the name of your station that will be displayed in the game
- `fm`: A number (Do not put it in quotation marks), which is used to place the station at the right place in the stations list. If the `displayName` has an FM number, it should be the same
- `volume`: Overall volume multiplier for the station (Also a number), make sure all songs have the same volume, then adjust the overall volume of the station with this value to match up with vanilla stations
- `icon`: The icon for the station, if you don't use a custom one. It can be any `UIIcon.` record. To find a list of all records, open the CET console's `TweakDB Editor` tab, and enter `UIIcon.` in the search bar (Make sure you have the [tweakdb.str](https://cdn-l-cyberpunk.cdprojektred.com/metadata-1.5.2.zip) file placed inside the `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks` folder)

#### Custom Icon
- All settings related to custom icons are inside the `customIcon` section of a stations `metadata.json` file
- `useCustom`: If this is set to `false` the icon specified inside `icon` will be used. If set to true the custom icon will be used
- `inkAtlasPath` points to the `.inkatlas` that holds the icon texture, e.g. `base\\gameplay\\gui\\world\\vending_machines\\atlas_roach_race.inkatlas` (Path requires double backslashes `\\`)
- `inkAtlasPart` specifies which part of the `.inkatlas` should be used for the icon, e.g. `gryphon_5`
- To create your own `.inkatlas` file, use [WolvenKit](https://github.com/WolvenKit/WolvenKit)
- Written tutorials can be found [here](https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-creators/modding-guides/custom-icons-and-ui) (The tutorials are for clothing / item icons, but the exact same process applies to radio station icons)
- A video tutorial can be found [here](https://www.youtube.com/watch?v=N8C8SaRypog) (WKit interface has changed a bit since the video has been made, so not everything shown there is at the same place anymore, but the general process is still the exact same)

#### Web Streams
- Instead of using song files placed in the station's folder, you can also use any web audio streams (URL's that end in e.g. `.mp3`, and display the default audio player when opened, e.g. `https://stream.antiradio.net/radio/8000/mp3`)
- Some examples can be found [here](https://truck-simulator.fandom.com/wiki/Radio_Stations#Radio_Stations_by_country)
- `isStream`: This must be set to true for the mod to try to stream from the specified URL
- `streamURL`: URL of the stream

#### Song Ordering
- The `order` field can be used to specify an order in which the songs should be played
- It must not contain all the songs of the station, any songs not specified in the `order` will be played randomly before / after the ordered section
- Simply add all the songs file names that you want ordered in the field, each as its own string and comma separated:
```json
"order": [
     "firstSongFile.mp3",
	 "secondSongFile.mp3",
	 "thirdSongFile.mp3"
]
```

## Troubleshooting
- If anything does not work as expected, firstly make sure that all the points of the [How to use](#how-to-use) section are fulfilled, and the required mods are working properly
- The mod prints messages to the CET console for most of the common issues, so open the CET console and look for any `"[RadioExt] Error/Warning: ..."` messages
>`"[RadioExt] Error: Red4Ext part of the mod is missing"`
- This means that the Red4Ext parts are either not installed, or could not be loaded by Red4Ext. Make sure you are on the most recent version of the game, and have the correct version of Red4Ext installed (Version of the game, version of Red4Ext and version of this mod must be compatible with each other). Also make sure that both the `RadioExt.dll` and `fmod.dll` files are present inside `Cyberpunk 2077\red4ext\plugins\RadioExt`
> `"[RadioExt] Red4Ext Part is not up to date: Version is xxx Expected: xxx or newer"`
- Make sure that the files inside `Cyberpunk 2077\red4ext\plugins\RadioExt` come from the same version of the mod you downloaded. Doing a clean install of the mod can help.
> `[RadioExt] Could not find metadata.json file in "radios/folderName""`
 - This means that you forgot to add the `metadata.json file` (See [Folder Structure](#folder-structure) section)
> `[RadioExt] Error: Failed to load the metadata.json file for "stationFolderName". Make sure the file is valid.`
- This means the `metadata.json` file is corrupted / not valid. Usually caused by missing brackets, commas or parentheses. Can also be caused by not properly escaped characters. Make sure to use a text editor with syntax highlighting / JSON validation.
> `"[RadioExt] Warning: The file "songFile.mp3" requested for the ordering of station "Station Name" was not found."`
- Make sure the file you specified in the `order` field does exist and that its filename is spelled properly
>`"[RadioExt] Error: Station "Station Name" is not a stream, but also has no song files. Using fallback webstream instead."`
- This happens if there are no song files in a station's folder, but the `isStream` flag in its `metadata.json` file is also not set to `true`
>`[RadioExt] Error: All channels used (Too many radios)`
- This happens if there are more physical radios playing a custom station than there are audio channels reserved by the mod (Currently 64, so this is extremely unlikely to ever happen)

#### Credits
- Uses [FMOD](https://www.fmod.com/) by Firelight Technologies
- [psiberx](https://github.com/psiberx/cp2077-cet-kit) for Cron.lua, GameUI.lua and GameSettings.lua
- [WSS](https://github.com/WSSDude420) for letting me use some of his C++ code
