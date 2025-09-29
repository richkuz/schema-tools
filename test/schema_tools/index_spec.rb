require_relative '../spec_helper'
require 'schema_tools/index'

RSpec.describe SchemaTools::Index do
  let(:client) { double('client') }
  
  describe '.find_live_index' do
    context 'when index exists' do
      it 'returns Index object for existing index' do
        allow(client).to receive(:index_exists?).with('products-3').and_return(true)
        
        result = SchemaTools::Index.find_live_index('products-3', client)
        
        expect(result).to be_a(SchemaTools::Index)
        expect(result.index_name).to eq('products-3')
        expect(result.base_name).to eq('products')
        expect(result.version_number).to eq(3)
      end
      
      it 'returns Index object for unversioned index' do
        allow(client).to receive(:index_exists?).with('products').and_return(true)
        
        result = SchemaTools::Index.find_live_index('products', client)
        
        expect(result).to be_a(SchemaTools::Index)
      expect(result.index_name).to eq('products')
      expect(result.base_name).to eq('products')
      expect(result.version_number).to be_nil
      end
    end
    
    context 'when index does not exist' do
      it 'returns nil for non-existent index' do
        allow(client).to receive(:index_exists?).with('nonexistent').and_return(false)
        
        result = SchemaTools::Index.find_live_index('nonexistent', client)
        
        expect(result).to be_nil
      end
    end
    
    context 'when client raises an error' do
      it 'returns nil when client raises an error' do
        allow(client).to receive(:index_exists?).with('error-index').and_raise(StandardError.new('Connection failed'))
        
        result = SchemaTools::Index.find_live_index('error-index', client)
        
        expect(result).to be_nil
      end
    end
  end
  
  describe '#initialize' do
    it 'sets index_name, base_name, and version_number correctly' do
      index = SchemaTools::Index.new('products-3')
      
      expect(index.index_name).to eq('products-3')
      expect(index.base_name).to eq('products')
      expect(index.version_number).to eq(3)
    end
    
    it 'handles unversioned index names' do
      index = SchemaTools::Index.new('products')
      
      expect(index.index_name).to eq('products')
      expect(index.base_name).to eq('products')
      expect(index.version_number).to be_nil
    end
  end
  
  describe '#generate_next_index_name' do
    it 'generates next version for unversioned index' do
      index = SchemaTools::Index.new('products')
      
      expect(index.generate_next_index_name).to eq('products-2')
    end
    
    it 'generates next version for versioned index' do
      index = SchemaTools::Index.new('products-3')
      
      expect(index.generate_next_index_name).to eq('products-4')
    end
  end
  
  describe '.find_matching_live_indexes' do
    it 'returns matching indexes sorted by version' do
      response = [
        { 'index' => 'products-3' },
        { 'index' => 'products-1' },
        { 'index' => 'products' }
      ]
      
      allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return(response)
      
      result = SchemaTools::Index.find_matching_live_indexes('products', client)
      
      expect(result.map(&:index_name)).to eq(['products', 'products-1', 'products-3'])
    end
    
    it 'filters out non-matching indexes' do
      response = [
        { 'index' => 'products-3' },
        { 'index' => 'products_dev' },
        { 'index' => 'products-test' }
      ]
      
      allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return(response)
      
      result = SchemaTools::Index.find_matching_live_indexes('products', client)
      
      expect(result.map(&:index_name)).to eq(['products-3'])
    end
    
    it 'returns empty array when no indexes found' do
      allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([])
      
      result = SchemaTools::Index.find_matching_live_indexes('products', client)
      
      expect(result).to eq([])
    end
  end
  
  describe '.find_file_index' do
    before do
      allow(SchemaTools::Config).to receive(:schemas_path).and_return('/tmp/schemas')
    end
    
    context 'when index folder exists' do
      it 'returns Index object for existing folder' do
        allow(Dir).to receive(:exist?).with('/tmp/schemas/products-3').and_return(true)
        
        result = SchemaTools::Index.find_file_index('products-3')
        
        expect(result).to be_a(SchemaTools::Index)
        expect(result.index_name).to eq('products-3')
        expect(result.base_name).to eq('products')
        expect(result.version_number).to eq(3)
      end
      
      it 'returns Index object for unversioned folder' do
        allow(Dir).to receive(:exist?).with('/tmp/schemas/products').and_return(true)
        
        result = SchemaTools::Index.find_file_index('products')
        
        expect(result).to be_a(SchemaTools::Index)
        expect(result.index_name).to eq('products')
        expect(result.base_name).to eq('products')
        expect(result.version_number).to be_nil
      end
    end
    
    context 'when index folder does not exist' do
      it 'returns nil for non-existent folder' do
        allow(Dir).to receive(:exist?).with('/tmp/schemas/nonexistent').and_return(false)
        
        result = SchemaTools::Index.find_file_index('nonexistent')
        
        expect(result).to be_nil
      end
    end
  end
  
  describe '.find_matching_file_indexes' do
    before do
      allow(SchemaTools::Config).to receive(:schemas_path).and_return('/tmp/schemas')
    end
    
    it 'returns matching file indexes sorted by version' do
      allow(Dir).to receive(:glob).with('/tmp/schemas/products*').and_return([
        '/tmp/schemas/products-3',
        '/tmp/schemas/products-1',
        '/tmp/schemas/products'
      ])
      allow(File).to receive(:directory?).and_return(true)
      
      result = SchemaTools::Index.find_matching_file_indexes('products')
      
      expect(result.map(&:index_name)).to eq(['products', 'products-1', 'products-3'])
    end
    
    it 'filters out non-matching directories' do
      allow(Dir).to receive(:glob).with('/tmp/schemas/products*').and_return([
        '/tmp/schemas/products-3',
        '/tmp/schemas/products_dev',
        '/tmp/schemas/products-test'
      ])
      allow(File).to receive(:directory?).and_return(true)
      
      result = SchemaTools::Index.find_matching_file_indexes('products')
      
      expect(result.map(&:index_name)).to eq(['products-3'])
    end
  end
  
  describe '.sort_by_version' do
    it 'sorts indexes by version number with nil first' do
      indexes = [
        SchemaTools::Index.new('products-3'),
        SchemaTools::Index.new('products-1'),
        SchemaTools::Index.new('products'),
        SchemaTools::Index.new('products-2')
      ]
      
      result = SchemaTools::Index.sort_by_version(indexes)
      
      expect(result.map(&:index_name)).to eq(['products', 'products-1', 'products-2', 'products-3'])
    end
  end
end