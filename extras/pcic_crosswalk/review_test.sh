#!/bin/bash
set -euo pipefail

# Tests for review_score.sh (NewGraphEnvironment/fwapg#8): builds small filled-in
# review GeoPackages from a fixture design and checks the scores, and that a
# GeoPackage that does not belong to the design is refused. Needs a database
# ($DATABASE_URL) and GDAL; writes only to a temporary directory.

T=$(mktemp -d -t review_test.XXXXXX)
trap 'rm -rf "$T"' EXIT
fails=0

# review_id 2 is also in the 'flagged' stratum, which did not draw it; 5 was
# drawn by 'random' and 'following'
cat > "$T/design.csv" <<'EOF'
review_id,subid,stratum,drawn
1,101,random,t
2,102,random,t
2,102,flagged,f
3,103,random,t
4,104,random,t
5,105,random,t
5,105,following,t
6,106,following,t
7,107,following,t
8,108,unplaced,t
EOF
sample_id=$(md5sum < "$T/design.csv" | cut -c1-32)

# gpkg <name> <sample_id>, review rows (review_id,verdict,confidence,note) on stdin
gpkg() {
  local g=$T/$1.gpkg
  { echo 'review_id,verdict,confidence,note,x,y'
    awk -F, '{ print $0 ",1200000," 500000 + NR }'
  } > "$T/$1.csv"
  printf '"Integer","String","String","String","Real","Real"\n' > "$T/$1.csvt"
  ogr2ogr -f GPKG "$g" "$T/$1.csv" -nln review -a_srs EPSG:3005 \
    -oo X_POSSIBLE_NAMES=x -oo Y_POSSIBLE_NAMES=y -oo KEEP_GEOM_COLUMNS=NO
  printf 'sample_id\n%s\n' "$2" > "$T/$1_sample.csv"
  ogr2ogr -update -f GPKG "$g" "$T/$1_sample.csv" -nln sample
  echo "$g"
}

full='1,right,,
2,wrong_stream,,
3,right,,
4,wrong_stream,low,parallel creek
5,wrong_position,,
6,right,,
7,should_not_be_placed,,
8,should_be_placed,,'

# a scorer that crashes is a failed check below, not an aborted run
score() { ./review_score.sh "$@" 2>&1 || echo "review_score.sh exited $?"; }
check() {  # check <description> <expected line> <output>
  if grep -qxF -- "$2" <<< "$3"; then echo "ok   $1"; else echo "FAIL $1: no line '$2'"; fails=$((fails + 1)); fi
}
refused() {  # refused <description> <gpkg> <message pattern>
  local out rc=0
  out=$(./review_score.sh "$2" "$T/design.csv" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && grep -q -- "$3" <<< "$out"; then
    echo "ok   $1"
  else
    echo "FAIL $1: exit $rc, output:"; echo "$out" | sed 's/^/     /'; fails=$((fails + 1))
  fi
}

# scores: stratum|drawn|reviewed|errors|rate|lo95|hi95, from drawn outlets only
out=$(score "$(gpkg full "$sample_id" <<< "$full")" "$T/design.csv")
check 'random stratum rate and Wilson interval' 'random|5|5|3|0.600|0.231|0.882' "$out"
check 'an outlet drawn by two strata counts toward both' 'following|3|3|2|0.667|0.208|0.939' "$out"
check 'should be placed counts as an error' 'unplaced|1|1|1|1.000|0.207|1.000' "$out"
check 'membership without a draw does not count' 'flagged|0|0|0|||' "$out"
check 'random errors no automatic check flagged' 'random errors in no flagged stratum|1' "$out"
check 'low confidence counted' 'random low confidence|1' "$out"

partial=$(sed -E 's/^(3|4),[^,]*,[^,]*,.*/\1,,,/' <<< "$full")
out=$(score "$(gpkg partial "$sample_id" <<< "$partial")" "$T/design.csv")
check 'blank verdicts are unreviewed, not errors' 'random|5|3|2|0.667|0.208|0.939' "$out"

refused 'another sample_id' "$(gpkg other 0123456789abcdef0123456789abcdef <<< "$full")" 'sample'
refused 'a review_id missing' "$(gpkg missing "$sample_id" <<< "$(sed '$d' <<< "$full")")" 'review_id'
refused 'a review_id added' "$(gpkg added "$sample_id" <<< "$full
9,right,,")" 'review_id'
refused 'a review_id duplicated' "$(gpkg dup "$sample_id" <<< "$full
3,right,,")" 'review_id'
refused 'an unknown verdict' "$(gpkg verdict "$sample_id" <<< "$(sed 's/^6,right/6,maybe/' <<< "$full")")" 'verdict'
refused 'an unknown confidence' "$(gpkg conf "$sample_id" <<< "$(sed 's/^1,right,/1,right,sure/' <<< "$full")")" 'confidence'

[ "$fails" -eq 0 ] && echo 'all review_score.sh tests pass' || { echo "$fails failed"; exit 1; }
