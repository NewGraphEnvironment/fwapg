set -u
P="psql -w -U postgres -X"
chk="select n.nspname, md5(p.prosrc), position('exbc' in p.prosrc)=0 as no_exbc, obj_description(p.oid,'pg_proc') is not null as has_comment from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='fwa_watershedatmeasure' order by 1"
for db in fwapg_exbc_mig fwapg_exbc_new; do
  $P -d postgres -q -c "DROP DATABASE IF EXISTS $db" -c "CREATE DATABASE $db" -c "ALTER DATABASE $db SET search_path TO public,whse_basemapping,usgs,hydrosheds" && $P -d $db -q -c "CREATE EXTENSION postgis" || exit 1
done
echo "== A: upstream schema.sql, then migrate.sh"
$P -d fwapg_exbc_mig -q -v ON_ERROR_STOP=1 -f /tmp/exbc/schema_upstream.sql > /tmp/exbc/load_a.log 2>&1; echo "load rc=$?"
$P -d fwapg_exbc_mig -At -c "$chk"
cd /tmp/exbc/db || exit 1
U=postgresql://postgres@/fwapg_exbc_mig
DATABASE_URL=$U ./migrate.sh --dry-run; DATABASE_URL=$U ./migrate.sh | grep -v '^$'; DATABASE_URL=$U ./migrate.sh
$P -d fwapg_exbc_mig -At -c "$chk" -c "select string_agg(tag, ',' order by applied_at) from fwapg.db_version"
echo "== B: new schema.sql, then a DB already at round 1's version"
$P -d fwapg_exbc_new -q -v ON_ERROR_STOP=1 -f /tmp/exbc/db/schema.sql > /tmp/exbc/load_b.log 2>&1; echo "load rc=$?"
$P -d fwapg_exbc_new -At -c "$chk"
$P -d fwapg_exbc_new -q -c "CREATE SCHEMA fwapg; CREATE TABLE fwapg.db_version (tag text not null, applied_at timestamptz not null default now()); INSERT INTO fwapg.db_version (tag) VALUES ('0'); INSERT INTO fwapg.db_version (tag, applied_at) VALUES ('202610131450', now() + interval '1 second')"
DATABASE_URL=postgresql://postgres@/fwapg_exbc_new ./migrate.sh | grep -v '^$'
$P -d fwapg_exbc_new -At -c "$chk" -c "select string_agg(tag, ',' order by applied_at) from fwapg.db_version"
echo "errors in load logs: $(cat /tmp/exbc/load_a.log /tmp/exbc/load_b.log | grep -ci error)"
for db in fwapg_exbc_mig fwapg_exbc_new; do $P -d postgres -q -c "DROP DATABASE $db"; done
$P -d postgres -At -c "select count(*) as scratch_left from pg_database where datname like 'fwapg_exbc%'"
