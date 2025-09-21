require 'schema_tools/config'

namespace :elasticsearch do
  desc "Migrate to a specific index schema revision"
  task :migrate, [:to_index, :dryrun, :revision_applied_by] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:migrate'].invoke(args[:to_index], args[:dryrun], args[:revision_applied_by])
  end

  desc "Generate diff between schema revisions"
  task :diff, [:index_name] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:diff'].invoke(args[:index_name])
  end

  desc "Create index with schema definition"
  task :create, [:index_name] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:create'].invoke(args[:index_name])
  end

  desc "Upload painless scripts to index"
  task :painless, [:index_name] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:painless'].invoke(args[:index_name])
  end

  desc "Reindex from source to destination index"
  task :reindex, [:index_name] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:reindex'].invoke(args[:index_name])
  end

  desc "Catchup reindex for new documents"
  task :catchup, [:index_name] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:catchup'].invoke(args[:index_name])
  end

  desc "Soft delete an index by renaming it"
  task :softdelete, [:index_name] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:softdelete'].invoke(args[:index_name])
  end

  desc "Hard delete an index (only works on deleted- prefixed indexes)"
  task :delete, [:index_name] do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:delete'].invoke(args[:index_name])
  end

  desc "Define schema files for a new or existing index"
  task :define do |t, args|
    ENV['ELASTICSEARCH_URL'] = ENV['ELASTICSEARCH_URL'] || ENV['OPENSEARCH_URL']
    Rake::Task['schema:define'].invoke
  end
end