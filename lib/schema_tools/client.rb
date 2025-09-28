require 'net/http'
require 'json'
require 'uri'
require 'logger'

module SchemaTools
  class Client
    attr_reader :url
    
    def initialize(url, dryrun: false, logger: Logger.new(STDOUT))
      @url = url
      @dryrun = dryrun
      @logger = logger
      @logger.info "Client is running in DRYRUN mode. No mutating operations will be performed." if dryrun
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
      if @dryrun
        print_curl_command('PUT', path, body)
        return { 'acknowledged' => true } # Return mock response for dry run
      end

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
      if @dryrun
        print_curl_command('POST', path, body)
        return { 'acknowledged' => true } # Return mock response for dry run
      end

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
      if @dryrun
        print_curl_command('DELETE', path)
        return { 'acknowledged' => true } # Return mock response for dry run
      end

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

    def get_index_mappings(index_name)
      response = get("/#{index_name}")
      return nil unless response
      response[index_name]['mappings']
    end

    def get_schema_revision(index_name)
      mappings = get_index_mappings(index_name)
      return nil unless mappings
      
      meta = mappings.dig('_meta', 'schemurai_revision')
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

    def update_index_mappings(index_name, mappings)
      put("/#{index_name}/_mapping", mappings)
    end

    def reindex(source_index, dest_index, script = nil)
      body = {
        source: { index: source_index },
        dest: { index: dest_index }
      }
      body[:script] = { source: script } if script
      
      url = "/_reindex?wait_for_completion=false"
      
      post(url, body)
    end

    def get_task_status(task_id)
      get("/_tasks/#{task_id}")
    end

    def put_script(script_name, script_content)
      body = { script: { lang: "painless", source: script_content } }
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

    private

    def print_curl_command(method, path, body = nil)
      uri = URI("#{@url}#{path}")
      curl_cmd = "curl -X #{method.upcase} '#{uri}'"
      
      if body
        curl_cmd += " -H 'Content-Type: application/json'"
        curl_cmd += " -d '#{body.to_json}'"
      end
      
      @logger.info "🔍 DRY RUN - Would execute: #{curl_cmd}"
    end
  end
end