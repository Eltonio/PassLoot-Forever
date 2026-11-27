# PassLoot Forever

## 5.1.3

- **Class books fixed**: a book, codex or tome for another class (such as "Book: Gift of the Wild II" for a druid) no longer counts as "Not learned yet, my profession", so a rule can no longer roll Need on it. The addon now reads the "Classes:" line of the book: another class means "Not my profession", and if the line cannot be read, recipe conditions do not match (you keep the roll).
- The "Classes:" line is read more reliably on French clients (non-breaking spaces), which also helps the "Usable by my class" condition.

## 5.1.2

- **Choose the chat window** where PassLoot messages appear (Options tab, "Show messages in"), saved per character, like in the original PassLoot. Falls back to the main chat window if that window is closed.
- **Rolls are checked**: the addon waits for the game to confirm each automatic roll before announcing it, tries once more if needed, and warns you in red if the game did not take it (useful with interface addons such as RealUI). A short delay before deciding gives the game time to load the item.
- **Known recipes are detected reliably** on WoW Forever, whose recipe tooltips show the crafted item first: no more Need on a recipe you already know. If the tooltip cannot be read, recipe conditions do not match (you keep the roll).
- Item type: **Armor - Miscellaneous** now also covers cloaks (no longer in Cloth), along with necklaces, rings and trinkets; the list says so.
- Test tab: a "Recipe" line shows whether the recipe is already learned and for your profession.
- New command `/plf tip <item>`: shows the item tooltip as the addon reads it, for bug reports.

## 5.1.1

- First stable release, after a week of beta testing. Same features as 5.1.0, no code changes.

## 5.1.0 (beta)

- New condition **Stat score gain vs equipped**: compares a drop with the gear it would replace, stat by stat, with weights per class and spec. Pick your spec with the **Score** button of the Test tab.
- The Test tab shows the stat score of the item, the score of your equipped item and the detail of each stat.
- `/plf diag` checks that the game can read item stats.
- Layout fixes for larger fonts and some resolutions: option rows no longer overlap, cut texts end with "..." and show in full in a tooltip, 1-pixel borders no longer disappear.

## 5.0.7 (beta)

- First public release: complete remake of PassLoot for WoW Forever (interface 16001), with a brand new interface.
- Rules with conditions, Test tab, profiles with export / import, journal, minimap button, English and French.
