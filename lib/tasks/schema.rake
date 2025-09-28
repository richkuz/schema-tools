require 'schema_tools/client'
require 'schema_tools/schema_files'
require 'schema_tools/schema_definer'
require 'schema_tools/config'
require 'schema_tools/utils'
require 'schema_tools/reindex'
require 'schema_tools/migrate'
require 'schema_tools/create'
require 'schema_tools/upload_painless'
require 'schema_tools/catchup'
require 'schema_tools/close'
require 'schema_tools/delete'
require 'schema_tools/define'
require 'schema_tools/diff'
require 'schema_tools/update_metadata'
require 'schema_tools/schema_revision'
require 'json'
require 'time'


def create_client!
  # Check if connection URL is configured
  if SchemaTools::Config::CONNECTION_URL.nil?
    puts "No connection URL configured."
    puts "Please set either OPENSEARCH_URL or ELASTICSEARCH_URL environment variable."
    puts "Example:"
    puts "  export OPENSEARCH_URL=http://localhost:9200"
    puts "  export ELASTICSEARCH_URL=https://your-cluster.com"
    puts "Then re-run the command."
    exit 1
  end
  
  # Initialize client and test connection
  client = SchemaTools::Client.new(SchemaTools::Config::CONNECTION_URL, dryrun: ENV['DRYRUN'] == 'true')
  unless client.test_connection
    puts "Failed to connect to OpenSearch/Elasticsearch at #{SchemaTools::Config::CONNECTION_URL}"
    puts "Please ensure that OPENSEARCH_URL or ELASTICSEARCH_URL environment variable is set correctly."
    puts "Example:"
    puts "  export OPENSEARCH_URL=http://localhost:9200"
    puts "  export ELASTICSEARCH_URL=https://your-cluster.com"
    puts "Then re-run the command."
    exit 1
  end
  client
end

namespace :schema do
  desc "Migrate to a specific index schema revision or migrate all schemas to their latest revisions"
  task :migrate, [:to_index] do |t, args|
    client = create_client!
    
    if args[:to_index]
      SchemaTools.migrate_one_schema(index_name: args[:to_index], client: client)
    else
      SchemaTools.migrate_all(client: client)
    end
  end

  desc "Generate diff output file for a given schema revision path, e.g. products-3/revisions/5"
  task :diff, [:revision_path] do |t, args|
    diff = SchemaTools.diff(
      schema_revision: SchemaRevision.new(revision_path)
    )
    
    puts diff
  end

  desc "Create index with schema definition"
  task :create, [:index_name] do |t, args|
    client = create_client!
    
    SchemaTools.create(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Upload painless scripts to index"
  task :painless, [:index_name] do |t, args|
    client = create_client!
    
    SchemaTools.upload_painless(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Reindex from source to destination index"
  task :reindex, [:index_name] do |t, args|
    client = create_client!

    SchemaTools.reindex(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Catchup reindex for new documents"
  task :catchup, [:index_name] do |t, args|
    client = create_client!
    
    SchemaTools.catchup(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Close an index"
  task :close, [:index_name] do |t, args|
    client = create_client!

    SchemaTools.close(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Hard delete an index (only works on closed indexes)"
  task :delete, [:index_name] do |t, args|
    client = create_client!

    SchemaTools.delete(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Define schema files for a new or existing index"
  task :define do |t, args|
    client = create_client!

    SchemaTools.define(
      client: client
    )
  end
end