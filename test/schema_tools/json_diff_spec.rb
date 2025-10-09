require_relative '../spec_helper'
require 'schema_tools/json_diff'

RSpec.describe SchemaTools::JsonDiff do
  let(:json_diff) { SchemaTools::JsonDiff.new }

  describe '#generate_diff' do
    context 'when comparing mappings with implicit object types' do
      it 'treats explicit and implicit object types as equivalent' do
        local_mappings = {
          "properties" => {
            "metadata" => {
              "type" => "object",
              "dynamic" => "strict",
              "properties" => {
                "priority" => { "type" => "integer" },
                "source" => { "type" => "keyword" }
              }
            }
          }
        }

        remote_mappings = {
          "properties" => {
            "metadata" => {
              "dynamic" => "strict",
              "properties" => {
                "priority" => { "type" => "integer" },
                "source" => { "type" => "keyword" }
              }
            }
          }
        }

        result = json_diff.generate_diff(remote_mappings, local_mappings)
        expect(result).to eq("No changes detected")
      end

      it 'detects actual differences in object fields' do
        local_mappings = {
          "properties" => {
            "metadata" => {
              "type" => "object",
              "dynamic" => "strict",
              "properties" => {
                "priority" => { "type" => "integer" },
                "source" => { "type" => "keyword" }
              }
            }
          }
        }

        remote_mappings = {
          "properties" => {
            "metadata" => {
              "dynamic" => "false",
              "properties" => {
                "priority" => { "type" => "integer" },
                "source" => { "type" => "keyword" }
              }
            }
          }
        }

        result = json_diff.generate_diff(remote_mappings, local_mappings)
        expect(result).to include("Changes Detected")
        expect(result).to include("MODIFIED: properties.metadata.dynamic")
      end

      it 'handles nested object fields correctly' do
        local_mappings = {
          "properties" => {
            "user" => {
              "type" => "object",
              "properties" => {
                "profile" => {
                  "type" => "object",
                  "properties" => {
                    "name" => { "type" => "text" }
                  }
                }
              }
            }
          }
        }

        remote_mappings = {
          "properties" => {
            "user" => {
              "properties" => {
                "profile" => {
                  "properties" => {
                    "name" => { "type" => "text" }
                  }
                }
              }
            }
          }
        }

        result = json_diff.generate_diff(remote_mappings, local_mappings)
        expect(result).to eq("No changes detected")
      end

      it 'handles mixed explicit and implicit object types' do
        local_mappings = {
          "properties" => {
            "explicit_object" => {
              "type" => "object",
              "properties" => {
                "field1" => { "type" => "text" }
              }
            },
            "implicit_object" => {
              "properties" => {
                "field2" => { "type" => "keyword" }
              }
            }
          }
        }

        remote_mappings = {
          "properties" => {
            "explicit_object" => {
              "properties" => {
                "field1" => { "type" => "text" }
              }
            },
            "implicit_object" => {
              "type" => "object",
              "properties" => {
                "field2" => { "type" => "keyword" }
              }
            }
          }
        }

        result = json_diff.generate_diff(remote_mappings, local_mappings)
        expect(result).to eq("No changes detected")
      end

      it 'does not affect non-object fields' do
        local_mappings = {
          "properties" => {
            "text_field" => {
              "type" => "text",
              "analyzer" => "standard"
            },
            "keyword_field" => {
              "type" => "keyword"
            }
          }
        }

        remote_mappings = {
          "properties" => {
            "text_field" => {
              "type" => "text",
              "analyzer" => "standard"
            },
            "keyword_field" => {
              "type" => "keyword"
            }
          }
        }

        result = json_diff.generate_diff(remote_mappings, local_mappings)
        expect(result).to eq("No changes detected")
      end

      it 'detects changes in non-object fields' do
        local_mappings = {
          "properties" => {
            "text_field" => {
              "type" => "text",
              "analyzer" => "custom"
            }
          }
        }

        remote_mappings = {
          "properties" => {
            "text_field" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }

        result = json_diff.generate_diff(remote_mappings, local_mappings)
        expect(result).to include("Changes Detected")
        expect(result).to include("MODIFIED: properties.text_field.analyzer")
      end
    end

    context 'when comparing non-mappings objects' do
      it 'works normally for settings objects' do
        local_settings = {
          "index" => {
            "refresh_interval" => "5s",
            "max_result_window" => 10000
          }
        }

        remote_settings = {
          "index" => {
            "refresh_interval" => "1s",
            "max_result_window" => 10000
          }
        }

        result = json_diff.generate_diff(remote_settings, local_settings)
        expect(result).to include("Changes Detected")
        expect(result).to include("MODIFIED: index.refresh_interval")
      end
    end

    context 'when objects are identical' do
      it 'returns no changes detected' do
        obj1 = { "key" => "value", "nested" => { "inner" => "data" } }
        obj2 = { "key" => "value", "nested" => { "inner" => "data" } }

        result = json_diff.generate_diff(obj1, obj2)
        expect(result).to eq("No changes detected")
      end
    end

    context 'when objects are completely different' do
      it 'shows all differences' do
        obj1 = { "key1" => "value1" }
        obj2 = { "key2" => "value2" }

        result = json_diff.generate_diff(obj1, obj2)
        expect(result).to include("Changes Detected")
        expect(result).to include("REMOVED: key1")
        expect(result).to include("ADDED: key2")
      end
    end
  end

  describe '#normalize_mappings' do
    it 'removes implicit object types from mappings' do
      mappings = {
        "properties" => {
          "metadata" => {
            "type" => "object",
            "properties" => {
              "priority" => { "type" => "integer" }
            }
          }
        }
      }

      normalized = json_diff.send(:normalize_mappings, mappings)
      
      expect(normalized["properties"]["metadata"]).not_to have_key("type")
      expect(normalized["properties"]["metadata"]["properties"]).to eq({
        "priority" => { "type" => "integer" }
      })
    end

    it 'handles nested object types' do
      mappings = {
        "properties" => {
          "user" => {
            "type" => "object",
            "properties" => {
              "profile" => {
                "type" => "object",
                "properties" => {
                  "name" => { "type" => "text" }
                }
              }
            }
          }
        }
      }

      normalized = json_diff.send(:normalize_mappings, mappings)
      
      expect(normalized["properties"]["user"]).not_to have_key("type")
      expect(normalized["properties"]["user"]["properties"]["profile"]).not_to have_key("type")
      expect(normalized["properties"]["user"]["properties"]["profile"]["properties"]).to eq({
        "name" => { "type" => "text" }
      })
    end

    it 'leaves non-object fields unchanged' do
      mappings = {
        "properties" => {
          "text_field" => {
            "type" => "text",
            "analyzer" => "standard"
          },
          "keyword_field" => {
            "type" => "keyword"
          }
        }
      }

      normalized = json_diff.send(:normalize_mappings, mappings)
      
      expect(normalized["properties"]["text_field"]).to eq({
        "type" => "text",
        "analyzer" => "standard"
      })
      expect(normalized["properties"]["keyword_field"]).to eq({
        "type" => "keyword"
      })
    end

    it 'handles empty mappings' do
      mappings = {}
      normalized = json_diff.send(:normalize_mappings, mappings)
      expect(normalized).to eq({})
    end

    it 'handles non-hash input' do
      expect(json_diff.send(:normalize_mappings, "string")).to eq("string")
      expect(json_diff.send(:normalize_mappings, nil)).to eq(nil)
    end
  end

  describe '#normalize_properties' do
    it 'recursively normalizes object properties' do
      properties = {
        "level1" => {
          "type" => "object",
          "properties" => {
            "level2" => {
              "type" => "object",
              "properties" => {
                "field" => { "type" => "text" }
              }
            }
          }
        }
      }

      normalized = json_diff.send(:normalize_properties, properties)
      
      expect(normalized["level1"]).not_to have_key("type")
      expect(normalized["level1"]["properties"]["level2"]).not_to have_key("type")
      expect(normalized["level1"]["properties"]["level2"]["properties"]["field"]).to eq({
        "type" => "text"
      })
    end

    it 'handles non-hash values' do
      properties = {
        "string_field" => "value",
        "number_field" => 123,
        "array_field" => [1, 2, 3]
      }

      normalized = json_diff.send(:normalize_properties, properties)
      expect(normalized).to eq(properties)
    end
  end
end