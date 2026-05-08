import mummy, mummy/routers, mummy/multipart
import nimja/parser
import std/[os, strutils, times, options, uri, tables, json]
import db
import auth

# --- Template Renderers ---

proc render_login(error: string): string =
  compile_template_file("templates/login.jinja", base_dir = get_script_dir() / "..")

proc render_index(username: string, books: seq[Book], bookmarks: Table[int, Bookmark]): string =
  compile_template_file("templates/index.jinja", base_dir = get_script_dir() / "..")

proc render_book_list(books: seq[Book], bookmarks: Table[int, Bookmark]): string =
  compile_template_file("templates/booklist.jinja", base_dir = get_script_dir() / "..")

proc render_reader(title: string, book_id: int, saved_cfi: string): string =
  compile_template_file("templates/reader.jinja", base_dir = get_script_dir() / "..")

# --- Helpers ---

proc html_resp(request: Request, code: int, body: string,
              extra_headers: seq[(string, string)] = @[]) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html; charset=utf-8"
  for (k, v) in extra_headers:
    headers[k] = v
  request.respond(code, headers, body)

proc redirect(request: Request, location: string,
              extra_headers: seq[(string, string)] = @[]) =
  var headers: HttpHeaders
  headers["Location"] = location
  for (k, v) in extra_headers:
    headers[k] = v
  request.respond(302, headers)

proc get_cookie(request: Request): string =
  request.headers["Cookie"]

proc parse_form_body(body: string): seq[(string, string)] =
  for pair in body.split('&'):
    let parts = pair.split('=', 1)
    if parts.len == 2:
      result.add((decode_url(parts[0]), decode_url(parts[1])))

proc get_form_field(fields: seq[(string, string)], name: string): string =
  for (k, v) in fields:
    if k == name: return v

proc get_user_bookmarks(username: string): Table[int, Bookmark] =
  for bm in get_bookmarks_for_user(username):
    result[bm.book_id] = bm

# --- Route Handlers ---

proc index_handler(request: Request) =
  let username = get_username(request.get_cookie)
  if username.len == 0:
    request.redirect("/login")
    return
  let books = list_books()
  let bookmarks = get_user_bookmarks(username)
  request.html_resp(200, render_index(username, books, bookmarks))

proc login_page_handler(request: Request) =
  if is_logged_in(request.get_cookie):
    request.redirect("/")
    return
  request.html_resp(200, render_login(""))

proc login_post_handler(request: Request) =
  let fields = parse_form_body(request.body)
  let username = fields.get_form_field("username")
  let password = fields.get_form_field("password")
  try:
    let set_cookie = try_login(username, password)
    request.redirect("/", @[("Set-Cookie", set_cookie)])
  except ValueError:
    request.html_resp(200, render_login("Invalid username or password."))

proc logout_handler(request: Request) =
  let set_cookie = do_logout()
  request.redirect("/login", @[("Set-Cookie", set_cookie)])

proc upload_handler(request: Request) =
  let username = get_username(request.get_cookie)
  if username.len == 0:
    request.respond(401)
    return

  let entries = request.decode_multipart()
  var title, book_author, filename: string
  var file_data: string

  for entry in entries:
    case entry.name
    of "title":
      if entry.data.is_some:
        let (s, e) = entry.data.get
        title = request.body[s .. e]
    of "author":
      if entry.data.is_some:
        let (s, e) = entry.data.get
        book_author = request.body[s .. e]
    of "file":
      if entry.filename.is_some:
        filename = entry.filename.get
      if entry.data.is_some:
        let (s, e) = entry.data.get
        file_data = request.body[s .. e]
    else: discard

  if title.len == 0 or filename.len == 0 or file_data.len == 0:
    request.respond(400)
    return

  # Store file with unique name
  let stored_name = $epoch_time().int & "_" & extract_filename(filename)
  let books_dir = "books"
  create_dir(books_dir)
  write_file(books_dir / stored_name, file_data)

  var book = Book(
    title: title,
    author: book_author,
    original_filename: extract_filename(filename),
    stored_filename: stored_name,
    size_bytes: file_data.len,
    uploaded_by: username,
    uploaded_at: now().format("yyyy-MM-dd HH:mm:ss")
  )
  insert_book(book)

  let books = list_books()
  let bookmarks = get_user_bookmarks(username)
  request.html_resp(200, render_book_list(books, bookmarks))

