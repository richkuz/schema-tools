require 'json'
require 'fileutils'
require 'schema_tools/breaking_change_detector'
require_relative 'utils'
require_relative 'schema_revision'

module SchemaTools
  class SchemaDefiner
    def initialize(client)
      @client = client
      @schema_manager = schema_manager = SchemaTools::SchemaManager.new()
      @breaking_change_detector = BreakingChangeDetector.new()
    end

    def define_schema_for_existing_index(index_name)
      base_name = extract_base_name(index_name)
      
      unless @client.index_exists?(base_name)
        latest_index = find_latest_index_version(base_name)
        unless latest_index
          puts "Index \"#{base_name}\" not found at #{@client.instance_variable_get(:@url)}"
          return
        end
        base_name = latest_index
      end
      
      puts "Index \"#{extract_base_name(index_name)}\" found at #{@client.instance_variable_get(:@url)}, latest index name is \"#{base_name}\""
      puts "Extracting live settings, mappings, and painless scripts from index \"#{base_name}\""
      
      live_data = extract_live_index_data(base_name)
      schema_base_name = extract_base_name(base_name)
      
      puts "Checking schemas/#{schema_base_name}* for the latest schema definition of \"#{schema_base_name}\""
      
      latest_schema_path = find_latest_schema_definition(schema_base_name)
      
      unless latest_schema_path
        puts "No schema definition exists for \"#{base_name}\""
        generate_example_schema_files(base_name, live_data)
        puts "\nCreate this index by running:"
        puts "$ rake schema:migrate"
        return
      end
      
      latest_schema_revision = SchemaRevision.for_latest_revision(File.basename(latest_schema_path))
      puts "Latest schema definition of \"#{schema_base_name}\" is defined in #{File.basename(latest_schema_path)}/revisions/#{latest_schema_revision.revision_number}."
      
      schema_data = @schema_manager.get_revision_files(latest_schema_revision.revision_absolute_path)
      
      if schemas_match?(live_data, schema_data)
        puts "Latest schema definition already matches the index."
        return
      end
      
      if @breaking_change_detector.breaking_change?(live_data, schema_data)
        puts "Index settings and mappings constitute a breaking change from the latest schema definition."
        new_index_name = generate_next_index_name(schema_base_name)
        generate_example_schema_files(new_index_name, live_data)
        puts "\nMigrate to this schema definition by running:"
        puts "$ rake schema:migrate"
      else
        puts "Index settings and mappings constitute a non-breaking change from the latest schema definition."
        next_revision = generate_next_revision_number(latest_schema_path)
        generate_revision_files(latest_schema_path, next_revision, live_data)
        puts "\nMigrate to this schema definition by running:"
        puts "$ rake schema:migrate"
      end
    end

    def define_example_schema_for_new_index(index_name)
      base_name = extract_base_name(index_name)
      
      puts "Checking schemas/#{base_name}* for any schema definition of \"#{base_name}\""
      
      latest_schema_path = find_latest_schema_definition(base_name)
      
      unless latest_schema_path
        puts "No schema definition exists for \"#{base_name}\""
        example_data = generate_example_data
        generate_example_schema_files(base_name, example_data)
        puts "\nCreate this index by running:"
        puts "$ rake schema:migrate"
        return
      end
      
      latest_schema_revision = SchemaRevision.for_latest_revision(File.basename(latest_schema_path))
      puts "Latest schema definition of \"#{base_name}\" is defined in #{File.basename(latest_schema_path)}/revisions/#{latest_schema_revision.revision_number}"
      puts "\nCreate this index by running:"
      puts "$ rake schema:migrate"
    end

    def define_breaking_change_schema(index_name)
      base_name = extract_base_name(index_name)
      
      puts "Checking schemas/#{base_name}* for the latest schema definition of \"#{base_name}\""
      
      latest_schema_path = find_latest_schema_definition(base_name)
      
      unless latest_schema_path
        puts "No schema definition exists for \"#{base_name}\"."
        return
      end
      
      latest_schema_revision = SchemaRevision.for_latest_revision(File.basename(latest_schema_path))
      puts "Latest schema definition of \"#{base_name}\" is defined in #{File.basename(latest_schema_path)}/revisions/#{latest_schema_revision.revision_number}"
      
      new_index_name = generate_next_index_name(base_name)
      example_data = generate_example_data
      generate_example_schema_files(new_index_name, example_data)
      puts "\nMigrate to this schema definition by running:"
      puts "$ rake schema:migrate"
    end

    def define_non_breaking_change_schema(index_name)
      base_name = extract_base_name(index_name)
      
      puts "Checking schemas/#{base_name}* for the latest schema definition of \"#{base_name}\""
      
      latest_schema_path = find_latest_schema_definition(base_name)
      
      unless latest_schema_path
        puts "No schema definition exists for \"#{base_name}\"."
        return
      end
      
      latest_schema_revision = SchemaRevision.for_latest_revision(File.basename(latest_schema_path))
      puts "Latest schema definition of \"#{base_name}\" is defined in #{File.basename(latest_schema_path)}/revisions/#{latest_schema_revision.revision_number}"
      
      next_revision = generate_next_revision_number(latest_schema_path)
      example_data = generate_example_data
      generate_revision_files(latest_schema_path, next_revision, example_data)
      puts "\nMigrate to this schema definition by running:"
      puts "$ rake schema:migrate"
    end

    private

    def extract_base_name(index_name)
      SchemaTools::Utils.extract_base_name(index_name)
    end

    def find_latest_index_version(base_name)
      response = @client.get("/_cat/indices/#{base_name}*?format=json")
      return nil unless response && response.is_a?(Array)
      
      versions = response.map { |index| index['index'] }
                        .select { |name| name.match?(/^#{Regexp.escape(base_name)}(-\d+)?$/) }
                        .map { |name| extract_version_number(name) }
                        .compact
                        .sort
      
      versions.empty? ? nil : "#{base_name}-#{versions.last}"
    end

    def extract_version_number(index_name)
      SchemaTools::Utils.extract_version_number(index_name)
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

    # Find the latest schema definition for a given base name
    # Example: "products" -> "schemas/products-3" (if products-3 is the latest)
    def find_latest_schema_definition(base_name)
      schema_dirs = Dir.glob(File.join(SchemaTools::Config::SCHEMAS_PATH, "#{base_name}*"))
                      .select { |d| File.directory?(d) }
                      .sort_by { |d| extract_version_number(File.basename(d)) }
      
      schema_dirs.last
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


    def schemas_match?(live_data, schema_data)
      normalize_settings(live_data[:settings]) == normalize_settings(schema_data[:settings]) &&
      normalize_mappings(live_data[:mappings]) == normalize_mappings(schema_data[:mappings])
    end

    # Generate the next index name for a given base index name
    # Example: "products" -> "products-2", "products-3" -> "products-4"
    def generate_next_index_name(base_name)
      latest_schema_path = find_latest_schema_definition(base_name)
      return "#{base_name}-2" unless latest_schema_path
      
      current_version = extract_version_number(File.basename(latest_schema_path))
      "#{base_name}-#{current_version + 1}"
    end

    def generate_next_revision_number(schema_path)
      revisions_path = File.join(schema_path, 'revisions')
      return 1 unless Dir.exist?(revisions_path)
      
      revision_dirs = Dir.glob(File.join(revisions_path, '*'))
                        .select { |d| File.directory?(d) }
                        .map { |d| File.basename(d).to_i }
                        .sort
      
      revision_dirs.empty? ? 1 : revision_dirs.last + 1
    end

    def generate_example_schema_files(index_name, data)
      schemas_path = @schema_manager.instance_variable_get(:@schemas_path)
      index_path = File.join(schemas_path, index_name)
      
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

    def generate_revision_files(schema_path, revision_number, data)
      revision_path = File.join(schema_path, 'revisions', revision_number.to_s)
      FileUtils.mkdir_p(revision_path)
      FileUtils.mkdir_p(File.join(revision_path, 'painless_scripts'))
      
      File.write(File.join(revision_path, 'settings.json'), JSON.pretty_generate(data[:settings]))
      File.write(File.join(revision_path, 'mappings.json'), JSON.pretty_generate(data[:mappings]))
      
      write_painless_scripts(File.join(revision_path, 'painless_scripts'), data[:painless_scripts])
      
      File.write(File.join(revision_path, 'diff_output.txt'), 'Schema revision')
      
      puts "\nGenerated example schema definition files:"
      puts "schemas/#{File.basename(schema_path)}"
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