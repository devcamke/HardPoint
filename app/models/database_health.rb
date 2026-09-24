# What the platform admin's Database page shows: size, connections, cache hit rates, the biggest
# tables, indexes that are never used, tables vacuum is behind on, long-running queries, and (when
# pg_stat_statements is loaded) the queries that take the most time overall. Read-only, from
# Postgres' own statistics views.
class DatabaseHealth
  Query = Data.define(:calls, :total_ms, :mean_ms, :rows, :query)

  def initialize(connection = ActiveRecord::Base.connection)
    @connection = connection
  end

  def version = value("SHOW server_version")
  def size = value("SELECT pg_size_pretty(pg_database_size(current_database()))")
  def max_connections = value("SHOW max_connections").to_i

  def connections
    rows("SELECT coalesce(state, 'background') AS state, count(*) FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC").to_h
  end

  # Share of table and index reads served from memory; below ~99% the database wants more RAM.
  def cache_hit_rates
    rows(<<~SQL).first.then { |table, index| { tables: table&.to_f, indexes: index&.to_f } }
      SELECT round(100.0 * sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2),
             (SELECT round(100.0 * sum(idx_blks_hit) / nullif(sum(idx_blks_hit) + sum(idx_blks_read), 0), 2) FROM pg_statio_user_indexes)
      FROM pg_statio_user_tables
    SQL
  end

  def largest_tables(limit = 12)
    rows(<<~SQL)
      SELECT relname, pg_size_pretty(pg_total_relation_size(relid)), n_live_tup, n_dead_tup,
             greatest(last_autovacuum, last_vacuum)
      FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT #{Integer(limit)}
    SQL
  end

  # Indexes that have never been read since statistics were last reset; unique ones enforce rules, so they stay.
  def unused_indexes
    rows(<<~SQL)
      SELECT s.relname, s.indexrelname, pg_size_pretty(pg_relation_size(s.indexrelid))
      FROM pg_stat_user_indexes s JOIN pg_index i ON i.indexrelid = s.indexrelid
      WHERE s.idx_scan = 0 AND NOT i.indisunique AND NOT i.indisprimary
      ORDER BY pg_relation_size(s.indexrelid) DESC LIMIT 12
    SQL
  end

  def long_running(seconds = 30)
    rows(<<~SQL)
      SELECT pid, now() - query_start, state, left(query, 200)
      FROM pg_stat_activity
      WHERE state <> 'idle' AND pid <> pg_backend_pid() AND query_start < now() - interval '#{Integer(seconds)} seconds'
      ORDER BY query_start
    SQL
  end

  # The extension must be installed here and preloaded by the server (a setting the app's role can't
  # read), so try the view itself; a savepoint keeps a failure from spoiling any open transaction.
  def query_stats?
    return @query_stats if defined?(@query_stats)

    @query_stats = value("SELECT count(*) FROM pg_extension WHERE extname = 'pg_stat_statements'").to_i.positive? &&
      begin
        @connection.transaction(requires_new: true) { @connection.select_value("SELECT 1 FROM pg_stat_statements LIMIT 1") }
        true
      rescue ActiveRecord::StatementInvalid
        false
      end
  end

  def slowest_queries(limit = 15)
    return [] unless query_stats?

    rows(<<~SQL).map { Query.new(*_1) }
      SELECT calls, round(total_exec_time::numeric, 1), round(mean_exec_time::numeric, 2), rows, left(query, 400)
      FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
      ORDER BY total_exec_time DESC LIMIT #{Integer(limit)}
    SQL
  end

  private
    def value(sql) = @connection.select_value(sql).to_s
    def rows(sql) = @connection.select_rows(sql)
end
