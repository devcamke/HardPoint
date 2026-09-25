namespace :storage do
  desc "Copy stored files between Active Storage services and switch them over, e.g. storage:copy[local,object_storage]"
  task :copy, %i[ from to ] => :environment do |_, args|
    copied = StorageCopy.new(from: args.fetch(:from), to: args.fetch(:to)).run
    puts "#{copied} files now on #{args[:to]}."
  end
end
