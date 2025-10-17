require_relative '../spec_helper'
require 'schema_tools/diff'

RSpec.describe SchemaTools::Diff do
  describe '.normalize_local_settings' do
    context 'when normalizing string values to proper types' do
      it 'converts string numbers to integers' do
        local_settings = {
          "number_of_replicas" => "1",
          "number_of_shards" => "3"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 1,
            "number_of_shards" => 3
          }
        })
      end

      it 'converts string floats to floats' do
        local_settings = {
          "scaling_factor" => "100.0",
          "boost" => "1.5"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "scaling_factor" => 100.0,
            "boost" => 1.5
          }
        })
      end

      it 'converts string booleans to booleans' do
        local_settings = {
          "enabled" => "true",
          "coerce" => "false"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "enabled" => true,
            "coerce" => false
          }
        })
      end

      it 'converts boolean aliases to numeric values' do
        local_settings = {
          "coerce" => "1",
          "enabled" => "0"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "coerce" => 1,
            "enabled" => 0
          }
        })
      end

      it 'handles mixed string and non-string values' do
        local_settings = {
          "number_of_replicas" => "1",
          "refresh_interval" => "5s",
          "enabled" => "true",
          "max_result_window" => 10000
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 1,
            "refresh_interval" => "5s",  # Non-numeric string kept as-is
            "enabled" => true,
            "max_result_window" => 10000
          }
        })
      end

      it 'handles nested hash structures' do
        local_settings = {
          "index" => {
            "number_of_replicas" => "1",
            "analysis" => {
              "analyzer" => {
                "custom" => {
                  "enabled" => "true",
                  "boost" => "1.5"
                }
              }
            }
          }
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 1,
            "analysis" => {
              "analyzer" => {
                "custom" => {
                  "enabled" => true,
                  "boost" => 1.5
                }
              }
            }
          }
        })
      end

      it 'handles array values with string conversions' do
        local_settings = {
          "index" => {
            "settings" => ["1", "2", "3"],
            "flags" => ["true", "false", "0"]
          }
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "settings" => [1, 2, 3],
            "flags" => [true, false, 0]
          }
        })
      end

      it 'preserves existing index wrapper structure' do
        local_settings = {
          "index" => {
            "number_of_replicas" => "1",
            "enabled" => "true"
          }
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 1,
            "enabled" => true
          }
        })
      end

      it 'handles empty settings' do
        local_settings = {}
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({})
      end

      it 'handles nil input' do
        result = SchemaTools::Diff.send(:normalize_local_settings, nil)
        
        expect(result).to be_nil
      end

      it 'handles non-hash input' do
        result = SchemaTools::Diff.send(:normalize_local_settings, "not a hash")
        
        expect(result).to eq("not a hash")
      end
    end

    context 'when handling edge cases' do
      it 'converts negative numbers correctly' do
        local_settings = {
          "offset" => "-1",
          "factor" => "-2.5"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "offset" => -1,
            "factor" => -2.5
          }
        })
      end

      it 'handles zero values correctly' do
        local_settings = {
          "count" => "0",
          "rate" => "0.0"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "count" => 0,
            "rate" => 0.0
          }
        })
      end

      it 'preserves non-numeric strings' do
        local_settings = {
          "analyzer" => "standard",
          "refresh_interval" => "5s",
          "timeout" => "30s"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "analyzer" => "standard",
            "refresh_interval" => "5s",
            "timeout" => "30s"
          }
        })
      end

      it 'handles case-insensitive boolean conversion' do
        local_settings = {
          "enabled" => "TRUE",
          "coerce" => "FALSE",
          "dynamic" => "True"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "enabled" => true,
            "coerce" => false,
            "dynamic" => true
          }
        })
      end

      it 'handles the specific gotcha examples from the user' do
        # String-to-Number: "index.number_of_replicas": "1" -> "index.number_of_replicas": 1
        local_settings = {
          "number_of_replicas" => "1"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 1
          }
        })
      end

      it 'handles string-to-boolean gotcha example' do
        # String-to-Boolean: "enabled": "true" -> "enabled": true
        local_settings = {
          "enabled" => "true"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "enabled" => true
          }
        })
      end

      it 'handles boolean aliases gotcha example' do
        # Boolean Aliases: "coerce": "1" -> "coerce": true (but we default to numeric 1 for settings)
        local_settings = {
          "coerce" => "1"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "coerce" => 1
          }
        })
      end

      it 'handles numeric strings gotcha example' do
        # Numeric Strings: "scaling_factor": "100.0" -> "scaling_factor": 100.0
        local_settings = {
          "scaling_factor" => "100.0"
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "scaling_factor" => 100.0
          }
        })
      end

      it 'handles complex nested structures with mixed types' do
        local_settings = {
          "index" => {
            "number_of_replicas" => "1",
            "analysis" => {
              "analyzer" => {
                "custom" => {
                  "enabled" => "true",
                  "boost" => "1.5",
                  "coerce" => "0",
                  "name" => "custom-analyzer"
                }
              },
              "filter" => {
                "stop" => {
                  "enabled" => "false",
                  "words" => ["1", "2", "3"],
                  "ignore_case" => "true"
                }
              }
            }
          }
        }
        
        result = SchemaTools::Diff.send(:normalize_local_settings, local_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 1,
            "analysis" => {
              "analyzer" => {
                "custom" => {
                  "enabled" => true,
                  "boost" => 1.5,
                  "coerce" => 0,
                  "name" => "custom-analyzer"
                }
              },
              "filter" => {
                "stop" => {
                  "enabled" => false,
                  "words" => [1, 2, 3],
                  "ignore_case" => true
                }
              }
            }
          }
        })
      end
    end
  end

  describe '.normalize_remote_settings' do
    context 'when normalizing remote settings from ES API' do
      it 'converts string values to proper types' do
        remote_settings = {
          "index" => {
            "number_of_replicas" => "0",
            "number_of_shards" => "1",
            "enabled" => "true"
          }
        }
        
        result = SchemaTools::Diff.send(:normalize_remote_settings, remote_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 0,
            "number_of_shards" => 1,
            "enabled" => true
          }
        })
      end

      it 'handles settings without index wrapper' do
        remote_settings = {
          "number_of_replicas" => "0",
          "number_of_shards" => "1"
        }
        
        result = SchemaTools::Diff.send(:normalize_remote_settings, remote_settings)
        
        expect(result).to eq({
          "index" => {
            "number_of_replicas" => 0,
            "number_of_shards" => 1
          }
        })
      end

      it 'handles nested structures' do
        remote_settings = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "custom" => {
                  "enabled" => "true",
                  "boost" => "1.5"
                }
              }
            }
          }
        }
        
        result = SchemaTools::Diff.send(:normalize_remote_settings, remote_settings)
        
        expect(result).to eq({
          "index" => {
            "analysis" => {
              "analyzer" => {
                "custom" => {
                  "enabled" => true,
                  "boost" => 1.5
                }
              }
            }
          }
        })
      end

      it 'handles empty settings' do
        remote_settings = {}
        
        result = SchemaTools::Diff.send(:normalize_remote_settings, remote_settings)
        
        expect(result).to eq({ "index" => {} })
      end

      it 'handles nil input' do
        result = SchemaTools::Diff.send(:normalize_remote_settings, nil)
        
        expect(result).to be_nil
      end
    end
  end

  describe '.normalize_string_value' do
    it 'converts "true" to boolean true' do
      expect(SchemaTools::Diff.send(:normalize_string_value, "true")).to eq(true)
      expect(SchemaTools::Diff.send(:normalize_string_value, "TRUE")).to eq(true)
      expect(SchemaTools::Diff.send(:normalize_string_value, "True")).to eq(true)
    end

    it 'converts "false" to boolean false' do
      expect(SchemaTools::Diff.send(:normalize_string_value, "false")).to eq(false)
      expect(SchemaTools::Diff.send(:normalize_string_value, "FALSE")).to eq(false)
      expect(SchemaTools::Diff.send(:normalize_string_value, "False")).to eq(false)
    end

    it 'converts "1" to integer 1' do
      expect(SchemaTools::Diff.send(:normalize_string_value, "1")).to eq(1)
    end

    it 'converts "0" to integer 0' do
      expect(SchemaTools::Diff.send(:normalize_string_value, "0")).to eq(0)
    end

    it 'converts integer strings to integers' do
      expect(SchemaTools::Diff.send(:normalize_string_value, "123")).to eq(123)
      expect(SchemaTools::Diff.send(:normalize_string_value, "-456")).to eq(-456)
    end

    it 'converts float strings to floats' do
      expect(SchemaTools::Diff.send(:normalize_string_value, "123.45")).to eq(123.45)
      expect(SchemaTools::Diff.send(:normalize_string_value, "-67.89")).to eq(-67.89)
      expect(SchemaTools::Diff.send(:normalize_string_value, "0.0")).to eq(0.0)
    end

    it 'preserves non-numeric strings' do
      expect(SchemaTools::Diff.send(:normalize_string_value, "standard")).to eq("standard")
      expect(SchemaTools::Diff.send(:normalize_string_value, "5s")).to eq("5s")
      expect(SchemaTools::Diff.send(:normalize_string_value, "custom-analyzer")).to eq("custom-analyzer")
    end
  end

  describe '.normalize_values' do
    it 'recursively normalizes hash values' do
      obj = {
        "level1" => {
          "level2" => {
            "enabled" => "true",
            "count" => "5"
          }
        }
      }
      
      result = SchemaTools::Diff.send(:normalize_values, obj)
      
      expect(result).to eq({
        "level1" => {
          "level2" => {
            "enabled" => true,
            "count" => 5
          }
        }
      })
    end

    it 'normalizes array values' do
      obj = ["1", "true", "2.5", "false"]
      
      result = SchemaTools::Diff.send(:normalize_values, obj)
      
      expect(result).to eq([1, true, 2.5, false])
    end

    it 'handles mixed arrays' do
      obj = ["1", "text", "true", 42]
      
      result = SchemaTools::Diff.send(:normalize_values, obj)
      
      expect(result).to eq([1, "text", true, 42])
    end

    it 'preserves non-string values' do
      obj = {
        "number" => 42,
        "boolean" => true,
        "string" => "text"
      }
      
      result = SchemaTools::Diff.send(:normalize_values, obj)
      
      expect(result).to eq({
        "number" => 42,
        "boolean" => true,
        "string" => "text"
      })
    end
  end

  describe '.check_replica_count_difference' do
    context 'when replica counts differ' do
      it 'returns warning message when local has more replicas' do
        remote_settings = { "index" => { "number_of_replicas" => 0 } }
        local_settings = { "index" => { "number_of_replicas" => 2 } }

        result = SchemaTools::Diff.send(:check_replica_count_difference, remote_settings, local_settings)
        
        expect(result).to eq("WARNING: The specified number of replicas 2 in the schema could not be applied to the cluster, likely because the cluster isn't running enough nodes.")
      end

      it 'returns warning message when remote has more replicas' do
        remote_settings = { "index" => { "number_of_replicas" => 3 } }
        local_settings = { "index" => { "number_of_replicas" => 1 } }

        result = SchemaTools::Diff.send(:check_replica_count_difference, remote_settings, local_settings)
        
        expect(result).to eq("WARNING: The specified number of replicas 1 in the schema could not be applied to the cluster, likely because the cluster isn't running enough nodes.")
      end

      it 'handles settings without index wrapper' do
        remote_settings = { "number_of_replicas" => 0 }
        local_settings = { "number_of_replicas" => 2 }

        result = SchemaTools::Diff.send(:check_replica_count_difference, remote_settings, local_settings)
        
        expect(result).to eq("WARNING: The specified number of replicas 2 in the schema could not be applied to the cluster, likely because the cluster isn't running enough nodes.")
      end
    end

    context 'when replica counts are the same' do
      it 'returns nil when counts match' do
        remote_settings = { "index" => { "number_of_replicas" => 1 } }
        local_settings = { "index" => { "number_of_replicas" => 1 } }

        result = SchemaTools::Diff.send(:check_replica_count_difference, remote_settings, local_settings)
        
        expect(result).to be_nil
      end

      it 'returns nil when both are nil' do
        remote_settings = { "index" => {} }
        local_settings = { "index" => {} }

        result = SchemaTools::Diff.send(:check_replica_count_difference, remote_settings, local_settings)
        
        expect(result).to be_nil
      end

      it 'returns nil when one is nil' do
        remote_settings = { "index" => { "number_of_replicas" => 1 } }
        local_settings = { "index" => {} }

        result = SchemaTools::Diff.send(:check_replica_count_difference, remote_settings, local_settings)
        
        expect(result).to be_nil
      end
    end

    context 'when settings are invalid' do
      it 'returns nil for non-hash input' do
        result = SchemaTools::Diff.send(:check_replica_count_difference, "not a hash", {})
        expect(result).to be_nil
      end

      it 'returns nil for nil input' do
        result = SchemaTools::Diff.send(:check_replica_count_difference, nil, {})
        expect(result).to be_nil
      end
    end
  end

  describe '.get_replica_count' do
    it 'extracts replica count from index wrapper' do
      settings = { "index" => { "number_of_replicas" => 2 } }
      result = SchemaTools::Diff.send(:get_replica_count, settings)
      expect(result).to eq(2)
    end

    it 'extracts replica count without index wrapper' do
      settings = { "number_of_replicas" => 1 }
      result = SchemaTools::Diff.send(:get_replica_count, settings)
      expect(result).to eq(1)
    end

    it 'returns nil when replica count not found' do
      settings = { "index" => { "other_setting" => "value" } }
      result = SchemaTools::Diff.send(:get_replica_count, settings)
      expect(result).to be_nil
    end

    it 'returns nil for non-hash input' do
      result = SchemaTools::Diff.send(:get_replica_count, "not a hash")
      expect(result).to be_nil
    end
  end

  describe '.generate_schema_diff' do
    let(:mock_client) { double('Client') }
    let(:alias_name) { 'test-alias' }
    let(:index_name) { 'test-index-123' }

    before do
      allow(mock_client).to receive(:alias_exists?).with(alias_name).and_return(true)
      allow(mock_client).to receive(:get_alias_indices).with(alias_name).and_return([index_name])
      allow(mock_client).to receive(:get_index_settings).with(index_name).and_return(remote_settings)
      allow(mock_client).to receive(:get_index_mappings).with(index_name).and_return(remote_mappings)
      allow(SchemaTools::SchemaFiles).to receive(:get_settings).with(alias_name).and_return(local_settings)
      allow(SchemaTools::SchemaFiles).to receive(:get_mappings).with(alias_name).and_return(local_mappings)
      allow(SchemaTools::SettingsFilter).to receive(:filter_internal_settings).and_return(remote_settings)
    end

    context 'when only replica count differs' do
      let(:remote_settings) do
        {
          "index" => {
            "number_of_replicas" => 0,
            "number_of_shards" => 1,
            "refresh_interval" => "5s"
          }
        }
      end

      let(:local_settings) do
        {
          "index" => {
            "number_of_replicas" => 2,
            "number_of_shards" => 1,
            "refresh_interval" => "5s"
          }
        }
      end

      let(:remote_mappings) { { "properties" => { "field1" => { "type" => "text" } } } }
      let(:local_mappings) { { "properties" => { "field1" => { "type" => "text" } } } }

      it 'returns no_changes status with replica warning' do
        result = SchemaTools::Diff.generate_schema_diff(alias_name, mock_client)

        expect(result[:status]).to eq(:no_changes)
        expect(result[:replica_warning]).to eq("WARNING: The specified number of replicas 2 in the schema could not be applied to the cluster, likely because the cluster isn't running enough nodes.")
        expect(result[:settings_diff]).to eq("No changes detected")
        expect(result[:mappings_diff]).to eq("No changes detected")
      end
    end

    context 'when replica count differs but other settings also differ' do
      let(:remote_settings) do
        {
          "index" => {
            "number_of_replicas" => 0,
            "number_of_shards" => 1,
            "refresh_interval" => "1s"
          }
        }
      end

      let(:local_settings) do
        {
          "index" => {
            "number_of_replicas" => 2,
            "number_of_shards" => 1,
            "refresh_interval" => "5s"
          }
        }
      end

      let(:remote_mappings) { { "properties" => { "field1" => { "type" => "text" } } } }
      let(:local_mappings) { { "properties" => { "field1" => { "type" => "text" } } } }

      it 'returns changes_detected status' do
        result = SchemaTools::Diff.generate_schema_diff(alias_name, mock_client)

        expect(result[:status]).to eq(:changes_detected)
        expect(result[:replica_warning]).to be_nil
        expect(result[:settings_diff]).to include("Changes Detected")
        expect(result[:settings_diff]).to include("MODIFIED: index.refresh_interval")
        expect(result[:settings_diff]).not_to include("number_of_replicas")
      end
    end

    context 'when replica counts match' do
      let(:remote_settings) do
        {
          "index" => {
            "number_of_replicas" => 1,
            "number_of_shards" => 1,
            "refresh_interval" => "5s"
          }
        }
      end

      let(:local_settings) do
        {
          "index" => {
            "number_of_replicas" => 1,
            "number_of_shards" => 1,
            "refresh_interval" => "5s"
          }
        }
      end

      let(:remote_mappings) { { "properties" => { "field1" => { "type" => "text" } } } }
      let(:local_mappings) { { "properties" => { "field1" => { "type" => "text" } } } }

      it 'returns no_changes status without warning' do
        result = SchemaTools::Diff.generate_schema_diff(alias_name, mock_client)

        expect(result[:status]).to eq(:no_changes)
        expect(result[:replica_warning]).to be_nil
        expect(result[:settings_diff]).to eq("No changes detected")
        expect(result[:mappings_diff]).to eq("No changes detected")
      end
    end
  end
end