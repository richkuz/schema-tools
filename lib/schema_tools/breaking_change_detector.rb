require 'json'
require 'logger'

module SchemaTools
  class BreakingChangeDetector
    def initialize(logger: Logger.new(STDOUT))
      @logger = logger
    end

    def breaking_change?(live_data, schema_data)
      live_settings = normalize_settings(live_data[:settings])
      schema_settings = normalize_settings(schema_data[:settings])
      live_mappings = normalize_mappings(live_data[:mappings])
      schema_mappings = normalize_mappings(schema_data[:mappings])

      return true if immutable_index_settings_changed?(live_settings, schema_settings)
      return true if analysis_settings_changed?(live_settings, schema_settings)
      return true if field_type_changed?(live_mappings, schema_mappings)
      return true if field_analyzer_changed?(live_mappings, schema_mappings)
      return true if immutable_field_properties_changed?(live_mappings, schema_mappings)
      return true if multi_field_definitions_changed?(live_mappings, schema_mappings)

      false
    end

    private

    def immutable_index_settings_changed?(live_settings, schema_settings)
      # These settings are immutable and require reindex
      immutable_settings = [
        'number_of_shards',
        'index.codec',
        'routing_partition_size',
        'index.sort.field',
        'index.sort.order',
        'index.sort.mode',
        'index.sort.missing'
      ]

      immutable_settings.any? do |setting|
        live_value = live_settings.dig('index', setting)
        schema_value = schema_settings.dig('index', setting)

        next false unless live_value && schema_value

        live_value != schema_value
      end
    end

    def analysis_settings_changed?(live_settings, schema_settings)
      live_analysis = live_settings.dig('index', 'analysis')
      schema_analysis = schema_settings.dig('index', 'analysis')

      return false unless live_analysis && schema_analysis

      # Any change to existing analyzers, tokenizers, filters, or char_filters requires reindex
      return true if analyzers_changed?(live_analysis, schema_analysis)
      return true if tokenizers_changed?(live_analysis, schema_analysis)
      return true if filters_changed?(live_analysis, schema_analysis)
      return true if char_filters_changed?(live_analysis, schema_analysis)

      false
    end

    def analyzers_changed?(live_analysis, schema_analysis)
      live_analyzers = live_analysis['analyzer'] || {}
      schema_analyzers = schema_analysis['analyzer'] || {}

      # Check if any existing analyzer was modified
      (live_analyzers.keys & schema_analyzers.keys).any? do |analyzer_name|
        live_analyzers[analyzer_name] != schema_analyzers[analyzer_name]
      end
    end

    def tokenizers_changed?(live_analysis, schema_analysis)
      live_tokenizers = live_analysis['tokenizer'] || {}
      schema_tokenizers = schema_analysis['tokenizer'] || {}

      # Check if any existing tokenizer was modified
      (live_tokenizers.keys & schema_tokenizers.keys).any? do |tokenizer_name|
        live_tokenizers[tokenizer_name] != schema_tokenizers[tokenizer_name]
      end
    end

    def filters_changed?(live_analysis, schema_analysis)
      live_filters = live_analysis['filter'] || {}
      schema_filters = schema_analysis['filter'] || {}

      # Check if any existing filter was modified
      (live_filters.keys & schema_filters.keys).any? do |filter_name|
        live_filters[filter_name] != schema_filters[filter_name]
      end
    end

    def char_filters_changed?(live_analysis, schema_analysis)
      live_char_filters = live_analysis['char_filter'] || {}
      schema_char_filters = schema_analysis['char_filter'] || {}

      # Check if any existing char_filter was modified
      (live_char_filters.keys & schema_char_filters.keys).any? do |char_filter_name|
        live_char_filters[char_filter_name] != schema_char_filters[char_filter_name]
      end
    end

    def field_type_changed?(live_mappings, schema_mappings)
      return false unless live_mappings['properties'] && schema_mappings['properties']

      live_props = live_mappings['properties']
      schema_props = schema_mappings['properties']

      # Check existing fields for type changes
      (live_props.keys & schema_props.keys).any? do |field|
        live_type = live_props.dig(field, 'type')
        schema_type = schema_props.dig(field, 'type')

        next false unless live_type && schema_type

        # Any type change requires reindex
        live_type != schema_type
      end
    end

    def field_analyzer_changed?(live_mappings, schema_mappings)
      return false unless live_mappings['properties'] && schema_mappings['properties']

      live_props = live_mappings['properties']
      schema_props = schema_mappings['properties']

      # Check existing fields for analyzer changes
      (live_props.keys & schema_props.keys).any? do |field|
        live_analyzer = live_props.dig(field, 'analyzer')
        schema_analyzer = schema_props.dig(field, 'analyzer')

        next false unless live_analyzer && schema_analyzer

        # Any analyzer change requires reindex
        live_analyzer != schema_analyzer
      end
    end

    def immutable_field_properties_changed?(live_mappings, schema_mappings)
      return false unless live_mappings['properties'] && schema_mappings['properties']

      live_props = live_mappings['properties']
      schema_props = schema_mappings['properties']

      # Check existing fields for immutable property changes
      (live_props.keys & schema_props.keys).any? do |field|
        live_field = live_props[field] || {}
        schema_field = schema_props[field] || {}

        # These properties are immutable and require reindex
        immutable_properties = [
          'index', 'store', 'doc_values', 'fielddata', 'norms'
        ]

        immutable_properties.any? do |property|
          live_value = live_field[property]
          schema_value = schema_field[property]

          # Skip if neither has the property
          next false unless live_value || schema_value

          # If one has the property and the other doesn't, it's a breaking change
          return true if live_value.nil? || schema_value.nil?

          # If both have the property, check if they're different
          live_value != schema_value
        end
      end
    end

    def mutable_field_properties_changed?(live_mappings, schema_mappings)
      return false unless live_mappings['properties'] && schema_mappings['properties']

      live_props = live_mappings['properties']
      schema_props = schema_mappings['properties']

      # Check existing fields for mutable property changes
      (live_props.keys & schema_props.keys).any? do |field|
        live_field = live_props[field] || {}
        schema_field = schema_props[field] || {}

        # These properties are mutable and do NOT require reindex
        mutable_properties = [
          'boost', 'search_analyzer', 'search_quote_analyzer', 'ignore_above', 'ignore_malformed'
        ]

        mutable_properties.any? do |property|
          live_value = live_field[property]
          schema_value = schema_field[property]

          # Skip if neither has the property
          next false unless live_value || schema_value

          # If one has the property and the other doesn't, it's a change but not breaking
          return false if live_value.nil? || schema_value.nil?

          # If both have the property, check if they're different
          live_value != schema_value
        end
      end
    end

    def multi_field_definitions_changed?(live_mappings, schema_mappings)
      return false unless live_mappings['properties'] && schema_mappings['properties']

      live_props = live_mappings['properties']
      schema_props = schema_mappings['properties']

      # Check existing fields for multi-field changes
      (live_props.keys & schema_props.keys).any? do |field|
        live_field = live_props[field] || {}
        schema_field = schema_props[field] || {}

        live_fields = live_field['fields'] || {}
        schema_fields = schema_field['fields'] || {}

        # Check if any subfield was modified or removed
        (live_fields.keys & schema_fields.keys).any? do |subfield_name|
          live_subfield = live_fields[subfield_name] || {}
          schema_subfield = schema_fields[subfield_name] || {}

          # Any change to subfield type or properties requires reindex
          live_subfield != schema_subfield
        end || 
        # Check if any subfield was added (new subfields are OK, but we need to be careful)
        (schema_fields.keys - live_fields.keys).any? do |new_subfield|
          # Only breaking if the new subfield conflicts with existing data structure
          false # For now, we'll be conservative and not consider new subfields as breaking
        end
      end
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
  end
end