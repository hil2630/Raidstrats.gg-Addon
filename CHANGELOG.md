# Changelog

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
- Added a way to share entire groups with your team, this should make it easier for Raidleads to import all plans -> Group -> Share entire group instead of single plans. To share a group simply rightclick the group name -> Share to group. A link will be sent in the chat they can click, just like with a normal plan share.

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