proc search_handler(request: Request) =
  let username = get_username(request.get_cookie)
  if username.len == 0:
    request.respond(401)
    return

  let q = request.query_params["q"]
  let books = if q.len > 0: search_books(q) else: list_books()
  let bookmarks = get_user_bookmarks(username)
  request.html_resp(200, render_book_list(books, bookmarks))

proc download_handler(request: Request) =
  let username = get_username(request.get_cookie)
  if username.len == 0:
    request.respond(401)
    return

  let id = try: parse_int(request.path_params["id"])
           except: 0
  if id == 0:
    request.respond(404)
    return

  let book = try: get_book(id)
             except: nil
  if book == nil:
    request.respond(404)
    return

  let file_path = "books" / book.stored_filename
  if not file_exists(file_path):
    request.respond(404)
    return

  let data = read_file(file_path)
  var headers: HttpHeaders
  headers["Content-Type"] = "application/epub+zip"
  headers["Content-Encoding"] = "identity"
  if request.query_params["dl"] != "":
    headers["Content-Disposition"] = "attachment; filename=\"" & book.original_filename & "\""
  request.respond(200, headers, data)

proc read_handler(request: Request) =
  let username = get_username(request.get_cookie)
  if username.len == 0:
    request.redirect("/login")
    return

  let id = try: parse_int(request.path_params["id"])
           except: 0
  if id == 0:
    request.respond(404)
    return

  let book = try: get_book(id)
             except: nil
  if book == nil:
    request.respond(404)
    return

  let bm = get_bookmark(username, book.id)
  let saved_cfi = if bm != nil: bm.cfi else: ""
  request.html_resp(200, render_reader(book.title, book.id, saved_cfi))

proc save_bookmark_handler(request: Request) =
  let username = get_username(request.get_cookie)
  if username.len == 0:
    request.respond(401)
    return
  let id = try: parse_int(request.path_params["id"])
           except: 0
  if id == 0:
    request.respond(400)
    return
  try:
    let j = parse_json(request.body)
    let cfi = j{"cfi"}.get_str()
    let progress = j{"progress"}.get_int()
    let section = j{"section"}.get_str()
    if cfi.len == 0:
      request.respond(400)
      return
    save_bookmark(username, id, cfi, progress, section)
    request.respond(204)
  except:
    request.respond(400)

proc delete_handler(request: Request) =
  let username = get_username(request.get_cookie)
  if username.len == 0:
    request.respond(401)
    return

  let id = try: parse_int(request.path_params["id"])
           except: 0
  if id == 0:
    request.respond(404)
    return

  let book = try: get_book(id)
             except: nil
  if book != nil:
    let file_path = "books" / book.stored_filename
    if file_exists(file_path):
      remove_file(file_path)
    delete_book(id)

  let books = list_books()
  let bookmarks = get_user_bookmarks(username)
  request.html_resp(200, render_book_list(books, bookmarks))

# --- Server Setup ---

proc main() =
  init_db()
  init_auth()
  create_dir("books")

  var router: Router

  router.not_found_handler = proc(request: Request) =
    request.html_resp(404, "<h1>Not Found</h1>")

  router.error_handler = proc(request: Request, e: ref Exception) =
    echo "Error: ", e.msg
    request.html_resp(500, "<h1>Internal Server Error</h1>")

  router.get("/", index_handler)
  router.get("/login", login_page_handler)
  router.post("/login", login_post_handler)
  router.get("/logout", logout_handler)
  router.post("/books", upload_handler)
  router.get("/books/search", search_handler)
  router.get("/books/@id/read", read_handler)
  router.put("/books/@id/bookmark", save_bookmark_handler)
  router.get("/books/@id/download", download_handler)
  router.delete("/books/@id", delete_handler)

  echo "NimShelf running on http://localhost:8080"
  let server = new_server(router, max_body_len = 50 * 1024 * 1024)
  server.serve(Port(8080))

main()
