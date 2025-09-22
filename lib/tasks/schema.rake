require 'schema_tools/client'
require 'schema_tools/schema_manager'
require 'schema_tools/schema_definer'
require 'schema_tools/config'
require 'schema_tools/utils'
require 'json'
require 'time'

def migrate_single_schema(to_index, dryrun, revision_applied_by, schema_manager, client)
  puts "=" * 60
  puts "Migrating to index #{to_index}, dryrun=#{dryrun}, revision_applied_by=#{revision_applied_by}"
  
  index_config = schema_manager.get_index_config(to_index)
  raise "Index configuration not found for #{to_index}" unless index_config
  
  latest_revision = schema_manager.get_latest_revision_path(to_index)
  raise "No revisions found for #{to_index}" unless latest_revision
  
  revision_name = "#{to_index}/revisions/#{File.basename(latest_revision)}"
  
  if client.index_exists?(to_index)
    current_revision = client.get_schema_revision(to_index)
    
    if current_revision == revision_name
      raise "Already at revision #{revision_name}. To re-create this index and re-migrate, run rake 'schema:close[#{to_index}]' and then re-run rake 'schema:migrate[#{to_index}]'"
    end
    
    if current_revision.nil?
      puts "Unable to determine the current schema revision of #{to_index} by inspecting the live index's _meta settings.
  The index was likely created outside this tool.
  Will attempt to migrate anyway as a non-breaking, in-place update to the index.
  If this operation fails, you may need to run rake 'schema:close[#{to_index}]' and then re-run rake 'schema:migrate[#{to_index}]'"
    end
  end
  
  # Check for reindex requirements before creating the index
  if index_config['from_index_name'] && !client.index_exists?(to_index)
    from_index = index_config['from_index_name']
    
    if client.index_exists?(from_index)
      puts "Reindexing from #{from_index} to #{to_index}"
      unless dryrun
        Rake::Task['schema:reindex'].invoke(to_index)
        Rake::Task['schema:catchup'].invoke(to_index)
      end
    else
      puts "Source index #{from_index} does not exist. Skipping reindex for #{to_index}."
      puts "Note: #{to_index} will be created as a new index without data migration."
    end
  end
  
  unless dryrun
    schema_manager.generate_diff_output_for_index_name_or_revision(to_index)
    Rake::Task['schema:create'].invoke(to_index)
    Rake::Task['schema:painless'].invoke(to_index)
    
    metadata = {
      revision: revision_name,
      revision_applied_at: Time.now.iso8601,
      revision_applied_by: revision_applied_by
    }
    schema_manager.update_revision_metadata(to_index, latest_revision, metadata)
    
    settings_update = {
      index: {
        _meta: {
          schemurai_revision: metadata
        }
      }
    }
    client.update_index_settings(to_index, settings_update)
    puts "=" * 60
  end
  
  puts "Migration completed successfully"
  puts "=" * 60
