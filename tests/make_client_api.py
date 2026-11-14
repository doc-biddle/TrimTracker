#!/usr/bin/env python3
"""Makes tests/client-api.lua and .luacheckrc from the real client's global names.

The names come from Biddle Utilities' /biddle apidump, saved in
  WTF/Account/<account>/SavedVariables/BiddleUtilities.lua
Run from the repository root:  python3 tests/make_client_api.py <path to BiddleUtilities.lua>

Only the names this addon (and its tests) actually mention are kept, so the files stay small. Names the addon
mentions that the client does NOT have are listed at the end: each must be one the code only uses after checking
it exists (a fallback for another client version). Review them, then list them in FALLBACKS below.
Needs the Python package lupa (pip install lupa) to read the saved-variables file.

This file is the same in every addon repository.
"""
import glob, os, re, subprocess, sys

import lupa

# Names the code uses only after checking they exist (other client versions). Shared by all three addons.
FALLBACKS = {
    "GetItemInfo", "GetItemInfoInstant", "GetSpellInfo", "IsHarmfulSpell", "GetAddOnMetadata",
    "GetContainerItemID", "GetContainerNumSlots", "GetItemCooldown", "UnitBuff", "GetMaxLevelForPlayerExpansion",
    "GetFactionInfo", "GetNumFactions", "CreateSettingsListSectionHeaderInitializer", "CUSTOM_CLASS_COLORS",
    "LibStub", "Titan_G", "Titan_Menu", "SPELL_CAST_CHANNELED", "UNIT_SKINNABLE_LEATHER", "GameTooltip_SetDefaultAnchor",
    "BackdropTemplateMixin", "EditModeManagerFrame", "QuestTimerFrame", "PlayerHasToy", "GetNumSkillLines", "GetSkillLineInfo",
}
# Globals the addons set themselves (saved variables and slash commands).
WRITES = ["HoverWiseDB", "RestedWatchDB", "TrimTrackerDB", "BiddleUtilitiesDB", "SlashCmdList",
          "SLASH_HOVERWISE1", "SLASH_RESTEDWATCH1", "SLASH_TRIMTRACKER1", "SLASH_TRIMTRACKER2"]
LUA51 = set("""assert collectgarbage dofile error getfenv getmetatable ipairs load loadfile loadstring module next pairs
pcall print rawequal rawget rawset require select setfenv setmetatable tonumber tostring type unpack xpcall
coroutine debug io math os package string table _G _VERSION newproxy gcinfo""".split())


def load_dump(path):
    lua = lupa.LuaRuntime()
    src = open(path, encoding="utf-8", errors="replace").read()
    env = lua.eval('function(s) local env = {}; assert(load(s, "sv", "t", env))(); return env end')(src)
    api = env["BiddleUtilitiesDB"]["api"]
    to_py = lambda t: {k: v for k, v in t.items()} if t else {}
    globals_ = to_py(api["globals"])
    namespaces = {k: to_py(v) for k, v in api["namespaces"].items()}
    enums = {k: sorted(to_py(v).keys()) for k, v in api["enums"].items()}
    return str(api["build"]), globals_, namespaces, enums


def addon_globals(files):
    """The globals the addon really reads, as luacheck sees them (locals excluded)."""
    out = subprocess.run(["luacheck", "--std", "lua51", "--no-config", "--formatter", "plain", "--codes", *files],
                         capture_output=True, text=True).stdout
    return set(re.findall(r"\(W11[23]\) (?:accessing undefined variable|mutating non-standard global variable|"
                          r"setting non-standard global variable) '(\w+)'", out))


def used_fields(files):
    """C_Namespace.Field and Enum.Name.Key mentioned anywhere in the addon or its tests."""
    ns, enum = {}, {}
    for path in files:
        text = open(path, encoding="utf-8").read()
        for a, b in re.findall(r"\b(C_\w+)\s*\.\s*(\w+)", text):
            ns.setdefault(a, set()).add(b)
        for m in re.finditer(r"\b(C_\w+)\s*=\s*\{([^}]*)\}", text):   # game.C_X = { Field = ... }
            ns.setdefault(m.group(1), set()).update(re.findall(r"(\w+)\s*=\s*function", m.group(2)))
        for a, b in re.findall(r"\bEnum\s*\.\s*(\w+)\s*\.\s*(\w+)", text):
            enum.setdefault(a, set()).add(b)
        for m in re.finditer(r"\bEnum\s*=\s*\{(.*?)\}\s*\}", text, re.S):  # game.Enum = { X = { K = 1 } }
            for name, body in re.findall(r"(\w+)\s*=\s*\{([^}]*)\}", m.group(1) + "}"):
                enum.setdefault(name, set()).update(re.findall(r"(\w+)\s*=", body))
    return ns, enum


