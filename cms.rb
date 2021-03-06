require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

VALID_FILE_EXTENSIONS = %w(md txt jpg jpeg png)

configure do
  enable :sessions
  set :session_secret, "secret"
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_html(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  file = File.read(path)
  case File.extname(path)
  when ".md"
    erb render_html(file)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    file
  when ".jpeg", ".jpg"
    headers["Content-Type"] = "image/jpeg"
    file
  when ".png"
    headers["Content-Type"] = "image/png"
    file
  end
end

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  unless user_signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

get "/" do
  @username = session[:username]
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  erb :index
end

get "/new" do
  require_signed_in_user

  erb :new
end

get "/upload" do
  require_signed_in_user

  erb :upload
end

post "/upload" do
  require_signed_in_user

  file = params[:file][:tempfile]
  file_name = params[:file][:filename]

  file_path = File.join(data_path, file_name)

  File.open(file_path, 'wb') do |f|
    f.write(file.read)
  end

  session[:message] = "#{file_name} was uploaded."
  redirect "/"
end

def valid_filename?(file_name)
  file_name.match?(/\w+\.(#{VALID_FILE_EXTENSIONS.join("|")})/)
end

def filename_message(file_name)
  if file_name.empty?
    "A name is required."
  elsif !valid_filename?(file_name)
    "Only #{VALID_FILE_EXTENSIONS.join(", ")} files are accepted."
  end
end

post "/create" do
  require_signed_in_user

  file_name = params[:filename]

  if valid_filename?(file_name)
    file_path = File.join(data_path, file_name)

    File.write(file_path, "")

    session[:message] = "#{file_name} was created."
    redirect "/"
  else
    session[:message] = filename_message(file_name)
    status 422
    erb :new
  end
end

def duplicate_filename(filename)
  parts = filename.split(".")
  parts.first << "(copy)"
  parts.join(".")
end

post "/clone" do
  require_signed_in_user

  old_file_name = params[:filename]
  new_file_name = duplicate_filename(old_file_name)
  
  old_file_path = File.join(data_path, old_file_name)
  new_file_path = File.join(data_path, new_file_name)
  contents = File.read(old_file_path)

  File.write(new_file_path, contents)

  session[:message] = "#{old_file_name} was duplicated."
  redirect "/"
end

get "/:file_name" do
  file_path = File.join(data_path, params[:file_name])

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:file_name]} does not exist."
    redirect "/"
  end
end

get "/:file_name/edit" do
  require_signed_in_user

  @file_name = params[:file_name]
  file_path = File.join(data_path, @file_name)
  @content = File.read(file_path)

  erb :edit
end

post "/:file_name" do
  require_signed_in_user

  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  File.write(file_path, params[:content])

  session[:message] = "#{file_name} has been updated."
  redirect "/"
end

post "/:file_name/delete" do
  require_signed_in_user

  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  File.delete(file_path)

  session[:message] = "#{file_name} has been deleted."
  redirect "/"
end

get "/users/signin" do
  erb :signin
end

get "/users/signup" do
  erb :signup
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

post "/users/signin" do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = params[:username]
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

def write_new_credentials(credentials, test_setup=false)
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end

  if test_setup
    File.open(credentials_path, "w") { |file| file.write(credentials.to_yaml) }
  else
    File.open(credentials_path, "w") { |file| YAML.dump(credentials, file) }
  end
end

def existing_user?(username)
  credentials = load_user_credentials

  credentials.key?(username)
end

def valid_username?(username)
  !username.empty? && username.match?(/\w{3,20}/) && !existing_user?(username)
end

def add_new_user(username, password)
  credentials = load_user_credentials
  credentials[username] = BCrypt::Password.create(params[:password]).to_s
  write_new_credentials(credentials)
end

def username_message(username)
  if !username.match?(/\w{3,20}/)
    "Username must be 3-20 characters (letters, numbers, & underscores only)"
  elsif existing_user?(username)
    "That username is taken. Please choose a new one."
  else
    "Something went wrong. Not sure what..."
  end
end

post "/users/signup" do
  username = params[:username]

  if valid_username?(username)
    add_new_user(username, params[:password])
    session[:username] = username
    session[:message] = "Your account has been created. Welcome!"
    redirect "/"
  else
    session[:message] = username_message(username)
    status 422
    erb :signup
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end