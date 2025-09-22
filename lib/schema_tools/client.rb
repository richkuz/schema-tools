require 'net/http'
require 'json'
require 'uri'
require 'logger'

module SchemaTools
  class Client
    def initialize(url, logger: Logger.new(STDOUT))
      @url = url
      @logger = logger
    end

    def get(path)
      uri = URI("#{@url}#{path}")
      request = Net::HTTP::Get.new(uri)
      response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
      
      case response.code.to_i
      when 200
        JSON.parse(response.body)
      when 404
        nil
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    end

    def put(path, body)
      uri = URI("#{@url}#{path}")
      request = Net::HTTP::Put.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = body.to_json
      
      response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
      
      case response.code.to_i
      when 200, 201
        JSON.parse(response.body) if response.body && !response.body.empty?
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    end

    def post(path, body)
      uri = URI("#{@url}#{path}")
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = body.to_json
      
      response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
      
      case response.code.to_i
      when 200, 201
        JSON.parse(response.body) if response.body && !response.body.empty?
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    end

    def delete(path)
      uri = URI("#{@url}#{path}")
      request = Net::HTTP::Delete.new(uri)
      
      response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
      
      case response.code.to_i
      when 200, 404
        JSON.parse(response.body) if response.body && !response.body.empty?
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    end

    def index_exists?(index_name)
      get("/#{index_name}") != nil
    end

    def get_index_settings(index_name)
      response = get("/#{index_name}")
      return nil unless response
      response[index_name]['settings']
    end

    def get_schema_revision(index_name)
      settings = get_index_settings(index_name)
      return nil unless settings
      
      meta = settings.dig('index', '_meta', 'schemurai_revision')
      meta ? meta['revision'] : nil
    end

    def create_index(index_name, settings, mappings)
      body = {
        settings: settings,
        mappings: mappings
      }
      put("/#{index_name}", body)
    end

    def update_index_settings(index_name, settings)
      put("/#{index_name}/_settings", settings)
    end

    def reindex(source_index, dest_index, script = nil)
      body = {
        source: { index: source_index },
        dest: { index: dest_index }
      }
      body[:script] = { source: script } if script
      
      post("/_reindex", body)
    end

    def get_task_status(task_id)
      get("/_tasks/#{task_id}")
    end

    def put_script(script_name, script_content)
      body = { script: { source: script_content } }
      put("/_scripts/#{script_name}", body)
    end

    def get_stored_scripts
      response = get("/_scripts")
      return {} unless response
      
      scripts = {}
      response.each do |script_id, script_data|
        scripts[script_id] = script_data.dig('script', 'source')
      end
      
      scripts
    rescue => e
      # If scripts endpoint is not available or returns an error, return empty hash
      @logger.warn("Could not retrieve stored scripts: #{e.message}") if @logger
      {}
    end

    def delete_index(index_name)
      delete("/#{index_name}")
    end

    def list_indices
      response = get("/_cat/indices?format=json")
      return [] unless response && response.is_a?(Array)
      
      response.map { |index| index['index'] }
              .reject { |name| name.start_with?('.') || name.start_with?('top_queries-') } # Exclude system indices
              .sort
    end

    def test_connection
      get("/_cluster/health")
      true
    rescue => e
      false
    end

    def close_index(index_name)
      post("/#{index_name}/_close", {})
    end

    def index_closed?(index_name)
      response = get("/#{index_name}")
      return false unless response
      
      # Check if the index is closed by looking at the index status
      # Closed indices have a specific status in the response
      index_info = response[index_name]
      return false unless index_info
      
      # Check if the index is closed by looking at the settings
      settings = index_info['settings']
      return false unless settings
      
      # An index is closed if it has the 'verified_before_close' setting set to true
      settings.dig('index', 'verified_before_close') == 'true'
    end
  end
end