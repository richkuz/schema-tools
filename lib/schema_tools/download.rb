require 'json'
require 'fileutils'
require_relative 'config'

module SchemaTools
  def self.download(client:)
    aliases = client.list_aliases
    indices = client.list_indices
    
    single_aliases = aliases.select { |_, indices| indices.length == 1 }
    multi_aliases = aliases.select { |_, indices| indices.length > 1 }
    unaliased_indices = indices.reject { |index| aliases.values.flatten.include?(index) }
    
    puts "\nAliases pointing to 1 index:"
    if single_aliases.empty?
      puts "  (none)"
    else
      single_aliases.each_with_index do |(alias_name, indices), index|
        puts "  #{index + 1}. #{alias_name} -> #{indices.first}"
      end
    end
    
    puts "\nIndexes not part of any aliases:"
    if unaliased_indices.empty?
      puts "  (none)"
    else
      unaliased_indices.each_with_index do |index_name, index|
        puts "  #{index + 1}. #{index_name}"
      end
    end
    
    if multi_aliases.any?
      puts "\nAliases pointing to more than 1 index (cannot choose):"
      multi_aliases.each do |alias_name, indices|
        puts "  - #{alias_name} -> #{indices.join(', ')}"
      end
    end
    
    puts "\nPlease choose an alias or index to download:"
    puts "Enter 'alias:<name>' for an alias or 'index:<name>' for an index:"
    
    choice = STDIN.gets&.chomp
    if choice.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    
    if choice.start_with?('alias:')
      alias_name = choice[6..-1]
      if single_aliases[alias_name]
        download_alias(alias_name, single_aliases[alias_name].first, client)
      else
        puts "Alias '#{alias_name}' not found or points to multiple indices."
        exit 1
      end
    elsif choice.start_with?('index:')
      index_name = choice[6..-1]
      if unaliased_indices.include?(index_name)
        puts "Warning: This tool only supports migrating aliases."
        puts "Create an alias for this index first:"
        puts "```"
        puts "POST /_aliases"
        puts "{"
        puts "  \"actions\": ["
        puts "    {"
        puts "      \"add\": {"
        puts "        \"index\": \"#{index_name}\","
        puts "        \"alias\": \"new_alias_name\""
        puts "      }"
        puts "    }"
        puts "  ]"
        puts "}"
        puts "```"
        puts "\nDo you want to download it anyway? (y/N)"
        confirm = STDIN.gets&.chomp&.downcase
        if confirm == 'y'
          download_index(index_name, client)
        else
          puts "Download cancelled."
        end
      else
        puts "Index '#{index_name}' not found or is already aliased."
        exit 1
      end
    else
      puts "Invalid choice. Please use 'alias:<name>' or 'index:<name>' format."
      exit 1
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
    
    schema_path = File.join(Config.schemas_path, folder_name)
    FileUtils.mkdir_p(schema_path)
    
    settings_file = File.join(schema_path, 'settings.json')
    mappings_file = File.join(schema_path, 'mappings.json')
    
    File.write(settings_file, JSON.pretty_generate(settings))
    File.write(mappings_file, JSON.pretty_generate(mappings))
    
    puts "✓ Schema downloaded to #{schema_path}"
    puts "  - settings.json"
    puts "  - mappings.json"
  end
end