require 'schema_tools/client'
require 'schema_tools/schema_manager'
require 'schema_tools/schema_definer'
require 'schema_tools/config'
require 'schema_tools/utils'
require 'json'
require 'time'

def migrate_single_schema(to_index, dryrun, revision_applied_by, schema_manager, client)
  puts "Migrating to index: #{to_index}"
  puts "Dry run: #{dryrun}"
  
  index_config = schema_manager.get_index_config(to_index)
  raise "Index configuration not found for #{to_index}" unless index_config
  
  latest_revision = schema_manager.get_latest_revision_path(to_index)
  raise "No revisions found for #{to_index}" unless latest_revision
  
  revision_name = "#{to_index}/revisions/#{File.basename(latest_revision)}"
  
  if client.index_exists?(to_index)
    current_revision = client.get_schema_revision(to_index)
    
    if current_revision == revision_name
      puts "Already at revision #{revision_name}. To re-create this index and re-migrate, run rake schema:softdelete[#{to_index}] and then re-run schema:migrate[to_index=#{to_index}]"
      return
    end
    
    if current_revision.nil?
      puts "Unable to determine the current schema revision of #{to_index}. To re-create this index and re-migrate, run rake schema:softdelete[#{to_index}] and then re-run schema:migrate[to_index=#{to_index}]"
      return
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
    Rake::Task['schema:diff'].invoke(to_index)
    Rake::Task['schema:create'].invoke(to_index)
    Rake::Task['schema:painless'].invoke(to_index)
  end
  
  unless dryrun
    metadata = {
      revision: revision_name,
      revision_applied_at: Time.now.iso8601,
      revision_applied_by: revision_applied_by
    }
    
    schema_manager.update_revision_metadata(to_index, latest_revision, metadata)
    
    settings_update = {
      index: {
        _meta: {
          schema_tools_revision: metadata
        }
      }
    }
    
    client.update_index_settings(to_index, settings_update)
  end
  
  puts "Migration completed successfully"
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
      
      schemas = schema_manager.discover_all_schemas_with_latest_revisions
      
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
      # Original single schema migration logic
      migrate_single_schema(to_index, dryrun, revision_applied_by, schema_manager, client)
    end
  end


  desc "Generate diff between schema revisions"
  task :diff, [:index_name_or_revision] do |t, args|
    index_name_or_revision = args[:index_name_or_revision]
    raise "index_name_or_revision parameter is required" unless index_name_or_revision
    
    # Check if the parameter is a specific revision path (contains '/revisions/')
    if index_name_or_revision.include?('/revisions/')
      # Parse the revision path to extract index name and revision
      revision_path = File.join(SchemaTools::Config::SCHEMAS_PATH, index_name_or_revision)
      raise "Revision path does not exist: #{revision_path}" unless Dir.exist?(revision_path)
      
      # Extract index name from the path
      index_name = index_name_or_revision.split('/revisions/').first
      
      # Find the previous revision
      previous_revision = schema_manager.get_previous_revision_path(index_name, revision_path)
      
      if previous_revision.nil?
        # Try to find the latest revision of the previous schema version
        previous_schema_name = SchemaTools::Utils.generate_previous_version_name(index_name)
        
        if previous_schema_name
          previous_schema_latest = schema_manager.get_latest_revision_path(previous_schema_name)
          
          if previous_schema_latest
            puts "No previous revision found within #{index_name}. Comparing against latest revision of #{previous_schema_name}."
            previous_revision = previous_schema_latest
          else
            puts "No previous revision found for #{index_name} and no previous schema version (#{previous_schema_name}) exists."
            puts "Diff generation requires at least two revisions to compare."
            exit 0
          end
        else
          puts "No previous revision found for #{index_name}. This appears to be the first revision."
          puts "Generating diff against empty baseline..."
          
          # Generate diff against empty baseline for first revision
          empty_revision = nil
          diff_output = schema_manager.generate_diff_output(index_name, revision_path, empty_revision)
          puts diff_output
          exit 0
        end
      end
      
      diff_output = schema_manager.generate_diff_output(index_name, revision_path, previous_revision)
      puts diff_output
    else
      # Original behavior: use index name to find latest revision
      index_name = index_name_or_revision
      
      latest_revision = schema_manager.get_latest_revision_path(index_name)
      raise "No revisions found for #{index_name}" unless latest_revision
      
      previous_revision = schema_manager.get_previous_revision_path(index_name, latest_revision)
      
      # If no previous revision within the same schema, try to find the latest revision of the previous schema version
      if previous_revision.nil?
        previous_schema_name = SchemaTools::Utils.generate_previous_version_name(index_name)
        
        if previous_schema_name
          previous_schema_latest = schema_manager.get_latest_revision_path(previous_schema_name)
          
          if previous_schema_latest
            puts "No previous revision found within #{index_name}. Comparing against latest revision of #{previous_schema_name}."
            previous_revision = previous_schema_latest
          else
            puts "No previous revision found for #{index_name} and no previous schema version (#{previous_schema_name}) exists."
            puts "Diff generation requires at least two revisions to compare."
            exit 0
          end
        else
          puts "No previous revision found for #{index_name}. This appears to be the first revision."
          puts "Generating diff against empty baseline..."
          
          # Generate diff against empty baseline for first revision
          empty_revision = nil
          diff_output = schema_manager.generate_diff_output(index_name, latest_revision, empty_revision)
          puts diff_output
          exit 0
        end
      end
      
      diff_output = schema_manager.generate_diff_output(index_name, latest_revision, previous_revision)
      puts diff_output
    end
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

  desc "Soft delete an index by renaming it"
  task :softdelete, [:index_name] do |t, args|
    validate_client!
    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    deleted_name = "deleted-#{index_name}-#{timestamp}"
    
    puts "Soft deleting index #{index_name} -> #{deleted_name}"
    
    if client.index_exists?(index_name)
      client.put("/#{index_name}/_alias/#{deleted_name}", {})
      client.delete("/#{index_name}")
      puts "Index #{index_name} soft deleted as #{deleted_name}"
    else
      puts "Index #{index_name} does not exist"
    end
  end

  desc "Hard delete an index (only works on deleted- prefixed indexes)"
  task :delete, [:index_name] do |t, args|
    validate_client!
    index_name = args[:index_name]
    raise "index_name parameter is required" unless index_name
    
    unless index_name.start_with?('deleted-')
      raise "Hard delete only allowed on indexes prefixed with 'deleted-'"
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