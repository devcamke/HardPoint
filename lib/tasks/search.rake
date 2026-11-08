# Puts the search functions' ownership back after a schema load (SearchFunctions): db/structure.sql can't
# carry it, and without it searches work but can't use the trigram indexes.
namespace :db do
  namespace :search do
    desc "Give the search functions to the role that bypasses row-level security, so searches use their indexes"
    task privileges: :environment do
      if SearchFunctions.ensure_privileges!
        puts "Search functions owned by #{SearchFunctions::ROLE}: indexes in use"
      else
        warn "Search functions not reassigned: create the #{SearchFunctions::ROLE} role as the database superuser (#{SearchFunctions::CREATE_ROLE_SQL}) and run db:search:privileges"
      end
    end
  end
end

%w[ db:prepare db:schema:load db:test:prepare db:migrate ].each do |task|
  Rake::Task[task].enhance { Rake::Task["db:search:privileges"].invoke } if Rake::Task.task_defined?(task)
end
