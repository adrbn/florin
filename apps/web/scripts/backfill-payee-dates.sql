-- One-shot backfill: rewrite occurred_at of bank-synced tx when the payee
-- embeds a DD.MM.YY / DD/MM/YY / DD-MM-YY date within +/-14 days of the
-- currently-stored date. Mirrors packages/core/src/lib/transactions/extract-date.ts.
--
-- Kept as pure SQL so it can be piped straight into psql on production
-- without tsx/node runtime (standalone Next image does not ship scripts/).
--
-- Usage:
--   docker compose exec -T db psql -U florin -d florin < backfill-payee-dates.sql
DO $$
DECLARE
  r RECORD;
  parts TEXT[];
  d INT;
  mo INT;
  yy INT;
  y INT;
  candidate DATE;
  booked DATE;
  updated_count INT := 0;
  scanned_count INT := 0;
BEGIN
  FOR r IN
    SELECT id, occurred_at, payee
      FROM transactions
     WHERE source IS NOT NULL
       AND deleted_at IS NULL
       AND payee IS NOT NULL
       AND payee ~ '\m[0-9]{1,2}[./\-][0-9]{1,2}[./\-][0-9]{2,4}\M'
  LOOP
    scanned_count := scanned_count + 1;
    parts := regexp_match(r.payee, '\m([0-9]{1,2})[./\-]([0-9]{1,2})[./\-]([0-9]{2,4})\M');
    IF parts IS NULL THEN CONTINUE; END IF;
    d := parts[1]::INT;
    mo := parts[2]::INT;
    yy := parts[3]::INT;
    IF yy < 100 THEN y := 2000 + yy;
    ELSIF yy < 1900 THEN y := 2000 + (yy % 100);
    ELSE y := yy;
    END IF;
    IF mo < 1 OR mo > 12 OR d < 1 OR d > 31 THEN CONTINUE; END IF;
    BEGIN
      candidate := make_date(y, mo, d);
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;
    booked := r.occurred_at::DATE;
    IF candidate = booked THEN CONTINUE; END IF;
    IF abs(candidate - booked) > 14 THEN CONTINUE; END IF;
    UPDATE transactions
       SET occurred_at = candidate::TIMESTAMP,
           updated_at = now()
     WHERE id = r.id;
    updated_count := updated_count + 1;
  END LOOP;
  RAISE NOTICE 'scanned=%, updated=%', scanned_count, updated_count;
END $$;
