require_relative '../spec_helper'
require 'schema_tools/settings_diff'

RSpec.describe SchemaTools::SettingsDiff do
  describe '#generate_minimal_changes' do
    context 'when schemas are identical' do
      it 'returns empty hash' do
        schema = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(schema, schema)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local schema has new settings' do
      it 'includes new settings in changes' do
        local = {
          "index" => {
            "number_of_replicas" => "2",
            "refresh_interval" => "5s",
            "max_result_window" => "10000"
          }
        }
        
        remote = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "number_of_replicas" => "2",
            "max_result_window" => "10000"
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema modifies existing settings' do
      it 'includes modified settings in changes' do
        local = {
          "index" => {
            "number_of_replicas" => "3",
            "refresh_interval" => "10s"
          }
        }
        
        remote = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "number_of_replicas" => "3",
            "refresh_interval" => "10s"
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema has nested changes' do
      it 'includes only changed nested properties' do
        local = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "custom_analyzer" => {
                  "type" => "custom",
                  "tokenizer" => "standard",
                  "filter" => ["lowercase"]
                }
              }
            },
            "number_of_replicas" => "1"
          }
        }
        
        remote = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "custom_analyzer" => {
                  "type" => "custom",
                  "tokenizer" => "standard",
                  "filter" => ["lowercase", "stop"]
                }
              }
            },
            "number_of_replicas" => "1"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "custom_analyzer" => {
                  "filter" => ["lowercase"]
                }
              }
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema removes settings' do
      it 'does not include removed settings in changes' do
        local = {
          "index" => {
            "number_of_replicas" => "1"
          }
        }
        
        remote = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s",
            "max_result_window" => "10000"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local schema has complex nested structures' do
      it 'handles deep nested changes correctly' do
        local = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "new_analyzer" => {
                  "type" => "custom",
                  "tokenizer" => "keyword"
                },
                "existing_analyzer" => {
                  "type" => "custom",
                  "tokenizer" => "standard",
                  "filter" => ["lowercase"]
                }
              },
              "filter" => {
                "new_filter" => {
                  "type" => "lowercase"
                }
              }
            }
          }
        }
        
        remote = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "existing_analyzer" => {
                  "type" => "custom",
                  "tokenizer" => "standard",
                  "filter" => ["lowercase", "stop"]
                }
              }
            }
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "new_analyzer" => {
                  "type" => "custom",
                  "tokenizer" => "keyword"
                },
                "existing_analyzer" => {
                  "filter" => ["lowercase"]
                }
              },
              "filter" => {
                "new_filter" => {
                  "type" => "lowercase"
                }
              }
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema has array changes' do
      it 'handles array differences correctly' do
        local = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "test_analyzer" => {
                  "filter" => ["lowercase", "stop", "trim"]
                }
              }
            }
          }
        }
        
        remote = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "test_analyzer" => {
                  "filter" => ["lowercase", "stop"]
                }
              }
            }
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "test_analyzer" => {
                  "filter" => ["lowercase", "stop", "trim"]
                }
              }
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when remote schema is empty' do
      it 'returns entire local schema' do
        local = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        remote = {}
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema is empty' do
      it 'returns empty hash' do
        local = {}
        
        remote = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local schema has no index wrapper' do
      it 'treats entire local schema as index settings' do
        local = {
          "number_of_replicas" => "2",
          "refresh_interval" => "5s",
          "max_result_window" => "10000"
        }
        
        remote = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "number_of_replicas" => "2",
            "max_result_window" => "10000"
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema has no index wrapper and is identical to remote' do
      it 'returns empty hash' do
        local = {
          "number_of_replicas" => "1",
          "refresh_interval" => "5s"
        }
        
        remote = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end

    context 'when local schema has no index wrapper with nested structures' do
      it 'handles nested changes correctly' do
        local = {
          "number_of_replicas" => "1",
          "analysis" => {
            "analyzer" => {
              "custom_analyzer" => {
                "type" => "custom",
                "tokenizer" => "standard",
                "filter" => ["lowercase"]
              }
            }
          }
        }
        
        remote = {
          "index" => {
            "number_of_replicas" => "1",
            "analysis" => {
              "analyzer" => {
                "custom_analyzer" => {
                  "type" => "custom",
                  "tokenizer" => "standard",
                  "filter" => ["lowercase", "stop"]
                }
              }
            }
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "analysis" => {
              "analyzer" => {
                "custom_analyzer" => {
                  "filter" => ["lowercase"]
                }
              }
            }
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema has no index wrapper and remote is empty' do
      it 'returns entire local schema as index settings' do
        local = {
          "number_of_replicas" => "1",
          "refresh_interval" => "5s"
        }
        
        remote = {}
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expected = {
          "index" => {
            "number_of_replicas" => "1",
            "refresh_interval" => "5s"
          }
        }
        
        expect(diff.generate_minimal_changes).to eq(expected)
      end
    end

    context 'when local schema has index wrapper but index is not a hash' do
      it 'returns empty hash' do
        local = {
          "index" => "invalid"
        }
        
        remote = {
          "index" => {
            "number_of_replicas" => "1"
          }
        }
        
        diff = SchemaTools::SettingsDiff.new(local, remote)
        expect(diff.generate_minimal_changes).to eq({})
      end
    end
  end
end