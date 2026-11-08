namespace :db do
  namespace :prepare do
    # The first boot of a fresh server: creates and loads the databases when there aren't any yet, and does
    # nothing once they exist. Later schema changes are migrations, run once per deploy by the pre-deploy
    # hook (.kamal/hooks/pre-deploy), never by containers as they start.
    desc "Create and load the databases if they don't exist yet; otherwise leave them alone"
    task if_empty: :load_config do
      require "active_record"

      configurations = ActiveRecord::Base.configurations.configs_for(env_name: ActiveRecord::Tasks::DatabaseTasks.env, include_hidden: false)
      primary = configurations.find(&:primary?) || configurations.first
      ActiveRecord::Base.establish_connection(primary)

      if ActiveRecord::Base.connection.schema_migration.table_exists?
        puts "Database #{primary.database} exists; migrations run from the pre-deploy hook"
      else
        puts "Database #{primary.database} is empty: preparing it"
        Rake::Task["db:prepare"].invoke
      end
    rescue ActiveRecord::NoDatabaseError
      puts "No database #{primary&.database} yet: preparing it"
      Rake::Task["db:prepare"].invoke
    end
  end
end
