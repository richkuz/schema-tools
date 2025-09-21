require_relative '../spec_helper'
require 'schema_tools/breaking_change_detector'

RSpec.describe SchemaTools::BreakingChangeDetector do
  let(:detector) { SchemaTools::BreakingChangeDetector.new }

  describe '#breaking_change?' do
    context 'when no changes detected' do
      let(:live_data) do
        {
          settings: { 'index' => { 'number_of_shards' => 1 } },
          mappings: { 'properties' => { 'id' => { 'type' => 'keyword' } } }
        }
      end

      let(:schema_data) do
        {
          settings: { 'index' => { 'number_of_shards' => 1 } },
          mappings: { 'properties' => { 'id' => { 'type' => 'keyword' } } }
        }
      end

      it 'returns false' do
        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end
    end

    context 'immutable index settings changes' do
      it 'detects number_of_shards change' do
        live_data = { settings: { 'index' => { 'number_of_shards' => 1 } }, mappings: {} }
        schema_data = { settings: { 'index' => { 'number_of_shards' => 2 } }, mappings: {} }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects index.codec change' do
        live_data = { settings: { 'index' => { 'index.codec' => 'default' } }, mappings: {} }
        schema_data = { settings: { 'index' => { 'index.codec' => 'best_compression' } }, mappings: {} }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects routing_partition_size change' do
        live_data = { settings: { 'index' => { 'routing_partition_size' => 1 } }, mappings: {} }
        schema_data = { settings: { 'index' => { 'routing_partition_size' => 3 } }, mappings: {} }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects index.sort.field change' do
        live_data = { settings: { 'index' => { 'index.sort.field' => 'timestamp' } }, mappings: {} }
        schema_data = { settings: { 'index' => { 'index.sort.field' => 'created_at' } }, mappings: {} }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects index.sort.order change' do
        live_data = { settings: { 'index' => { 'index.sort.order' => 'asc' } }, mappings: {} }
        schema_data = { settings: { 'index' => { 'index.sort.order' => 'desc' } }, mappings: {} }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end
    end

    context 'analysis settings changes' do
      it 'detects analyzer changes' do
        live_data = {
          settings: {
            'index' => {
              'analysis' => {
                'analyzer' => {
                  'custom_text' => {
                    'type' => 'custom',
                    'tokenizer' => 'standard',
                    'filter' => ['lowercase']
                  }
                }
              }
            }
          },
          mappings: {}
        }

        schema_data = {
          settings: {
            'index' => {
              'analysis' => {
                'analyzer' => {
                  'custom_text' => {
                    'type' => 'custom',
                    'tokenizer' => 'whitespace',
                    'filter' => ['lowercase']
                  }
                }
              }
            }
          },
          mappings: {}
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects tokenizer changes' do
        live_data = {
          settings: {
            'index' => {
              'analysis' => {
                'tokenizer' => {
                  'custom_tokenizer' => {
                    'type' => 'standard'
                  }
                }
              }
            }
          },
          mappings: {}
        }

        schema_data = {
          settings: {
            'index' => {
              'analysis' => {
                'tokenizer' => {
                  'custom_tokenizer' => {
                    'type' => 'keyword'
                  }
                }
              }
            }
          },
          mappings: {}
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects filter changes' do
        live_data = {
          settings: {
            'index' => {
              'analysis' => {
                'filter' => {
                  'custom_filter' => {
                    'type' => 'lowercase'
                  }
                }
              }
            }
          },
          mappings: {}
        }

        schema_data = {
          settings: {
            'index' => {
              'analysis' => {
                'filter' => {
                  'custom_filter' => {
                    'type' => 'uppercase'
                  }
                }
              }
            }
          },
          mappings: {}
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects char_filter changes' do
        live_data = {
          settings: {
            'index' => {
              'analysis' => {
                'char_filter' => {
                  'custom_char_filter' => {
                    'type' => 'html_strip'
                  }
                }
              }
            }
          },
          mappings: {}
        }

        schema_data = {
          settings: {
            'index' => {
              'analysis' => {
                'char_filter' => {
                  'custom_char_filter' => {
                    'type' => 'mapping',
                    'mappings' => ['&=>and']
                  }
                }
              }
            }
          },
          mappings: {}
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'allows adding new analyzers' do
        live_data = {
          settings: {
            'index' => {
              'analysis' => {
                'analyzer' => {
                  'existing_analyzer' => {
                    'type' => 'standard'
                  }
                }
              }
            }
          },
          mappings: {}
        }

        schema_data = {
          settings: {
            'index' => {
              'analysis' => {
                'analyzer' => {
                  'existing_analyzer' => {
                    'type' => 'standard'
                  },
                  'new_analyzer' => {
                    'type' => 'keyword'
                  }
                }
              }
            }
          },
          mappings: {}
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end
    end

    context 'field type changes' do
      it 'detects field type changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'user_id' => { 'type' => 'keyword' }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'user_id' => { 'type' => 'integer' }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects text to keyword change' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'status' => { 'type' => 'text' }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'status' => { 'type' => 'keyword' }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'allows adding new fields' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'existing_field' => { 'type' => 'keyword' }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'existing_field' => { 'type' => 'keyword' },
              'new_field' => { 'type' => 'text' }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end
    end

    context 'field analyzer changes' do
      it 'detects analyzer changes on text fields' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'analyzer' => 'english' }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'analyzer' => 'standard' }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end
    end

    context 'immutable field properties changes' do
      it 'detects index property changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'index' => true }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'index' => false }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects store property changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'store' => true }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'store' => false }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects doc_values property changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'count' => { 'type' => 'integer', 'doc_values' => true }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'count' => { 'type' => 'integer', 'doc_values' => false }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects fielddata property changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'fielddata' => true }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'fielddata' => false }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects norms property changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'text', 'norms' => true }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'text', 'norms' => false }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end
    end

    context 'multi-field definitions changes' do
      it 'detects subfield type changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => {
                'type' => 'text',
                'fields' => {
                  'raw' => { 'type' => 'keyword' }
                }
              }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => {
                'type' => 'text',
                'fields' => {
                  'raw' => { 'type' => 'text' }
                }
              }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'detects subfield property changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => {
                'type' => 'text',
                'fields' => {
                  'raw' => { 'type' => 'keyword', 'index' => true }
                }
              }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => {
                'type' => 'text',
                'fields' => {
                  'raw' => { 'type' => 'keyword', 'index' => false }
                }
              }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be true
      end

      it 'allows adding new subfields' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => {
                'type' => 'text',
                'fields' => {
                  'raw' => { 'type' => 'keyword' }
                }
              }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => {
                'type' => 'text',
                'fields' => {
                  'raw' => { 'type' => 'keyword' },
                  'suggest' => { 'type' => 'completion' }
                }
              }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end
    end

    context 'mutable settings that should not be breaking' do
      it 'allows number_of_replicas changes' do
        live_data = { settings: { 'index' => { 'number_of_replicas' => 0 } }, mappings: {} }
        schema_data = { settings: { 'index' => { 'number_of_replicas' => 1 } }, mappings: {} }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end

      it 'allows refresh_interval changes' do
        live_data = { settings: { 'index' => { 'refresh_interval' => '1s' } }, mappings: {} }
        schema_data = { settings: { 'index' => { 'refresh_interval' => '30s' } }, mappings: {} }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end

      it 'allows dynamic mapping changes' do
        live_data = { settings: {}, mappings: { 'dynamic' => true } }
        schema_data = { settings: {}, mappings: { 'dynamic' => false } }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end
    end

    context 'mutable field properties that should not be breaking' do
      it 'allows boost changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'boost' => 1.0 }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'boost' => 2.0 }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end

      it 'allows search_analyzer changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'analyzer' => 'standard', 'search_analyzer' => 'standard' }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'analyzer' => 'standard', 'search_analyzer' => 'keyword' }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end

      it 'allows search_quote_analyzer changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'search_quote_analyzer' => 'standard' }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'search_quote_analyzer' => 'keyword' }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end

      it 'allows adding mutable properties' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text' }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'boost' => 2.0 }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end

      it 'allows ignore_above changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'keyword', 'ignore_above' => 256 }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'keyword', 'ignore_above' => 512 }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end

      it 'allows ignore_malformed changes' do
        live_data = {
          settings: {},
          mappings: {
            'properties' => {
              'price' => { 'type' => 'float', 'ignore_malformed' => false }
            }
          }
        }

        schema_data = {
          settings: {},
          mappings: {
            'properties' => {
              'price' => { 'type' => 'float', 'ignore_malformed' => true }
            }
          }
        }

        expect(detector.breaking_change?(live_data, schema_data)).to be false
      end
    end
  end
end