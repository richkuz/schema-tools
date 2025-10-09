require_relative '../spec_helper'
require 'schema_tools/api_aware_mappings_diff'

RSpec.describe SchemaTools::ApiAwareMappingsDiff do
  describe '#generate_minimal_changes' do
    context 'when mappings are identical' do
      it 'returns empty hash' do
        mappings = {
          "properties" => {
            "title" => { "type" => "text" },
            "content" => { "type" => "text" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(mappings, mappings)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local mappings have new fields' do
      it 'includes new fields in changes' do
        local = {
          "properties" => {
            "title" => { "type" => "text" },
            "content" => { "type" => "text" },
            "new_field" => { "type" => "keyword" }
          }
        }
        remote = {
          "properties" => {
            "title" => { "type" => "text" },
            "content" => { "type" => "text" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "properties" => {
            "new_field" => { "type" => "keyword" }
          }
        })
      end
    end

    context 'when local mappings modify field properties' do
      it 'includes complete field definition for API compatibility' do
        local = {
          "properties" => {
            "title" => { "type" => "text", "analyzer" => "custom_analyzer" }
          }
        }
        remote = {
          "properties" => {
            "title" => { "type" => "text", "analyzer" => "standard" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "properties" => {
            "title" => { "type" => "text", "analyzer" => "custom_analyzer" }
          }
        })
      end
    end

    context 'when local mappings change field type' do
      it 'includes complete field definition' do
        local = {
          "properties" => {
            "title" => { "type" => "keyword" }
          }
        }
        remote = {
          "properties" => {
            "title" => { "type" => "text" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "properties" => {
            "title" => { "type" => "keyword" }
          }
        })
      end
    end

    context 'when local mappings have nested field changes' do
      it 'includes complete field definition for nested fields' do
        local = {
          "properties" => {
            "title" => {
              "type" => "text",
              "fields" => {
                "keyword" => { "type" => "keyword", "ignore_above" => 256 }
              }
            }
          }
        }
        remote = {
          "properties" => {
            "title" => {
              "type" => "text",
              "fields" => {
                "keyword" => { "type" => "keyword", "ignore_above" => 128 }
              }
            }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "properties" => {
            "title" => {
              "type" => "text",
              "fields" => {
                "keyword" => { "type" => "keyword", "ignore_above" => 256 }
              }
            }
          }
        })
      end
    end

    context 'when local mappings change dynamic setting' do
      it 'includes dynamic setting in changes' do
        local = {
          "dynamic" => "strict",
          "properties" => {
            "title" => { "type" => "text" }
          }
        }
        remote = {
          "dynamic" => "true",
          "properties" => {
            "title" => { "type" => "text" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "dynamic" => "strict"
        })
      end
    end

    context 'when local mappings have complex nested structures' do
      it 'includes complete field definitions for nested objects' do
        local = {
          "properties" => {
            "chunks" => {
              "type" => "nested",
              "properties" => {
                "content" => {
                  "type" => "text",
                  "analyzer" => "custom_analyzer"
                },
                "metadata" => {
                  "type" => "object",
                  "properties" => {
                    "score" => { "type" => "float" }
                  }
                }
              }
            }
          }
        }
        remote = {
          "properties" => {
            "chunks" => {
              "type" => "nested",
              "properties" => {
                "content" => {
                  "type" => "text",
                  "analyzer" => "standard"
                },
                "metadata" => {
                  "type" => "object",
                  "properties" => {
                    "score" => { "type" => "float" }
                  }
                }
              }
            }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "properties" => {
            "chunks" => {
              "type" => "nested",
              "properties" => {
                "content" => {
                  "type" => "text",
                  "analyzer" => "custom_analyzer"
                },
                "metadata" => {
                  "type" => "object",
                  "properties" => {
                    "score" => { "type" => "float" }
                  }
                }
              }
            }
          }
        })
      end
    end

    context 'when remote mappings are empty' do
      it 'includes all local mappings' do
        local = {
          "properties" => {
            "title" => { "type" => "text" },
            "content" => { "type" => "text" }
          }
        }
        remote = {}
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "properties" => {
            "title" => { "type" => "text" },
            "content" => { "type" => "text" }
          }
        })
      end
    end

    context 'when local mappings are empty' do
      it 'returns empty hash' do
        local = {}
        remote = {
          "properties" => {
            "title" => { "type" => "text" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local mappings have no properties key' do
      it 'returns empty hash' do
        local = { "dynamic" => "true" }
        remote = {
          "properties" => {
            "title" => { "type" => "text" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when only dynamic setting changes' do
      it 'includes only dynamic setting' do
        local = {
          "dynamic" => "strict",
          "properties" => {
            "title" => { "type" => "text" }
          }
        }
        remote = {
          "dynamic" => "true",
          "properties" => {
            "title" => { "type" => "text" }
          }
        }
        diff = SchemaTools::ApiAwareMappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({
          "dynamic" => "strict"
        })
      end
    end
  end

  describe '#is_field_definition?' do
    it 'returns true for objects with type key' do
      diff = SchemaTools::ApiAwareMappingsDiff.new({}, {})
      expect(diff.send(:is_field_definition?, { "type" => "text" })).to be true
      expect(diff.send(:is_field_definition?, { "type" => "keyword", "analyzer" => "custom" })).to be true
    end

    it 'returns false for objects without type key' do
      diff = SchemaTools::ApiAwareMappingsDiff.new({}, {})
      expect(diff.send(:is_field_definition?, { "analyzer" => "custom" })).to be false
      expect(diff.send(:is_field_definition?, { "properties" => {} })).to be false
      expect(diff.send(:is_field_definition?, {})).to be false
    end

    it 'returns false for non-hash values' do
      diff = SchemaTools::ApiAwareMappingsDiff.new({}, {})
      expect(diff.send(:is_field_definition?, "text")).to be false
      expect(diff.send(:is_field_definition?, 123)).to be false
      expect(diff.send(:is_field_definition?, nil)).to be false
    end
  end
end