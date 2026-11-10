namespace :dev do
  # The shops db/seeds.rb makes. Anything else in the database (shops made by signing up) is left alone.
  SEEDED_SHOPS = %w[ demo coast lakeside ].freeze

  desc "Rebuild the demo shops from db/seeds.rb with fresh dates (development only; other shops are kept)"
  task refresh_demo: :environment do
    abort "dev:refresh_demo only runs in development" unless Rails.env.development?

    Account.without_isolation do
      Account.where(subdomain: SEEDED_SHOPS).find_each do |account|
        puts "Removing #{account.name} (#{account.subdomain})"
        account.purge!
      end
    end
    Rake::Task["db:seed"].invoke
    puts "Rebuilt #{SEEDED_SHOPS.join(", ")}. Sign in at http://demo.localhost:3000 as owner@demo.test / hardpoint-demo."
  end
end
