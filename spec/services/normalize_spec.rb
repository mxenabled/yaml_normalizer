# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe YamlNormalizer::Services::Normalize do
  subject { described_class.new(*args) }

  let(:path) { "#{SpecConfig.data_path}#{File::SEPARATOR}" }
  let(:args) { ["#{path}#{file}"] }

  context 'invalid args, no arg matches file' do
    subject { described_class.new(*args).call }
    let(:args) { ['lol', :foo, nil] }
    it { expect { -> { subject } }.to_not raise_error }
    it { is_expected.to eql [] }
  end

  context 'partially invalid args' do
    let(:args) { ["#{path}*.1", :invalid, "#{path}1.*"] }
    it 'sanitaizes list of files before processing' do
      expect(subject.files).to eql ["#{path}1.1", "#{path}1.2", "#{path}2.1"]
    end
  end

  describe '#call' do
    subject { described_class.new(*args).call }
    context 'invalid YAML file' do
      let(:file) { 'invalid.yml' }

      it 'prints "not a YAML file" message to STDERR' do
        expect { subject }
          .to output("#{path}invalid.yml not a YAML file\n").to_stderr
      end
    end

    context 'single-document YAML file' do
      let(:file) { 'valid.yml' }
      let(:expected) { 'valid_normalized.yml' }

      it 'normalizes and updates the yaml file' do
        Tempfile.open(file) do |yaml|
          yaml.write(File.read(path + file))
          yaml.rewind
          expect do
            stderr = $stderr
            $stderr = StringIO.new
            described_class.new(yaml.path).call
            $stderr = stderr
          end.to(
            change { File.read(yaml.path) }
            .from(File.read("#{path}#{file}"))
            .to(File.read("#{path}#{expected}"))
          )
        end
      end

      it 'prints out a success message with relative file path' do
        Tempfile.open(file) do |yaml|
          yaml.write(File.read(path + file))
          yaml.rewind
          f = Pathname.new(yaml.path).relative_path_from(Pathname.new(Dir.pwd))
          expect { described_class.new(yaml.path).call }
            .to output("[NORMALIZED] #{f}\n").to_stderr
        end
      end
    end

    context 'multi-document YAML file' do
      let(:file) { 'valid2.yml' }

      it 'normalizes the yaml file' do
        Tempfile.open(file) do |yaml|
          yaml.write(File.read(path + file))
          yaml.rewind
          f = Pathname.new(yaml.path).relative_path_from(Pathname.new(Dir.pwd))
          expect { described_class.new(yaml.path).call }
            .to output("[NORMALIZED] #{f}\n").to_stderr
        end
      end
    end

    context 'not stable' do
      let(:file) { 'valid.yml' }
      let(:other) { 'valid_normalized.yml' }
      let(:defect) { [{ error: nil }.extend(YamlNormalizer::Ext::Namespaced)] }

      it 'prints out an error to STDERR' do
        Tempfile.open(file) do |yaml|
          yaml.write(File.read(path + file))
          yaml.rewind
          normalize = described_class.new(yaml.path)

          allow(normalize).to receive(:parse)
            .with(File.read(path + file)).and_call_original
          allow(normalize).to receive(:parse)
            .with(File.read(path + other)).and_return(defect)

          f = Pathname.new(yaml.path).relative_path_from(Pathname.new(Dir.pwd))
          expect { normalize.call }
            .to output("[ERROR]      Could not normalize #{f}\n")
            .to_stderr
        end
      end
    end
  end
end
