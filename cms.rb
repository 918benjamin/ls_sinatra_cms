require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"

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

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  erb :index
end

get "/new" do
  erb :new
end

post "/create" do
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
  @file_name = params[:file_name]
  file_path = File.join(data_path, @file_name)
  @content = File.read(file_path)

  erb :edit
end

post "/:file_name" do
  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  File.write(file_path, params[:content])

  session[:message] = "#{file_name} has been updated."
  redirect "/"
end

post "/:file_name/delete" do
  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  File.delete(file_path)

  session[:message] = "#{file_name} has been deleted."
  redirect "/"
end