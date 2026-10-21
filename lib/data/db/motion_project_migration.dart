const motionProjectStatements = [
  '''CREATE TABLE IF NOT EXISTS motion_project (
    id TEXT PRIMARY KEY,
    set_id TEXT UNIQUE REFERENCES set_entry(id) ON DELETE SET NULL,
    mode TEXT NOT NULL CHECK(mode IN ('import','camera')),
    folder TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  '''INSERT OR IGNORE INTO motion_project(id,set_id,mode,folder,payload,created_at,updated_at)
    SELECT 'legacy-' || set_id,set_id,'import',folder,payload,0,0 FROM video_review''',
  'DELETE FROM video_review',
];