end

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
    
    # If no to_index is provided, discover and migrate all schemas
    if to_index.nil?
      puts "No specific index provided. Discovering all schemas and migrating to latest revisions..."
      puts "Dry run: #{dryrun}"
      
      schemas = SchemaTools::Utils.discover_latest_schema_versions_only(SchemaTools::Config::SCHEMAS_PATH)
      
      if schemas.empty?
        puts "No schemas found in #{SchemaTools::Config::SCHEMAS_PATH}"
        exit
      end
      
      puts "Found #{schemas.length} schema(s) to migrate:"
      schemas.each do |schema|
        puts "  - #{schema[:index_name]} (latest revision: #{schema[:revision_number]})"
      end
      puts
      
      schemas.each do |schema|
        puts "=" * 60
        puts "Migrating #{schema[:index_name]} to revision #{schema[:revision_number]}"
        puts "=" * 60
        
        begin
          migrate_single_schema(schema[:index_name], dryrun, revision_applied_by, schema_manager, client)
          puts "✓ Migration completed successfully for #{schema[:index_name]}"
        rescue => e
          puts "✗ Migration failed for #{schema[:index_name]}: #{e.message}"
          puts "Continuing with next schema..."
        end
        puts
      end
      
      puts "All migrations completed!"
    else
      migrate_single_schema(to_index, dryrun, revision_applied_by, schema_manager, client)
    end
  end


  desc "Generate diff between schema revisions"
  task :diff, [:index_name_or_revision] do |t, args|
    schema_manager = SchemaTools::SchemaManager.new(SchemaTools::Config::SCHEMAS_PATH)
    puts schema_manager.generate_diff_output_for_index_name_or_revision(index_name_or_revision)
  end

  desc "Create index with schema definition"
  task :create, [:index_name] do |t, args|
    validate_client!
    
    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    latest_revision = schema_manager.get_latest_revision_path(index_name)
    raise "No revisions found for #{index_name}" unless latest_revision
    
    revision_files = schema_manager.get_revision_files(latest_revision)
    
    if client.index_exists?(index_name)
      puts "Index #{index_name} already exists, updating settings only"
      client.update_index_settings(index_name, revision_files[:settings])
    else
      puts "Creating index #{index_name}"
      client.create_index(index_name, revision_files[:settings], revision_files[:mappings])
    end
  end

  desc "Upload painless scripts to index"
  task :painless, [:index_name] do |t, args|
    validate_client!
    
    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    latest_revision = schema_manager.get_latest_revision_path(index_name)
    raise "No revisions found for #{index_name}" unless latest_revision
    
    revision_files = schema_manager.get_revision_files(latest_revision)
    
    revision_files[:painless_scripts].each do |script_name, script_content|
      puts "Uploading script: #{script_name}"
      client.put_script(script_name, script_content)
    end
  end

  desc "Reindex from source to destination index"
  task :reindex, [:index_name] do |t, args|
    validate_client!
    
    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    index_config = schema_manager.get_index_config(index_name)
    raise "Index configuration not found for #{index_name}" unless index_config
    
    from_index = index_config['from_index_name']
    raise "from_index_name not specified in index configuration" unless from_index
    
    unless client.index_exists?(from_index)
      raise "Source index #{from_index} does not exist. Cannot reindex to #{index_name}."
    end
    
    reindex_script = schema_manager.get_reindex_script(index_name)
    
    puts "Starting reindex from #{from_index} to #{index_name}"
    response = client.reindex(from_index, index_name, reindex_script)
    
    task_id = response['task']
    puts "Reindex task started: #{task_id}"
    
    loop do
      sleep 5
      task_status = client.get_task_status(task_id)
      
      if task_status['completed']
        puts "Reindex completed successfully"
        break
      end
      
      puts "Reindex in progress..."
    end
  end

  desc "Catchup reindex for new documents"
  task :catchup, [:index_name] do |t, args|
    validate_client!
    
    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    index_config = schema_manager.get_index_config(index_name)
    raise "Index configuration not found for #{index_name}" unless index_config
    
    from_index = index_config['from_index_name']
    raise "from_index_name not specified in index configuration" unless from_index
    
    unless client.index_exists?(from_index)
      raise "Source index #{from_index} does not exist. Cannot perform catchup reindex to #{index_name}."
    end
    
    reindex_script = schema_manager.get_reindex_script(index_name)
    
    puts "Starting catchup reindex from #{from_index} to #{index_name}"
    response = client.reindex(from_index, index_name, reindex_script)
    
    task_id = response['task']
    puts "Catchup task started: #{task_id}"
    
    loop do
      sleep 5
      task_status = client.get_task_status(task_id)
      
      if task_status['completed']
        puts "Catchup completed successfully"
        break
      end
      
      puts "Catchup in progress..."
    end
  end

  desc "Close an index"
  task :close, [:index_name] do |t, args|
    validate_client!

    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    puts "Closing index #{index_name}"
    
    if client.index_exists?(index_name)
      client.close_index(index_name)
      puts "Index #{index_name} closed"
    else
      puts "Index #{index_name} does not exist"
    end
  end

  desc "Hard delete an index (only works on closed indexes)"
  task :delete, [:index_name] do |t, args|
    validate_client!

    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    unless client.index_closed?(index_name)
      raise "Hard delete only allowed on closed indexes. Please run 'schema:close[#{index_name}]' first."
    end
    
    puts "Hard deleting index #{index_name}"
    
    if client.index_exists?(index_name)
      client.delete_index(index_name)
      puts "Index #{index_name} hard deleted"
    else
      puts "Index #{index_name} does not exist"
    end
  end

  desc "Define schema files for a new or existing index"
  task :define do |t, args|
    begin
      validate_client!

      schema_definer = SchemaTools::SchemaDefiner.new(client, schema_manager)
      
      puts "Please choose:"
      puts "1. Define a schema for an index that exists in OpenSearch or Elasticsearch"
      puts "2. Define an example schema for an index that doesn't exist"
      puts "3. Define an example schema for a breaking change to an existing defined schema"
      puts "4. Define an example schema for a non-breaking change to an existing defined schema"
      
      choice = STDIN.gets&.chomp
      if choice.nil?
        puts "No input provided. Exiting."
        exit 1
      end
      
      case choice
      when '1'
        # List available indices (connection already validated during client initialization)
        puts "Connecting to #{SchemaTools::Config::CONNECTION_URL}..."
        indices = client.list_indices
        
        if indices.empty?
          puts "No indices found in the cluster."
          puts "Please create an index first or choose option 2 to define a schema for a new index."
          exit 0
        end
        
        puts "Available indices:"
        indices.each_with_index do |index_name, index|
          puts "#{index + 1}. #{index_name}"
        end
        
        puts "\nPlease select an index by number (1-#{indices.length}):"
        selection_input = STDIN.gets&.chomp
        if selection_input.nil?
          puts "No input provided. Exiting."
          exit 1
        end
        selection = selection_input.to_i
        
        if selection < 1 || selection > indices.length
          puts "Invalid selection. Please run the task again and select a valid number."
          exit 1
        end
        
        selected_index = indices[selection - 1]
        puts "Selected index: #{selected_index}"
        puts "Checking #{SchemaTools::Config::CONNECTION_URL} for the latest version of \"#{selected_index}\""
        schema_definer.define_schema_for_existing_index(selected_index)
      when '2'
        puts "Type the name of a new index to define. A version number suffix is not required."
        index_name = STDIN.gets&.chomp
        if index_name.nil?
          puts "No input provided. Exiting."
          exit 1
        end
        schema_definer.define_example_schema_for_new_index(index_name)
      when '3'
        puts "Type the name of an existing schema to change. A version number suffix is not required."
        index_name = STDIN.gets&.chomp
        if index_name.nil?
          puts "No input provided. Exiting."
          exit 1
        end
        schema_definer.define_breaking_change_schema(index_name)
      when '4'
        puts "Type the name of an existing schema to change. A version number suffix is not required."
        index_name = STDIN.gets&.chomp
        if index_name.nil?
          puts "No input provided. Exiting."
          exit 1
        end
        schema_definer.define_non_breaking_change_schema(index_name)
      else
        puts "Invalid choice. Please run the task again and select 1, 2, 3, or 4."
      end
    rescue => e
      puts "Failed to connect to OpenSearch at #{SchemaTools::Config::CONNECTION_URL}"
      puts "Error: #{e.message}"
    end
  end
end