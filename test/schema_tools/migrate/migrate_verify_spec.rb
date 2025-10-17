require_relative '../../spec_helper'
require 'schema_tools/migrate/migrate_verify'

RSpec.describe SchemaTools do
  describe '.verify_migration' do
    let(:alias_name) { 'test-alias' }
    let(:mock_client) { double('Client') }

    before do
      allow(SchemaTools::Diff).to receive(:generate_schema_diff).and_return(diff_result)
    end

    context 'when migration is successful with no differences' do
      let(:diff_result) do
        {
          status: :no_changes,
          settings_diff: "No changes detected",
          mappings_diff: "No changes detected"
        }
      end

      it 'reports successful migration' do
        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to output(
          /Verifying migration by comparing local schema with remote index\.\.\./m
        ).to_stdout

        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to output(
          /✓ Migration verification successful - no differences detected/m
        ).to_stdout

        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to output(
          /Migration completed successfully!/m
        ).to_stdout
      end
    end

    context 'when migration is successful but replica count differs' do
      let(:diff_result) do
        {
          status: :no_changes,
          settings_diff: "No changes detected",
          mappings_diff: "No changes detected",
          replica_warning: "WARNING: The specified number of replicas 2 in the schema could not be applied to the cluster, likely because the cluster isn't running enough nodes."
        }
      end

      it 'reports successful migration with replica warning' do
        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to output(
          /✓ Migration verification successful - no differences detected/m
        ).to_stdout

        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to output(
          /⚠️  WARNING: The specified number of replicas 2 in the schema could not be applied to the cluster, likely because the cluster isn't running enough nodes\./m
        ).to_stdout

        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to output(
          /Migration completed successfully!/m
        ).to_stdout
      end
    end

    context 'when migration verification fails' do
      let(:diff_result) do
        {
          status: :changes_detected,
          settings_diff: "=== Changes Detected ===\n🔄 MODIFIED: index.refresh_interval",
          mappings_diff: "No changes detected",
          alias_name: alias_name,
          comparison_context: {
            new_files: {
              settings: "#{alias_name}/settings.json",
              mappings: "#{alias_name}/mappings.json"
            },
            old_api: {
              settings: "GET /test-index-123/_settings",
              mappings: "GET /test-index-123/_mappings"
            }
          }
        }
      end

      it 'raises an error with diff details' do
        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to raise_error(
          "Migration verification failed - local schema does not match remote index after migration"
        )
      end
    end

    context 'when alias does not exist' do
      let(:diff_result) do
        {
          status: :alias_not_found,
          error: "Alias 'test-alias' not found in cluster",
          alias_name: alias_name
        }
      end

      it 'raises an error' do
        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to raise_error(
          "Migration verification failed - local schema does not match remote index after migration"
        )
      end
    end

    context 'when local files are not found' do
      let(:diff_result) do
        {
          status: :local_files_not_found,
          error: "Local schema files not found for test-alias",
          alias_name: alias_name
        }
      end

      it 'raises an error' do
        expect { SchemaTools.verify_migration(alias_name, mock_client) }.to raise_error(
          "Migration verification failed - local schema does not match remote index after migration"
        )
      end
    end
  end
end