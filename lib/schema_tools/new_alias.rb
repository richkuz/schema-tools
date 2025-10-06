require 'json'
require 'fileutils'
require 'time'
require_relative 'config'

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
    
    File.write(settings_file, JSON.pretty_generate(sample_settings))
    File.write(mappings_file, JSON.pretty_generate(sample_mappings))
    
    puts "✓ Sample schema created at #{schema_path}"
    puts "  - settings.json"
    puts "  - mappings.json"
  end
end