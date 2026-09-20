import argparse
import ctypes
import os
import pathlib
import sys

project_root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description="Parse every mod Lua file with DST's Lua 5.1 runtime.")
parser.add_argument("--mod-root", type=pathlib.Path)
parser.add_argument("--lua-deps", type=pathlib.Path)
args = parser.parse_args()
root = args.mod_root or (project_root / "work" / "dst_haptics_compat")
deps = args.lua_deps or pathlib.Path(os.environ.get(
    "DST_LUA51_DEPS",
    r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\Luajit\deps",
))
if not root.exists():
    raise SystemExit(f"mod root not found: {root}")
if not (deps / "lua51Original.dll").exists():
    raise SystemExit("lua51Original.dll not found; pass --lua-deps or set DST_LUA51_DEPS")
os.add_dll_directory(str(deps))
lua=ctypes.WinDLL(str(deps/'lua51Original.dll'))
lua.luaL_newstate.restype=ctypes.c_void_p
lua.luaL_loadfile.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lua.luaL_loadfile.restype=ctypes.c_int
lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_close.argtypes=[ctypes.c_void_p]
failed=False
excluded = {'.git', 'build', 'outputs', 'work'}
for path in sorted(root.rglob('*.lua')):
    if any(part in excluded for part in path.relative_to(root).parts):
        continue
    L=lua.luaL_newstate()
    rc=lua.luaL_loadfile(L, str(path).encode('utf-8'))
    if rc:
        n=ctypes.c_size_t()
        msg=lua.lua_tolstring(L,-1,ctypes.byref(n))
        print('FAIL',path, msg[:n.value].decode('utf-8','replace'))
        failed=True
    else:
        print('OK  ',path.relative_to(root))
    lua.lua_close(L)
sys.exit(1 if failed else 0)
