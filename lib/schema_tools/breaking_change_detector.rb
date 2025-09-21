require 'json'
require 'logger'

module SchemaTools
  class BreakingChangeDetector
    def initialize(logger: Logger.new(STDOUT))
      @logger = logger
    end

    def breaking_change?(proposed_data, current_data)
      proposed_settings = normalize_settings(proposed_data[:settings])
      current_settings = normalize_settings(current_data[:settings])
      proposed_mappings = normalize_mappings(proposed_data[:mappings])
      current_mappings = normalize_mappings(current_data[:mappings])

      return true if immutable_index_settings_changed?(proposed_settings, current_settings)
      return true if analysis_settings_changed?(proposed_settings, current_settings)
      return true if dynamic_mapping_changed?(proposed_mappings, current_mappings)
      return true if field_type_changed?(proposed_mappings, current_mappings)
      return true if field_analyzer_changed?(proposed_mappings, current_mappings)
      return true if immutable_field_properties_changed?(proposed_mappings, current_mappings)
      return true if field_existence_changed?(proposed_mappings, current_mappings)
      return true if multi_field_definitions_changed?(proposed_mappings, current_mappings)

      false
    end

    private

    def immutable_index_settings_changed?(proposed_settings, current_settings)
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
        proposed_value = proposed_settings.dig('index', setting)
        current_value = current_settings.dig('index', setting)

        next false unless proposed_value && current_value

        proposed_value != current_value
      end
    end

    def analysis_settings_changed?(proposed_settings, current_settings)
      proposed_analysis = proposed_settings.dig('index', 'analysis')
      current_analysis = current_settings.dig('index', 'analysis')

      return false unless proposed_analysis && current_analysis

      return true if analyzers_changed?(proposed_analysis, current_analysis)
      return true if tokenizers_changed?(proposed_analysis, current_analysis)
      return true if filters_changed?(proposed_analysis, current_analysis)
      return true if char_filters_changed?(proposed_analysis, current_analysis)

      false
    end

    def analyzers_changed?(proposed_analysis, current_analysis)
      proposed_analyzers = proposed_analysis['analyzer'] || {}
      current_analyzers = current_analysis['analyzer'] || {}

      (proposed_analyzers.keys & current_analyzers.keys).any? do |analyzer_name|
        proposed_analyzers[analyzer_name] != current_analyzers[analyzer_name]
      end
    end

    def tokenizers_changed?(proposed_analysis, current_analysis)
      proposed_tokenizers = proposed_analysis['tokenizer'] || {}
      current_tokenizers = current_analysis['tokenizer'] || {}

      (proposed_tokenizers.keys & current_tokenizers.keys).any? do |tokenizer_name|
        proposed_tokenizers[tokenizer_name] != current_tokenizers[tokenizer_name]
      end
    end

    def filters_changed?(proposed_analysis, current_analysis)
      proposed_filters = proposed_analysis['filter'] || {}
      current_filters = current_analysis['filter'] || {}

      (proposed_filters.keys & current_filters.keys).any? do |filter_name|
        proposed_filters[filter_name] != current_filters[filter_name]
      end
    end

    def char_filters_changed?(proposed_analysis, current_analysis)
      proposed_char_filters = proposed_analysis['char_filter'] || {}
      current_char_filters = current_analysis['char_filter'] || {}

      (proposed_char_filters.keys & current_char_filters.keys).any? do |char_filter_name|
        proposed_char_filters[char_filter_name] != current_char_filters[char_filter_name]
      end
    end

    def dynamic_mapping_changed?(proposed_mappings, current_mappings)
      proposed_dynamic = proposed_mappings['dynamic']
      current_dynamic = current_mappings['dynamic']

      return false unless proposed_dynamic && current_dynamic

      proposed_dynamic != current_dynamic
    end

    def field_type_changed?(proposed_mappings, current_mappings)
      return false unless proposed_mappings['properties'] && current_mappings['properties']

      proposed_props = proposed_mappings['properties']
      current_props = current_mappings['properties']

      (proposed_props.keys & current_props.keys).any? do |field|
        proposed_type = proposed_props.dig(field, 'type')
        current_type = current_props.dig(field, 'type')

        next false unless proposed_type && current_type

        proposed_type != current_type
      end
    end

    def field_analyzer_changed?(proposed_mappings, current_mappings)
      return false unless proposed_mappings['properties'] && current_mappings['properties']

      proposed_props = proposed_mappings['properties']
      current_props = current_mappings['properties']

      (proposed_props.keys & current_props.keys).any? do |field|
        proposed_analyzer = proposed_props.dig(field, 'analyzer')
        current_analyzer = current_props.dig(field, 'analyzer')

        next false unless proposed_analyzer && current_analyzer

        proposed_analyzer != current_analyzer
      end
    end

    def immutable_field_properties_changed?(proposed_mappings, current_mappings)
      return false unless proposed_mappings['properties'] && current_mappings['properties']

      proposed_props = proposed_mappings['properties']
      current_props = current_mappings['properties']

      (proposed_props.keys & current_props.keys).any? do |field|
        proposed_field = proposed_props[field] || {}
        current_field = current_props[field] || {}

        immutable_properties = [
          'index', 'store', 'doc_values', 'fielddata', 'norms',
          'enabled', 'format', 'copy_to', 'term_vector', 'index_options',
          'null_value', 'ignore_z_value', 'precision', 'ignore_above'
        ]

        immutable_properties.any? do |property|
          proposed_value = proposed_field[property]
          current_value = current_field[property]

          next false unless proposed_value || current_value

          return true if proposed_value.nil? || current_value.nil?

          proposed_value != current_value
        end
      end
    end

    def mutable_field_properties_changed?(proposed_mappings, current_mappings)
      return false unless proposed_mappings['properties'] && current_mappings['properties']

      proposed_props = proposed_mappings['properties']
      current_props = current_mappings['properties']

      (proposed_props.keys & current_props.keys).any? do |field|
        proposed_field = proposed_props[field] || {}
        current_field = current_props[field] || {}

        mutable_properties = [
          'boost', 'search_analyzer', 'search_quote_analyzer', 'ignore_malformed'
        ]

        mutable_properties.any? do |property|
          proposed_value = proposed_field[property]
          current_value = current_field[property]

          next false unless proposed_value || current_value

          return false if proposed_value.nil? || current_value.nil?

          proposed_value != current_value
        end
      end
    end

    def field_existence_changed?(proposed_mappings, current_mappings)
      return false unless proposed_mappings['properties'] && current_mappings['properties']

      proposed_props = proposed_mappings['properties']
      current_props = current_mappings['properties']

      removed_fields = current_props.keys - proposed_props.keys
      removed_fields.any?
    end

    def multi_field_definitions_changed?(proposed_mappings, current_mappings)
      return false unless proposed_mappings['properties'] && current_mappings['properties']

      proposed_props = proposed_mappings['properties']
      current_props = current_mappings['properties']

      (proposed_props.keys & current_props.keys).any? do |field|
        proposed_field = proposed_props[field] || {}
        current_field = current_props[field] || {}

        proposed_fields = proposed_field['fields'] || {}
        current_fields = current_field['fields'] || {}

        existing_subfields_changed = (proposed_fields.keys & current_fields.keys).any? do |subfield_name|
          proposed_subfield = proposed_fields[subfield_name] || {}
          current_subfield = current_fields[subfield_name] || {}

          proposed_subfield != current_subfield
        end

        removed_subfields = current_fields.keys - proposed_fields.keys
        removed_subfields_exist = removed_subfields.any?

        existing_subfields_changed || removed_subfields_exist
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