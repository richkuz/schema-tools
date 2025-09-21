require_relative '../spec_helper'
require 'schema_tools/breaking_change_detector'

RSpec.describe SchemaTools::BreakingChangeDetector do
  let(:detector) { SchemaTools::BreakingChangeDetector.new }

  describe '#breaking_change?' do
    context 'when no changes detected' do
      let(:proposed_data) do
        {
          settings: { 'index' => { 'number_of_shards' => 1 } },
          mappings: { 'properties' => { 'id' => { 'type' => 'keyword' } } }
        }
      end

      let(:current_data) do
        {
          settings: { 'index' => { 'number_of_shards' => 1 } },
          mappings: { 'properties' => { 'id' => { 'type' => 'keyword' } } }
        }
      end

      it 'returns false' do
        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end

    context 'immutable index settings changes' do
      it 'detects number_of_shards change' do
        proposed_data = { settings: { 'index' => { 'number_of_shards' => 1 } }, mappings: {} }
        current_data = { settings: { 'index' => { 'number_of_shards' => 2 } }, mappings: {} }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects index.codec change' do
        proposed_data = { settings: { 'index' => { 'index.codec' => 'default' } }, mappings: {} }
        current_data = { settings: { 'index' => { 'index.codec' => 'best_compression' } }, mappings: {} }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects routing_partition_size change' do
        proposed_data = { settings: { 'index' => { 'routing_partition_size' => 1 } }, mappings: {} }
        current_data = { settings: { 'index' => { 'routing_partition_size' => 3 } }, mappings: {} }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects index.sort.field change' do
        proposed_data = { settings: { 'index' => { 'index.sort.field' => 'timestamp' } }, mappings: {} }
        current_data = { settings: { 'index' => { 'index.sort.field' => 'created_at' } }, mappings: {} }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects index.sort.order change' do
        proposed_data = { settings: { 'index' => { 'index.sort.order' => 'asc' } }, mappings: {} }
        current_data = { settings: { 'index' => { 'index.sort.order' => 'desc' } }, mappings: {} }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end
    end

    context 'analysis settings changes' do
      it 'detects analyzer changes' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects tokenizer changes' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects filter changes' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects char_filter changes' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'allows adding new analyzers' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end

    context 'field type changes' do
      it 'detects field type changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'user_id' => { 'type' => 'keyword' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'user_id' => { 'type' => 'integer' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects text to keyword change' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'status' => { 'type' => 'text' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'status' => { 'type' => 'keyword' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'allows adding new fields' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'existing_field' => { 'type' => 'keyword' },
              'new_field' => { 'type' => 'text' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'existing_field' => { 'type' => 'keyword' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end

    context 'field analyzer changes' do
      it 'detects analyzer changes on text fields' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'analyzer' => 'english' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'analyzer' => 'standard' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end
    end

    context 'immutable field properties changes' do
      it 'detects index property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'index' => true }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'index' => false }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects store property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'store' => true }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'store' => false }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects doc_values property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'count' => { 'type' => 'integer', 'doc_values' => true }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'count' => { 'type' => 'integer', 'doc_values' => false }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects fielddata property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'fielddata' => true }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'fielddata' => false }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects norms property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'text', 'norms' => true }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'text', 'norms' => false }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects enabled property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'metadata' => { 'type' => 'object', 'enabled' => true }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'metadata' => { 'type' => 'object', 'enabled' => false }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects format property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'timestamp' => { 'type' => 'date', 'format' => 'yyyy-MM-dd' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'timestamp' => { 'type' => 'date', 'format' => 'epoch_millis' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects copy_to property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'copy_to' => 'all_text' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'copy_to' => 'search_text' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects term_vector property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'term_vector' => 'with_positions_offsets' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'term_vector' => 'no' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects index_options property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'index_options' => 'freqs' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'index_options' => 'docs' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects null_value property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'status' => { 'type' => 'keyword', 'null_value' => 'UNKNOWN' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'status' => { 'type' => 'keyword', 'null_value' => 'MISSING' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects ignore_z_value property changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'location' => { 'type' => 'geo_point', 'ignore_z_value' => true }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'location' => { 'type' => 'geo_point', 'ignore_z_value' => false }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end
    end

    context 'multi-field definitions changes' do
      it 'detects subfield type changes' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'detects subfield property changes' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'allows adding new subfields' do
        proposed_data = {
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

        current_data = {
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

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end

    context 'dynamic mapping changes' do
      it 'detects dynamic mapping changes' do
        proposed_data = {
          settings: {},
          mappings: { 'dynamic' => true }
        }

        current_data = {
          settings: {},
          mappings: { 'dynamic' => 'strict' }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'allows adding dynamic mapping' do
        proposed_data = {
          settings: {},
          mappings: { 'dynamic' => true }
        }

        current_data = {
          settings: {},
          mappings: {}
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end

    context 'field existence changes' do
      it 'detects field removal' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text' },
              'description' => { 'type' => 'text' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be true
      end

      it 'allows adding new fields' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text' },
              'description' => { 'type' => 'text' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end

    context 'mutable settings that should not be breaking' do
      it 'allows number_of_replicas changes' do
        proposed_data = { settings: { 'index' => { 'number_of_replicas' => 0 } }, mappings: {} }
        current_data = { settings: { 'index' => { 'number_of_replicas' => 1 } }, mappings: {} }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end

      it 'allows refresh_interval changes' do
        proposed_data = { settings: { 'index' => { 'refresh_interval' => '1s' } }, mappings: {} }
        current_data = { settings: { 'index' => { 'refresh_interval' => '30s' } }, mappings: {} }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end

      it 'allows dynamic mapping changes' do
        proposed_data = { settings: {}, mappings: { 'dynamic' => true } }
        current_data = { settings: {}, mappings: { 'dynamic' => false } }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end

    context 'mutable field properties that should not be breaking' do
      it 'allows boost changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'boost' => 1.0 }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'boost' => 2.0 }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end

      it 'allows search_analyzer changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'analyzer' => 'standard', 'search_analyzer' => 'standard' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'analyzer' => 'standard', 'search_analyzer' => 'keyword' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end

      it 'allows search_quote_analyzer changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'search_quote_analyzer' => 'standard' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'content' => { 'type' => 'text', 'search_quote_analyzer' => 'keyword' }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end

      it 'allows adding mutable properties' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text' }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'title' => { 'type' => 'text', 'boost' => 2.0 }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end

      it 'allows ignore_above changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'keyword', 'ignore_above' => 256 }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'description' => { 'type' => 'keyword', 'ignore_above' => 512 }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end

      it 'allows ignore_malformed changes' do
        proposed_data = {
          settings: {},
          mappings: {
            'properties' => {
              'price' => { 'type' => 'float', 'ignore_malformed' => false }
            }
          }
        }

        current_data = {
          settings: {},
          mappings: {
            'properties' => {
              'price' => { 'type' => 'float', 'ignore_malformed' => true }
            }
          }
        }

        expect(detector.breaking_change?(proposed_data, current_data)).to be false
      end
    end
  end
end