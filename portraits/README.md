# Imported enemy portraits

Add boss and trash portraits as TGA files using this structure:

```text
portraits/
  <raid>/
    <boss>/
      <enemy>.tga
```

Raid/boss folders are derived from the website icon path
`icon/raids/<raid>/Bosses/<boss>/...` (not only the DB display name). File names
keep the exact image basename (e.g. `plexus_sentienl.tga`) and also a slug alias
(`plexus-sentienl.tga`). Admin ZIP export walks that icon tree so names match
imports.

Example:

```text
portraits/
  the-voidspire/
    vorasius/
      vorasius.tga
      shadowguard-mage.tga
```

New website exports include each enemy's source filename plus the raid/boss
folders from its icon path (`portraitRaid` / `portraitBoss`). That matters for
multi-boss plans where each scene uses a different boss folder. Give the TGA
the same filename (but with `.tga`) for an exact match. Older exports fall back
to the icon path, scene background slug, then the plan-level boss name.
Imported plans automatically use a matching portrait; if no file exists, the
addon keeps the existing labeled boss/trash badge.

BLP files are also supported, but TGA is the expected format.
