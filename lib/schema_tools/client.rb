require 'net/http'
require 'json'
require 'uri'
require 'logger'
require_relative 'settings_filter'

module SchemaTools
  class Client
    attr_reader :url
    
    def initialize(url, dryrun: false, logger: Logger.new(STDOUT), username: nil, password: nil)
      @url = url
      @dryrun = dryrun
      @logger = logger
      @username = username
      @password = password
      @logger.info "Client is running in DRYRUN mode. No mutating operations will be performed." if dryrun
    end

    def get(path)
      uri = URI("#{@url}#{path}")
      request = Net::HTTP::Get.new(uri)
      add_auth_header(request)
      response = make_http_request(uri) { |http| http.request(request) }
      
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
      add_auth_header(request)
      
      response = make_http_request(uri) { |http| http.request(request) }
      
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
      add_auth_header(request)
      
      response = make_http_request(uri) { |http| http.request(request) }
      
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
      add_auth_header(request)
      
      response = make_http_request(uri) { |http| http.request(request) }
      
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

    def get_index_doc_count(index_name)
      response = get("/#{index_name}/_count")
      return 0 unless response
      response['count'] || 0
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
        dest: { index: dest_index },
        conflicts: "proceed"
      }
      body[:script] = { source: script } if script
      
      url = "/_reindex?wait_for_completion=false&refresh=false"
      
      post(url, body)
    end

    def get_task_status(task_id)
      get("/_tasks/#{task_id}")
    end

    def put_script(script_name, script_content)
      body = { script: { lang: "painless", source: script_content } }
      put("/_scripts/#{script_name}", body)
    end

    def delete_script(script_name)
      if @dryrun
        print_curl_command('DELETE', "/_scripts/#{script_name}")
        return { 'acknowledged' => true } # Return mock response for dry run
      end

      uri = URI("#{@url}/_scripts/#{script_name}")
      request = Net::HTTP::Delete.new(uri)
      add_auth_header(request)
      
      response = make_http_request(uri) { |http| http.request(request) }
      
      case response.code.to_i
      when 200
        JSON.parse(response.body) if response.body && !response.body.empty?
      when 404
        raise "HTTP 404: Script '#{script_name}' not found"
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
    end

    def get_stored_scripts
      # Try the legacy Elasticsearch API first (works for Elasticsearch and older OpenSearch)
      begin
        response = get("/_scripts")
        return {} unless response
        
        scripts = {}
        response.each do |script_id, script_data|
          scripts[script_id] = script_data.dig('script', 'source')
        end
        
        return scripts
      rescue => e
        # If the legacy API fails (e.g., OpenSearch 2.x), try the new API
        begin
          response = get("/_cluster/state/metadata?filter_path=metadata.stored_scripts")
          return {} unless response
          
          stored_scripts_data = response.dig('metadata', 'stored_scripts')
          return {} unless stored_scripts_data
          
          scripts = {}
          stored_scripts_data.each do |script_id, script_data|
            scripts[script_id] = script_data['source']
          end
          
          return scripts
        rescue => fallback_error
          # If both APIs fail, log the original error and return empty hash
          @logger.warn("Could not retrieve stored scripts: #{e.message}") if @logger
          {}
        end
      end
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

    def list_aliases
      response = get("/_aliases")
      return {} unless response
      
      aliases = {}
      response.each do |index_name, index_data|
        index_aliases = index_data['aliases']
        next unless index_aliases && !index_aliases.empty?
        
        index_aliases.each do |alias_name, alias_data|
          aliases[alias_name] ||= []
          aliases[alias_name] << index_name
        end
      end
      
      aliases
    end

    def get_alias_indices(alias_name)
      response = get("/_alias/#{alias_name}")
      return [] unless response
      
      response.keys
    end

    def create_alias(alias_name, index_name)
      body = {
        actions: [
          {
            add: {
              index: index_name,
              alias: alias_name
            }
          }
        ]
      }
      post("/_aliases", body)
    end

    def alias_exists?(alias_name)
      response = get("/_alias/#{alias_name}")
      response && !response.empty?
    end

    def delete_alias(alias_name, indices = nil)
      # If no indices specified, get all indices for this alias
      if indices.nil?
        indices = get_alias_indices(alias_name)
      end
      
      actions = indices.map do |index_name|
        {
          remove: {
            index: index_name,
            alias: alias_name
          }
        }
      end
      
      body = { actions: actions }
      post("/_aliases", body)
    end

    def update_index_settings(index_name, settings)
      # Filter out internal settings that can't be updated
      filtered_settings = SettingsFilter.filter_internal_settings(settings)
      
      body = { index: filtered_settings['index'] || {} }
      put("/#{index_name}/_settings", body)
    end

    def update_index_mappings(index_name, mappings)
      body = { properties: mappings['properties'] || {} }
      put("/#{index_name}/_mapping", body)
    end

    def test_connection
      path = "/_cluster/health"
      puts "Testing connection to #{@url}#{path}"
      get(path)
      true
    rescue => e
      puts e
      false
    end

    def close_index(index_name)
      post("/#{index_name}/_close", {})
    end

    def update_by_query(source_index, dest_index, script = nil)
      body = {
        source: { index: source_index },
        dest: { index: dest_index }
      }
      body[:script] = { source: script } if script
      
      url = "/_update_by_query?wait_for_completion=false"
      
      post(url, body)
    end

    def update_aliases(actions)
      body = { actions: actions }
      post("/_aliases", body)
    end

    def wait_for_task(task_id, timeout = 3600)
      start_time = Time.now
      
      loop do
        task_status = get_task_status(task_id)
        
        if task_status['completed']
          return task_status
        end
        
        if Time.now - start_time > timeout
          raise "Task #{task_id} timed out after #{timeout} seconds"
        end
        
        sleep 5
      end
    end

    def bulk_index(documents, index_name)
      if @dryrun
        print_curl_command('POST', '/_bulk', documents)
        return { 'items' => documents.map { |doc| { 'index' => { 'status' => 201 } } } }
      end

      bulk_body = documents.map do |doc|
        [
          { index: { _index: index_name } },
          doc
        ]
      end.flatten

      ndjson = bulk_body.map(&:to_json).join("\n") + "\n"

      uri = URI("#{@url}/_bulk")
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/x-ndjson'
      request.body = ndjson
      add_auth_header(request)
      
      response = make_http_request(uri) { |http| http.request(request) }
      
      case response.code.to_i
      when 200
        JSON.parse(response.body)
      else
        raise "HTTP #{response.code}: #{response.body}"
      end
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

    def make_http_request(uri)
      use_ssl = uri.scheme == 'https'
      port = uri.port || (use_ssl ? 443 : 80)
      
      Net::HTTP.start(uri.hostname, port, use_ssl: use_ssl) do |http|
        yield(http)
      end
    end

    def add_auth_header(request)
      if @username && @password
        request.basic_auth(@username, @password)
      end
    end

    def print_curl_command(method, path, body = nil)
      uri = URI("#{@url}#{path}")
      curl_cmd = "curl -X #{method.upcase} '#{uri}'"
      
      if @username && @password
        curl_cmd += " -u '#{@username}:#{@password}'"
      end
      
      if body
        curl_cmd += " -H 'Content-Type: application/json'"
        curl_cmd += " -d '#{body.to_json}'"
      end
      
      @logger.info "🔍 DRY RUN - Would execute: #{curl_cmd}"
    end
  end
end