import ctypes
import argparse
import os
import pathlib
import sys

PROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent


def first_existing(candidates):
    for candidate in candidates:
        if candidate and candidate.exists():
            return candidate
    return None


parser = argparse.ArgumentParser(description="Run a Lua 5.1 test with DST-compatible syntax/runtime semantics.")
parser.add_argument("test", type=pathlib.Path)
parser.add_argument("--lua-deps", type=pathlib.Path, help="Directory containing lua51Original.dll")
parser.add_argument("--mod-root", type=pathlib.Path, help="Mod source root exposed to Lua tests")
parser.add_argument("--original-scripts", type=pathlib.Path, help="Extracted current DST scripts directory")
args = parser.parse_args()

deps = args.lua_deps or first_existing([
    pathlib.Path(os.environ["DST_LUA51_DEPS"]) if os.environ.get("DST_LUA51_DEPS") else None,
    pathlib.Path(r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\Luajit\deps"),
])
if deps is None:
    raise SystemExit("lua51Original.dll directory not found; pass --lua-deps or set DST_LUA51_DEPS")

mod_root = args.mod_root or first_existing([
    PROJECT_ROOT if (PROJECT_ROOT / "modinfo.lua").exists() else None,
    PROJECT_ROOT / "work" / "dst_haptics_compat",
    PROJECT_ROOT / "dst_haptics_compat",
])
if mod_root is not None:
    os.environ["DST_HAPTICS_MOD_ROOT"] = str(mod_root.resolve())
if args.original_scripts is not None:
    os.environ["DST_ORIGINAL_SCRIPTS"] = str(args.original_scripts.resolve())
elif (PROJECT_ROOT / "work" / "original_scripts" / "scripts").exists():
    os.environ["DST_ORIGINAL_SCRIPTS"] = str((PROJECT_ROOT / "work" / "original_scripts" / "scripts").resolve())

os.add_dll_directory(str(deps))
lua = ctypes.WinDLL(str(deps / "lua51Original.dll"))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.luaL_loadfile.restype = ctypes.c_int
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_pcall.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

path = args.test.resolve()
state = lua.luaL_newstate()
lua.luaL_openlibs(state)

def fail(prefix):
    size = ctypes.c_size_t()
    message = lua.lua_tolstring(state, -1, ctypes.byref(size))
    text = message[:size.value].decode("utf-8", "replace") if message else "unknown Lua error"
    print(prefix + ": " + text)
    lua.lua_close(state)
    raise SystemExit(1)

if lua.luaL_loadfile(state, str(path).encode("utf-8")):
    fail("load failed")
if lua.lua_pcall(state, 0, 0, 0):
    fail("runtime failed")
lua.lua_close(state)
print("Lua 5.1 harness completed")
