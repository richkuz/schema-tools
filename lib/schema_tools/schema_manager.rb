require 'json'
require 'fileutils'
require 'time'
require 'logger'
require_relative 'json_diff'

module SchemaTools
  class SchemaManager
    def initialize(schemas_path, logger: Logger.new(STDOUT))
      @schemas_path = schemas_path
      @logger = logger
      @json_diff = JsonDiff.new(logger: logger)
    end

    def get_index_config(index_name)
      index_path = File.join(@schemas_path, index_name)
      return nil unless Dir.exist?(index_path)
      
      index_json_path = File.join(index_path, 'index.json')
      return nil unless File.exist?(index_json_path)
      
      JSON.parse(File.read(index_json_path))
    end

    def get_latest_revision_path(index_name)
      return nil unless index_name
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

    # Find a previous revision within this index_name
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

    def get_previous_revision_path_across_indexes(revision_path)
      index_name = File.basename(revision_path.split('/revisions/').first)
      previous_revision_path = self.get_previous_revision_path(index_name, revision_path)
      return previous_revision_path if previous_revision_path

      # Look in the previous index for its latest revision
      previous_schema_name = SchemaTools::Utils.generate_previous_version_name(index_name)
      self.get_latest_revision_path(previous_schema_name)
    end

    def get_reindex_script(index_name)
      index_path = File.join(@schemas_path, index_name)
      script_path = File.join(index_path, 'reindex.painless')
      
      File.exist?(script_path) ? File.read(script_path) : nil
    end

    # index_name_or_revision can be "products-3" or "produts-3/revisions/2"
    #
    # Given "products-3", return the diff against "products-3/revisions/<Latest minus 1>"
    # Given "products-3/revisions/2", return the diff against "products-3/revisions/1"
    # Given "products-3/revisions/1", return the diff against "products-2/revisions/<Latest>"
    def generate_diff_output_for_index_name_or_revision(index_name_or_revision)
      raise "index_name_or_revision parameter is required" unless index_name_or_revision
      
      revision_path = ''
      if index_name_or_revision.include?('/revisions/')
        revision_path = File.join(SchemaTools::Config::SCHEMAS_PATH, index_name_or_revision)
        raise "revision path #{index_name_or_revision} does not exist!" unless Dir.exist?(revision_path)
      else
        revision_path = self.get_latest_revision_path(index_name_or_revision)
        raise "No revisions found for #{index_name}" unless revision_path
      end
      generate_diff_output_for_revision_path(revision_path)
    end

    # revision_path e.g. "/Users/foo/schemas/products-3/revisions/1"
    def generate_diff_output_for_revision_path(revision_path)
      previous_revision_path = self.get_previous_revision_path_across_indexes(revision_path)
      self.generate_diff_output(revision_path, previous_revision_path)
    end

    def generate_diff_output(revision_path, previous_revision_path)
      current_files = get_revision_files(revision_path)
      previous_files = previous_revision_path ? get_revision_files(previous_revision_path) : { settings: {}, mappings: {}, painless_scripts: {} }
      
      diff_content = []
      
      if previous_revision_path
        diff_content << "Diff between current revision #{revision_path} and previous revision #{previous_revision_path}"
      else
        diff_content << "Diff between current revision #{revision_path} and empty baseline"
      end
      diff_content << ""
      
      diff_content << "=== Settings Diff ==="
      diff_content << @json_diff.generate_diff(previous_files[:settings], current_files[:settings])
      
      diff_content << "\n=== Mappings Diff ==="
      diff_content << @json_diff.generate_diff(previous_files[:mappings], current_files[:mappings])
      
      diff_content << "\n=== Painless Scripts Diff ==="
      diff_content << generate_scripts_diff(previous_files[:painless_scripts], current_files[:painless_scripts])
      
      diff_output_path = File.join(revision_path, 'diff_output.txt')
      File.write(diff_output_path, diff_content.join("\n"))
      puts "Wrote diff output to #{diff_output_path}"
      
      diff_content.join("\n")
    end

    def update_revision_metadata(index_name, revision_path, metadata)
      settings = {
        index: {
          _meta: {
            schemurai_revision: metadata
          }
        }
      }
      
      settings_path = File.join(revision_path, 'settings.json')
      current_settings = load_json_file(settings_path) || {}
      
      current_settings['index'] ||= {}
      current_settings['index']['_meta'] ||= {}
      current_settings['index']['_meta']['schemurai_revision'] = metadata
      
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


    def generate_scripts_diff(old_scripts, new_scripts)
      all_script_names = (old_scripts.keys + new_scripts.keys).uniq.sort
      changes = []
      
      if all_script_names.empty?
        return "No painless scripts found in either version"
      end
      
      all_script_names.each do |script_name|
        old_content = old_scripts[script_name]
        new_content = new_scripts[script_name]
        
        if old_content.nil? && new_content
          changes << "➕ ADDED SCRIPT: #{script_name}"
          changes << "  Content:"
          new_content.split("\n").each_with_index do |line, index|
            changes << "    #{index + 1}: #{line}"
          end
        elsif old_content && new_content.nil?
          changes << "➖ REMOVED SCRIPT: #{script_name}"
          changes << "  Previous content:"
          old_content.split("\n").each_with_index do |line, index|
            changes << "    #{index + 1}: #{line}"
          end
        elsif old_content != new_content
          changes << "🔄 MODIFIED SCRIPT: #{script_name}"
          
          # Show line-by-line differences for modified scripts
          old_lines = old_content.split("\n")
          new_lines = new_content.split("\n")
          
          changes << "  Changes:"
          max_lines = [old_lines.length, new_lines.length].max
          
          (0...max_lines).each do |line_num|
            old_line = old_lines[line_num]
            new_line = new_lines[line_num]
            
            if old_line.nil?
              changes << "    + #{line_num + 1}: #{new_line}"
            elsif new_line.nil?
              changes << "    - #{line_num + 1}: #{old_line}"
            elsif old_line != new_line
              changes << "    ~ #{line_num + 1}: #{old_line} → #{new_line}"
            end
          end
        end
      end
      
      changes.empty? ? "No script changes" : changes.join("\n")
    end

  end
end