extends SceneTree
## Converts a grayscale heightmap image (for example a MOLA / Mars Trek DEM tile downloaded
## during development and shipped under assets/nasa/) into a map JSON for WorldMapData.
##
## Run:
##   Godot --headless --path . --script tests/world/tools/heightmap_to_map.gd -- \
##     --heightmap res://assets/nasa/<tile>.png --out res://data/maps/<id>.json --id <id> \
##     [--size 48] [--min-m 0] [--max-m 12] [--airlock 10,24] [--slope-nonbuildable 0.6] \
##     [--slope-impassable 1.5] [--source "<provenance text>"]
##
## The result is a blockout at one cell per metre: cell height is the bilinear sample of the
## image luminance scaled to [min-m, max-m]; a cell whose height differs from any neighbour by
## more than --slope-nonbuildable is not buildable, and by more than --slope-impassable is
## impassable. Record the asset in ATTRIBUTION.md before committing the output.

const DEFAULTS := {
    "heightmap": "", "out": "", "id": "", "size": "48", "min-m": "0", "max-m": "12",
    "airlock": "", "slope-nonbuildable": "0.6", "slope-impassable": "1.5", "source": "",
}


func _initialize() -> void:
    var args := _parse_args()
    for key in ["heightmap", "out", "id"]:
        if args[key].is_empty():
            push_error("--%s is required" % key)
            quit(2)
            return
    var image: Image = Image.load_from_file(ProjectSettings.globalize_path(args.heightmap))
    if image == null or image.is_empty():
        push_error("Could not load heightmap " + args.heightmap)
        quit(1)
        return
    var size := int(args["size"])
    var min_m := float(args["min-m"])
    var max_m := float(args["max-m"])
    var heights: Array = []
    for z in size:
        var row: Array = []
        for x in size:
            var u := (float(x) + 0.5) / float(size)
            var v := (float(z) + 0.5) / float(size)
            row.append(snappedf(lerpf(min_m, max_m, _sample(image, u, v)), 0.01))
        heights.append(row)
    var airlock := [size / 2, size / 2]
    if not args.airlock.is_empty():
        var parts: PackedStringArray = args.airlock.split(",")
        airlock = [int(parts[0]), int(parts[1])]
    var overrides: Array = []
    var impassable := float(args["slope-impassable"])
    var nonbuildable := float(args["slope-nonbuildable"])
    for z in size:
        for x in size:
            var h: float = heights[z][x]
            var slope := 0.0
            for step in [[1, 0], [0, 1], [-1, 0], [0, -1]]:
                var nx: int = x + step[0]
                var nz: int = z + step[1]
                if nx >= 0 and nx < size and nz >= 0 and nz < size:
                    slope = maxf(slope, absf(heights[nz][nx] - h))
            var passable := slope <= impassable
            var buildable := slope <= nonbuildable
            if [x, z] == airlock:
                passable = true
            if h != 0.0 or not passable or not buildable:
                overrides.append({"cell": [x, z], "passable": passable, "buildable": buildable, "height_m": h})
    var map := {
        "schema_version": 1,
        "id": args.id,
        "revision": 1,
        "owner": "task_02_world",
        "metadata": {
            "status": "heightmap_derived",
            "source": args.source,
            "heightmap_path": args.heightmap,
            "height_range_m": [min_m, max_m],
            "note": "Cell heights sampled from the referenced heightmap; passable/buildable flags derived from local slope thresholds. Vertical scale is a game abstraction unless the source record says otherwise.",
        },
        "size_cells": [size, size],
        "default_cell": {"passable": true, "buildable": true, "height_m": 0.0},
        "cell_overrides": overrides,
        "base_airlock_cell": airlock,
    }
    var file := FileAccess.open(args.out, FileAccess.WRITE)
    if file == null:
        push_error("Cannot write " + args.out)
        quit(1)
        return
    file.store_string(JSON.stringify(map, "  "))
    file.close()
    print("HEIGHTMAP_MAP_WRITTEN ", args.out, " cells=", size * size, " overrides=", overrides.size())
    quit(0)


func _sample(image: Image, u: float, v: float) -> float:
    var fx := u * (image.get_width() - 1)
    var fy := v * (image.get_height() - 1)
    var x0 := int(floor(fx))
    var y0 := int(floor(fy))
    var x1 := mini(x0 + 1, image.get_width() - 1)
    var y1 := mini(y0 + 1, image.get_height() - 1)
    var tx := fx - x0
    var ty := fy - y0
    var a := image.get_pixel(x0, y0).get_luminance()
    var b := image.get_pixel(x1, y0).get_luminance()
    var c := image.get_pixel(x0, y1).get_luminance()
    var d := image.get_pixel(x1, y1).get_luminance()
    return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _parse_args() -> Dictionary:
    var args := DEFAULTS.duplicate()
    var user_args := OS.get_cmdline_user_args()
    var index := 0
    while index < user_args.size():
        var arg: String = user_args[index]
        if arg.begins_with("--"):
            var key := arg.substr(2)
            var value := ""
            if arg.contains("="):
                key = arg.substr(2, arg.find("=") - 2)
                value = arg.substr(arg.find("=") + 1)
            elif index + 1 < user_args.size():
                index += 1
                value = user_args[index]
            args[key] = value
        index += 1
    return args
