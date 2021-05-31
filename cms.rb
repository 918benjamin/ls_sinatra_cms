require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

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

post "/create" do
  require_signed_in_user

  file_name = params[:filename]

  if file_name.empty?
    session[:message] = "A name is required."
    status 422
    erb :new
  else
    file_path = File.join(data_path, file_name)

    File.write(file_path, "")

    session[:message] = "#{file_name} was created."
    redirect "/"
  end
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

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end