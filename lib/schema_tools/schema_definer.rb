require 'json'
require 'fileutils'
require_relative 'breaking_change_detector'
require_relative 'utils'
require_relative 'schema_revision'
require_relative 'config'
require_relative 'index'
require_relative 'schema_files'

module SchemaTools
  class SchemaDefiner

    def initialize(client)
      @client = client
      @breaking_change_detector = BreakingChangeDetector.new()
    end

    # index_name_pattern: e.g. "products" or "products-3"
    def define_schema_for_existing_index(index_name_pattern)
      base_name = Utils.extract_base_name(index_name_pattern) # "products"
      latest_live_index = Index.find_matching_live_indexes(base_name, @client).last # "products-5"
      unless latest_live_index
        puts "No live indexes found starting with \"#{base_name}\" at #{@client.url}"
        return
      end
      puts "Index \"#{latest_live_index.index_name}\" is the latest versioned index name found at #{@client.url}"

      puts "Extracting live settings, mappings, and painless scripts from index \"#{latest_live_index.index_name}\""
      live_data = extract_live_index_data(latest_live_index.index_name)

      puts "Searching for index folders on disk that start with #{base_name}"
      latest_file_index = Index.find_matching_file_indexes(base_name).last
      unless latest_file_index
        puts "No index folder exists starting with \"#{index_name_pattern}\" in \"#{Config.SCHEMAS_PATH}\""
        puts "Creating a new example index revision folder."
        generate_example_schema_files(base_name, live_data)
        puts "\nCreate a live index for this example by running:"
        puts "$ rake schema:migrate"
        return
      end

      latest_schema_revision = SchemaRevision.find_latest_revision(latest_file_index.index_name)
      unless latest_schema_revision
        puts "No revision folders exist in #{Config.SCHEMAS_PATH} for \"#{latest_file_index.index_name}\""
        puts "Creating a new example index revision folder."
        generate_example_schema_files(base_name, live_data)
        puts "\nCreate a live index for this example by running:"
        puts "$ rake schema:migrate"
        return
      end
      puts "Latest schema definition found at \"#{latest_schema_revision.revision_relative_path}\""

      puts "Comparing live index to the latest schema definition's settings, mappings, and painless scripts..."
      schema_data = SchemaFiles.get_revision_files(latest_schema_revision)
      
      if schemas_match?(live_data, schema_data)
        puts "Latest schema definition already matches the live index."
      elsif @breaking_change_detector.breaking_change?(live_data, schema_data)
        puts "Index settings and mappings constitute a breaking change from the latest schema definition."
        new_index_name = latest_file_index.generate_next_index_name
        generate_example_schema_files(new_index_name, live_data)
        puts "\nMigrate to this schema definition by running:"
        puts "$ rake schema:migrate"
      else
        puts "Index settings and mappings constitute a non-breaking change from the latest schema definition."
        generate_next_revision_files(
          latest_file_index.index_name,
          latest_schema_revision.generate_next_revision_absolute_path,
          live_data
        )
        puts "\nMigrate to this schema definition by running:"
        puts "$ rake schema:migrate"
      end
    end

    def define_breaking_change_schema(index_name_pattern)
      base_name = Utils.extract_base_name(index_name_pattern) # "products"
      
      puts "Searching for index folders on disk that start with #{base_name}"
      latest_file_index = Index.find_matching_file_indexes(base_name).last
      unless latest_file_index
        puts "No index folder exists starting with \"#{index_name_pattern}\" in \"#{Config.SCHEMAS_PATH}\""
        return
      end

      latest_schema_revision = SchemaRevision.find_latest_revision(latest_file_index.index_name)
      unless latest_schema_revision
        puts "No revision folders exist in #{Config.SCHEMAS_PATH} for \"#{latest_file_index.index_name}\""
        return
      end
      puts "Latest schema definition found at \"#{latest_schema_revision.revision_relative_path}\""
      
      new_index_name = latest_file_index.generate_next_index_name
      example_data = generate_example_data
      generate_example_schema_files(new_index_name, example_data)
      puts "\nMigrate to this schema definition by running:"
      puts "$ rake schema:migrate"
    end

    def define_non_breaking_change_schema(index_name_pattern)
      base_name = Utils.extract_base_name(index_name_pattern) # "products"
      
      puts "Searching for index folders on disk that start with #{base_name}"
      latest_file_index = Index.find_matching_file_indexes(base_name).last
      unless latest_file_index
        puts "No index folder exists starting with \"#{index_name_pattern}\" in \"#{Config.SCHEMAS_PATH}\""
        return
      end

      latest_schema_revision = SchemaRevision.find_latest_revision(latest_file_index.index_name)
      unless latest_schema_revision
        puts "No revision folders exist in #{Config.SCHEMAS_PATH} for \"#{latest_file_index.index_name}\""
        return
      end
      puts "Latest schema definition found at \"#{latest_schema_revision.revision_relative_path}\""
      
      example_data = generate_example_data
      generate_next_revision_files(
        latest_file_index.index_name,
        latest_schema_revision.generate_next_revision_absolute_path,
        example_data
      )
      puts "\nMigrate to this schema definition by running:"
      puts "$ rake schema:migrate"
    end

    def define_example_schema_for_new_index(index_name_pattern)
      base_name = Utils.extract_base_name(index_name_pattern)
      
      puts "Searching for index folders on disk that start with #{base_name}"
      latest_file_index = Index.find_matching_file_indexes(base_name).last
      
      if latest_file_index
        latest_schema_revision = SchemaRevision.find_latest_revision(latest_file_index.index_name)
        if latest_schema_revision
          puts "Latest schema definition of \"#{base_name}\" is defined at \"#{latest_schema_revision.revision_relative_path}\""
          return
        end
      end
      
      puts "No schema definition exists for \"#{index_name_pattern}\""
      example_data = generate_example_data
      generate_example_schema_files(index_name_pattern, example_data)
      puts "\nCreate a live index for this example by running:"
      puts "$ rake schema:migrate"
    end


    private

    def schemas_match?(live_data, schema_data)
      normalize_settings(live_data[:settings]) == normalize_settings(schema_data[:settings]) &&
      normalize_mappings(live_data[:mappings]) == normalize_mappings(schema_data[:mappings])
    end

    def extract_live_index_data(index_name)
      settings = @client.get_index_settings(index_name)
      mappings_response = @client.get("/#{index_name}/_mapping")
      mappings = mappings_response ? mappings_response[index_name]['mappings'] : {}
      painless_scripts = @client.get_stored_scripts
      
      {
        settings: filter_internal_settings(settings || {}),
        mappings: mappings,
        painless_scripts: painless_scripts
      }
    end

    def filter_internal_settings(settings)
      return settings unless settings.is_a?(Hash)
      
      # Deep clone the settings to avoid modifying the original
      filtered_settings = JSON.parse(JSON.generate(settings))
      
      # Remove OpenSearch/Elasticsearch internal fields that shouldn't be in schema definitions
      internal_fields = [
        'creation_date',
        'provided_name', 
        'uuid',
        'version'
      ]
      
      if filtered_settings['index']
        internal_fields.each do |field|
          filtered_settings['index'].delete(field)
        end
      end
      
      filtered_settings
    end

    def generate_example_schema_files(index_name, data)
      index_path = File.join(Config.SCHEMAS_PATH, index_name)
      
      FileUtils.mkdir_p(index_path)
      FileUtils.mkdir_p(File.join(index_path, 'revisions', '1'))
      FileUtils.mkdir_p(File.join(index_path, 'revisions', '1', 'painless_scripts'))
      
      index_config = {
        index_name: index_name,
        from_index_name: nil
      }
      
      File.write(File.join(index_path, 'index.json'), JSON.pretty_generate(index_config))
      File.write(File.join(index_path, 'reindex.painless'), generate_reindex_script)
      
      File.write(File.join(index_path, 'revisions', '1', 'settings.json'), JSON.pretty_generate(data[:settings]))
      File.write(File.join(index_path, 'revisions', '1', 'mappings.json'), JSON.pretty_generate(data[:mappings]))
      
      write_painless_scripts(File.join(index_path, 'revisions', '1', 'painless_scripts'), data[:painless_scripts])
      
      File.write(File.join(index_path, 'revisions', '1', 'diff_output.txt'), 'Initial schema definition')
      
      puts "\nGenerated example schema definition files:"
      puts "schemas/#{index_name}"
      puts "  index.json"
      puts "  reindex.painless"
      puts "  revisions/1"
      puts "    settings.json"
      puts "    mappings.json"
      puts "    painless_scripts/"
      data[:painless_scripts].each do |script_name, _|
        puts "      #{script_name}.painless"
      end
      puts "    diff_output.txt"
    end

    def generate_next_revision_files(index_name, revision_path, data)
      FileUtils.mkdir_p(revision_path)
      FileUtils.mkdir_p(File.join(revision_path, 'painless_scripts'))
      
      File.write(File.join(revision_path, 'settings.json'), JSON.pretty_generate(data[:settings]))
      File.write(File.join(revision_path, 'mappings.json'), JSON.pretty_generate(data[:mappings]))
      
      write_painless_scripts(File.join(revision_path, 'painless_scripts'), data[:painless_scripts])
      
      File.write(File.join(revision_path, 'diff_output.txt'), 'Schema revision')
      
      revision_number = File.basename(revision_path)
      
      puts "\nGenerated example schema definition files:"
      puts "schemas/#{index_name}"
      puts "  revisions/#{revision_number}"
      puts "    settings.json"
      puts "    mappings.json"
      puts "    painless_scripts/"
      data[:painless_scripts].each do |script_name, _|
        puts "      #{script_name}.painless"
      end
      puts "    diff_output.txt"
    end

    def generate_example_data
      {
        settings: {
          index: {
            number_of_shards: 1,
            number_of_replicas: 0,
            refresh_interval: "1s",
            analysis: {
              analyzer: {
                example_analyzer: {
                  type: "custom",
                  tokenizer: "standard",
                  filter: ["lowercase", "stop"]
                }
              }
            }
          }
        },
        mappings: {
          properties: {
            id: { type: "keyword" },
            name: { type: "text", analyzer: "example_analyzer" },
            description: { type: "text", analyzer: "example_analyzer" },
            created_at: { type: "date" },
            updated_at: { type: "date" }
          }
        },
        painless_scripts: {}
      }
    end

    def generate_reindex_script
      "# Example reindex script for transforming data during migration\n" +
      "# Modify this script to transform your data as needed\n" +
      "#\n" +
      "# Example: Rename a field\n" +
      "# if (ctx._source.containsKey('old_field_name')) {\n" +
      "#   ctx._source.new_field_name = ctx._source.old_field_name;\n" +
      "#   ctx._source.remove('old_field_name');\n" +
      "# }\n" +
      "#\n" +
      "# Example: Add a new field\n" +
      "# ctx._source.new_field = 'default_value';\n"
    end

    def generate_example_script
      "# Example painless script\n" +
      "# Modify this script for your specific use case\n" +
      "# ctx._source.example_field = 'example_value';"
    end

    def generate_painless_scripts_instructions
      "Add into this folder all painless scripts you want uploaded into the index.\n" +
      "Painless script files must end with the extension .painless\n" +
      "\n" +
      "Example:\n" +
      "  my_script.painless\n" +
      "  another_script.painless\n" +
      "\n" +
      "Scripts will be uploaded to the index when you run:\n" +
      "  rake 'schema:migrate[index_name]'"
    end

    def normalize_settings(settings)
      return {} unless settings
      
      normalized = settings.dup
      normalized.delete('index') if normalized['index']
      normalized['index'] = settings['index'] if settings['index']
      
      JSON.parse(JSON.generate(normalized))
    end

    def normalize_mappings(mappings)
      return {} unless mappings
      JSON.parse(JSON.generate(mappings))
    end

    def write_painless_scripts(scripts_dir, painless_scripts)
      FileUtils.mkdir_p(scripts_dir)
      
      if painless_scripts.empty?
        # Write instruction file if no scripts found
        File.write(File.join(scripts_dir, 'README.txt'), generate_painless_scripts_instructions)
      else
        # Write actual scripts from live index
        painless_scripts.each do |script_name, script_content|
          File.write(File.join(scripts_dir, "#{script_name}.painless"), script_content)
        end
      end
    end
  end
end