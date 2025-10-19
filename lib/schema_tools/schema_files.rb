require 'json'
require 'fileutils'

module SchemaTools
  class SchemaFiles
    def self.get_settings(alias_name)
      settings_path = File.join(Config.schemas_path, alias_name, 'settings.json')
      return nil unless File.exist?(settings_path)
      
      JSON.parse(File.read(settings_path))
    end

    def self.get_mappings(alias_name)
      mappings_path = File.join(Config.schemas_path, alias_name, 'mappings.json')
      return nil unless File.exist?(mappings_path)
      
      JSON.parse(File.read(mappings_path))
    end

    def self.get_reindex_script(alias_name)
      script_path = File.join(Config.schemas_path, alias_name, 'reindex.painless')
      
      File.exist?(script_path) ? File.read(script_path) : nil
    end

    def self.get_sample_docs(alias_name)
      sample_docs_path = File.join(Config.schemas_path, alias_name, 'sample_docs.json')
      return nil unless File.exist?(sample_docs_path)

      JSON.parse(File.read(sample_docs_path))
    end

    def self.get_doc_seeder_class(alias_name)
      seeder_path = File.join(Config.schemas_path, alias_name, 'doc_seeder.rb')
      
      return nil unless File.exist?(seeder_path)
      require(File.expand_path(seeder_path))
      return DocSeeder
    end

    def self.discover_all_schemas
      return [] unless Dir.exist?(Config.schemas_path)
      
      schemas = []
      
      Dir.glob(File.join(Config.schemas_path, '*'))
         .select { |d| File.directory?(d) }
         .each do |schema_dir|
        alias_name = File.basename(schema_dir)
        
        if has_schema_files?(alias_name)
          schemas << alias_name
        end
      end
      
      schemas
    end

    private

    def self.has_schema_files?(alias_name)
      settings_path = File.join(Config.schemas_path, alias_name, 'settings.json')
      mappings_path = File.join(Config.schemas_path, alias_name, 'mappings.json')
      
      File.exist?(settings_path) && File.exist?(mappings_path)
    end
  end
end