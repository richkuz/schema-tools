require 'json'

module SchemaTools
  class SettingsFilter
    # Remove read-only OpenSearch/Elasticsearch internal fields
    def self.filter_internal_settings(settings)
      return settings unless settings.is_a?(Hash)
      
      filtered_settings = JSON.parse(JSON.generate(settings))
      
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
  end
end