# Package
version       = "0.0.1"
author        = "silent-brad"
description   = "A Simple Self-hosted Digital Library in Nim"
license       = "MIT"
bin           = @["src/main"]

# Dependencies
requires "nim >= 2.0.0"
requires "nimja"
requires "prologue >= 0.6.0"
requires "mummy"
requires "debby"
requires "zippy"
requires "nim-httpauth"
