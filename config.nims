switch("threads", "on")
switch("mm", "orc")

import std/[os, strutils]

# Link libsodium statically to avoid version mismatch with dynlib
switch("dynlibOverride", "libsodium")
let sodiumLib = gorge("nix eval --raw nixpkgs#libsodium.outPath 2>/dev/null").strip()
if sodiumLib.len > 0 and dirExists(sodiumLib):
  switch("passL", "-L" & sodiumLib / "lib" & " -lsodium")
else:
  switch("passL", "-lsodium")

# Link sqlite3 statically to avoid runtime dynlib issues on NixOS
switch("dynlibOverride", "sqlite3")
let sqliteLib = gorge("nix eval --raw nixpkgs#sqlite.out 2>/dev/null").strip()
if sqliteLib.len > 0 and dirExists(sqliteLib):
  switch("passL", "-L" & sqliteLib / "lib" & " -lsqlite3")
else:
  switch("passL", "-lsqlite3")
