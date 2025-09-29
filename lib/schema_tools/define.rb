module SchemaTools
  def self.define(client:)
    schema_definer = SchemaDefiner.new(client)
    
    puts "\nPlease choose:"
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
      puts "Connecting to #{Config.connection_url}..."
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
      puts "Checking #{Config.connection_url} for the latest version of \"#{selected_index}\""
      schema_definer.define_schema_for_existing_live_index(selected_index)
    when '2'
      puts "Type the name of a new index to define. A version number suffix is not required."
      index_name = STDIN.gets&.chomp
      if index_name.nil?
        puts "No input provided. Exiting."
        exit 1
      end
      schema_definer.define_example_schema_for_new_index(index_name)
    when '3'
      select_existing_schema_for_breaking_change(schema_definer)
    when '4'
      select_existing_schema_for_non_breaking_change(schema_definer)
    else
      puts "Invalid choice. Please run the task again and select 1, 2, 3, or 4."
    end
  end

  private

  def self.select_existing_schema_for_breaking_change(schema_definer)
    selected_schema = select_existing_schema
    schema_definer.define_breaking_change_schema(selected_schema)
  end

  def self.select_existing_schema_for_non_breaking_change(schema_definer)
    selected_schema = select_existing_schema
    schema_definer.define_non_breaking_change_schema(selected_schema)
  end

  def self.select_existing_schema
    schemas = discover_available_schemas
    
    if schemas.empty?
      puts "No existing schemas found in #{Config.schemas_path}"
      puts "Please create a schema first using option 1 or 2."
      exit 0
    end
    
    puts "Available schemas:"
    schemas.each_with_index do |schema, index|
      puts "#{index + 1}. #{schema[:index_name]} (latest revision: #{schema[:revision_number]})"
    end
    
    puts "\nPlease select a schema by number (1-#{schemas.length}):"
    selection_input = STDIN.gets&.chomp
    if selection_input.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    selection = selection_input.to_i
    
    if selection < 1 || selection > schemas.length
      puts "Invalid selection. Please run the task again and select a valid number."
      exit 1
    end
    
    selected_schema = schemas[selection - 1]
    puts "Selected schema: #{selected_schema[:index_name]}"
    selected_schema[:index_name]
  end

  def self.discover_available_schemas
    return [] unless Dir.exist?(Config.schemas_path)
    
    schemas = []
    
    # Get all directories in the schemas path
    Dir.glob(File.join(Config.schemas_path, '*'))
       .select { |d| File.directory?(d) }
       .each do |schema_dir|
      schema_name = File.basename(schema_dir)
      
      # Check if this schema has an index.json and revisions
      index_config = SchemaFiles.get_index_config(schema_name)
      latest_schema_revision = SchemaRevision.find_latest_revision(schema_name)
      
      if index_config && latest_schema_revision
        schemas << {
          index_name: schema_name,
          latest_revision: latest_schema_revision.revision_absolute_path,
          revision_number: latest_schema_revision.revision_number
        }
      end
    end
    
    schemas
  end
end