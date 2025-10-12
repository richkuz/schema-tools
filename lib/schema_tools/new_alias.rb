require 'json'
require 'fileutils'
require 'time'
require_relative 'config'
require_relative 'settings_filter'

module SchemaTools
  def self.new_alias(client:)
    puts "\nEnter a new alias name:"
    alias_name = STDIN.gets&.chomp
    if alias_name.nil? || alias_name.empty?
      puts "No alias name provided. Exiting."
      exit 1
    end
    
    if client.alias_exists?(alias_name)
      puts "Alias '#{alias_name}' already exists."
      exit 1
    end
    
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    index_name = "#{alias_name}-#{timestamp}"
    
    puts "Creating index '#{index_name}' with alias '#{alias_name}'..."
    
    sample_settings = {
      "number_of_shards" => 1,
      "number_of_replicas" => 0,
      "replication": {
        "type": "DOCUMENT"
      },
      "analysis" => {
        "analyzer" => {
          "default" => {
            "type" => "standard"
          }
        }
      }
    }
    
    sample_mappings = {
      "properties" => {
        "id" => {
          "type" => "keyword"
        },
        "created_at" => {
          "type" => "date"
        },
        "updated_at" => {
          "type" => "date"
        }
      }
    }
    
    client.create_index(index_name, sample_settings, sample_mappings)
    client.create_alias(alias_name, index_name)
    
    puts "✓ Created index '#{index_name}' with alias '#{alias_name}'"
    
    schema_path = File.join(Config.schemas_path, alias_name)
    FileUtils.mkdir_p(schema_path)
    
    settings_file = File.join(schema_path, 'settings.json')
    mappings_file = File.join(schema_path, 'mappings.json')
    reindex_file = File.join(schema_path, 'reindex.painless')
    
    File.write(settings_file, JSON.pretty_generate(sample_settings))
    File.write(mappings_file, JSON.pretty_generate(sample_mappings))
    
    # Create example reindex.painless file
    reindex_content = <<~PAINLESS
      // Example reindex script for transforming data during migration
      // Modify this script to transform your data as needed
      //
      // Example: Rename a field
      // if (ctx._source.containsKey('old_field_name')) {
      //   ctx._source.new_field_name = ctx._source.old_field_name;
      //   ctx._source.remove('old_field_name');
      // }
      //
      // Example: Add a new field
      // ctx._source.new_field = 'default_value';
      long timestamp = System.currentTimeMillis();
    PAINLESS
    
    File.write(reindex_file, reindex_content)
    
    puts "✓ Sample schema created at #{schema_path}"
    puts "  - settings.json"
    puts "  - mappings.json"
    puts "  - reindex.painless"
  end

  def self.create_alias_for_index(client:)
    aliases = client.list_aliases
    indices = client.list_indices
    
    unaliased_indices = indices.reject { |index| aliases.values.flatten.include?(index) || index.start_with?('.') || client.index_closed?(index) }
    
    puts "\nIndexes not part of any aliases:"
    if unaliased_indices.empty?
      puts "  (none)"
      puts "\nNo unaliased indices available to create aliases for."
      return
    end
    
    unaliased_indices.each_with_index do |index_name, index|
      puts "  #{index + 1}. #{index_name}"
    end
    
    puts "\nPlease choose an index to create an alias for:"
    puts "Enter the number (1-#{unaliased_indices.length}):"
    
    choice = STDIN.gets&.chomp
    if choice.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    
    choice_num = choice.to_i
    if choice_num < 1 || choice_num > unaliased_indices.length
      puts "Invalid choice. Please enter a number between 1 and #{unaliased_indices.length}."
      exit 1
    end
    
    selected_index = unaliased_indices[choice_num - 1]
    
    puts "\nType the name of a new alias to create for this index:"
    new_alias_name = STDIN.gets&.chomp
    if new_alias_name.nil? || new_alias_name.empty?
      puts "No alias name provided. Exiting."
      exit 1
    end
    
    if client.alias_exists?(new_alias_name)
      puts "Alias '#{new_alias_name}' already exists."
      exit 1
    end
    
    puts "Creating alias '#{new_alias_name}' for index '#{selected_index}'..."
    client.create_alias(new_alias_name, selected_index)
    
    puts "✓ Created alias '#{new_alias_name}' -> '#{selected_index}'"
    
    # Download the schema for the newly aliased index
    download_schema(new_alias_name, selected_index, client)
  end

  private

  def self.download_schema(folder_name, index_name, client)
    settings = client.get_index_settings(index_name)
    mappings = client.get_index_mappings(index_name)
    
    if settings.nil? || mappings.nil?
      puts "Failed to retrieve settings or mappings for #{index_name}"
      exit 1
    end
    
    # Filter out internal settings
    filtered_settings = SettingsFilter.filter_internal_settings(settings)
    
    schema_path = File.join(Config.schemas_path, folder_name)
    FileUtils.mkdir_p(schema_path)
    
    settings_file = File.join(schema_path, 'settings.json')
    mappings_file = File.join(schema_path, 'mappings.json')
    reindex_file = File.join(schema_path, 'reindex.painless')
    
    File.write(settings_file, JSON.pretty_generate(filtered_settings))
    File.write(mappings_file, JSON.pretty_generate(mappings))
    
    # Create example reindex.painless file
    reindex_content = <<~PAINLESS
      # Example reindex script for transforming data during migration
      # Modify this script to transform your data as needed
      #
      # Example: Rename a field
      # if (ctx._source.containsKey('old_field_name')) {
      #   ctx._source.new_field_name = ctx._source.old_field_name;
      #   ctx._source.remove('old_field_name');
      # }
      #
      # Example: Add a new field
      # ctx._source.new_field = 'default_value';
    PAINLESS
    
    File.write(reindex_file, reindex_content)
    
    puts "✓ Schema downloaded to #{schema_path}"
    puts "  - settings.json"
    puts "  - mappings.json"
    puts "  - reindex.painless"
  end

end