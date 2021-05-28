require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"

root = File.expand_path("..", __FILE__)

configure do
  enable :sessions
  set :session_secret, "secret"
end

def render_html(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  file = File.read(path)
  case File.extname(path)
  when ".md"
    render_html(file)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    file
  end
end

get "/" do
  @files = Dir.glob(root + "/data/*").map do |path|
    File.basename(path)
  end
  erb :index
end

get "/:file_name" do
  file_path = root + "/data/" + params[:file_name]

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:file_name]} does not exist."
    redirect "/"
  end
end

get "/:file_name/edit" do
  @file_name = params[:file_name]
  file_path = root + "/data/" + @file_name

  if File.exist?(file_path)
    @content = load_file_content(file_path)
    headers["Content-Type"] = "text/html"
    erb :edit
  else
    session[:message] = "#{@file_name} does not exist."
    redirect "/"
  end
end

post "/:file_name" do
  file_name = params[:file_name]
  file_path = root + "/data/" + file_name

  File.write(file_path, params[:content])
  session[:message] = "#{file_name} has been updated."
  redirect "/"
end