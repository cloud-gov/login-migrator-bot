-- Daily read-only reporting queries against the UAA database.
-- All statements MUST be read-only SELECTs. Results are printed to the
-- Concourse build output by ci/uaa-queries.sh.

select origin, count(*) from users where active=true group by origin order by 2 desc;

select email, split_part(email, '@', 2) as domain, id from users where origin='cloud.gov' and active=true order by 2,1;

select email, split_part(email, '@', 2) as domain, id from users where origin='login.gov' and active=true order by 2,1;
