require 'schema_tools/client'
require 'schema_tools/schema_files'
require 'schema_tools/config'
require 'schema_tools/migrate/migrate'
require 'schema_tools/painless_scripts_download'
require 'schema_tools/painless_scripts_upload'
require 'schema_tools/painless_scripts_delete'
require 'schema_tools/close'
require 'schema_tools/delete'
require 'schema_tools/download'
require 'schema_tools/new_alias'
require 'schema_tools/seed'
require 'schema_tools/diff'
require 'seeder/seeder'
require 'json'
require 'time'


def create_client!
  # Check if connection URL is configured
  if SchemaTools::Config.connection_url.nil?
    puts "No connection URL configured."
    puts "Please set either OPENSEARCH_URL or ELASTICSEARCH_URL environment variable."
    puts "Example:"
    puts "  export OPENSEARCH_URL=http://localhost:9200"
    puts "  export ELASTICSEARCH_URL=https://your-cluster.com"
    puts "Then re-run the command."
    exit 1
  end
  
  # Initialize client and test connection
  client = SchemaTools::Client.new(
    SchemaTools::Config.connection_url, 
    dryrun: ENV['DRYRUN'] == 'true',
    interactive: ENV['INTERACTIVE'] == 'true',
    username: SchemaTools::Config.connection_username,
    password: SchemaTools::Config.connection_password
  )
  unless client.test_connection
    puts "Failed to connect to OpenSearch/Elasticsearch at #{SchemaTools::Config.connection_url}"
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
  desc "Migrate to a specific alias schema or migrate all schemas to their latest revisions"
  task :migrate, [:alias_name] do |t, args|
    client = create_client!
    
    if args[:alias_name]
      SchemaTools.migrate_one_schema(alias_name: args[:alias_name], client: client)
    else
      SchemaTools.migrate_all(client: client)
    end
  end

  desc "Create a new alias with sample schema"
  task :new do |t, args|
    client = create_client!

    SchemaTools.new_alias(
      client: client
    )
  end

  desc "schema:new"
  task :create => :new
  
  desc "Close an index or alias"
  task :close, [:name] do |t, args|
    client = create_client!

    SchemaTools.close(
      name: args[:name],
      client: client
    )
  end

  desc "Hard delete an index (only works on closed indexes) or delete an alias"
  task :delete, [:name] do |t, args|
    client = create_client!

    SchemaTools.delete(
      name: args[:name],
      client: client
    )
  end

  desc "Delete an alias (does not delete the index)"
  task :drop, [:alias_name] do |t, args|
    client = create_client!

    unless args[:alias_name]
      puts "Error: alias_name is required"
      puts "Usage: rake 'schema:drop[alias_name]'"
      exit 1
    end

    alias_name = args[:alias_name]

    unless client.alias_exists?(alias_name)
      puts "Error: Alias '#{alias_name}' does not exist"
      exit 1
    end

    indices = client.get_alias_indices(alias_name)
    puts "Deleting alias '#{alias_name}' from indices: #{indices.join(', ')}"

    client.delete_alias(alias_name)
    puts "✓ Alias '#{alias_name}' deleted successfully"
  end

  desc "Download schema from an existing alias or index"
  task :download do |t, args|
    client = create_client!

    SchemaTools.download(
      client: client
    )
  end

  desc "Create an alias for an existing index"
  task :alias do |t, args|
    client = create_client!

    SchemaTools.create_alias_for_index(
      client: client
    )
  end

  desc "Seed data to a live index"
  task :seed do |t, args|
    client = create_client!

    SchemaTools.seed(
      client: client
    )
  end

  desc "Compare all schemas to their corresponding downloaded alias settings and mappings"
  task :diff do |t, args|
    client = create_client!

    SchemaTools::Diff.diff_all_schemas(client)
  end
end

namespace :painless_scripts do
  desc "Download all painless scripts from cluster and store them locally"
  task :download do |t, args|
    client = create_client!
    
    SchemaTools.painless_scripts_download(client: client)
  end

  desc "Upload all painless scripts from local directory to cluster"
  task :upload do |t, args|
    client = create_client!
    
    SchemaTools.painless_scripts_upload(client: client)
  end

  desc "Delete a specific painless script from cluster"
  task :delete, [:script_name] do |t, args|
    client = create_client!
    
    SchemaTools.painless_scripts_delete(script_name: args[:script_name], client: client)
  end
end