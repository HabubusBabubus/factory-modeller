# Factory Modeller

A visual production planner for **Factorio 2.1**, in the spirit of Satisfactory Modeler: build production graphs on a canvas, group parts into factories with inputs and outputs, and see rates, machine counts, belts, fuel and electricity.

* Mod portal description (features and how to use it, English and Russian): [docs/mod-portal-description.md](docs/mod-portal-description.md)
* In-game user guide (Russian): [factory-modeller/README.md](factory-modeller/README.md)

Not affiliated with the authors of Satisfactory Modeler.

## Repository layout

    factory-modeller/          the mod itself (this folder goes into the archive)
        info.json              mod metadata, version
        changelog.txt          changelog shown in the game and on the mod portal
        data.lua               hotkeys, shortcut button
        settings.lua           mod settings
        control.lua            events, input handling, actions
        scripts/
            model.lua          projects, nodes, links, prototype helpers
            solver.lua         flow, surplus and electricity calculation
            render.lua         drawing the graph on the canvas surface
            gui.lua            window, panels, inspector, settings window
        locale/en, locale/ru   translations
    tests/                     automated tests with Factorio API stubs
    tools/                     build scripts
    docs/                      texts for the mod portal

## Building

The archive for the mods folder or the mod portal is written to `dist/` (not committed).

Windows:

    powershell -ExecutionPolicy Bypass -File tools/build.ps1

Linux / macOS:

    sh tools/build.sh

To install, copy `dist/factory-modeller_<version>.zip` to `%APPDATA%\Factorio\mods\`.

## Tests

The tests run the mod's logic outside the game against stubs of the Factorio API (Lua 5.2, the same version Factorio uses):

    lua5.2 tests/test.lua

They cover the solver (rates, surplus, priority splitter, electricity, fuel), grouping into factories and the canvas interactions. The stubs only imitate the game, so changes that touch the GUI or prototypes still need a check in Factorio.

## Debugging

`/fm-debug` in the game console shows the invisible drag handles on the canvas and logs GUI events to the chat and to `factorio-current.log`.
