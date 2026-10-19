const videoReviewStatements = [
  '''CREATE TABLE IF NOT EXISTS video_review (
    set_id TEXT PRIMARY KEY REFERENCES set_entry(id) ON DELETE CASCADE,
    folder TEXT NOT NULL,
    payload TEXT NOT NULL
  )''',
];
