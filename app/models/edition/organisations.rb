module Edition::Organisations
  extend ActiveSupport::Concern

  class Trait < Edition::Traits::Trait
    def process_associations_before_save(edition)
      @edition.edition_organisations.each do |association|
        edition.edition_organisations.build(association.attributes.except("id"))
      end
    end
  end

  included do
    # NOTE: we have 3 associations that point to the same underlying
    # table (EditionOrganisation). So we have to do our uniqueness
    # validation manually in case the data is manipulated via multiple
    # associations at once
    has_many :edition_organisations, foreign_key: :edition_id, dependent: :destroy
    has_many :organisations, through: :edition_organisations

    has_many :lead_edition_organisations, foreign_key: :edition_id,
                                          class_name: 'EditionOrganisation',
                                          conditions: {lead: true},
                                          order: 'edition_organisations.lead_ordering'

    has_many :supporting_edition_organisations, foreign_key: :edition_id,
                                                class_name: 'EditionOrganisation',
                                                conditions: {lead: false}

    def lead_organisations
      organisations.where(edition_organisations: { lead: true }).reorder('edition_organisations.lead_ordering')
    end

    def supporting_organisations
      organisations.where(edition_organisations: { lead: false })
    end
    accepts_nested_attributes_for :edition_organisations,
      reject_if: ->(attributes) { attributes['organisation_id'].blank? && attributes['id'].blank? },
      allow_destroy: true

    before_validation :make_all_edition_organisations_mine
    after_save :reset_edition_organisations
    validate :at_least_one_lead_organisation
    validate :no_duplication_of_organisations
    before_update :destroy_marked_for_destruction_edition_organisations

    add_trait Trait
  end

  module ClassMethods
    def in_organisation(organisation)
      organisations = [*organisation]
      slugs = organisations.map(&:slug)
      where('exists (
               select * from edition_organisations eo_orgcheck
                 join organisations orgcheck on eo_orgcheck.organisation_id=orgcheck.id
               where
                 eo_orgcheck.edition_id=editions.id
               and orgcheck.slug in (?))', slugs)
    end
  end

  def association_with_organisation(organisation)
    edition_organisations.where(organisation_id: organisation.id).first
  end

  def skip_organisation_validation?
    false
  end

private
  def destroy_marked_for_destruction_edition_organisations
    # AR will destroy things in order as it finds them. this can mean that
    # we have duplicates in the db during the transaction.  e.g. if we
    # have lead org 1 = MOD, lead org 2 = BIS and we want to update to
    # lead org 1 = BIS, lead org 2 = destroy, the update to lead org 1
    # happens before the destruction of lead org 2, and so, we have a dup
    # If we destroy them all first, this should be ok.
    to_die = edition_organisations.select { |eo| eo.marked_for_destruction? } +
              lead_edition_organisations.select { |leo| leo.marked_for_destruction? } +
              supporting_edition_organisations.select { |seo| seo.marked_for_destruction? }
    to_die.map { |eo| eo.destroy }
  end

  def at_least_one_lead_organisation
    unless skip_organisation_validation?
      unless lead_edition_organisations.any? || edition_organisations.detect {|eo| eo.lead? }
        errors[:lead_organisations] = "at least one required"
      end
    end
  end

  def no_duplication_of_organisations
    # NOTE: we have a uniquness index on the table to prevent this, but it's
    # a good idea to trap it somewhere earlier where we can show a nice error
    # validates_uniqueness_of on the EditionOrganisation wouldn't really
    # give us a nice error (edition_organisations is invalid), so lets try
    # something on the edition itself.
    new_eos = []
    existing_eos = []
    to_die = []
    __get_edition_organisations_for_validation(edition_organisations, new_eos, existing_eos, to_die)
    __get_edition_organisations_for_validation(lead_edition_organisations, new_eos, existing_eos, to_die)
    __get_edition_organisations_for_validation(supporting_edition_organisations, new_eos, existing_eos, to_die)
    # strip out any that have been marked for deletion becaue the same
    # object will appear from two associations, but it's likely only one
    # is marked for deletion. If we don't strip both instances out then
    # we run the risk of adding an error because things aren't unique when
    # they will be because we're deleting one of them
    existing_eos = existing_eos.reject { |(eo_id, _, _)| to_die.include?(eo_id) }

    # get rid of existing ones where the change flag is false and there's
    # another existing entry for the same edition_organisation id with a
    # change flag that is true.
    # Because we don't want to detect internal dupes when we're updating
    # an instance in place via one association but we get the instance
    # from the other association
    existing_eos = existing_eos.reject do |(eo_id, org_id, change_flag)|
      if change_flag
        false
      else
        existing_eos.any? { |(o_eo_id, _, o_change_flag)| eo_id == o_eo_id && o_change_flag }
      end
    end

    # adding the same org twice
    if new_eos.map { |(eo_id, org_id, _)| org_id }.uniq.size != new_eos.size
      errors.add(:organisations, 'must be unique')
    # adding an org that we've already got
    elsif (new_eos.map { |(eo_id, org_id, _)| org_id } & existing_eos.map { |(eo_id, org_id)| org_id }).any?
      errors.add(:organisations, 'must be unique')
    else
      # existing org somehow added on more than one eo
      existing_dupes = existing_eos.map do |(eo_id, org_id, _)|
        existing_eos.any? { |(o_eo_id, o_org_id, _)| (eo_id != o_eo_id) && (org_id == o_org_id) }
      end
      errors.add(:organisations, 'must be unique') if existing_dupes.any?
    end
  end
  def __get_edition_organisations_for_validation(edition_organisation_association, new_eos, existing_eos, to_die)
    all_eos = edition_organisation_association
    grouped = all_eos.
      reject { |eo| eo.destroyed? || eo.marked_for_destruction? }.
      # for orgs that are to be created when we do this, grab the object id
      map { |eo| [eo.id, eo.organisation_id || eo.organisation.object_id, eo.changed?] }.
      group_by { |(eo_id, org_id)| eo_id.nil? }
    new_eos.push(*grouped[true]) if grouped[true].present?
    existing_eos.push(*grouped[false]) if grouped[false].present?
    to_die.push(*all_eos.select { |eo| eo.destroyed? || eo.marked_for_destruction? }.map(&:id))
    nil
  end

  def make_all_edition_organisations_mine
    edition_organisations.each { |eo| eo.edition = self unless eo.edition == self }
    lead_edition_organisations.each { |eo| eo.edition = self unless eo.edition == self }
    supporting_edition_organisations.each { |eo| eo.edition = self unless eo.edition == self }
  end

  def reset_edition_organisations
    # we have 3 ways into the underlying data structure for EditionOrganisations
    # safest to reset all the assocations after saving so they all pick up
    # any changes made via the other endpoints.
    self.association(:edition_organisations).reset
    self.association(:organisations).reset
    self.association(:lead_edition_organisations).reset
    self.association(:supporting_edition_organisations).reset
  end
end
