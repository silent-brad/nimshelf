import debby/sqlite
import debby/pools

type
  Book* = ref object
    id*: int
    title*: string
    author*: string
    originalFilename*: string
    storedFilename*: string
    sizeBytes*: int
    uploadedBy*: string
    uploadedAt*: string

var pool* = newPool[SQLiteConnection](10, "library.db")

proc initDb*() {.gcsafe.} =
  pool.withDb:
    db.createTableIfNotExists(Book)

proc insertBook*(book: var Book) {.gcsafe.} =
  pool.withDb:
    db.insert(book)

proc listBooks*(): seq[Book] {.gcsafe.} =
  result = pool.filter(Book)

proc getBook*(id: int): Book {.gcsafe.} =
  pool.withDb:
    result = Book(id: id)
    db.get(result)

proc deleteBook*(id: int) {.gcsafe.} =
  pool.withDb:
    var book = Book(id: id)
    db.delete(book)

proc searchBooks*(query: string): seq[Book] {.gcsafe.} =
  let pattern = "%" & query & "%"
  pool.withDb:
    result = db.rawQuery(
      Book,
      "SELECT * FROM book WHERE title LIKE ? OR author LIKE ?",
      pattern, pattern
    )
