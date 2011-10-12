Given /^a fact checker has commented "([^"]*)" on the draft policy titled "([^"]*)"$/ do |comment, title|
  document = create(:draft_policy, title: title)
  create(:fact_check_request, document: document, comments: comment)
end

Then /^"([^"]*)" should be notified by email that "([^"]*)" has requested a fact check$/ do |email_address, writer_name|
  assert_equal 1, unread_emails_for(email_address).size
  email = unread_emails_for(email_address).last
  assert_equal "Fact checking request from #{writer_name}", email.subject
end

When /^"([^"]*)" clicks the email link to the draft policy$/ do |email_address|
  email = unread_emails_for(email_address).last
  links = URI.extract(email.body.to_s, ["http", "https"])
  visit links.first
end

Then /^they provide feedback "([^"]*)"$/ do |comments|
  fill_in "Comments", with: comments
  click_button "Submit"
end