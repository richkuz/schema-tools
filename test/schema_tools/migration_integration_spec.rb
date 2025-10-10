require_relative '../spec_helper'
require 'schema_tools/migrate/migrate'
require 'schema_tools/settings_diff'
require 'schema_tools/api_aware_mappings_diff'
require 'schema_tools/settings_filter'
require 'schema_tools/config'
require 'json'
require 'fileutils'
require 'tempfile'

RSpec.describe 'Migration Integration Test' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:alias_name) { 'integration-test-alias' }
  let(:schema_path) { File.join(schemas_path, alias_name) }
  
  # Mock client that simulates OpenSearch/Elasticsearch behavior
  let(:mock_client) do
    double('Client').tap do |client|
      allow(client).to receive(:test_connection).and_return(true)
      allow(client).to receive(:alias_exists?).with(alias_name).and_return(true)
      allow(client).to receive(:get_alias_indices).with(alias_name).and_return(['test-index-123'])
      allow(client).to receive(:index_exists?).with('test-index-123').and_return(true)
      allow(client).to receive(:index_exists?).and_return(true) # Handle any other index names
      
      # Mock settings and mappings to return updated values after updates
      settings_updated = false
      mappings_updated = false
      
      # Normalize the settings to match what ES would return (canonical types)
      normalized_remote_settings = normalize_settings_for_es(remote_settings)
      normalized_new_settings = normalize_settings_for_es(new_settings)
      
      allow(client).to receive(:get_index_settings).with('test-index-123') do
        settings_updated ? normalized_new_settings : normalized_remote_settings
      end
      
      allow(client).to receive(:get_index_mappings).with('test-index-123') do
        mappings_updated ? new_mappings : remote_mappings
      end
      
      allow(client).to receive(:update_index_settings) do |index_name, settings|
        settings_updated = true
        { 'acknowledged' => true }
      end
      
      allow(client).to receive(:update_index_mappings) do |index_name, mappings|
        mappings_updated = true
        { 'acknowledged' => true }
      end
      
      # Mock methods that might be called during breaking change migration
      allow(client).to receive(:post).and_return({ 'acknowledged' => true })
      allow(client).to receive(:create_index).and_return({ 'acknowledged' => true })
      allow(client).to receive(:reindex).and_return({ 'took' => 100 })
      allow(client).to receive(:update_aliases).and_return({ 'acknowledged' => true })
      allow(client).to receive(:close_index).and_return({ 'acknowledged' => true })
      allow(client).to receive(:wait_for_task).and_return(true)
    end
  end

  # Comprehensive initial settings (what's currently in the cluster)
  let(:remote_settings) do
    {
      "index" => {
        "number_of_shards" => "3",
        "number_of_replicas" => "1",
        "refresh_interval" => "30s",
        "max_result_window" => "10000",
        "max_inner_result_window" => "1000",
        "max_ngram_diff" => "50",
        "knn" => "false",
        "analysis" => {
          "analyzer" => {
            "standard" => {
              "type" => "standard"
            },
            "keyword" => {
              "type" => "keyword"
            },
            "simple_analyzer" => {
              "type" => "custom",
              "tokenizer" => "keyword",
              "filter" => ["lowercase"]
            },
            "text_analyzer" => {
              "type" => "custom",
              "tokenizer" => "standard",
              "filter" => ["lowercase", "stop", "stemmer"]
            }
          },
          "filter" => {
            "stemmer" => {
              "type" => "stemmer",
              "language" => "english"
            },
            "stop" => {
              "type" => "stop",
              "stopwords" => ["_english_"]
            }
          },
          "tokenizer" => {
            "ngram_tokenizer" => {
              "type" => "ngram",
              "min_gram" => "2",
              "max_gram" => "10",
              "token_chars" => ["letter", "digit"]
            }
          }
        },
        "similarity" => {
          "default" => {
            "type" => "BM25",
            "k1" => "1.2",
            "b" => "0.75"
          }
        }
      }
    }
  end

  # Comprehensive initial mappings (what's currently in the cluster)
  let(:remote_mappings) do
    {
      "dynamic" => "true",
      "properties" => {
        "id" => {
          "type" => "keyword"
        },
        "title" => {
          "type" => "text",
          "analyzer" => "text_analyzer",
          "fields" => {
            "keyword" => {
              "type" => "keyword",
              "ignore_above" => 256
            },
            "suggest" => {
              "type" => "completion"
            }
          }
        },
        "description" => {
          "type" => "text",
          "analyzer" => "text_analyzer"
        },
        "price" => {
          "type" => "double"
        },
        "category" => {
          "type" => "keyword"
        },
        "tags" => {
          "type" => "keyword"
        },
        "created_at" => {
          "type" => "date",
          "format" => "strict_date_optional_time||epoch_millis"
        },
        "metadata" => {
          "type" => "object",
          "properties" => {
            "source" => {
              "type" => "keyword"
            },
            "version" => {
              "type" => "integer"
            }
          }
        },
        "location" => {
          "type" => "geo_point"
        },
        "nested_items" => {
          "type" => "nested",
          "properties" => {
            "name" => {
              "type" => "text",
              "analyzer" => "simple_analyzer"
            },
            "value" => {
              "type" => "float"
            }
          }
        }
      }
    }
  end

  # New comprehensive settings (what we want to achieve)
  let(:new_settings) do
    {
      "index" => {
        "number_of_shards" => "5",  # Changed from 3 to 5
        "number_of_replicas" => "2", # Changed from 1 to 2
        "refresh_interval" => "30s", # Same
        "max_result_window" => "50000", # Changed from 10000 to 50000
        "max_inner_result_window" => "5000", # Changed from 1000 to 5000
        "max_ngram_diff" => "100", # Changed from 50 to 100
        "knn" => "true", # Changed from false to true
        "analysis" => {
          "analyzer" => {
            "standard" => {
              "type" => "standard"
            },
            "keyword" => {
              "type" => "keyword"
            },
            "simple_analyzer" => {
              "type" => "custom",
              "tokenizer" => "keyword",
              "filter" => ["lowercase"]
            },
            "text_analyzer" => {
              "type" => "custom",
              "tokenizer" => "standard",
              "filter" => ["lowercase", "stop", "stemmer", "trim"] # Added trim filter
            },
            "advanced_analyzer" => { # New analyzer
              "type" => "custom",
              "tokenizer" => "ngram_tokenizer",
              "filter" => ["lowercase", "stop"]
            }
          },
          "filter" => {
            "stemmer" => {
              "type" => "stemmer",
              "language" => "english"
            },
            "stop" => {
              "type" => "stop",
              "stopwords" => ["_english_"]
            },
            "trim" => { # New filter
              "type" => "trim"
            }
          },
          "tokenizer" => {
            "ngram_tokenizer" => {
              "type" => "ngram",
              "min_gram" => "3", # Changed from 2 to 3
              "max_gram" => "15", # Changed from 10 to 15
              "token_chars" => ["letter", "digit"]
            }
          }
        },
        "similarity" => {
          "default" => {
            "type" => "BM25",
            "k1" => "1.5", # Changed from 1.2 to 1.5
            "b" => "0.8" # Changed from 0.75 to 0.8
          },
          "custom_similarity" => { # New similarity
            "type" => "BM25",
            "k1" => "2.0",
            "b" => "0.0"
          }
        }
      }
    }
  end

  # New comprehensive mappings (what we want to achieve)
  let(:new_mappings) do
    {
      "dynamic" => "strict", # Changed from true to strict
      "properties" => {
        "id" => {
          "type" => "keyword"
        },
        "title" => {
          "type" => "text",
          "analyzer" => "advanced_analyzer", # Changed analyzer
          "fields" => {
            "keyword" => {
              "type" => "keyword",
              "ignore_above" => 512 # Changed from 256 to 512
            },
            "suggest" => {
              "type" => "completion"
            },
            "ngram" => { # New field
              "type" => "text",
              "analyzer" => "advanced_analyzer"
            }
          }
        },
        "description" => {
          "type" => "text",
          "analyzer" => "advanced_analyzer" # Changed analyzer
        },
        "price" => {
          "type" => "double"
        },
        "category" => {
          "type" => "keyword"
        },
        "tags" => {
          "type" => "keyword"
        },
        "created_at" => {
          "type" => "date",
          "format" => "strict_date_optional_time||epoch_millis"
        },
        "updated_at" => { # New field
          "type" => "date",
          "format" => "strict_date_optional_time||epoch_millis"
        },
        "metadata" => {
          "type" => "object",
          "properties" => {
            "source" => {
              "type" => "keyword"
            },
            "version" => {
              "type" => "integer"
            },
            "priority" => { # New nested field
              "type" => "integer"
            }
          }
        },
        "location" => {
          "type" => "geo_point"
        },
        "nested_items" => {
          "type" => "nested",
          "properties" => {
            "name" => {
              "type" => "text",
              "analyzer" => "advanced_analyzer" # Changed analyzer
            },
            "value" => {
              "type" => "float"
            },
            "description" => { # New nested field
              "type" => "text",
              "analyzer" => "simple_analyzer"
            }
          }
        },
        "search_vector" => { # New top-level field
          "type" => "dense_vector",
          "dims" => 128
        }
      }
    }
  end

  before do
    # Set up temporary schema directory
    FileUtils.mkdir_p(schema_path)
    
    # Write new settings and mappings files
    File.write(File.join(schema_path, 'settings.json'), JSON.pretty_generate(new_settings))
    File.write(File.join(schema_path, 'mappings.json'), JSON.pretty_generate(new_mappings))
    
    # Mock the config to use our temp directory
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(schemas_path)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'comprehensive migration with significant non-breaking changes' do
    it 'calculates and applies only the minimal necessary changes' do
      # Capture the output
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      begin
        # Run the migration
        SchemaTools.migrate_one_schema(alias_name: alias_name, client: mock_client)
      ensure
        $stdout = original_stdout
      end

      migration_output = output.string

      # Verify that the migration was attempted
      expect(migration_output).to include("Attempting to update index 'test-index-123' in place with new schema as a non-breaking change...")

      # Verify that minimal settings changes were calculated and applied
      expect(migration_output).to include("Applying minimal settings changes:")
      expect(migration_output).to include("✓ Settings updated successfully")

      # Verify that minimal mappings changes were calculated and applied
      expect(migration_output).to include("Applying minimal mappings changes:")
      expect(migration_output).to include("✓ Mappings updated successfully")

      # Verify that the migration completed successfully
      expect(migration_output).to include("✓ Index 'test-index-123' updated successfully")
      expect(migration_output).to include("Migration completed successfully!")

      # Test the SettingsDiff directly to verify it calculates correct minimal changes
      filtered_remote_settings = SchemaTools::SettingsFilter.filter_internal_settings(remote_settings)
      settings_diff = SchemaTools::SettingsDiff.new(new_settings, filtered_remote_settings)
      minimal_settings_changes = settings_diff.generate_minimal_changes

      # Verify that only changed settings are included
      expect(minimal_settings_changes).to include("index")
      expect(minimal_settings_changes["index"]).to include("number_of_shards" => 5)
      expect(minimal_settings_changes["index"]).to include("number_of_replicas" => 2)
      expect(minimal_settings_changes["index"]).to include("max_result_window" => 50000)
      expect(minimal_settings_changes["index"]).to include("max_inner_result_window" => 5000)
      expect(minimal_settings_changes["index"]).to include("max_ngram_diff" => 100)
      expect(minimal_settings_changes["index"]).to include("knn" => true)

      # Verify that unchanged settings are not included
      expect(minimal_settings_changes["index"]).not_to include("refresh_interval")

      # Verify nested changes are minimal
      expect(minimal_settings_changes["index"]["analysis"]["analyzer"]["text_analyzer"]).to eq({
        "filter" => ["lowercase", "stop", "stemmer", "trim"]
      })
      expect(minimal_settings_changes["index"]["analysis"]["analyzer"]).to include("advanced_analyzer")

      # Test the MappingsDiff directly to verify it calculates correct minimal changes
      mappings_diff = SchemaTools::ApiAwareMappingsDiff.new(new_mappings, remote_mappings)
      minimal_mappings_changes = mappings_diff.generate_minimal_changes

      # Verify that only changed mappings are included
      expect(minimal_mappings_changes).to include("dynamic" => "strict")
      expect(minimal_mappings_changes).to include("properties")

      # Verify that changed properties are included
      expect(minimal_mappings_changes["properties"]["title"]).to include("analyzer" => "advanced_analyzer")
      expect(minimal_mappings_changes["properties"]["title"]["fields"]["keyword"]).to include("ignore_above" => 512)
      expect(minimal_mappings_changes["properties"]["title"]["fields"]).to include("ngram")

      # Verify that unchanged properties are not included
      expect(minimal_mappings_changes["properties"]).not_to include("price")
      expect(minimal_mappings_changes["properties"]).not_to include("category")

      # Verify that new properties are included
      expect(minimal_mappings_changes["properties"]).to include("updated_at")
      expect(minimal_mappings_changes["properties"]).to include("search_vector")

      # Verify nested changes are minimal
      expect(minimal_mappings_changes["properties"]["metadata"]["properties"]).to include("priority")
      expect(minimal_mappings_changes["properties"]["nested_items"]["properties"]).to include("description")
    end

    it 'handles the case where no changes are needed' do
      # Create identical settings and mappings
      File.write(File.join(schema_path, 'settings.json'), JSON.pretty_generate(remote_settings))
      File.write(File.join(schema_path, 'mappings.json'), JSON.pretty_generate(remote_mappings))

      # Capture the output
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      begin
        # Run the migration
        SchemaTools.migrate_one_schema(alias_name: alias_name, client: mock_client)
      ensure
        $stdout = original_stdout
      end

      migration_output = output.string

      # Verify that no changes were needed
      expect(migration_output).to include("✓ No differences detected between local schema and live alias")
      expect(migration_output).to include("✓ Migration skipped - index is already up to date")
      expect(migration_output).not_to include("Migration completed successfully!")
    end
  end

  # Helper method to normalize settings to match ES canonical format
  def normalize_settings_for_es(settings)
    return settings unless settings.is_a?(Hash)
    
    normalized = {}
    settings.each do |key, value|
      if value.is_a?(Hash)
        normalized[key] = normalize_settings_for_es(value)
      elsif value.is_a?(String)
        # Convert string values to their proper types (same logic as Diff.normalize_string_value)
        case value.downcase
        when "true"
          normalized[key] = true
        when "false"
          normalized[key] = false
        when "1"
          normalized[key] = 1
        when "0"
          normalized[key] = 0
        else
          if value.match?(/\A-?\d+\z/)
            normalized[key] = value.to_i
          elsif value.match?(/\A-?\d*\.\d+\z/)
            normalized[key] = value.to_f
          else
            normalized[key] = value
          end
        end
      else
        normalized[key] = value
      end
    end
    
    normalized
  end
end