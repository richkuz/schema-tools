require 'schema_tools/client'
require 'schema_tools/schema_manager'
require 'schema_tools/schema_definer'
require 'schema_tools/config'
require 'schema_tools/utils'
require 'schema_tools/reindex'
require 'schema_tools/migrate'
require 'schema_tools/create'
require 'schema_tools/painless'
require 'schema_tools/catchup'
require 'schema_tools/close'
require 'schema_tools/delete'
require 'schema_tools/define'
require 'json'
require 'time'


def validate_client!
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
  client = SchemaTools::Client.new(SchemaTools::Config::CONNECTION_URL)
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
  client = SchemaTools::Client.new(SchemaTools::Config::CONNECTION_URL)
  schema_manager = SchemaTools::SchemaManager.new(SchemaTools::Config::SCHEMAS_PATH)

  desc "Migrate to a specific index schema revision or migrate all schemas to their latest revisions"
  task :migrate, [:to_index, :dryrun, :revision_applied_by] do |t, args|
    validate_client!
    to_index = args[:to_index]
    dryrun = args[:dryrun] == 'true'
    revision_applied_by = args[:revision_applied_by] || "rake task"
    
    SchemaTools.migrate(
      to_index: to_index,
      dryrun: dryrun,
      revision_applied_by: revision_applied_by,
      client: client,
      schema_manager: schema_manager
    )
  end


  desc "Generate diff between schema revisions"
  task :diff, [:index_name_or_revision] do |t, args|
    schema_manager = SchemaTools::SchemaManager.new(SchemaTools::Config::SCHEMAS_PATH)
    puts schema_manager.generate_diff_output_for_index_name_or_revision(index_name_or_revision)
  end

  desc "Create index with schema definition"
  task :create, [:index_name] do |t, args|
    validate_client!
    
    SchemaTools.create(
      index_name: args[:index_name],
      client: client,
      schema_manager: schema_manager
    )
  end

  desc "Upload painless scripts to index"
  task :painless, [:index_name] do |t, args|
    validate_client!
    
    SchemaTools.painless(
      index_name: args[:index_name],
      client: client,
      schema_manager: schema_manager
    )
  end

  desc "Reindex from source to destination index"
  task :reindex, [:index_name] do |t, args|
    validate_client!
    SchemaTools::reindex(index_name: args[:index_name], client:, schema_manager:)
  end

  desc "Catchup reindex for new documents"
  task :catchup, [:index_name] do |t, args|
    validate_client!
    
    SchemaTools.catchup(
      index_name: args[:index_name],
      client: client,
      schema_manager: schema_manager
    )
  end

  desc "Close an index"
  task :close, [:index_name] do |t, args|
    validate_client!

    SchemaTools.close(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Hard delete an index (only works on closed indexes)"
  task :delete, [:index_name] do |t, args|
    validate_client!

    SchemaTools.delete(
      index_name: args[:index_name],
      client: client
    )
  end

  desc "Define schema files for a new or existing index"
  task :define do |t, args|
    begin
      validate_client!

      SchemaTools.define(
        client: client,
        schema_manager: schema_manager
      )
    rescue => e
      puts "Failed to connect to OpenSearch at #{SchemaTools::Config::CONNECTION_URL}"
      puts "Error: #{e.message}"
    end
  end
end