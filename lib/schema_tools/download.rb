require 'json'
require 'fileutils'
require_relative 'config'
require_relative 'settings_filter'

module SchemaTools
  def self.download(client:)
    aliases = client.list_aliases
    indices = client.list_indices
    
    single_aliases = aliases.select { |alias_name, indices| indices.length == 1 && !alias_name.start_with?('.') }
    multi_aliases = aliases.select { |alias_name, indices| indices.length > 1 && !alias_name.start_with?('.') }
    unaliased_indices = indices.reject { |index| aliases.values.flatten.include?(index) || index.start_with?('.') }
    
    # Create a combined list with sequential numbering
    options = []
    
    puts "\nAliases pointing to 1 index:"
    if single_aliases.empty?
      puts "  (none)"
    else
      single_aliases.each_with_index do |(alias_name, indices), index|
        option_number = options.length + 1
        options << { type: :alias, name: alias_name, index: indices.first }
        puts "  #{option_number}. #{alias_name} -> #{indices.first}"
      end
    end
    
    puts "\nIndexes not part of any aliases:"
    if unaliased_indices.empty?
      puts "  (none)"
    else
      unaliased_indices.each_with_index do |index_name, index|
        option_number = options.length + 1
        options << { type: :index, name: index_name, index: index_name }
        puts "  #{option_number}. #{index_name}"
      end
    end
    
    if multi_aliases.any?
      puts "\nAliases pointing to more than 1 index (cannot choose):"
      multi_aliases.each do |alias_name, indices|
        puts "  - #{alias_name} -> #{indices.join(', ')}"
      end
    end
    
    if options.empty?
      puts "\nNo aliases or indices available to download."
      return
    end
    
    puts "\nPlease choose an alias or index to download:"
    puts "Enter the number (1-#{options.length}):"
    
    choice = STDIN.gets&.chomp
    if choice.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    
    choice_num = choice.to_i
    if choice_num < 1 || choice_num > options.length
      puts "Invalid choice. Please enter a number between 1 and #{options.length}."
      exit 1
    end
    
    selected_option = options[choice_num - 1]
    
    if selected_option[:type] == :alias
      download_alias(selected_option[:name], selected_option[:index], client)
    else
      download_index(selected_option[:name], client)
    end
  end

  private

  def self.download_alias(alias_name, index_name, client)
    puts "Downloading alias '#{alias_name}' (index: #{index_name})..."
    download_schema(alias_name, index_name, client)
  end

  def self.download_index(index_name, client)
    puts "Downloading index '#{index_name}'..."
    download_schema(index_name, index_name, client)
  end

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
    
    File.write(settings_file, JSON.pretty_generate(filtered_settings))
    File.write(mappings_file, JSON.pretty_generate(mappings))
    
    puts "✓ Schema downloaded to #{schema_path}"
    puts "  - settings.json"
    puts "  - mappings.json"
  end

end