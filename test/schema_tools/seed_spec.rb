require_relative '../spec_helper'
require 'schema_tools/seed'
require 'schema_tools/config'
require 'seeder/seeder'

RSpec.describe SchemaTools do
  describe '.seed' do
    let(:mock_client) { double('client') }
    let(:sample_indices) { ['products-1', 'users-2', 'orders-3'] }
    let(:sample_mappings) do
      {
        'properties' => {
          'name' => { 'type' => 'text' },
          'price' => { 'type' => 'float' }
        }
      }
    end

    before do
      allow(SchemaTools::Config).to receive(:connection_url).and_return('http://localhost:9200')
      allow(mock_client).to receive(:list_indices).and_return(sample_indices)
      allow(mock_client).to receive(:get_index_mappings).and_return(sample_mappings)
      allow(Seed).to receive(:seed_data)
    end

    context 'when indices are available' do
      it 'lists available indices and prompts for selection' do
        allow(STDIN).to receive(:gets).and_return("1\n", "5\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Available indices:/).to_stdout
      end

      it 'fetches mappings for selected index' do
        allow(STDIN).to receive(:gets).and_return("2\n", "10\n")

        expect(mock_client).to receive(:get_index_mappings).with('users-2')

        SchemaTools.seed(client: mock_client)
      end

      it 'prompts for number of documents to seed' do
        allow(STDIN).to receive(:gets).and_return("1\n", "25\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/How many documents would you like to seed\?/).to_stdout
      end

      it 'calls Seed.seed_data with correct parameters' do
        allow(STDIN).to receive(:gets).and_return("3\n", "100\n")

        expect(Seed).to receive(:seed_data).with(100, sample_mappings, mock_client, 'orders-3')

        SchemaTools.seed(client: mock_client)
      end

      it 'validates document count input' do
        allow(STDIN).to receive(:gets).and_return("1\n", "0\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid number of documents/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'validates document count input for negative numbers' do
        allow(STDIN).to receive(:gets).and_return("1\n", "-5\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid number of documents/).to_stdout
          .and raise_error(SystemExit)
      end

      it 'validates document count input for non-numeric input' do
        allow(STDIN).to receive(:gets).and_return("1\n", "abc\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Invalid number of documents/).to_stdout
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

      it 'handles failed mapping fetch' do
        allow(STDIN).to receive(:gets).and_return("1\n")
        allow(mock_client).to receive(:get_index_mappings).and_return(nil)

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Failed to fetch mappings/).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context 'when no indices are available' do
      before do
        allow(mock_client).to receive(:list_indices).and_return([])
      end

      it 'exits gracefully with message' do
        expect { SchemaTools.seed(client: mock_client) }
          .to output(/No indices found in the cluster/).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context 'integration with real input' do
      it 'processes complete workflow successfully' do
        # Mock user input: select index 2, seed 50 documents
        allow(STDIN).to receive(:gets).and_return("2\n", "50\n")

        expect(Seed).to receive(:seed_data).with(50, sample_mappings, mock_client, 'users-2')

        SchemaTools.seed(client: mock_client)
      end

      it 'shows progress messages' do
        allow(STDIN).to receive(:gets).and_return("1\n", "10\n")

        expect { SchemaTools.seed(client: mock_client) }
          .to output(/Selected index: products-1/).to_stdout
      end
    end
  end
end