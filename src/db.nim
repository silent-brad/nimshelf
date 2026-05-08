import debby/sqlite
import debby/pools

type
  Book* = ref object
    id*: int
    title*: string
    author*: string
    original_filename*: string
    stored_filename*: string
    size_bytes*: int
    uploaded_by*: string
    uploaded_at*: string

var pool*: Pool

proc init_db*() =
  pool = new_pool()
  for i in 0 ..< 10:
    pool.add sqlite.open_database("library.db")
  pool.with_db:
    if not db.table_exists(Book):
      db.create_table(Book)

proc insert_book*(book: var Book) {.gcsafe.} =
  pool.with_db:
    db.insert(book)

proc list_books*(): seq[Book] {.gcsafe.} =
  result = pool.filter(Book)

proc get_book*(id: int): Book {.gcsafe.} =
  result = pool.get(Book, id)

proc delete_book*(id: int) {.gcsafe.} =
  pool.with_db:
    var book = Book(id: id)
    db.delete(book)

proc search_books*(query: string): seq[Book] {.gcsafe.} =
  let pattern = "%" & query & "%"
  pool.with_db:
    result = db.query(
      Book,
      "SELECT * FROM book WHERE title LIKE ? OR author LIKE ?",
      pattern, pattern
    )
