class FileAttachment < Attachment
  delegate :url, :content_type, :pdf?, :csv?,
    :extracted_text, :file_extension, :file_size,
    :number_of_pages, :file, :filename, :filename_without_extension, :virus_status,
    to: :attachment_data

  after_destroy :destroy_unused_attachment_data

  accepts_nested_attributes_for :attachment_data

  validate :filename_is_unique

  def html?
    false
  end

  def could_contain_viruses?
    true
  end

private

  # Only destroy the associated attachment_data record if no other attachments are using it
  def destroy_unused_attachment_data
    if attachment_data && Attachment.where(attachment_data_id: attachment_data.id).empty?
      attachment_data.destroy
    end
  end

  def filename_is_unique
    if filename && attachable && attachable.attachments.any? { |a| !a.html? && a != self && a.filename.downcase == filename.downcase }
      self.errors[:base] << "This #{attachable_model_name} already has a file called \"#{filename}\""
    end
  end
end
