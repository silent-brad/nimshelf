import libsodium/sodium
import locks, strutils, times, base64
import debby/sqlite
import debby/pools
import db

type
  Account* = ref object
    id*: int
    username*: string
    password_hash*: string
    created_at*: string

var auth_lock*: Lock
var session_key: string

init_lock(auth_lock)

proc init_auth*() =
  session_key = crypto_secretbox_keygen()
  pool.with_db:
    if not db.table_exists(Account):
      db.create_table(Account)
    let users = db.filter(Account)
    if users.len == 0:
      let hash = crypto_pwhash_str("admin")
      var admin = Account(
        username: "admin",
        password_hash: hash,
        created_at: now().format("yyyy-MM-dd HH:mm:ss")
      )
      db.insert(admin)
      echo "Created default admin user (admin/admin)"

proc make_session_token(username: string): string =
  let payload = "session|" & username & "|" & $epoch_time().int64
  crypto_secretbox_easy(session_key, payload)

proc decode_session_token(token: string): string =
  try:
    let payload = crypto_secretbox_open_easy(session_key, token)
    let parts = payload.split('|')
    if parts.len >= 2 and parts[0] == "session":
      return parts[1]
  except:
    discard
  return ""

proc try_login*(username, password: string): string =
  ## Returns a Set-Cookie header value on success. Raises ValueError on failure.
  {.gcsafe.}:
    with_lock auth_lock:
      var user: Account
      pool.with_db:
        let users = db.filter(Account, it.username == username)
        if users.len == 0:
          raise new_exception(ValueError, "Invalid credentials")
        user = users[0]
      if not crypto_pwhash_str_verify(user.password_hash, password):
        raise new_exception(ValueError, "Invalid credentials")
      let token = make_session_token(username)
      let encoded = encode(token)
      result = "nimshelf=" & encoded & "; Path=/; HttpOnly; SameSite=Lax"

proc do_logout*(): string =
  result = "nimshelf=; Path=/; HttpOnly; Max-Age=0"

proc get_username*(cookie: string): string =
  {.gcsafe.}:
    with_lock auth_lock:
      if cookie.len == 0:
        return ""
      for part in cookie.split(';'):
        let trimmed = part.strip()
        if trimmed.starts_with("nimshelf="):
          let encoded = trimmed[len("nimshelf=") .. ^1]
          if encoded.len == 0:
            return ""
          try:
            let token = decode(encoded)
            return decode_session_token(token)
          except:
            return ""
      return ""

proc is_logged_in*(cookie: string): bool =
  get_username(cookie).len > 0
