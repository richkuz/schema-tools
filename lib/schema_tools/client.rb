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
      
      meta = settings.dig('index', '_meta', 'schema_tools_revision')
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

    def delete_index(index_name)
      delete("/#{index_name}")
    end
  end
end