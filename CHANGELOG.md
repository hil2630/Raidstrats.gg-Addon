# Changelog

## [Release 0.0.50]

We are now out of alpha testing and went straight to release candidates.

Added:

- Tidebound Grotto added to the ingame plannner.

New:

- In-game language picker (Settings -> Misc).
  - Choose Auto (client locale), English, Danish, or Traditional Chinese.
  - Addon UI strings refresh live when you change language.
  - If you want to add your own translationn, please see the enUS.lua and follow the same steps and contact me on discord and we can add it.
    Currently looking for french, spanish, german, polish and such.
- Imported boss and trash markers now use bundled portraits when a matching
  image exists, with the existing labeled badge as a fallback.
  - Raid admins can download an addon-ready TGA portrait ZIP from the website.

Fixed:

- Addon exports now include boss and trash objects from every scene, not only
  the scene that was open when the plan was exported or saved.

## [Alpha 0.0.49-f]

New:

- Share to Group now preloads the plan (or plan group) once over party/raid/instance AceComm.
  - Clickers import from the local cache instead of each whispering a full download from the sharer.
  - Whisper request remains as fallback for late joiners / missed broadcasts.
  - With `/rsggdebug` on, receiving a share cache logs plan/group name, sender, and payload size.

Fixed:

- Plan/group share transfers no longer spam hundreds of tiny BULK packets (was taking 1–2+ minutes or hanging on "Requesting plan...").
  - Sends one AceComm message (library multipart) at NORMAL priority instead.
  - Chat link is posted slightly after the preload so receivers can cache first.
  - Request timeouts after 45s with a clear error instead of spinning forever.
  - `/rsggdebug` logs cache hit/miss, REQ handling, and send sizes.
  - Raidcheck send-notif / missing-plan whispers use the same faster NORMAL transfer path.

## [Alpha 0.0.48]

New:

- Readycheck Raidcheck now checks plan sync version, not only whether someone has the plan.
  - If they have the plan but a different version, status shows Wrong version. Hover to see theirs vs correct.
  - Setting: Check plan versions on readycheck (raid leaders) — Settings -> Raid Lead, on by default.
  - Right-click / Send to all missing also covers wrong-version players.
  - Version bumps only when readycheck/share sees real content changes vs the last stamped baseline (not on every drag/edit, and not on every identical re-send).
- Planner canvas shows a subtle `Version: X-key` in the bottom-right when a plan is open.
- Settings: new Raider and Raid Lead tabs (readycheck options split out of Misc).
  - Raider: assignments, auto not ready, grace/phase, hide raidcheck notifications.
  - Raid Lead: side raidcheck on readycheck, plan version check, expanded raidcheck panel.
- Edit Mode: Raidstrats is now a checkbox in Account Settings (Basic options) instead of the side logo button.
  - Settings Compact now Opens Edit mode and starts the compact position preview (auto-saves when moved).
- Settings Compact: Preview next to Show background opens a live compact preview beside the dialog.
  - New Background opacity control (disabled when background is hidden).

Fixed:

- Readycheck / note-plan bundle import now overrides existing plans (same UUID/identity) instead of skipping them.

## [Alpha 0.0.47]

New:

- Added a raid-leader setting to show Raidcheck on readycheck (Settings -> Misc, on by default).
  - Opens a side Raidcheck panel on the right of the screen (works alongside readycheck assignments).
  - Checks only the plans bound in the loaded NSRT note (`rsgg-bind`) and shows X/Y per player.
  - Stays open for 30 seconds after readycheck ends (or until closed).
  - Right-click a player missing plans to Send all note plans, or use Send to all missing.
- Added Auto Not Ready if missing note plans (Settings -> Misc, on by default).
  - Players with the addon who are missing any plans, auto-answer Not Ready on Readychecks.
  - When that happens, they request the note plans from the raid leader, who auto-sends one Import N plans popup for the full note set (every `rsgg-bind`, not only assigned/missing ones).
  - On the raid leader's readycheck Raidcheck panel, those players show as Auto-sent after the plans are sent, so the RL doesn't have to send them manually.

Updates:

- `dur:` now shows the plan before the cue time instead of after (same pattern as other NSRT timers).
  - Example: `time:100;dur:30` shows from 70 to 100.
- Readycheck grace period default is now 10 seconds (was 5).

## [Alpha 0.0.46]

New:

- Added a guided tour for first-time users (replay anytime with /rsggtour).
- Added Ctrl+click in the Plan Library to select multiple plans, then right-click to group them.
- Added more tips to the in-game Help window.
- Added a setting to hide raid plans during combat (Settings -> Misc, off by default).
- Added a Copy button for our Patreon link (join.raidstrats.gg).

Fixed:

