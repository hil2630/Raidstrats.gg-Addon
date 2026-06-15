# Changelog

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
