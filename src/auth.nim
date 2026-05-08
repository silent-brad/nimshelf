import httpauth, locks, mummy, os
import std/httpcore as hc

var
  authLock: Lock
  auth: HTTPAuth

initLock(authLock)

block:
  let backend = newSQLBackend("sqlite:///" & getAppDir() / "library.db")
  auth = newHTTPAuth("localhost", backend,
    cookie_name = "nimshelf", https_only_cookies = false)
  auth.initialize_admin_user(username = "admin", password = "admin")

proc toStdHeaders(headers: HttpHeaders): hc.HttpHeaders =
  result = hc.newHttpHeaders()
  for (k, v) in headers:
    result.add(k, v)

proc toMummyHeaders(headers: hc.HttpHeaders): HttpHeaders =
  var s: seq[(string, string)]
  for k, v in headers:
    s.add((k, v))
  result = s.HttpHeaders

proc tryLogin*(headers: HttpHeaders, username, password: string): HttpHeaders {.gcsafe.} =
  withLock authLock:
    var stdH = toStdHeaders(headers)
    auth.headers_hook(stdH)
    auth.login(username, password)
    result = toMummyHeaders(stdH)

proc doLogout*(headers: HttpHeaders): HttpHeaders {.gcsafe.} =
  withLock authLock:
    var stdH = toStdHeaders(headers)
    auth.headers_hook(stdH)
    auth.logout()
    result = toMummyHeaders(stdH)

proc getUsername*(headers: HttpHeaders): string {.gcsafe.} =
  withLock authLock:
    var stdH = toStdHeaders(headers)
    auth.headers_hook(stdH)
    try:
      result = auth.current_user.username
    except AuthError:
      result = ""

proc isLoggedIn*(headers: HttpHeaders): bool {.gcsafe.} =
  withLock authLock:
    var stdH = toStdHeaders(headers)
    auth.headers_hook(stdH)
    result = not auth.is_user_anonymous()