- Only one "new version available" message now, instead of several.
- The Plan Library no longer jumps to the top when you load a plan.
- Imported text now keeps its alignment and background color.
- Text background color no longer grows too large when you zoom in (it stays around the text).
- Opening the planner now closes the readycheck assignment popup first.
- Cones and other shapes now fill with a solid color instead of showing lines.

## [Alpha 0.0.45]

As we've changed our system to work with uuids, it's not feasable to have multiple plans with same UUID, hence why we've done some changes. Check below.

- Added a way to import multiple plans using our basic !raidstrats-addon prefix, so you can copy e.g. 3 import strings in to import all at once.

- Updated the default duration of NSRT to be 8 sec instead of 30 sec, if dur:N is not set.

- Fixed an issue where you could import the same plan with same uuids as 2 different ones.
- Fixed an issue where you could import duplicate groups.

- Removed the NSRT Button for now.

## [Alpha 0.0.44]

- Added a new setting to only show ready-check assignments in raid groups. Enabled by default.
- Added a new setting to remove background tint when NSRT triggers compact mode in combat so you'll only see objects and nothing else (if background is also disabled)
- Added a new setting to keep the Compact mode open during combat so it'll always show your next assignment coming up.
  - This is disabled by default and needs to be enabled under Misc.

- updated the NSRT Compact mode to be click-through and non-expandable during combat
  - This means you can place it anywhere and wont move it by mistake during combat. And even have it on top of your char if needed (cool for arrow assignment)
    This is a setting in the settings panel and enabled by default.

- Updated how tagging works. You can now push an NSRT note with assignments and the labels in the plans affected will be updated accordingly to the NSRT Note, but only while the NSRT Note is loaded. This means you don't have to change labels in the plan anymore to make it show "correctly" for everyone.

- Fixed an issue where the Raidcheck would show on the NSRT trigggered compact mode.
- Fixed an issue where hiding the background wouldn't work sometimes

## [Alpha 0.0.43]

Info: The NSRT assignments are now fixed, so they should work properly ingame in combat.

- Added tabs on top of the ready-check compact mode so you can quickly switch between assignments on readycheck.
- Added a grace period for the compact mode so it doesn't instantly close once everyone is ready. This grace period can be changed in Settings -> Dispaly -> Readycheck Graceperiod.
- Added a "Raidcheck expand mode" in settings -> Display -> Raidcheck expanded. Enabled by default.
- Added The Venomus Abyss backgrounds to the planner.
- Added Arrows/Lines as objects. Rightclick the object in the palette to switch between them.
- Added a "replace" to the right-click menu when doing it on worldmarkers, so you can quickly replace them.

- Updated the New Plan and New Scene modal to include expansion to have less clutter in the raid list. Should now only show raids from selected expansion.
- Updated the planner to now also include spell icons when importing plans.
  - You can enable tooltips on abilities also, by enabling them from the bottom left cornor on plans where abilities are present.
- Updated Donut shapes to properly render and be moveable
- Updated Ellipses to also include strokes as other objects by default.
- Updated arrows & lines to be moveable.

- Fixed an issue with NSRT assignments not properly showing when NSRT fires new events. It should now properly work. Please use the NSRT builder on the website to create correct notes.
- Fixed an issue where colored backgrounds (with no arenas) wasn't properly imported in scenes.
- Some minor fixes all around to up optimization.

## [Alpha 0.0.42]

Info:
The NSRT Builder is now legacy, I recommend using our new NSRT Builder on the website.
Planner -> Share -> NSRT Note.

- Added the Compact mode viewer to the editmode, so you can move it via wow's edit mode.
- Click the Raidstrats.gg logo on the left side of editmode to enable it.
- Added the Export Roster to the main planner now, to export your current roster to the website.
- Added a way to reorder plans in the library, simply drag and drop them on top of eachother, one way or another.
- Added a way to rename plans in the plan library, right click -> Rename.
- Added a way to shift+click plans in the library to share the plan quickly, instead of clicking the share to group button. (e.g. for Private
  messages, etc).
- This also works for groups, shift+click on the group name while your chat is open.
- Added delta-sharing when pushing updates, so you don't have to fuilly reimport the entire plan on minor changes.
- This is a new way of updating plans. Now when you update objects and pushes updates, only that specific object is pushed to everyone else
  that has it. Please report any bugs that may occur. Preferable if you can send debug log (/rsggdebug).
- Added a new method to the Raidcheck that allows raidleaders to Rightclick a user -> Send notif to send a notification to that specific user
  instead of all in group.

- Removed the update available popup. I'll now just show in your chat to update.
- Removed the legacy window for the addon. The planner is now the main window where you do everything now.

- Updated modals to follow our own design aesthetics, rather than wow's default.
- Updated deleting plans. No more modals, it's just a simply yes/no on the plan row to make it quick.
- Updated the Share to Group. Now no longer shares to Guild if not in a group, instead it'll send in say chat.
- Updated import time of plans. Note that big plans with many objects can still take some time to import

