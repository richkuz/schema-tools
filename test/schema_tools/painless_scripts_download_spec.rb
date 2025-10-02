require_relative '../spec_helper'
require 'schema_tools/painless_scripts_download'
require 'schema_tools/config'
require 'tempfile'

RSpec.describe SchemaTools do
  describe '.painless_scripts_download' do
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

    context 'when no painless scripts exist in cluster' do
      before do
        allow(client).to receive(:get_stored_scripts).and_return({})
      end

      it 'prints no scripts message and returns early' do
        expect { SchemaTools.painless_scripts_download(client: client) }
          .to output(/No painless scripts found in cluster/).to_stdout
      end

      it 'does not create painless_scripts directory' do
        SchemaTools.painless_scripts_download(client: client)
        expect(Dir.exist?(painless_scripts_path)).to be false
      end
    end

    context 'when painless scripts exist in cluster' do
      let(:scripts) do
        {
          'script1' => 'ctx._source.field = "value"',
          'script2' => 'ctx._source.other = "test"'
        }
      end

      before do
        allow(client).to receive(:get_stored_scripts).and_return(scripts)
      end

      it 'fetches and stores all scripts' do
        expect { SchemaTools.painless_scripts_download(client: client) }
          .to output(/Downloading all painless scripts from cluster.*Downloaded script: script1.*Downloaded script: script2.*Successfully downloaded 2 painless script\(s\) to #{Regexp.escape(painless_scripts_path)}/m).to_stdout
      end

      it 'creates painless_scripts directory' do
        SchemaTools.painless_scripts_download(client: client)
        expect(Dir.exist?(painless_scripts_path)).to be true
      end

      it 'writes script files with correct content' do
        SchemaTools.painless_scripts_download(client: client)
        
        script1_path = File.join(painless_scripts_path, 'script1.painless')
        script2_path = File.join(painless_scripts_path, 'script2.painless')
        
        expect(File.exist?(script1_path)).to be true
        expect(File.exist?(script2_path)).to be true
        
        expect(File.read(script1_path)).to eq('ctx._source.field = "value"')
        expect(File.read(script2_path)).to eq('ctx._source.other = "test"')
      end

      it 'handles empty script content' do
        empty_scripts = { 'empty_script' => '' }
        allow(client).to receive(:get_stored_scripts).and_return(empty_scripts)
        
        SchemaTools.painless_scripts_download(client: client)
        
        empty_script_path = File.join(painless_scripts_path, 'empty_script.painless')
        expect(File.exist?(empty_script_path)).to be true
        expect(File.read(empty_script_path)).to eq('')
      end
    end

    context 'when painless_scripts directory already exists' do
      let(:scripts) { { 'script1' => 'ctx._source.field = "value"' } }

      before do
        FileUtils.mkdir_p(painless_scripts_path)
        File.write(File.join(painless_scripts_path, 'old_script.painless'), 'old content')
        allow(client).to receive(:get_stored_scripts).and_return(scripts)
      end

      it 'overwrites existing files' do
        SchemaTools.painless_scripts_download(client: client)
        
        script1_path = File.join(painless_scripts_path, 'script1.painless')
        old_script_path = File.join(painless_scripts_path, 'old_script.painless')
        
        expect(File.exist?(script1_path)).to be true
        expect(File.read(script1_path)).to eq('ctx._source.field = "value"')
        expect(File.exist?(old_script_path)).to be true
        expect(File.read(old_script_path)).to eq('old content')
      end
    end
  end
end