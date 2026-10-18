#!/usr/bin/env bash
# Build the database and the dashboard data from scratch.
#
#   DATABASE_URL=postgresql://localhost/shop ./scripts/build.sh
#
# 1. Simulate the shop's year (skip with --keep-data to load your own CSVs in data/)
# 2. Create the tables and load the CSVs
# 3. Create the views in sql/views/, in file order
# 4. Run the data checks and stop if any fail
# 5. Export the views for the web dashboard (docs/data.js) and Looker Studio (looker-studio/*.csv)
set -euo pipefail
cd "$(dirname "$0")/.."

DATABASE_URL="${DATABASE_URL:-postgresql://localhost/shop}"
PSQL=(psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1)

if [[ "${1:-}" != "--keep-data" ]]; then
  python3 scripts/generate_data.py data
fi

"${PSQL[@]}" -c "set client_min_messages = warning" -f sql/01_schema.sql -f sql/02_load.sql
for f in sql/views/*.sql; do
  "${PSQL[@]}" -f "$f"
done

echo "Data checks:"
"${PSQL[@]}" -At -F ' | ' -c "select case when failures = 0 then 'pass' else 'FAIL' end, check_name, failures from shop.v_data_checks"
failed=$("${PSQL[@]}" -At -c "select count(*) from shop.v_data_checks where failures > 0")
if [[ "$failed" != "0" ]]; then
  echo "$failed check(s) failed. Fix the data before trusting the dashboard." >&2
  exit 1
fi

DATABASE_URL="$DATABASE_URL" python3 scripts/export.py
