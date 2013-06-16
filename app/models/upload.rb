require 'digest/sha1'
require 'image_sizer'
require 's3'
require 'local_store'

class Upload < ActiveRecord::Base
  belongs_to :user

  has_many :post_uploads
  has_many :posts, through: :post_uploads

  validates_presence_of :filesize
  validates_presence_of :original_filename

  def self.create_for(user_id, file)
    # compute the sha
    sha = Digest::SHA1.file(file.tempfile).hexdigest
    # check if the file has already been uploaded
    upload = Upload.where(sha: sha).first

    # otherwise, create it
    if upload.blank?
      # retrieve image info
      image_info = FastImage.new(file.tempfile, raise_on_failure: true)
      # compute image aspect ratio
      width, height = ImageSizer.resize(*image_info.size)
      # create a db record (so we can use the id)
      upload = Upload.create!({
        user_id: user_id,
        original_filename: file.original_filename,
        filesize: File.size(file.tempfile),
        sha: sha,
        width: width,
        height: height,
        url: ""
      })
      # make sure we're at the beginning of the file (FastImage is moving the pointer)
      file.rewind
      # store the file and update its url
      upload.url = Upload.store_file(file, sha, image_info, upload.id)
      # save the url
      upload.save
    end
    # return the uploaded file
    upload
  end

  def self.store_file(file, sha, image_info, upload_id)
    return S3.store_file(file, sha, image_info, upload_id) if SiteSetting.enable_s3_uploads?
    return LocalStore.store_file(file, sha, image_info, upload_id)
  end

  def self.uploaded_regex
    /\/uploads\/#{RailsMultisite::ConnectionManagement.current_db}\/(?<upload_id>\d+)\/[0-9a-f]{16}\.(png|jpg|jpeg|gif|tif|tiff|bmp)/
  end

  def self.has_been_uploaded?(url)
    (url =~ /^\/[^\/]/) == 0 || url.start_with?(base_url)
  end

  def self.base_url
    asset_host.present? ? asset_host : Discourse.base_url_no_prefix
  end

  def self.asset_host
    ActionController::Base.asset_host
  end

end

# == Schema Information
#
# Table name: uploads
#
#  id                :integer          not null, primary key
#  user_id           :integer          not null
#  original_filename :string(255)      not null
#  filesize          :integer          not null
#  width             :integer
#  height            :integer
#  url               :string(255)      not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_uploads_on_forum_thread_id  (topic_id)
#  index_uploads_on_user_id          (user_id)
#
