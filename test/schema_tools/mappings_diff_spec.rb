require_relative '../spec_helper'
require 'schema_tools/mappings_diff'

RSpec.describe SchemaTools::MappingsDiff do
  describe '#generate_minimal_changes' do
    context 'when mappings are identical' do
      it 'returns empty hash' do
        mappings = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(mappings, mappings)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local mappings have new properties' do
      it 'includes new properties in changes' do
        local = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            },
            "description" => {
              "type" => "text",
              "analyzer" => "custom_analyzer"
            }
          }
        }
        
        remote = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "properties" => {
            "description" => {
              "type" => "text",
              "analyzer" => "custom_analyzer"
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local mappings modify existing properties' do
      it 'includes modified properties in changes' do
        local = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "custom_analyzer"
            }
          }
        }
        
        remote = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "properties" => {
            "title" => {
              "analyzer" => "custom_analyzer"
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local mappings have nested changes' do
      it 'includes only changed nested properties' do
        local = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard",
              "fields" => {
                "keyword" => {
                  "type" => "keyword",
                  "ignore_above" => 256
                }
              }
            }
          }
        }
        
        remote = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard",
              "fields" => {
                "keyword" => {
                  "type" => "keyword",
                  "ignore_above" => 128
                }
              }
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "properties" => {
            "title" => {
              "fields" => {
                "keyword" => {
                  "ignore_above" => 256
                }
              }
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local mappings remove properties' do
      it 'does not include removed properties in changes' do
        local = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }
        
        remote = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            },
            "description" => {
              "type" => "text",
              "analyzer" => "custom_analyzer"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local mappings have complex nested structures' do
      it 'handles deep nested changes correctly' do
        local = {
          "properties" => {
            "chunks" => {
              "type" => "nested",
              "properties" => {
                "content" => {
                  "type" => "text",
                  "analyzer" => "custom_analyzer",
                  "fields" => {
                    "keyword" => {
                      "type" => "keyword"
                    }
                  }
                },
                "metadata" => {
                  "type" => "object",
                  "properties" => {
                    "score" => {
                      "type" => "float"
                    }
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
                  "analyzer" => "standard",
                  "fields" => {
                    "keyword" => {
                      "type" => "keyword"
                    }
                  }
                },
                "metadata" => {
                  "type" => "object",
                  "properties" => {
                    "score" => {
                      "type" => "float"
                    }
                  }
                }
              }
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "properties" => {
            "chunks" => {
              "properties" => {
                "content" => {
                  "analyzer" => "custom_analyzer"
                }
              }
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local mappings have array changes' do
      it 'handles array differences correctly' do
        local = {
          "properties" => {
            "tags" => {
              "type" => "keyword"
            },
            "categories" => {
              "type" => "keyword"
            }
          }
        }
        
        remote = {
          "properties" => {
            "tags" => {
              "type" => "text"
            },
            "categories" => {
              "type" => "keyword"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "properties" => {
            "tags" => {
              "type" => "keyword"
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local mappings have dynamic setting' do
      it 'includes dynamic setting if different' do
        local = {
          "dynamic" => "strict",
          "properties" => {
            "title" => {
              "type" => "text"
            }
          }
        }
        
        remote = {
          "dynamic" => "true",
          "properties" => {
            "title" => {
              "type" => "text"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "dynamic" => "strict"
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local mappings add dynamic setting' do
      it 'includes dynamic setting when remote does not have it' do
        local = {
          "dynamic" => "strict",
          "properties" => {
            "title" => {
              "type" => "text"
            }
          }
        }
        
        remote = {
          "properties" => {
            "title" => {
              "type" => "text"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "dynamic" => "strict"
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when remote mappings is empty' do
      it 'returns entire local mappings' do
        local = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }
        
        remote = {}
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expected = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local mappings is empty' do
      it 'returns empty hash' do
        local = {}
        
        remote = {
          "properties" => {
            "title" => {
              "type" => "text",
              "analyzer" => "standard"
            }
          }
        }
        
        diff = SchemaTools::MappingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end
  end
end