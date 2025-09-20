require 'schema_tools/config'

namespace :schema do
  desc "Define schema files for a new or existing index"
  task :define do |t, args|
    if ENV['OPENSEARCH_URL'] && !ENV['OPENSEARCH_URL'].empty?
      Rake::Task['opensearch:define'].invoke
    elsif ENV['ELASTICSEARCH_URL'] && !ENV['ELASTICSEARCH_URL'].empty?
      Rake::Task['elasticsearch:define'].invoke
    else
      puts "Please set either OPENSEARCH_URL or ELASTICSEARCH_URL environment variable"
      puts "Example: OPENSEARCH_URL=http://localhost:9200 rake schema:define"
      exit 1
    end
  end

  desc "Migrate to a specific index schema revision"
  task :migrate, [:to_index, :dryrun, :revision_applied_by] do |t, args|
    if ENV['OPENSEARCH_URL'] && !ENV['OPENSEARCH_URL'].empty?
      Rake::Task['opensearch:migrate'].invoke(args[:to_index], args[:dryrun], args[:revision_applied_by])
    elsif ENV['ELASTICSEARCH_URL'] && !ENV['ELASTICSEARCH_URL'].empty?
      Rake::Task['elasticsearch:migrate'].invoke(args[:to_index], args[:dryrun], args[:revision_applied_by])
    else
      puts "Please set either OPENSEARCH_URL or ELASTICSEARCH_URL environment variable"
      puts "Example: OPENSEARCH_URL=http://localhost:9200 rake schema:migrate[products-1]"
      exit 1
    end
  end
end