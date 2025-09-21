require 'json'
require 'fileutils'
require 'time'
require 'logger'

module SchemaTools
  class SchemaManager
    def initialize(schemas_path, logger: Logger.new(STDOUT))
      @schemas_path = schemas_path
      @logger = logger
    end

    def get_index_config(index_name)
      index_path = File.join(@schemas_path, index_name)
      return nil unless Dir.exist?(index_path)
      
      index_json_path = File.join(index_path, 'index.json')
      return nil unless File.exist?(index_json_path)
      
      JSON.parse(File.read(index_json_path))
    end

    def get_latest_revision_path(index_name)
      index_path = File.join(@schemas_path, index_name)
      return nil unless Dir.exist?(index_path)
      
      revisions_path = File.join(index_path, 'revisions')
      return nil unless Dir.exist?(revisions_path)
      
      revision_dirs = Dir.glob(File.join(revisions_path, '*'))
                        .select { |d| File.directory?(d) }
                        .sort_by { |d| File.basename(d).to_i }
      
      revision_dirs.last
    end

    def get_revision_files(revision_path)
      {
        settings: load_json_file(File.join(revision_path, 'settings.json')),
        mappings: load_json_file(File.join(revision_path, 'mappings.json')),
        painless_scripts: load_painless_scripts(File.join(revision_path, 'painless_scripts'))
      }
    end

    def get_previous_revision_path(index_name, current_revision)
      index_path = File.join(@schemas_path, index_name)
      revisions_path = File.join(index_path, 'revisions')
      return nil unless Dir.exist?(revisions_path)
      
      revision_dirs = Dir.glob(File.join(revisions_path, '*'))
                        .select { |d| File.directory?(d) }
                        .sort_by { |d| File.basename(d).to_i }
      
      current_index = revision_dirs.find_index { |d| d == current_revision }
      return nil unless current_index && current_index > 0
      
      revision_dirs[current_index - 1]
    end

    def get_reindex_script(index_name)
      index_path = File.join(@schemas_path, index_name)
      script_path = File.join(index_path, 'reindex.painless')
      
      File.exist?(script_path) ? File.read(script_path) : nil
    end

    def generate_diff_output(index_name, current_revision, previous_revision)
      current_files = get_revision_files(current_revision)
      previous_files = previous_revision ? get_revision_files(previous_revision) : { settings: {}, mappings: {}, painless_scripts: {} }
      
      diff_content = []
      
      diff_content << "=== Settings Diff ==="
      diff_content << generate_json_diff(previous_files[:settings], current_files[:settings])
      
      diff_content << "\n=== Mappings Diff ==="
      diff_content << generate_json_diff(previous_files[:mappings], current_files[:mappings])
      
      diff_content << "\n=== Painless Scripts Diff ==="
      diff_content << generate_scripts_diff(previous_files[:painless_scripts], current_files[:painless_scripts])
      
      diff_output_path = File.join(current_revision, 'diff_output.txt')
      File.write(diff_output_path, diff_content.join("\n"))
      
      diff_content.join("\n")
    end

    def update_revision_metadata(index_name, revision_path, metadata)
      settings = {
        index: {
          _meta: {
            schema_tools_revision: metadata
          }
        }
      }
      
      settings_path = File.join(revision_path, 'settings.json')
      current_settings = load_json_file(settings_path) || {}
      
      current_settings['index'] ||= {}
      current_settings['index']['_meta'] ||= {}
      current_settings['index']['_meta']['schema_tools_revision'] = metadata
      
      File.write(settings_path, JSON.pretty_generate(current_settings))
    end

    def discover_all_schemas_with_latest_revisions
      return [] unless Dir.exist?(@schemas_path)
      
      schemas = []
      
      # Get all directories in the schemas path
      Dir.glob(File.join(@schemas_path, '*'))
         .select { |d| File.directory?(d) }
         .each do |schema_dir|
        schema_name = File.basename(schema_dir)
        
        # Check if this schema has an index.json and revisions
        index_config = get_index_config(schema_name)
        latest_revision = get_latest_revision_path(schema_name)
        
        if index_config && latest_revision
          schemas << {
            index_name: schema_name,
            latest_revision: latest_revision,
            revision_number: File.basename(latest_revision)
          }
        end
      end
      
      schemas
    end

    private

    def load_json_file(file_path)
      return {} unless File.exist?(file_path)
      JSON.parse(File.read(file_path))
    rescue JSON::ParserError => e
      @logger.error "Failed to parse JSON file #{file_path}: #{e.message}"
      {}
    end

    def load_painless_scripts(scripts_dir)
      return {} unless Dir.exist?(scripts_dir)
      
      scripts = {}
      Dir.glob(File.join(scripts_dir, '*.painless')).each do |script_file|
        script_name = File.basename(script_file, '.painless')
        scripts[script_name] = File.read(script_file)
      end
      
      scripts
    end

    def generate_json_diff(old_json, new_json)
      old_normalized = normalize_json(old_json)
      new_normalized = normalize_json(new_json)
      
      if old_normalized == new_normalized
        "No changes"
      else
        "Changes detected between revisions"
      end
    end

    def generate_scripts_diff(old_scripts, new_scripts)
      all_script_names = (old_scripts.keys + new_scripts.keys).uniq
      changes = []
      
      all_script_names.each do |script_name|
        old_content = old_scripts[script_name]
        new_content = new_scripts[script_name]
        
        if old_content.nil? && new_content
          changes << "Added script: #{script_name}"
        elsif old_content && new_content.nil?
          changes << "Removed script: #{script_name}"
        elsif old_content != new_content
          changes << "Modified script: #{script_name}"
        end
      end
      
      changes.empty? ? "No script changes" : changes.join("\n")
    end

    def normalize_json(json_obj)
      return {} unless json_obj
      JSON.parse(JSON.generate(json_obj))
    end
  end
end