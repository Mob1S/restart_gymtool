const beverageStatements = [
  '''CREATE TABLE IF NOT EXISTS beverage (
    id TEXT PRIMARY KEY NOT NULL,
    payload TEXT NOT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS drink_record (
    id TEXT PRIMARY KEY NOT NULL,
    beverage_id TEXT REFERENCES beverage(id) ON DELETE SET NULL,
    occurred_at INTEGER NOT NULL CHECK(occurred_at >= 0),
    date TEXT NOT NULL,
    payload TEXT NOT NULL
  )''',
  'CREATE INDEX IF NOT EXISTS drink_record_date ON drink_record(date, occurred_at)',
];