- Fixed an issue where loading plans with midnight falls background didn't load the background properly.
- Fixed some issues with the raidcheck
- Fixed several ui design issues

Note: We're nearing us an initial beta release. Stay tuned for more and as always, join our discord for the most up-to-date info: https://discord.gg/QtU244VZ8X

## [Alpha v0.0.41] Fixes to importing, readycheck assignment check, group imports and more.

- Fixed an issue where importing raidplans with multiple scenes would show wrong object sizes on other scenes (You will have to
  re-import the plan from raidstrats.gg)
- Fixed the preview/show names so it actually works with attached labels now also.
- Fixed an issue where, when reassigning a circle, the circle color would not change to the class color.
- Fixed an issue where when hovering an assignment-object, the tooltip wouldn't render correct names after changing them.

- Added a new ready-check setting. When readycheck pops, your assignment will showup and you'll be able to navigate through them using
  the arrows in the readycheck-compact view. You can enable this in your settings. The position of the assignment is defined by the NSRT Position you set in the settings.
- Added a "show/hide assignments" in the planner that'll hide any assignments if any.
- Added a way to import groups from the website. If you have multiple plans in a group on the website simply go to the Groups tab under My Plans and Export to addon -> Import this. It'll auto-import all the plans in the group and give the group a name.

## [Alpha v0.0.40] Fixes to backgrounds, importing circle-modes, assignments, debugging and more.

- Upped version to 12.0.7.

- Fixed an issue where imported raidplans with circle mode enabled didn't render correctly
- Fixed an issue where the midnight falls background didn't work correctly due to spelling mistake :(
- Fixed an issue where multi-plan assignments would show your assignment twice on multiple scenes, even if you don't have multiple assigns.

- Updated the rsggtest debug to only be local to you and stop it via /rsggtest stop
- With this update it also works for all phases and not only a specific phase, unless phase specified (e.g. /rsggtest 3183 2 to test phase 2 of Lura note)

- Added a new settings interface
- Added a way to hide the minimap icon from Settings -> Misc tab
- Added a way to remove indexes from objects in the plan in the right-click menu on objects.
- Added grouping to the plan library, so you can now right click a plan -> Group and then drag and drop other plans into thegroup. You can also select multiple plans by holding down Shift + click and rightclicking -> Group.
- Added a way to share entire groups with your team, this should make it easier for RaidleFads to import all plans -> Group -> Share entire group instead of single plans. To share a group simply rightclick the group name -> Share to group. A link will be sent in the chat they can click, just like with a normal plan share.

_WIP Added The Venomus Abyss Boss names in the plan creater, backgrounds coming very soon._

## [Alpha v0.0.39] Multi-plan assignments, changes to preview & set compact modes, and more.

- Fixed an issue where imported arrows would all point in the same direction
- Fixed an issue where the preview & set would not correctly show the settings set on the comapct mode (e.g. hide bg, etc. )
- Fixed an issue where cones could not properly be moved.
- Fixed an issue where text would sometimes have an index.
- If they do, the index will be removed on import.
- Fixed an issue where some objects would be grey even if they had no indexes
- We recolor objects to grey (default) if they have assignments to differentiate between your assignment and others.

- Added a way to use multiple plans for 1 assignment.
  Note: Each plan now have a unique key based on their UUID of the raidplan from raidstrats.gg. The NSRT Export will automatically fillout this and use this (WIP)
  In the NSRT Export function on the website, you can now add multiple plans together, simply open up the plans you need to work on and add them in there with aliasses, e.g.:
  Plan A and Plan B. You do whaatevre you need on Plan A and then you open the NSRT Export and define an Alias, in this case we'll call it A.
  Plan B you open in a new tab and do your assignments in there, open NSRT Exporter, you should now see Plan A already in there, no simply call this one plan B.
  All info is automatically added to the note.

  Note that you MUST import both plans for this to work!

- Updated the Preivew & Set/compact to allow a bigger size as well as info-header that it's only for NSRT Triggered plans.
- Updated the Import Plan input box to now have clear feedback that it's selected.
- Updated the default cue timers in settings to be 0.

## [Alpha v0.0.38] Scrubbing in the timeline, frontal animations available and more

- Fixed an issue where the compact-mode would show unwanted items. Should now only show the compact window.
- Fixed a few issues with zooming in the canvas.
- Fixed an issue where when having multiple assignments on the same plan and in the same phase, it would default to the last available assignment.
- Fixed an issue where the compact mode were unintendedly using the main-window size as reference.

- Updated the design of some buttons and areas overall.
- Preview index' have been moved to another button in the bottom right of the planner.

