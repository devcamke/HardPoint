# strong_migrations refuses a migration that would lock a table the tills write to, or that the version still
# serving during a deploy couldn't live with (removing a column in one step, adding a column with a default
# on an old Postgres, an index built without CONCURRENTLY, and so on). It explains the safe way in the error.
# A migration that is known to be safe for a reason the gem can't see wraps itself in `safety_assured { }`.
StrongMigrations.start_after = 20261108110000 # migrations up to this one were written before the gem

# Postgres settings set for the migration's session: a migration waits at most this long for a lock
# (config/postgres/postgresql.conf sets the same server-wide) and no single statement runs for more than an hour.
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour

# The Postgres version checks are judged against production, not whatever a laptop or CI runs.
StrongMigrations.target_version = 18
