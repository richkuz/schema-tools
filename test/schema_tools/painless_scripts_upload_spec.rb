require_relative '../spec_helper'
require 'schema_tools/painless_scripts_upload'
require 'schema_tools/config'
require 'tempfile'

RSpec.describe SchemaTools do
  describe '.painless_scripts_upload' do
    let(:temp_dir) { Dir.mktmpdir }
    let(:painless_scripts_path) { File.join(temp_dir, 'painless_scripts') }
    let(:original_painless_scripts_path) { SchemaTools::Config.painless_scripts_path }
    let(:client) { double('client') }
    
    before do
      allow(SchemaTools::Config).to receive(:painless_scripts_path).and_return(painless_scripts_path)
    end
    
    after do
      allow(SchemaTools::Config).to receive(:painless_scripts_path).and_return(original_painless_scripts_path)
      FileUtils.rm_rf(temp_dir)
    end

    context 'when painless_scripts directory does not exist' do
      it 'prints directory not found message and returns early' do
        expect { SchemaTools.painless_scripts_upload(client: client) }
          .to output(/Painless scripts directory #{painless_scripts_path} does not exist/).to_stdout
      end

      it 'does not call client put_script' do
        expect(client).not_to receive(:put_script)
        SchemaTools.painless_scripts_upload(client: client)
      end
    end

    context 'when painless_scripts directory exists but is empty' do
      before do
        FileUtils.mkdir_p(painless_scripts_path)
      end

      it 'prints no scripts message and returns early' do
        expect { SchemaTools.painless_scripts_upload(client: client) }
          .to output(/No painless script files found in #{painless_scripts_path}/).to_stdout
      end

      it 'does not call client put_script' do
        expect(client).not_to receive(:put_script)
        SchemaTools.painless_scripts_upload(client: client)
      end
    end

    context 'when painless_scripts directory contains script files' do
      before do
        FileUtils.rm_rf(painless_scripts_path) if Dir.exist?(painless_scripts_path)
        FileUtils.mkdir_p(painless_scripts_path)
        File.write(File.join(painless_scripts_path, 'script1.painless'), 'ctx._source.field = "value"')
        File.write(File.join(painless_scripts_path, 'script2.painless'), 'ctx._source.other = "test"')
        File.write(File.join(painless_scripts_path, 'not_painless.txt'), 'this should be ignored')
      end

      it 'pushes all painless scripts to cluster' do
        expect(client).to receive(:put_script).with('script1', 'ctx._source.field = "value"')
        expect(client).to receive(:put_script).with('script2', 'ctx._source.other = "test"')
        
        expect { SchemaTools.painless_scripts_upload(client: client) }
          .to output(/Uploading all painless scripts from #{Regexp.escape(painless_scripts_path)} to cluster.*Uploaded script: script1.*Uploaded script: script2.*Successfully uploaded 2 painless script\(s\) to cluster/m).to_stdout
      end

      it 'ignores non-painless files' do
        expect(client).to receive(:put_script).with('script1', 'ctx._source.field = "value"')
        expect(client).to receive(:put_script).with('script2', 'ctx._source.other = "test"')
        
        SchemaTools.painless_scripts_upload(client: client)
      end

      it 'handles empty script content' do
        FileUtils.rm_rf(painless_scripts_path) if Dir.exist?(painless_scripts_path)
        FileUtils.mkdir_p(painless_scripts_path)
        File.write(File.join(painless_scripts_path, 'empty_script.painless'), '')
        
        expect(client).to receive(:put_script).with('empty_script', '')
        
        SchemaTools.painless_scripts_upload(client: client)
      end

      it 'handles scripts with special characters in names' do
        FileUtils.rm_rf(painless_scripts_path) if Dir.exist?(painless_scripts_path)
        FileUtils.mkdir_p(painless_scripts_path)
        File.write(File.join(painless_scripts_path, 'script-with-dashes.painless'), 'ctx._source.test = "value"')
        
        expect(client).to receive(:put_script).with('script-with-dashes', 'ctx._source.test = "value"')
        
        SchemaTools.painless_scripts_upload(client: client)
      end
    end

    context 'when painless_scripts directory contains only non-painless files' do
      before do
        FileUtils.mkdir_p(painless_scripts_path)
        File.write(File.join(painless_scripts_path, 'script.txt'), 'not a painless script')
        File.write(File.join(painless_scripts_path, 'script.js'), 'javascript code')
      end

      it 'prints no scripts message and returns early' do
        expect { SchemaTools.painless_scripts_upload(client: client) }
          .to output(/No painless script files found in #{painless_scripts_path}/).to_stdout
      end

      it 'does not call client put_script' do
        expect(client).not_to receive(:put_script)
        SchemaTools.painless_scripts_upload(client: client)
      end
    end

    context 'when client put_script raises an error' do
      before do
        FileUtils.mkdir_p(painless_scripts_path)
        File.write(File.join(painless_scripts_path, 'script1.painless'), 'ctx._source.field = "value"')
      end

      it 'propagates the error' do
        allow(client).to receive(:put_script).and_raise('Upload failed')
        
        expect { SchemaTools.painless_scripts_upload(client: client) }
          .to raise_error('Upload failed')
      end
    end
  end
end