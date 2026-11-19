# Titan Panel [Arranger]

Drag and drop arranging for Titan Panel, with a lock and Edit Mode support. For World of Warcraft: Forever.

Titan Panel places its plugins through right-click menus: a checkbox for the side, "take it off and put it back"
for the order, and a separate Short bar for anything in the middle. Dragging a plugin ignores where you drop it.
Arranger lets you put every plugin exactly where you want it by dragging, and keeps them there.

- **Drag and drop:** drag any plugin to any place on any Titan bar. A gold line shows exactly where it will land.
- **Left, centre or right:** every bar has a centre area as well as its two ends, so a plugin can sit in the middle.
- **Locked unless you are arranging:** plugins only move while you arrange, so a stray drag never moves anything.
  Start arranging by opening Blizzard's Edit Mode, by clicking the Arranger button (two tiles and an arrow) on your
  bar, with `/arranger` or with a key binding.
- **Show and hide by dragging:** while you arrange, a panel lists the plugins that are on no bar. Drag one onto a bar
  to show it, or drag a plugin from a bar onto the panel to hide it.
- **Plugin options in one click:** click a plugin while arranging for its side, its display choices (icon, label,
  value, coloured text), its margins on the left and right, and a Hide button.
- **Short bars without modifier keys:** drag a Short bar to move it and drag its right edge to size it.
- **Spacing for each area:** a slider each for the gap between plugins on the left, in the centre and on the right,
  and you see the change as you slide. Left and right are Titan's own Button Spacing and Icon Spacing; the centre
  has its own.
- **Margins for one plugin:** give any single plugin more room on its left or right, on top of its area's spacing,
  or less: below zero it moves towards its neighbour, at most halfway over the narrower of the two, so neither ever
  disappears, and never off the bar.
- **Arrow keys:** a selected plugin moves one place at a time, into the next area at the end of its own; a selected
  Short bar moves a pixel at a time (ten with Shift).
- **Revert:** puts every plugin and Short bar back where it was when you started arranging.

Every plugin Titan shows can be arranged: Titan's own, third-party Titan plugins and LibDataBroker plugins alike.
Your layout stays in Titan's own settings, per Titan profile.

## Using it

1. Open Edit Mode, click the Arranger button (two tiles and an arrow) on your Titan bar, type `/arranger`, or press
   the key you bound under Key Bindings, AddOns. Every plugin gets a blue box and the Arranger panel opens.
2. Drag plugins where you want them. Drop one on the panel's list to hide it; drag one from the list onto a bar to
   show it. Click a plugin for its options.
3. Close Edit Mode, click Done on the panel, click the Arranger button again or type `/arranger`. Plugins are locked
   again.

`/arranger revert` undoes everything since arranging started. `/arranger help` lists the commands. The panel has a
switch for whether Edit Mode starts arranging.

## Good to know

- The panel and the options popup are built like Edit Mode's own windows, with a Titan bar for a title in your
  bars' skin or colour, and Titan's font. The boxes over plugins stay blue, like the boxes Edit Mode draws around
  Blizzard's frames at the same time.
- The panel is as tall as its list, and grows or shrinks with it while its top stays put, up to 85% of the screen
  and never down over Titan's bottom bars (a drop on the panel hides a plugin, so it keeps out of their way); past
  that the list scrolls. Its corner sets the width, or a shorter height if you would rather the list scrolled; drag
  it taller again to go back to fitting the list.
  It can be moved, and remembers its place and size. When you arrange from Edit Mode it opens beside Edit Mode's own
  window.
- Titan spaces its two sides differently: "Button Spacing" for the left (20 by default) and "Icon Spacing" for the
  right (0 by default), from when the right side held only icons. The panel's Left and Right sliders are those two
  settings, also in Titan's own options; the Centre slider is Arranger's and starts out matching the left. All three
  run from 0 to 80. Titan's own options page offers 5 to 80 and 0 to 20 for its two, and shows a value outside that
  at its nearest end; Titan lays out any value.
- The Centre slider is grey until a plugin is in a centre area: drag one to the middle of a bar, where the bar says
  Centre while you arrange.
- Combat stops arranging, and it cannot start in combat.
- Bars set to auto-hide stay out while you arrange, so you can drop plugins on them. When you finish, each one
  slides away again as soon as the mouse is off it.
- Arranger keeps Titan's own "Lock Buttons" option ticked while you are not arranging. If you remove Arranger, untick
  it in Titan's options to get Titan's own dragging back.
- Titan's "Center Text" bar option does nothing on a bar that has plugins in its centre area: the centre area does
  that job.
- The Arranger button is a Titan plugin like any other: move it, or hide it and use Edit Mode, the slash command or
  the key binding instead.
- Needs Titan Panel 9.3.7 or later. If Titan changes in a way Arranger does not know, Arranger says so once in chat
  and stays out of the way, and Titan works as it always did.

## Install

Install it from [CurseForge](https://www.curseforge.com/wow/addons/titan-panel-arranger), by hand or with an addon
manager, or extract the zip from the newest [release](https://github.com/Rambomst/titan-arranger/releases) into
`World of Warcraft/_forever_/Interface/AddOns`, next to Titan Panel.

## Bugs and ideas

Report them as an [issue](https://github.com/Rambomst/titan-arranger/issues), with what you dragged and where.

## Support

If Arranger saves you some fiddling with Titan's menus and you'd like to say thanks, you can
[buy me a coffee on Ko-fi](https://ko-fi.com/ram01). It's free either way.
