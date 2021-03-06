module Whitehall
  module DocumentFilter
    class Options

      def initialize(options = {})
        @locale = options[:locale] || I18n.locale
      end

      def for(option_name)
        raise ArgumentError.new("Unknown option name #{option_name}") unless self.class.valid_option_name?(option_name)
        send(:"options_for_#{option_name}")
      end

      def for_filter_key(filter_key)
        option_name = option_name_for_filter_key(filter_key)
        self.for(option_name)
      end

      def label_for(filter_key, value)
        for_filter_key(filter_key).label_for(value)
      rescue UnknownFilterKey
        nil
      end

      OPTIONS = {
        document_type: 'document_type',
        publication_type: 'publication_filter_option',
        organisations: 'departments',
        topics: 'topics',
        announcement_type: 'announcement_filter_option',
        official_documents: 'official_document_status',
        locations: 'world_locations'
      }.freeze

      def self.valid_option_name?(option_name)
        OPTIONS.has_key?(option_name)
      end

      def self.valid_filter_key?(filter_key)
        OPTIONS.has_value?(filter_key.to_s)
      end

      def self.invalid_filter_key?(*args)
        !valid_filter_key?(*args)
      end

      def self.valid_filter_key_and_value?(filter_key, filter_value)
        new.sentence_fragment_for(filter_key, filter_value) != nil
      end

      class UnknownFilterKey < StandardError; end

    protected
      def option_name_for_filter_key(filter_key)
        raise UnknownFilterKey.new("Unknown filter key #{filter_key}") unless self.class.valid_filter_key?(filter_key)
        OPTIONS.key(filter_key)
      end

      def options_for_organisations
        StructuredOptions.new(all_label: "All departments", grouped: Organisation.grouped_by_type(@locale))
      end

      def options_for_topics
        StructuredOptions.new(all_label: "All topics", grouped: Classification.grouped_by_type)
      end

      def options_for_document_type
        StructuredOptions.new(
          all_label: "All document types",
          ungrouped: [
            ['Announcements', 'announcements'],
            ['Policies', 'policies'],
            ['Publications', 'publications']
          ]
        )
      end

      def options_for_publication_type
        StructuredOptions.create_from_ungrouped("All publication types", Whitehall::PublicationFilterOption.all.sort_by(&:label).map { |o| [o.label, o.slug, o.group_key] })
      end

      def options_for_announcement_type
        StructuredOptions.create_from_ungrouped("All announcement types", Whitehall::AnnouncementFilterOption.all.sort_by(&:label).map { |o| [o.label, o.slug, o.group_key] })
      end

      def options_for_official_documents
        StructuredOptions.new(
          all_label: "All documents",
          ungrouped: [
            ['Command or act papers', 'command_and_act_papers'],
            ['Command papers only', 'command_papers_only'],
            ['Act papers only', 'act_papers_only']
          ]
        )
      end

      def options_for_locations
        StructuredOptions.new(
          all_label: I18n.t("document_filters.world_locations.all"),
          ungrouped: WorldLocation.includes(:translations).ordered_by_name.map { |l| [l.name, l.slug] }
        )
      end
    end
  end
end
