require_relative '../spec_helper'
require 'schema_tools/seed'
require 'schema_tools/config'
require 'seeder/seeder'

RSpec.describe SchemaTools do
  describe '.seed' do
    let(:mock_client) { double('client') }
    let(:sample_indices) { ['products-1', 'users-2', 'orders-3'] }
    let(:sample_aliases) { {} }
    let(:sample_mappings) do
      {
        'properties' => {
          'name' => { 'type' => 'text' },
          'price' => { 'type' => 'float' }
        }
      }
    end
    let(:mock_seeder) { double('seeder') }

    before do
      allow(SchemaTools::Config).to receive(:connection_url).and_return('http://localhost:9200')
      allow(mock_client).to receive(:list_indices).and_return(sample_indices)
      allow(mock_client).to receive(:list_aliases).and_return(sample_aliases)
      allow(mock_client).to receive(:get_index_mappings).and_return(sample_mappings)
      allow(mock_client).to receive(:alias_exists?).and_return(false)
      allow(mock_client).to receive(:index_closed?).and_return(false)
      allow(SchemaTools::Seeder::Seeder).to receive(:new).and_return(mock_seeder)
      allow(mock_seeder).to receive(:seed)
    end

    context 'when indices are available' do
      it 'lists available indices and prompts for selection' do
        allow(STDIN).to receive(:gets).and_return("1\n", "5\n", "\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Available indices and aliases:/).to_stdout
      end

      it 'creates seeder with selected index' do
        allow(STDIN).to receive(:gets).and_return("2\n", "10\n", "\n")

        expect(SchemaTools::Seeder::Seeder).to receive(:new).with(
          index_or_alias_name: 'users-2',
          client: mock_client
        )

        SchemaTools.seed(client: mock_client)
      end

      it 'prompts for number of documents to seed' do
        allow(STDIN).to receive(:gets).and_return("1\n", "25\n", "\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/How many documents would you like to seed\?/).to_stdout
      end

      it 'calls seeder.seed with correct parameters' do
        allow(STDIN).to receive(:gets).and_return("3\n", "100\n", "\n")

        expect(mock_seeder).to receive(:seed).with(num_docs: 100, batch_size: 50)

        SchemaTools.seed(client: mock_client)
      end

      it 'validates document count input' do
        allow(STDIN).to receive(:gets).and_return("1\n", "0\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid input/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'validates document count input for negative numbers' do
        allow(STDIN).to receive(:gets).and_return("1\n", "-5\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid input/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'validates document count input for non-numeric input' do
        allow(STDIN).to receive(:gets).and_return("1\n", "abc\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid input/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'validates index selection input' do
        allow(STDIN).to receive(:gets).and_return("5\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid selection/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'validates index selection input for zero' do
        allow(STDIN).to receive(:gets).and_return("0\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid selection/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'validates index selection input for negative numbers' do
        allow(STDIN).to receive(:gets).and_return("-1\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid selection/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'handles nil input for index selection' do
        allow(STDIN).to receive(:gets).and_return(nil)

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/No input provided/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'handles nil input for document count' do
        allow(STDIN).to receive(:gets).and_return("1\n", nil)

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/No input provided/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'handles seeder initialization failure' do
        allow(STDIN).to receive(:gets).and_return("1\n", "5\n", "\n")
        allow(SchemaTools::Seeder::Seeder).to receive(:new).and_raise("No custom document seeder, sample documents, or mappings found for products-1")

        expect { SchemaTools.seed(client: mock_client) }
          .to raise_error("No custom document seeder, sample documents, or mappings found for products-1")
      end
    end

    context 'when no indices are available' do
      before do
        allow(mock_client).to receive(:list_indices).and_return([])
        allow(mock_client).to receive(:list_aliases).and_return({})
      end

      it 'exits gracefully with message' do
        expect { SchemaTools.seed(client: mock_client) }
          .to output(/No indices or aliases found in the cluster/).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context 'with aliases' do
      let(:sample_aliases) { { 'products' => ['products-20251014142208'] } }
      let(:sample_indices) { ['products-1', 'users-2'] }

      before do
        allow(mock_client).to receive(:list_aliases).and_return(sample_aliases)
        allow(mock_client).to receive(:alias_exists?).with('products').and_return(true)
        allow(mock_client).to receive(:get_alias_indices).with('products').and_return(['products-20251014142208'])
      end

      it 'shows aliases first in the list' do
        allow(STDIN).to receive(:gets).and_return("1\n", "5\n", "\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/1\. products -> products-20251014142208/).to_stdout
      end

      it 'creates seeder with alias name' do
        allow(STDIN).to receive(:gets).and_return("1\n", "10\n", "\n")

        expect(SchemaTools::Seeder::Seeder).to receive(:new).with(
          index_or_alias_name: 'products',
          client: mock_client
        )

        SchemaTools.seed(client: mock_client)
      end

      it 'shows selected alias message' do
        allow(STDIN).to receive(:gets).and_return("1\n", "5\n", "\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Selected alias: products/).to_stdout
      end
    end

    context 'integration with real input' do
      it 'processes complete workflow successfully' do
        # Mock user input: select index 2, seed 50 documents
        allow(STDIN).to receive(:gets).and_return("2\n", "50\n", "\n")

        expect(SchemaTools::Seeder::Seeder).to receive(:new).with(
          index_or_alias_name: 'users-2',
          client: mock_client
        )
        expect(mock_seeder).to receive(:seed).with(num_docs: 50, batch_size: 50)

        SchemaTools.seed(client: mock_client)
      end

      it 'shows progress messages' do
        allow(STDIN).to receive(:gets).and_return("1\n", "10\n", "\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Selected index: products-1/).to_stdout
      end
    end
  end
end