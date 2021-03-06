require 'test_helper'

class Admin::PublicationsControllerTest < ActionController::TestCase
  setup do
    login_as :policy_writer
  end

  should_be_an_admin_controller

  should_allow_creating_of :publication
  should_allow_editing_of :publication

  should_allow_speed_tagging_of :publication
  should_allow_related_policies_for :publication
  should_allow_organisations_for :publication
  should_allow_ministerial_roles_for :publication
  should_allow_references_to_statistical_data_sets_for :publication
  should_allow_attached_images_for :publication
  should_allow_association_between_world_locations_and :publication
  should_prevent_modification_of_unmodifiable :publication
  should_allow_alternative_format_provider_for :publication
  should_allow_scheduled_publication_of :publication
  should_allow_access_limiting_of :publication

  view_test "new displays publication fields" do
    get :new

    assert_select "form#new_edition" do
      assert_select "select[name*='edition[first_published_at']", count: 5
      assert_select "select[name='edition[publication_type_id]']"
    end
  end

  test "create should create a new publication" do
    post :create, edition: controller_attributes_for(:publication,
      first_published_at: Time.zone.parse("2001-10-21 00:00:00"),
      publication_type_id: PublicationType::ResearchAndAnalysis.id
    )

    created_publication = Publication.last
    assert_equal Time.zone.parse("2001-10-21 00:00:00"), created_publication.first_published_at
    assert_equal PublicationType::ResearchAndAnalysis, created_publication.publication_type
  end

  view_test "edit displays publication fields" do
    publication = create(:publication)

    get :edit, id: publication

    assert_select "form#edit_edition" do
      assert_select "select[name='edition[publication_type_id]']"
      assert_select "select[name*='edition[first_published_at']", count: 5
    end
  end

  test "update should save modified publication attributes" do
    publication = create(:publication)

    put :update, id: publication, edition: {
      first_published_at: Time.zone.parse("2001-06-18 00:00:00")
    }

    saved_publication = publication.reload
    assert_equal Time.zone.parse("2001-06-18 00:00:00"), saved_publication.first_published_at
  end

  view_test "should remove the publish buttons if the edition breaks the rules permitting publishing" do
    # This applies to all editions but can't be tested in the editions controller test due to redirects.
    # After conversation with DH I picked publications arbitrarily.
    login_as(create(:departmental_editor))
    publication = create(:draft_publication)

    [EditionPublisher, EditionForcePublisher].each do |publisher|
      publisher.any_instance.stubs(:failure_reasons).returns(["This edition is not dope enough"])
    end

    get :show, id: publication.id

    assert_response :success
    refute_select ".publish"
    refute_select ".force-publish"
  end

  private

  def controller_attributes_for(edition_type, attributes = {})
    super.except(:alternative_format_provider).reverse_merge(
      alternative_format_provider_id: create(:alternative_format_provider).id
    )
  end
end
