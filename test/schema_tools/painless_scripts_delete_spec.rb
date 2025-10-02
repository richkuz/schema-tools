require_relative '../spec_helper'
require 'schema_tools/painless_scripts_delete'
require 'schema_tools/config'
require 'tempfile'

RSpec.describe SchemaTools do
  describe '.painless_scripts_delete' do
    let(:client) { double('client') }

    context 'when script_name parameter is missing' do
      it 'raises an error' do
        expect { SchemaTools.painless_scripts_delete(script_name: nil, client: client) }
          .to raise_error('script_name parameter is required')
      end
    end

    context 'when script_name parameter is empty' do
      it 'raises an error' do
        expect { SchemaTools.painless_scripts_delete(script_name: '', client: client) }
          .to raise_error('script_name parameter is required')
      end
    end

    context 'when script exists in cluster' do
      before do
        allow(client).to receive(:delete_script).with('test_script').and_return({ 'acknowledged' => true })
      end

      it 'deletes the script successfully' do
        expect { SchemaTools.painless_scripts_delete(script_name: 'test_script', client: client) }
          .to output(/Deleting painless script 'test_script' from cluster.*Successfully deleted painless script 'test_script' from cluster/m).to_stdout
      end

      it 'removes .painless extension if provided' do
        expect { SchemaTools.painless_scripts_delete(script_name: 'test_script.painless', client: client) }
          .to output(/Deleting painless script 'test_script' from cluster.*Successfully deleted painless script 'test_script' from cluster/m).to_stdout
      end

      it 'calls client.delete_script with correct script name' do
        expect(client).to receive(:delete_script).with('test_script')
        SchemaTools.painless_scripts_delete(script_name: 'test_script', client: client)
      end
    end

    context 'when script does not exist in cluster' do
      before do
        allow(client).to receive(:delete_script).with('nonexistent_script')
          .and_raise('HTTP 404: Script \'nonexistent_script\' not found')
      end

      it 'handles 404 error gracefully' do
        expect { SchemaTools.painless_scripts_delete(script_name: 'nonexistent_script', client: client) }
          .to output(/Deleting painless script 'nonexistent_script' from cluster.*Script 'nonexistent_script' not found in cluster/m).to_stdout
      end
    end

    context 'when script deletion fails with other error' do
      before do
        allow(client).to receive(:delete_script).with('test_script')
          .and_raise('HTTP 500: Internal Server Error')
      end

      it 'propagates the error' do
        expect { SchemaTools.painless_scripts_delete(script_name: 'test_script', client: client) }
          .to raise_error('HTTP 500: Internal Server Error')
      end
    end

    context 'when script name contains special characters' do
      before do
        allow(client).to receive(:delete_script).with('script-with-dashes').and_return({ 'acknowledged' => true })
      end

      it 'handles script names with special characters' do
        expect { SchemaTools.painless_scripts_delete(script_name: 'script-with-dashes', client: client) }
          .to output(/Deleting painless script 'script-with-dashes' from cluster.*Successfully deleted painless script 'script-with-dashes' from cluster/m).to_stdout
      end
    end

    context 'when script name has multiple .painless extensions' do
      before do
        allow(client).to receive(:delete_script).with('test_script.painless').and_return({ 'acknowledged' => true })
      end

      it 'only removes the last .painless extension' do
        expect { SchemaTools.painless_scripts_delete(script_name: 'test_script.painless.painless', client: client) }
          .to output(/Deleting painless script 'test_script.painless' from cluster.*Successfully deleted painless script 'test_script.painless' from cluster/m).to_stdout
      end
    end
  end
end