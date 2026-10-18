const trainingV8Statements = <String>[
  'CREATE TABLE exercise_catalog_binding(id TEXT PRIMARY KEY, exercise_id TEXT NOT NULL REFERENCES exercise(id) ON DELETE CASCADE)',
  'CREATE TABLE training_program(id TEXT PRIMARY KEY REFERENCES training_plan(id) ON DELETE CASCADE, payload TEXT NOT NULL)',
  'CREATE TABLE session_prescription(id TEXT PRIMARY KEY REFERENCES session_exercise(id) ON DELETE CASCADE, payload TEXT NOT NULL)',
  'CREATE TABLE set_detail(id TEXT PRIMARY KEY REFERENCES set_entry(id) ON DELETE CASCADE, payload TEXT NOT NULL)',
];
