require 'json'
require 'fileutils'
require 'time'
require_relative 'schema_revision'

module SchemaTools
  class SchemaFiles
    def self.get_index_config(index_name)
      index_path = File.join(Config.SCHEMAS_PATH, index_name)
      return nil unless Dir.exist?(index_path)
      
      index_json_path = File.join(index_path, 'index.json')
      return nil unless File.exist?(index_json_path)
      
      JSON.parse(File.read(index_json_path))
    end

    # Return a map of settings, mappings, and painless_scripts content
    # Raises an error if settings or mappings don't exist and are not valid JSON
    def self.get_revision_files(schema_revision)
      {
        settings: load_json_file(File.join(schema_revision.revision_absolute_path, 'settings.json')),
        mappings: load_json_file(File.join(schema_revision.revision_absolute_path, 'mappings.json')),
        painless_scripts: load_painless_scripts(File.join(schema_revision.revision_absolute_path, 'painless_scripts'))
      }
    end

    def self.get_reindex_script(index_name)
      index_path = File.join(Config.SCHEMAS_PATH, index_name)
      script_path = File.join(index_path, 'reindex.painless')
      
      File.exist?(script_path) ? File.read(script_path) : nil
    end

    def self.discover_all_schemas_with_latest_revisions
      return [] unless Dir.exist?(Config.SCHEMAS_PATH)
      
      schemas = []
      
      # Get all directories in the schemas path
      Dir.glob(File.join(Config.SCHEMAS_PATH, '*'))
         .select { |d| File.directory?(d) }
         .each do |schema_dir|
        schema_name = File.basename(schema_dir)
        
        # Check if this schema has an index.json and revisions
        index_config = get_index_config(schema_name)
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

    private

    def self.load_json_file(file_path)
      raise "#{file_path} not found" unless File.exist?(file_path)
      JSON.parse(File.read(file_path))
    end

    def self.load_painless_scripts(scripts_dir)
      return {} unless Dir.exist?(scripts_dir)
      
      scripts = {}
      Dir.glob(File.join(scripts_dir, '*.painless')).each do |script_file|
        script_name = File.basename(script_file, '.painless')
        scripts[script_name] = File.read(script_file)
      end
      
      scripts
    end
  end
end