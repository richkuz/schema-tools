require 'schema_tools/config'

namespace :elasticsearch do
  desc "Migrate to a specific index schema revision"
  task :migrate, [:to_index, :dryrun, :revision_applied_by] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:migrate'].invoke(args[:to_index], args[:dryrun], args[:revision_applied_by])
  end

  desc "Generate diff between schema revisions"
  task :diff, [:index_name] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:diff'].invoke(args[:index_name])
  end

  desc "Create index with schema definition"
  task :create, [:index_name] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:create'].invoke(args[:index_name])
  end

  desc "Upload painless scripts to index"
  task :painless, [:index_name] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:painless'].invoke(args[:index_name])
  end

  desc "Reindex from source to destination index"
  task :reindex, [:index_name] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:reindex'].invoke(args[:index_name])
  end

  desc "Catchup reindex for new documents"
  task :catchup, [:index_name] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:catchup'].invoke(args[:index_name])
  end

  desc "Soft delete an index by renaming it"
  task :softdelete, [:index_name] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:softdelete'].invoke(args[:index_name])
  end

  desc "Hard delete an index (only works on deleted- prefixed indexes)"
  task :delete, [:index_name] do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:delete'].invoke(args[:index_name])
  end

  desc "Define schema files for a new or existing index"
  task :define do |t, args|
    ENV['OPENSEARCH_URL'] = SchemaTools::Config::ELASTICSEARCH_URL
    Rake::Task['opensearch:define'].invoke
  end
end