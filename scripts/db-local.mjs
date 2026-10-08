import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

// Deliberately accepts no URL, container, database or remote project argument.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const container = 'supabase_db_mercatto';
export function docker(args, input) {
  const result = spawnSync('docker', ['exec', ...(input === undefined ? [] : ['-i']),
    container, ...args], { input, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || 'Docker failed');
  return result.stdout;
}
export function sql(query, database = 'postgres') {
  if (!['postgres', 'mercatto_foundation_test'].includes(database)) throw new Error('Database is not allowlisted');
  return docker(['psql', '-X', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-At'], query);
}
export function assertLocal() {
  // Connection is a Unix socket inside this exact local container; never uses .env files.
  if (sql("SELECT inet_server_addr() IS NULL AND current_database() = 'postgres';").trim() !== 't') {
    throw new Error('Expected the local PostgreSQL Unix socket. Aborting.');
  }
}
function backup() {
  mkdirSync(resolve(root, '.local-db'), { recursive: true });
  const path = resolve(root, '.local-db', `backup-${Date.now()}.sql`);
  writeFileSync(path, docker(['pg_dump', '-U', 'postgres', '-d', 'postgres']));
  console.log(`Local backup saved: ${path}`);
}
export function migrate(database = 'postgres') {
  if (database === 'postgres') backup();
  if (database === 'mercatto_foundation_test') {
    sql('CREATE SCHEMA IF NOT EXISTS supabase_migrations; CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]);', database);
  }
  const folder = resolve(root, 'supabase/migrations');
  for (const name of readdirSync(folder).filter(n => /^\d+_.+\.sql$/.test(n)).sort()) {
    const version = name.split('_')[0];
    const source = readFileSync(resolve(folder, name), 'utf8');
    if (source.includes('$migration_source$')) throw new Error('Migration contains a reserved delimiter');
    // A single transaction registers the migration only after every statement succeeds.
    const body = `BEGIN; SELECT pg_advisory_xact_lock(173812904);
SELECT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='${version}') AS applied \\gset
\\if :applied
${version === '00000000000000' ? '' : `DO $verify_source$ BEGIN
IF (SELECT statements FROM supabase_migrations.schema_migrations WHERE version='${version}') IS DISTINCT FROM ARRAY[$migration_source$${source}$migration_source$] THEN
RAISE EXCEPTION 'Applied migration ${version} has changed; create a new migration instead';
END IF; END $verify_source$;`}
\\echo Already applied: ${name}
\\else
${source}
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES ('${version}','${name.slice(version.length + 1, -4)}', ARRAY[$migration_source$${source}$migration_source$]);
\\echo Applied: ${name}
\\endif
COMMIT;`;
    console.log(sql(body, database));
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assertLocal();
  const action = process.argv[2];
  if (process.argv.length !== 3) throw new Error('Use: node scripts/db-local.mjs status|backup|migrate');
  if (action === 'status') console.log(sql('SELECT version,name FROM supabase_migrations.schema_migrations ORDER BY version;'));
  else if (action === 'backup') backup();
  else if (action === 'migrate') migrate();
  else throw new Error('Unsupported action; remote operations are not available.');
}