def test_globals(files):
    """The game names the tests define (game.Name = ...) and the fake game itself defines."""
    names = set()
    for path in files:
        names |= set(re.findall(r"\bgame\.(\w+)", open(path, encoding="utf-8").read()))
    return names


def lua_list(items, indent="\t"):
    return "".join(f'{indent}"{x}",\n' for x in sorted(items))


def main():
    build, globals_, namespaces, enums = load_dump(sys.argv[1])
    addon_files = [f for f in glob.glob("*.lua")]
    test_files = glob.glob("tests/*.lua")
    used_addon = addon_globals(addon_files)
    ns_used, enum_used = used_fields(addon_files + test_files)
    used = used_addon | test_globals(test_files)

    in_client = sorted(n for n in used if n in globals_)
    missing = sorted(n for n in used_addon if n not in globals_ and n not in LUA51 and n not in WRITES)

    # tests/client-api.lua: the client's names that this addon or its tests mention, and for each C_ namespace
    # mentioned, all of its functions.
    with open("tests/client-api.lua", "w") as out:
        out.write(f"-- Made by tests/make_client_api.py from /biddle apidump, client build {build}. Do not edit.\n")
        out.write("-- The game names this addon or its tests mention, as the real client has them.\n")
        out.write("return {\n\tglobals = {\n")
        for n in in_client:
            out.write(f'\t\t["{n}"] = "{globals_[n]}",\n')
        out.write("\t},\n\tnamespaces = {\n")
        for n in in_client:
            if n in namespaces:
                keep = sorted(f for f in ns_used.get(n, ()) if f in namespaces[n])
                out.write(f'\t\t["{n}"] = {{ ' + ", ".join(f'["{f}"] = "f"' for f in keep) + " },\n")
        out.write("\t},\n}\n")

    # .luacheckrc: the same names as read-only globals, C_ namespaces and Enum with their real fields, so a call to
    # anything the client lacks is a warning (and fails the pipeline).
    with open(".luacheckrc", "w") as out:
        out.write(f"-- Made by tests/make_client_api.py from /biddle apidump, client build {build}. Do not edit.\n")
        out.write('std = "lua51"\nmax_line_length = false\nexclude_files = { "tests/", ".release/" }\n')
        out.write('ignore = { "212" }   -- unused arguments (event handlers and hooks get fixed argument lists)\n')
        out.write("globals = {\n" + lua_list(WRITES) + "}\n")
        out.write("read_globals = {\n")
        for n in (x for x in in_client if x not in WRITES):
            if n in namespaces:
                keep = sorted(f for f in ns_used.get(n, ()) if f in namespaces[n])
                out.write(f'\t{n} = {{ fields = {{ ' + ", ".join(f'"{f}"' for f in keep) + " } },\n")
            elif n == "Enum":
                out.write("\tEnum = { fields = {\n")
                for e in sorted(enum_used):
                    if e in enums:
                        keep = sorted(k for k in enum_used[e] if k in enums[e])
                        out.write(f'\t\t{e} = {{ fields = {{ ' + ", ".join(f'"{k}"' for k in keep) + " } },\n")
                out.write("\t} },\n")
            elif n not in LUA51:
                out.write(f'\t"{n}",\n')
        out.write("\t-- Not in this client: used only after checking they exist (other client versions).\n")
        out.write(lua_list(sorted(n for n in missing if n in FALLBACKS)))
        out.write("}\n")

    print(f"client build {build}: {len(globals_)} globals, {len(namespaces)} C_ namespaces")
    print(f"{len(in_client)} client names mentioned by this addon or its tests")
    for n, fs in sorted(ns_used.items()):
        absent = sorted(f for f in fs if n in namespaces and f not in namespaces[n])
        if absent:
            print(f"  {n}: not in this client: {', '.join(absent)} (fine only if checked before use)")
    for e, ks in sorted(enum_used.items()):
        absent = sorted(k for k in ks if e not in enums or k not in enums[e])
        if absent:
            print(f"  Enum.{e}: not in this client: {', '.join(absent)}")
    unreviewed = [n for n in missing if n not in FALLBACKS]
    if missing:
        print("mentioned by the addon but not in this client:")
        for n in missing:
            print(f"  {n}{'' if n in FALLBACKS else '   <-- NOT REVIEWED: guarded fallback, or a bug?'}")
    sys.exit(1 if unreviewed else 0)


if __name__ == "__main__":
    main()