- Added a NSRT Export button below the canvas. Click it to quickly create a custom assignment note
- The Export system automatically detects players in your plan and their indexes and auto-adds them to your note
  you will have to specify timers and phases for the note to work properly
  Note that group-tag is currently a WIP and for now it'll just tag people individually.
  When clicking "Add + send" the note will auto-append to your current note and send the update to all in your group.
  Notes are plan-based. Meaning it knows what note belongs to what plan, so when you open NSRT Export up, it'll load in your current assignments on this specific plan and note.

- Added a way to scrub in the timeline, simply click and drag to see animations come to life.
- Added frontal animations (most should work)
- Added the possibility to have multiple assignments on the same scene for the same player.
- If you have multiple assiggnments on a scene, you can switch between them in the dropdown below the "Hide names"
  This will only show if you have more than 1 assignment.
- Added a zoom-in-compact mode that allows you to zoom into your assignment for easier view.
- You can enable this in the settings and control the zoom level from there.
- Preview the zoom level by clicking "Preview zoom" - this will bring up the compact version and allow you to set the zoom levels using the +/- to your liking. It'll by default show your current assignment in the current raidplan, in the preview.

## [Alpha v0.0.37] Delete scenes, Rotmire added, auto-scene switch as raid-lead and much more.

- Fixed an issue where you couldn't remove or even move cone objects.
- Fixed an issue where plan wouldn't correctly categorize into the correct expansions or raids
- Fixed an issue where when pushing updated plans, any new scenes wouldn't correctly be shown until refresh.
- Fixed an issue where "share to group" and "New scene" were active even when no plan was loaded.
- Fixed an issue where when moving Cones specifically, it wouldn't move it with a live preview due to how it's rendered.
- Fixed an issue where the palette was still usable even though no plan was loaded.
- Fixed an issue where arrows would not be exported correctly from the website to the addon.

- Updated the planner to now also include Sporefall - Rotmire backgrounds.
- Updated the plan list to be a little more compact. You can disable compact view in the settings, enabled by default.
- Updated the char limits of the plan name on top to 50 from 20.

- Added a "Search for plan" and plan filter by expansion.
- Added a fallback to boss images, since we do not plan to implement boss-images. Boss images will not be a circle with "Boss" text.
- Added a way to delete scenes, right click a scene -> Delete.
  - Note: Scene 1 cannot be deleted. This would just delete the plan, so just delete the plan from your plan library instead.
- Added a way for raidleaders to decide the scene to look at.
  - Members of the group will be asked to approve or deny auto-switch and the raidlead will be able to see who have it enabled/disabled in the raid-check overview. Checkmark = Enabled, X = Disabled
- Added a info strip at the bottom of the planner window with basic info, and moved the version, etc. down there.
- Added a way to change scene in compact mode using arrows (enable this from settings)

- Removed the 30 second cooldown for "Send notif" in the raid checker.
  - Note that users may disable the notification popup from their settings in the addon.

## [Alpha v0.0.36] going live today.

- Fixed an issue where spec-icons were not properly mapped on import
- Fixed an issue where labels were added to all objects with their object-name. Objects should now only have labels, if they are added beforehand.
- Fixed an issue where resizing the main window wouldn't resize the palette properly, causing some icons to be bigger than their parent box.
- Fixed some spelling mistakes in our bg TGA files.

- Added a way to enable Circle mode.
  - After importing a raidplan with class/spec- icons you can new decide to show them as circles instead, this makes it easier to see positions. This option is available in the Settings panel.
- Added specs + class icons to the palette.
- Added a "New plan" button. This allows you to create plans ingame, rather than on the website.
  - Note: The addon currently does NOT support exporting plans and importing them into the website, this is a WIP.
- Added a "New scene" button to create a new scene.
- Added a "Change background" which will allow you to change the background of the current plan.
- Added new backgrounds for Midnight intermission, p2 and p3 Soaks

- Updated the icons to now have a ghost-version of the icon follow your mouse before placing it.
- Updated the Preview names to also work on imported plans where labels are attached to objects.
- Updated some allignment issues for arrows, text, etc.

## [Alpha v0.0.35]

- Fixed an issue where you couldn't click properly in the import plan textbox modal
- Fixed an issue where cones were not imported correctly and instead showed as squares
- Fixed an issue where imported text would be OFF by a tiny bit to the right.
- Fixed an issue where labels were too small when enabling "Preview names"
- Fixed an issue where labels were not imported if you had labels on objects.

- Updated plans to now follow the same layerIndexing as on the webplanner, so objects should now be also have layering, e.g. items in front/behind other objects.
- Added extra info to the help section about NSRT Setups.
- Added credits

## [Alpha release v0.0.31]

- Up TOC to correct number

## [Unreleased]

### Added

- In-game raid assignment viewer
- Share to Group and Push Update for raid leaders
- Roster sync from your current group
- Raidcheck status panel
- NSRT integration for timed assignment popups
- Import/export with the Raidstrats.gg web planner
